/*
 *  TPNetwork.m
 *
 *  Copyright 2016 Avérous Julien-Pierre
 *
 *  This file is part of TorProxifier.
 *
 *  TorProxifier is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  TorProxifier is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with TorProxifier.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

@import Security;

#import <dispatch/dispatch.h>
#import <netdb.h>

#import "TPNetworkHelper.h"


/*
** NSURLConnection
*/
#pragma mark - NSURLConnection

NSData *data_with_url_connection(NSURLRequest *urlRequest)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	return [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:nil error:nil];
#pragma clang diagnostic pop
}



/*
** NSURLSession
*/
#pragma mark - NSURLSession

NSData *data_with_url_session(NSURLRequest *urlRequest)
{
	__block NSData				*result = nil;
	dispatch_semaphore_t		semaphore = dispatch_semaphore_create(0);
	NSURLSessionConfiguration	*config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	NSURLSession				*session = [NSURLSession sessionWithConfiguration:config];
	
	[[session dataTaskWithRequest:urlRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
		result = data;
		dispatch_semaphore_signal(semaphore);
	}] resume];
	
	dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
	
	return result;
}



/*
** Socket
*/
#pragma mark - Socket

#pragma mark Prototypes

OSStatus sslReadCall(SSLConnectionRef connection, void *data, size_t *dataLength);
OSStatus sslWriteCall(SSLConnectionRef connection, const void *data, size_t *dataLength);


#pragma mark Helper
// Inspired from ReactiveCocoa code.

static inline void _execBlock (__strong dispatch_block_t *block) {
	(*block)();
}

#define __concat_(A, B) A ## B
#define __concat(A, B) __concat_(A, B)

#define _onExit \
	__strong dispatch_block_t __concat(_exitBlock_, __LINE__) __attribute__((cleanup(_execBlock), unused)) = ^


#pragma mark Main

