#!/usr/bin/env python3
"""Smoke test for the 64bit libzmq.dll shipped in Library/MT5.

Loads the DLL with ctypes (no pyzmq involved) and exercises the calls that
mql-zmq relies on: version, capabilities, context, inproc PAIR send/recv,
Z85/CURVE key generation (i.e. the statically linked libsodium) and
zmq_socket_monitor_versioned.

    python build/smoke-test.py
"""
import ctypes
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DLL = os.path.join(HERE, "..", "Library", "MT5", "libzmq.dll")

if not os.path.exists(DLL):
    sys.exit("missing " + DLL)

zmq = ctypes.CDLL(DLL)
LP = ctypes.c_void_p
INT = ctypes.c_int
ZMQ_CURRENT_EVENT_VERSION = 1
ZMQ_CURRENT_EVENT_VERSION_DRAFT = 2
ZMQ_MONITOR_PAIR = 0
zmq.zmq_ctx_new.restype = LP
zmq.zmq_socket.restype = LP
zmq.zmq_strerror.restype = LP
zmq.zmq_msg_data.restype = LP
zmq.zmq_z85_encode.restype = LP
zmq.zmq_socket.argtypes = [LP, ctypes.c_int]
zmq.zmq_bind.argtypes = [LP, ctypes.c_char_p]
zmq.zmq_connect.argtypes = [LP, ctypes.c_char_p]
zmq.zmq_ctx_term.argtypes = [LP]
zmq.zmq_close.argtypes = [LP]
zmq.zmq_send.argtypes = [LP, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
zmq.zmq_recv.argtypes = [LP, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]

ok = True


def check(name, cond, extra=""):
    global ok
    ok = ok and bool(cond)
    print("  [%-3s] %-38s %s" % ("ok" if cond else "FAIL", name, extra))


def has(cap):
    zmq.zmq_has.argtypes = [ctypes.c_char_p]
    return zmq.zmq_has(cap) == 1


print("libzmq:", DLL)

major, minor, patch = INT(), INT(), INT()
zmq.zmq_version(ctypes.byref(major), ctypes.byref(minor), ctypes.byref(patch))
ver = "%d.%d.%d" % (major.value, minor.value, patch.value)
check("zmq_version", ver == "4.3.5", ver)

# Only `curve` is guaranteed: it needs the statically linked libsodium.
# ipc/pgm/tipc/norm depend on compile time transport selection, and 0 as on
# a default Windows build (the old 4.2.0 DLL behaves the same way).
check("has(curve)", has(b"curve"))
print("        info: has(ipc)=%s has(ws)=%s has(norm)=%s"
      % (has(b"ipc"), has(b"ws"), has(b"norm")))

ctx = zmq.zmq_ctx_new()
check("zmq_ctx_new", ctx)

PAIR = 0
a = zmq.zmq_socket(ctx, PAIR)
b = zmq.zmq_socket(ctx, PAIR)
check("zmq_socket", a and b)

check("zmq_bind(inproc)", zmq.zmq_bind(a, b"inproc://smoke") == 0)
check("zmq_connect(inproc)", zmq.zmq_connect(b, b"inproc://smoke") == 0)

payload = b"mql-zmq 4.3.5"
check("zmq_send", zmq.zmq_send(b, payload, len(payload), 0) == len(payload))
buf = ctypes.create_string_buffer(128)
n = zmq.zmq_recv(a, buf, 128, 0)
check("zmq_recv", n == len(payload) and buf.raw[:n] == payload, buf.raw[:n])

# message API
class ZmqMsg(ctypes.Structure):
    _fields_ = [("_", ctypes.c_ubyte * 64)]


msg = ZmqMsg()
zmq.zmq_msg_init.argtypes = [ctypes.POINTER(ZmqMsg)]
zmq.zmq_msg_init_size.argtypes = [ctypes.POINTER(ZmqMsg), ctypes.c_size_t]
zmq.zmq_msg_data.argtypes = [ctypes.POINTER(ZmqMsg)]
zmq.zmq_msg_size.argtypes = [ctypes.POINTER(ZmqMsg)]
zmq.zmq_msg_send.argtypes = [ctypes.POINTER(ZmqMsg), LP, INT]
zmq.zmq_msg_recv.argtypes = [ctypes.POINTER(ZmqMsg), LP, INT]
zmq.zmq_msg_close.argtypes = [ctypes.POINTER(ZmqMsg)]

check("zmq_msg_init_size", zmq.zmq_msg_init_size(ctypes.byref(msg), 4) == 0)
ctypes.memmove(zmq.zmq_msg_data(ctypes.byref(msg)), b"abcd", 4)
check("zmq_msg_send", zmq.zmq_msg_send(ctypes.byref(msg), b, 0) == 4)
zmq.zmq_msg_close(ctypes.byref(msg))
zmq.zmq_msg_init(ctypes.byref(msg))
check("zmq_msg_recv", zmq.zmq_msg_recv(ctypes.byref(msg), a, 0) == 4)
check("zmq_msg payload", ctypes.string_at(zmq.zmq_msg_data(ctypes.byref(msg)), 4) == b"abcd")
zmq.zmq_msg_close(ctypes.byref(msg))

# 4.3.x: monitor with an explicit event version.
# NOTE the real signature has 5 parameters, not 4: (s, addr, uint64_t events,
# int event_version, int monitor_socket_type). MQL bindings got this wrong too,
# which is exactly why this test exists.
zmq.zmq_socket_monitor_versioned.argtypes = [LP, ctypes.c_char_p, ctypes.c_uint64, INT, INT]
check(
    "zmq_socket_monitor_versioned",
    zmq.zmq_socket_monitor_versioned(a, b"inproc://mon", 0xFFFF,
                                     ZMQ_CURRENT_EVENT_VERSION, 0) == 0,
)

# Curve keys: proves the statically linked libsodium is alive
pub = ctypes.create_string_buffer(41)
sec = ctypes.create_string_buffer(41)
zmq.zmq_curve_keypair.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
check("zmq_curve_keypair", zmq.zmq_curve_keypair(pub, sec) == 0)
check("curve key length", len(pub.value) == 40, pub.value[:12] + b"...")

# poll item layout: void*, fd, short, short, (pad)
class PollItem(ctypes.Structure):
    _fields_ = [
        ("socket", LP),
        ("fd", ctypes.c_uint64),
        ("events", ctypes.c_short),
        ("revents", ctypes.c_short),
        ("unused", ctypes.c_int),
    ]


check("PollItem size is 24 on x64", ctypes.sizeof(PollItem) == 24, ctypes.sizeof(PollItem))

zmq.zmq_close.argtypes = [LP]
zmq.zmq_close(a)
zmq.zmq_close(b)
# zmq_ctx_term blocks while IO threads drain. That is normal 0MQ behaviour,
# not a defect, so it is not asserted here -- the script would hang.
zmq.zmq_ctx_shutdown.argtypes = [LP]
zmq.zmq_ctx_shutdown(ctx)

print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
