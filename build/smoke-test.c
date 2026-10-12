/* Smoke test for the shipped libzmq.dll.
 *
 * Compiled twice: once with the 32bit toolchain against Library/MT4/libzmq.dll
 * and once with the 64bit toolchain against Library/MT5/libzmq.dll. A 32bit
 * executable runs fine on a 64bit Windows, so both flavours can be checked
 * from the same machine.
 *
 *   i686-w64-mingw32-gcc   -o smoke32.exe smoke-test.c -L../Library/MT4 -l:libzmq.dll
 *   x86_64-w64-mingw32-gcc -o smoke64.exe smoke-test.c -L../Library/MT5 -l:libzmq.dll
 *
 * It exercises the calls mql-zmq relies on, including the 4.3.x additions and
 * the statically linked libsodium.
 */
#include <stdio.h>
#include <string.h>
/* libzmq hides the 4.3.x draft symbols (zmq_socket_monitor_versioned,
 * zmq_socket_monitor_pipes_stats, the ZMQ_*_DRAFT constants) behind this
 * macro. The shipped DLLs are built with --enable-drafts, so define it here
 * too, otherwise the prototypes are not declared and the calls get an
 * implicit declaration warning. */
#define ZMQ_BUILD_DRAFT_API 1
#include <zmq.h>

static int failures = 0;

static void check(const char *name, int cond, const char *extra)
{
    printf("  [%-3s] %-38s %s\n", cond ? "ok" : "FAIL", name, extra ? extra : "");
    if (!cond)
        failures++;
}

int main(void)
{
    int major, minor, patch;
    void *ctx, *a, *b;
    char buf[128];
    char pub[41], sec[41];
    char ver[32];

    zmq_version(&major, &minor, &patch);
    sprintf(ver, "%d.%d.%d", major, minor, patch);
    check("zmq_version", strcmp(ver, "4.3.5") == 0, ver);

    /* Only `curve` is guaranteed: it needs the statically linked libsodium.
     * ipc/pgm/tipc/norm depend on the compile time transport selection and
     * report 0 on a default Windows build (same for the old 4.2.0 DLL). */
    check("has(curve)", zmq_has("curve") == 1, "");
    printf("        info: has(ipc)=%d has(ws)=%d has(norm)=%d\n",
            zmq_has("ipc"), zmq_has("ws"), zmq_has("norm"));

    ctx = zmq_ctx_new();
    check("zmq_ctx_new", ctx != NULL, "");

    a = zmq_socket(ctx, ZMQ_PAIR);
    b = zmq_socket(ctx, ZMQ_PAIR);
    check("zmq_socket", a != NULL && b != NULL, "");

    check("zmq_bind(inproc)", zmq_bind(a, "inproc://smoke") == 0, "");
    check("zmq_connect(inproc)", zmq_connect(b, "inproc://smoke") == 0, "");

    check("zmq_send", zmq_send(b, "mql-zmq", 7, 0) == 7, "");
    {
        int n = zmq_recv(a, buf, sizeof(buf), 0);
        buf[n < 0 ? 0 : n] = '\0';
        check("zmq_recv", n == 7 && strcmp(buf, "mql-zmq") == 0, buf);
    }

    /* 4.3.x: monitor with an explicit event version.
     * NOTE the real signature has FIVE parameters: (s, addr, events,
     * event_version, monitor_socket_type). A four-argument call is wrong. */
    check("zmq_socket_monitor_versioned",
          zmq_socket_monitor_versioned(a, "inproc://mon", ZMQ_EVENT_ALL,
                                       ZMQ_CURRENT_EVENT_VERSION,
                                       0 /* ZMQ_PAIR */) == 0, "");

    /* curve keys: proves the statically linked libsodium is alive */
    check("zmq_curve_keypair", zmq_curve_keypair(pub, sec) == 0, "");
    check("curve key length", strlen(pub) == 40, pub);

    /* zmq_msg_t size must fit the 64 byte blob used by the MQL binding */
    {
        char msgcheck[64];
        sprintf(msgcheck, "sizeof=%d ptr=%d", (int) sizeof(zmq_msg_t),
                (int) sizeof(void *));
        check("zmq_msg_t fits in 64 bytes", sizeof(zmq_msg_t) <= 64, msgcheck);
    }

    check("zmq_socket_monitor_pipes_stats present",
          zmq_socket_monitor_pipes_stats != NULL, "");

    zmq_close(a);
    zmq_close(b);
    check("zmq_ctx_term", zmq_ctx_term(ctx) == 0, "");

    printf("RESULT: %s\n", failures == 0 ? "PASS" : "FAIL");
    return failures == 0 ? 0 : 1;
}
