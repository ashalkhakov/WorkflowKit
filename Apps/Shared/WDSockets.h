/* WDSockets: the few socket calls signing in needs (WDSignIn.m's loopback
 * listener, where the browser returns), one file for each kind of system:
 * WDSockets-posix.m (BSD sockets: macOS, Linux) and WDSockets-windows.m
 * (Winsock). The GNUmakefiles name the POSIX file and take the Windows one in
 * its place there; the Xcode project, written from them, compiles the POSIX
 * one. */
#import <Foundation/Foundation.h>

/* A socket: a descriptor on POSIX, a SOCKET on Windows, either of which fits. */
typedef intptr_t WDSocket;
#define WDInvalidSocket ((WDSocket)-1)

/* A socket listening on 127.0.0.1, on a port the system picks (*port), or
 * WDInvalidSocket. */
WDSocket WDSocketListenOnLoopback(uint16_t *port);
/* A connection the listener took, or WDInvalidSocket. */
WDSocket WDSocketAccept(WDSocket listener);
/* Whether the socket can be read within milliseconds: 1 yes, 0 not yet, -1
 * an error (an interruption counts as not yet). */
int WDSocketWaitReadable(WDSocket socket, int milliseconds);
/* recv(2) and send(2), sending no SIGPIPE where a system would. */
ssize_t WDSocketReceive(WDSocket socket, void *buffer, size_t length);
ssize_t WDSocketSend(WDSocket socket, const void *bytes, size_t length);
void WDSocketClose(WDSocket socket);
/* The last socket call's error, as words. */
NSString *WDSocketLastError(void);
