#!/bin/bash
echo "starting orbd"
orbd -ORBInitialPort 1050 -ORBInitialHost localhost &
ORB_PROC=$!
sleep 5 #give orbd time to start
echo "started orb"
echo "starting server"
java HelloServer -ORBInitialPort 1050 -ORBInitialHost localhost &
SERVER_PROC=$!
sleep 5 #give server time to start
echo "started server"
echo "starting client (debug mode)"
java -Xdebug -Xrunjdwp:transport=dt_socket,address=8000,server=y,suspend=y HelloClient -ORBInitialPort 1050 -ORBInitialHost localhost &
JVM_PROC=$!
sleep 5 #give jvm/debugger/client time to start
echo "started client (debug mode)"
echo "starting debugger and issuing commands"
(sleep 5;
echo "stop in com.sun.corba.se.impl.protocol.CorbaClientRequestDispatcherImpl.unregisterWaiter";
sleep 5;
echo "run";
sleep 5;
echo "cont";
sleep 5;
echo "cont";
sleep 5;
echo "cont";
sleep 5;
echo "suspend 1";
sleep 5;
kill -9 $SERVER_PROC &> /dev/null; 
sleep 5;
echo "cont";
sleep 5;
echo "thread 1"
sleep 5;
echo "clear com.sun.corba.se.impl.protocol.CorbaClientRequestDispatcherImpl.unregisterWaiter"
sleep 5;
echo "resume 1";
)| jdb -attach 8000

kill -9 $ORB_PROC