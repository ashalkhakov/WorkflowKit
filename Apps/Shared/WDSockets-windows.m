/* WDSockets on Windows: Winsock (WDSockets.h). Started on first use (signing
 * in, which listens, holds a lock while it does); no SIGPIPE to keep away. */
#import "WDSockets.h"
#include <winsock2.h>
#include <ws2tcpip.h>

static void
WDSocketsStart(void)
{
	static BOOL started;
	if (!started) {
		WSADATA data;
		started = WSAStartup(MAKEWORD(2, 2), &data) == 0;
	}
}

WDSocket
WDSocketListenOnLoopback(uint16_t *port)
{
	WDSocketsStart();
	SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
	struct sockaddr_in address;
	memset(&address, 0, sizeof address);
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address.sin_port = 0;
	int length = sizeof address;
	if (s == INVALID_SOCKET || bind(s, (struct sockaddr *)&address, sizeof address) != 0
	    || listen(s, 4) != 0 || getsockname(s, (struct sockaddr *)&address, &length) != 0) {
		if (s != INVALID_SOCKET) {
			int saved = WSAGetLastError();
			closesocket(s);
			WSASetLastError(saved);
		}
		return WDInvalidSocket;
	}
	*port = ntohs(address.sin_port);
	return (WDSocket)s;
}

WDSocket
WDSocketAccept(WDSocket listener)
{
	SOCKET client = accept((SOCKET)listener, NULL, NULL);
	return client == INVALID_SOCKET ? WDInvalidSocket : (WDSocket)client;
}

int
WDSocketWaitReadable(WDSocket socket, int milliseconds)
{
	WSAPOLLFD ready = { (SOCKET)socket, POLLRDNORM, 0 };
	int count = WSAPoll(&ready, 1, milliseconds);
	if (count == SOCKET_ERROR) {
		return WSAGetLastError() == WSAEINTR ? 0 : -1;
	}
	return count > 0 ? 1 : 0;
}

ssize_t
WDSocketReceive(WDSocket socket, void *buffer, size_t length)
{
	int count = recv((SOCKET)socket, buffer, (int)length, 0);
	return count == SOCKET_ERROR ? -1 : count;
}

ssize_t
WDSocketSend(WDSocket socket, const void *bytes, size_t length)
{
	int sent = send((SOCKET)socket, bytes, (int)length, 0);
	return sent == SOCKET_ERROR ? -1 : sent;
}

void
WDSocketClose(WDSocket socket)
{
	closesocket((SOCKET)socket);
}

NSString *
WDSocketLastError(void)
{
	return [NSString stringWithFormat:@"Winsock error %d", WSAGetLastError()];
}
