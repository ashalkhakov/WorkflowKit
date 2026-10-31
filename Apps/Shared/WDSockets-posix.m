/* WDSockets on POSIX: BSD sockets (WDSockets.h). */
#import "WDSockets.h"
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

WDSocket
WDSocketListenOnLoopback(uint16_t *port)
{
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	struct sockaddr_in address;
	memset(&address, 0, sizeof address);
	address.sin_family = AF_INET;
	address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	address.sin_port = 0;
	socklen_t length = sizeof address;
	if (fd < 0 || bind(fd, (struct sockaddr *)&address, sizeof address) != 0
	    || listen(fd, 4) != 0 || getsockname(fd, (struct sockaddr *)&address, &length) != 0) {
		if (fd >= 0) {
			int saved = errno;
			close(fd);
			errno = saved;
		}
		return WDInvalidSocket;
	}
	*port = ntohs(address.sin_port);
	return fd;
}

WDSocket
WDSocketAccept(WDSocket listener)
{
	int client = accept((int)listener, NULL, NULL);
	if (client < 0) {
		return WDInvalidSocket;
	}
#ifdef SO_NOSIGPIPE
	int on = 1;
	setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof on);
#endif
	return client;
}

int
WDSocketWaitReadable(WDSocket socket, int milliseconds)
{
	struct pollfd ready = { (int)socket, POLLIN, 0 };
	int count = poll(&ready, 1, milliseconds);
	if (count < 0) {
		return errno == EINTR ? 0 : -1;
	}
	return count > 0 ? 1 : 0;
}

ssize_t
WDSocketReceive(WDSocket socket, void *buffer, size_t length)
{
	return recv((int)socket, buffer, length, 0);
}

ssize_t
WDSocketSend(WDSocket socket, const void *bytes, size_t length)
{
#ifdef MSG_NOSIGNAL
	return send((int)socket, bytes, length, MSG_NOSIGNAL);
#else
	return send((int)socket, bytes, length, 0);
#endif
}

void
WDSocketClose(WDSocket socket)
{
	close((int)socket);
}

NSString *
WDSocketLastError(void)
{
	return [NSString stringWithUTF8String:strerror(errno)];
}
