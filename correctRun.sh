#!/bin/bash
echo "starting orbd"
orbd -ORBInitialPort 1050 -ORBInitialHost localhost &
ORB_PROC=$!
sleep 5
echo "started orb"
echo "starting server"
java HelloServer -ORBInitialPort 1050 -ORBInitialHost localhost &
SERVER_PROC=$!
sleep 5 
echo "started server"
echo "starting client"
java HelloClient -ORBInitialPort 1050 -ORBInitialHost localhost
kill -9 $SERVER_PROC
kill -9 $ORB_PROC
echo "finished!"
