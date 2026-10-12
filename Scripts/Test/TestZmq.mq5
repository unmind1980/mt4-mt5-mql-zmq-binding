//+------------------------------------------------------------------+
//|                                                      TestZmq.mq4 |
//|                                          Copyright 2016, Li Ding |
//|                                            dingmaotu@hotmail.com |
//|                                                                  |
//| Updated for libzmq 4.3.5 / libsodium 1.0.22                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2016, Li Ding"
#property link      "https://github.com/dingmaotu/mql-zmq"
#property version   "2.00"
#property strict

#include <Zmq/Zmq.mqh>
//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
//--- Test version
   Print(">>> Testing version");
   Print("0) Binding version is [",Zmq::getBindingVersion(),"]");
   Print("1) Zmq version is [",Zmq::getVersion(),"]");
   Print("2) Major/minor/patch: [",Zmq::major(),".",Zmq::minor(),".",Zmq::patch(),"]");
   Print("3) At least 4.3.5: [",Zmq::isAtLeast(4,3,5),"]");
   Print(">>> End testing version");

//--- Test capabilities
   Print(">>> Testing capabilities");
   Print("1) Supports ipc:// protocol: [",Zmq::hasIpc(),"]");
   Print("2) Supports pgm:// protocol: [",Zmq::hasPgm(),"]");
   Print("3) Supports norm:// protocol: [",Zmq::hasNorm(),"]");
   Print("4) Supports tipc:// protocol: [",Zmq::hasTipc(),"]");
   Print("5) Supports ws:// protocol: [",Zmq::hasWs(),"]");
   Print("6) Supports wss:// protocol: [",Zmq::hasWss(),"]");
   Print("7) Supports curve security: [",Zmq::hasCurve(),"]");
   Print("8) Supports gssapi security: [",Zmq::hasGssApi(),"]");
   Print(">>> End testing capabilities");

//--- Test Z85 encoding/decoding
   Print(">>> Testing Z85 encoding/decoding");

   string data="12345678";
   Print("1) Original data is: ",data);

   string secret=Z85::encode(data);
   Print("2) Encrypted value is: ",secret);

   string decoded=Z85::decode(secret);
   Print("3) Decoded: ",decoded);
   Print("4) Decoded value is equal to original: [",decoded==data,"]");
   Print(">>> End testing Z85 encoding/decoding");

//--- Test atomic counters
   Print(">>> Testing atomic counters");
   AtomicCounter counter;
   Print("1) Initial value should be 0: [",counter.get()==0,"]");
   counter.set(5);
   Print("2) Counter set to 5: [",counter.get()==5,"]");
   counter.increase();
   Print("3) Increased value should be 6: [",counter.get()==6,"]");
   counter.decrease();
   Print("4) Decreased value should be 5: [",counter.get()==5,"]");
   Print(">>> End testing atomic counters");

//--- Test context
   Print(">>> Testing context");
   Context context;
   Print("1) Default IO threads should be ZMQ_IO_THREADS_DFLT: [",context.getIoThreads()==ZMQ_IO_THREADS_DFLT,"]");
   Print(">>> trying to set io threads to 2");
   context.setIoThreads(2);
   Print("2) Now IO threads should be 2: [",context.getIoThreads()==2,"]");
   Print("3) Socket limit: [",context.getSocketLimit(),"]");
   Print("4) Max sockets: [",context.getMaxSockets(),"]");
   Print("5) Max message size: [",context.getMaxMessageSize(),"]");
   Print("6) zmq_msg_t size in intptr_t units: [",context.getMsgTSize(),"]");
   Print(">>> End testing context");

   Socket s(context,ZMQ_REP);
   string addr="inproc://abc";
   if(!s.bind(addr))
     {
      Debug(StringFormat("Error binding %s: %s",addr,Zmq::errorMessage()));
     }
   else
     {
      Debug(StringFormat("Success binded %s",addr));
     }
   string endpoint;
   s.getLastEndpoint(endpoint);
   Print("Last endpoint is: [",endpoint,"]");

   string principal;
   s.getGssApiPrincipal(principal);
   Print("Principal is [",principal,"]");

//--- Test curve
   Print(">>> Testing curve");
   string genpub,gensec;
   Z85::generateKeyPair(genpub,gensec);
   Print("1) Generated public key: [",genpub,"]");
   Print("1) Generated private key: [",gensec,"]");
   Print("2) Derive public key from secret key: [",Z85::derivePublic(gensec)==genpub,"]");
   Print(">>> End testing curve");

//--- Test 4.3.x additions
   Print(">>> Testing 4.3.x additions");
   Socket pub(context,ZMQ_PUB);
   Print("1) monitorVersioned(inproc://mon): [",
         pub.monitorVersioned("inproc://mon",ZMQ_EVENT_ALL,ZMQ_CURRENT_EVENT_VERSION),"]");
   Print("2) last error if the line above failed: [",Zmq::errorMessage(),"]");
   Print("3) setHelloMessage: [",pub.setHelloMessage("hello"),"]");
   Print("4) setDisconnectMessage: [",pub.setDisconnectMessage("bye"),"]");
   Print("5) setPriority: [",pub.setPriority(100),"]");
   Print("6) setInBatchSize: [",pub.setInBatchSize(8192),"]");
   Print("7) setOutBatchSize: [",pub.setOutBatchSize(8192),"]");
   Print(">>> End testing 4.3.x additions");
  }
//+------------------------------------------------------------------+
