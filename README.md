CORBA RACE CONDITION
---------------------
David MacDonald
d.macdonald@auckland.ac.nz
2011/05/25
The University of Auckland

Brief summary
---------------------

A race condition has been identified in the CORBA code that means ABORTed connections are not taken out of the CORBA connection cache. This race condition causes an exception just after the connection has been marked as ABORT but before the connection is removed from the cache. This, and other similar problems whereby lack of exception handling with ABORTed connections leaves the CORBA client in an inconsistent state has been encountered in production environments.

Affects versions 1.6.0_24+

Technical summary
---------------------

In the standard flow of events we expect logic similar to the following:
1. A request is sent to the CORBA client code
2. The CORBA code creates a connection, stores it in the cache and sends the request to the remote server
3. While waiting for the response the CORBA client code puts the request thread in a 'waiting room'
4. When the response has been returned the CORBA client code unregisters the waiter from the waiting room and returns back to the requestor

The race condition can arise when the server is killed just after it has returned a response to the client but before the CORBA client code has had time to remove the thread from the 'waiting room':
1. A thread has been placed in the CORBA response 'waiting room'.
2. The CORBA server returns a response, the CORBA client code starts processing it, closes things up, and is currently at the line unregisterWaiter(orb) in com.sun.corba.se.impl.protocol.CorbaClientRequestDispatcherImpl (line 889).
3. Before it executes unregisterWaiter(orb), the CORBA server is killed.
4. At this point, the thread monitoring the connection cleans up by running the purgeCalls method of SocketOrChannelConnectionImpl.java. This method first sets the connection state to ABORT and then calls the signalExceptionToAllWaiters method to be executed in the CorbaResponseWaitingRoomImpl class. This method throws an exception because the response has actually completed successfully. The exception is rethrown up and beyond the purgeCalls method because there is no exception hander. This leads to the inconsistent state where the connection is marked as ABORT but has not been removed from the connection cache. 
5. When another request comes into the CORBA client code, it retrieves this ABORTed connection for use: the client then throws the exception: 
org.omg.CORBA.COMM_FAILURE: vmcid: SUN minor code: 203 completed: No 
when it tries to use this connection.

This raises two issues with the CORBA code base:
1. Marking a connection as ABORT and removing the connection from the cache should be an all-or-nothing process. This can be achieved in SocketOrChannelConnectionImpl by simply adding a try/finally clause to the purgeCalls method and placing the cache remove code in the finally part (see the end for code details). This means that now the only way that the connection can be left in an inconsistent state is if the socket close method calls block (this is done right after setting the connection state to ABORT). This case shouldn't happen however as they are asynchronous.
2. Managing the messageMediator by closing Input/Output objects in the com.sun.corba.se.impl.protocol.CorbaClient.RequestDispatcherImpl.endRequest method needs to be handled in an atomic way with the unregisterWaiter call. Note that an exception handler in the SocketOrChannelConnectionImpl.purgeCalls method will mean this isn't necessary to fix this exact issue.

Test case
---------------------

A test case has been constructed that contains a simple 'hello world' CORBA client and server. It can be compiled with the command:
./compile.sh
The client/server can be run 'normally' with the command (Java 1.6.0_24):
./correctRun.sh
This should return a series of 5 'Hello world !!'s. The race condition issue can be raised with the following command (Java 1.6.0_24):
./raceCondition.sh
This should return a series of debug information followed by 4 of the 'COMM_FAILURE' exceptions.

The race condition script does the following:
- starts orbd
- starts the CORBA server
- starts the CORBA client in the debugger (note execution does not start)
- connects to the debugger and places a break point in com.sun.corba.se.impl.protocol.CorbaClientRequestDispatcherImpl.unregisterWaiter
- starts the CORBA client code running: it will meet a break point
- the first break point corresponds to the CORBA request method "get": we continue execution
- the second break point corresponds to the CORBA request method "is_a": we continue execution
- the third break point corresponds to the CORBA request method "resolve_str": we continue execution
- the forth break point corresponds to the CORBA request method "sayHello": since this is the actual request we are interested in we are going to induce race condition failure and do not continue execution right away
- suspend the main thread in the client (i.e. the code currently sitting at the breakpoint) and resume the rest of the threads (we are interested in the thread that manages the connection)
- kill the server process
- this will have a completed response in the waiting room that will throw an exception when called from the purgeCalls method. The connection will be marked as ABORT but not removed from the connection cache.
- clear the break point in the client and resume the main thread
- the remaining attempts will use the ABORT connection and throw the 'COMM_FAILURE' exception

Sample output in production
---------------------

The following has been encountered in a production environment (Java 1.6.0_24):
org.omg.CORBA.COMM_FAILURE: vmcid: SUN minor code: 203 completed: No
at com.sun.corba.se.impl.logging.ORBUtilSystemException.writeErrorSend(ORBUtilSystemException.java:2259)
at com.sun.corba.se.impl.logging.ORBUtilSystemException.writeErrorSend(ORBUtilSystemException.java:2281)
at com.sun.corba.se.impl.transport.SocketOrChannelConnectionImpl.writeLock(SocketOrChannelConnectionImpl.java:957)
at com.sun.corba.se.impl.encoding.BufferManagerWriteStream.sendFragment(BufferManagerWriteStream.java:86)
at com.sun.corba.se.impl.encoding.BufferManagerWriteStream.sendMessage(BufferManagerWriteStream.java:104)
at com.sun.corba.se.impl.encoding.CDROutputObject.finishSendingMessage(CDROutputObject.java:144)
at com.sun.corba.se.impl.protocol.CorbaMessageMediatorImpl.finishSendingRequest(CorbaMessageMediatorImpl.java:247)
at com.sun.corba.se.impl.protocol.CorbaClientRequestDispatcherImpl.marshalingComplete1(CorbaClientRequestDispatcherImpl.java:355)
at com.sun.corba.se.impl.protocol.CorbaClientRequestDispatcherImpl.marshalingComplete(CorbaClientRequestDispatcherImpl.java:336)
at com.sun.corba.se.impl.protocol.CorbaClientDelegateImpl.invoke(CorbaClientDelegateImpl.java:129)
at com.sun.corba.se.impl.protocol.CorbaClientDelegateImpl.is_a(CorbaClientDelegateImpl.java:213)
at org.omg.CORBA.portable.ObjectImpl._is_a(ObjectImpl.java:112)
at weblogic.corba.j2ee.naming.Utils.narrowContext(Utils.java:126)
at weblogic.corba.j2ee.naming.InitialContextFactoryImpl.getInitialContext(InitialContextFactoryImpl.java:94)
at weblogic.corba.j2ee.naming.InitialContextFactoryImpl.getInitialContext(InitialContextFactoryImpl.java:31)
at weblogic.jndi.WLInitialContextFactory.getInitialContext(WLInitialContextFactory.java:41)
at javax.naming.spi.NamingManager.getInitialContext(NamingManager.java:667)
at javax.naming.InitialContext.getDefaultInitCtx(InitialContext.java:288)
at javax.naming.InitialContext.init(InitialContext.java:223)
at javax.naming.InitialContext.<init>(InitialContext.java:197)

Possible fix
---------------------

A try/finally clause was added to the purgeCalls method in com.sun.corba.se.impl.transport.SocketOrChannelConnectionImpl.java at line 1495 (using latest OpenJDK version) with the finally part containing the cache remove code. The changed code has been attached. Note that this will handle all exceptions but will leave a connection in an inconsistent state if the socket blocks on close however this should not happen as they are all asynchronous.