NSData *data_with_socket(NSURLRequest *urlRequest)
{
	// Extract info from request.
	NSURL		*url = urlRequest.URL;
	NSString	*host = url.host;
	NSString	*scheme = url.scheme;
	NSNumber	*port = url.port;
	NSString	*portStr;

	if (!host || !scheme)
		return nil;
	
	if (port)
		portStr = [port stringValue];
	else
	{
		if ([scheme isEqualToString:@"http"])
			portStr = @"80";
		else if ([scheme isEqualToString:@"https"])
			portStr = @"443";
		else
			return nil;
	}
	
	// Resolve host.
	struct addrinfo hints, *res, *res0 = NULL;
	int s = -1;
	
	memset(&hints, 0, sizeof(hints));
	
	hints.ai_flags = AI_NUMERICSERV;
	hints.ai_family = PF_INET;
	hints.ai_socktype = SOCK_STREAM;
	
	if (getaddrinfo(host.UTF8String, portStr.UTF8String, &hints, &res0) != 0)
		return nil;
	
	for (res = res0; res; res = res->ai_next)
	{
		s = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
		if (s < 0)
			continue;
		
		if (connect(s, res->ai_addr, res->ai_addrlen) < 0)
		{
			close(s);
			s = -1;
			continue;
		}
		
		break;
	}
	
	if (s < 0)
		return nil;
	
	// Cleaner.
	SSLContextRef	ctx = NULL;
	int				*sock = NULL;
	
	_onExit {
		if (ctx)
		{
			SSLClose(ctx);
			CFRelease(ctx);
		}
		
		if (sock)
			free(sock);
		
		if (s >= 0)
			close(s);
		
		if (res0)
			freeaddrinfo(res0);
	};
	
	// Prepare reader / writter.
	ssize_t (^lread)(char *buffer, size_t size) = nil;
	ssize_t (^lwrite)(const char *buffer, size_t size) = nil;

	if ([scheme isEqualToString:@"https"])
	{
		sock = malloc(sizeof(int));
		*sock = s;
		
		// > Configure.
		ctx = SSLCreateContext(kCFAllocatorDefault, kSSLClientSide, kSSLStreamType);
		
		if (!ctx)
			return nil;
		
		SSLSetIOFuncs(ctx, sslReadCall, sslWriteCall);
		SSLSetConnection(ctx, sock);
		SSLSetPeerDomainName(ctx, host.UTF8String, strlen(host.UTF8String));
		
		// > Handshake.
		if (SSLHandshake(ctx) != errSecSuccess)
			return nil;
		
		// > Set read / writter.
		lread = ^ ssize_t (char *buffer, size_t size) {
			
			size_t		processed = 0;
			OSStatus	status = SSLRead(ctx, buffer, size, &processed);
			
			if (status == errSecSuccess)
				return processed;
			else
				return -1;
		};
		
		lwrite = ^ ssize_t (const char *buffer, size_t size) {
			
			size_t		processed = 0;
			OSStatus	status = SSLWrite(ctx, buffer, size, &processed);
			
			if (status == errSecSuccess)
				return processed;
			else
				return -1;
		};
	}
	else
	{
		lread = ^ ssize_t (char *buffer, size_t size) { return recv(s, buffer, size, 0); };
		lwrite = ^ ssize_t (const char *buffer, size_t size) { return send(s, buffer, size, 0); };
	}
	
	// Forge request, and send it.
	NSString	*requestStr = [NSString stringWithFormat:@"GET %@ HTTP/1.0\r\nHost: %@\r\n\r\n", url.path, url.host];
	NSData		*requestData = [requestStr dataUsingEncoding:NSUTF8StringEncoding];

	if (lwrite(requestData.bytes, requestData.length) != requestData.length)
		return nil;
	
	// Read answer.
	NSMutableData *rdata = [[NSMutableData alloc] init];
	
	while (1)
	{
		char	buffer[1024];
		ssize_t	result = 0;
		
		result = lread(buffer, sizeof(buffer));
		
		if (result <= 0)
			break;

		[rdata appendBytes:buffer length:result];
	}
	
	if (rdata.length == 0)
		return nil;
	
	// Search empty line.
	NSRange		rg, rg1, rg2, rg3;
	char		sep1[] = { '\r', '\n', '\r', '\n' }, sep2[] = { '\n', '\n' }, sep3[] = { '\r', '\r' };
	
	rg1 = [rdata rangeOfData:[NSData dataWithBytes:&sep1 length:sizeof(sep1)] options:0 range:NSMakeRange(0, rdata.length)];
	rg2 = [rdata rangeOfData:[NSData dataWithBytes:&sep2 length:sizeof(sep2)] options:0 range:NSMakeRange(0, rdata.length)];
	rg3 = [rdata rangeOfData:[NSData dataWithBytes:&sep3 length:sizeof(sep3)] options:0 range:NSMakeRange(0, rdata.length)];

	if (rg1.location < rg2.location)
	{
		if (rg1.location < rg3.location)
			rg = rg1;
		else
			rg = rg3;
	}
	else
	{
		if (rg2.location < rg3.location)
			rg = rg2;
		else
			rg = rg3;
	}
	
	// Return body data.
	NSUInteger location = rg.location + rg.length;
	NSUInteger length = rdata.length - location;

	return [rdata subdataWithRange:NSMakeRange(location, length)];
}


#pragma mark Helpers

OSStatus sslReadCall(SSLConnectionRef connection, void *data, size_t *dataLength)
{
	const int	*sock = connection;
	size_t		length = *dataLength;
	
	while (length > 0)
	{
		ssize_t sz = recv(*sock, data, length, 0);
		
		if (sz < 0)
		{
			*dataLength = *dataLength - length;
			return errSSLClosedAbort;
		}
		else if (sz == 0)
		{
			*dataLength = *dataLength - length;
			return errSSLClosedGraceful;
		}
		else
		{
			data += sz;
			length -= sz;
		}
	}
	
	return errSecSuccess;
}

OSStatus sslWriteCall(SSLConnectionRef connection, const void *data, size_t *dataLength)
{
	const int	*sock = connection;
	size_t		length = *dataLength;
	
	while (length > 0)
	{
		ssize_t sz = send(*sock, data, length, 0);
		
		if (sz < 0)
		{
			*dataLength = *dataLength - length;
			return errSSLClosedAbort;
		}
		else if (sz == 0)
		{
			*dataLength = *dataLength - length;
			return errSSLClosedGraceful;
		}
		else
		{
			data += sz;
			length -= sz;
		}
	}
	
	return errSecSuccess;
}
