/*
 *  SimpleHTTPProtocol.m
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

#import "SimpleHTTPProtocol.h"

#import "TPControlHelper.h"



/*
** Prototypes
*/
#pragma mark - Prototypes

static size_t write_callback(char *ptr, size_t size, size_t nmemb, void *userdata);
static size_t header_callback(char *buffer, size_t size, size_t nitems, void *userdata);



/*
** SimpleHTTPProtocol - Private
*/
#pragma mark SimpleHTTPProtocol - Private

@interface SimpleHTTPProtocol () <NSStreamDelegate>


@end



/*
** SimpleHTTPProtocol
*/
#pragma mark SimpleHTTPProtocol

@implementation SimpleHTTPProtocol

/*
** SimpleHTTPProtocol - NSObject
*/
#pragma mark SimpleHTTPProtocol  - NSObject

+ (void)initialize
{
	// stupid & unsafe, but we don't have choice.

	static dispatch_once_t onceToken;
	
	dispatch_once(&onceToken, ^{
		curl_global_init(CURL_GLOBAL_ALL);
	});
}

/*
** SimpleHTTPProtocol - Registering
*/
#pragma mark SimpleHTTPProtocol  - Registering

+ (void)registerClass
{
	[NSURLProtocol registerClass:self];
}

+ (void)unregisterClass
{
	[NSURLProtocol unregisterClass:self];
}



/*
** SimpleHTTPProtocol - NSURLProtocol
*/
#pragma mark SimpleHTTPProtocol  - NSURLProtocol

#pragma mark Properties

+ (BOOL)canInitWithRequest:(NSURLRequest *)request
{
	NSString *scheme = request.URL.scheme;
	
	return (([scheme compare:@"http" options:NSCaseInsensitiveSearch] == NSOrderedSame) || ([scheme compare:@"https" options:NSCaseInsensitiveSearch] == NSOrderedSame));
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
	return request;
}

#pragma mark Instance

- (id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id < NSURLProtocolClient >)client
{
	self = [super initWithRequest:request cachedResponse:cachedResponse client:client];
	
	if (self)
	{
		_curl = curl_easy_init();
		
		if (!_curl)
			return nil;
		
		curl_easy_setopt(_curl, CURLOPT_URL, request.URL.absoluteString.UTF8String);
		
		curl_easy_setopt(_curl, CURLOPT_FOLLOWLOCATION, 1L);
		curl_easy_setopt(_curl, CURLOPT_HEADER, 0L);
		
		// Method.
		NSString *method = request.HTTPMethod;
		
		if ([[method uppercaseString] isEqualToString:@"GET"])
			curl_easy_setopt(_curl, CURLOPT_HTTPGET, 1L);
		else if ([[method uppercaseString] isEqualToString:@"POST"])
			 curl_easy_setopt(_curl, CURLOPT_POST, 1L);
		else if ([[method uppercaseString] isEqualToString:@"PUT"])
			curl_easy_setopt(_curl, CURLOPT_PUT, 1L);
		
		// Proxy.
		char buffer[1024] = { 0 };
		
		if (tpcontrol_get_url_config(buffer))
		{
			TPLogDebug(@"Use proxy '%s'", buffer);
			curl_easy_setopt(_curl, CURLOPT_PROXY, buffer);
			curl_easy_setopt(_curl, CURLOPT_NOPROXY, "localhost,127.0.0.0"); // stupid: no-proxy is not based on IP & IP range, but on hostname...
		}
		
		// Headers.
		NSDictionary *headers = request.allHTTPHeaderFields;
		
		for (NSString *key in headers)
		{
			NSString *value = headers[key];
			NSString *raw = [NSString stringWithFormat:@"%@: %@", key, value];
			
			_chunk = curl_slist_append(_chunk, raw.UTF8String);
		}
		
		if (_chunk)
			curl_easy_setopt(_curl, CURLOPT_HTTPHEADER, _chunk);
		
		// Set body.
		NSData *body = request.HTTPBody;
		
		if (body)
		{
			curl_easy_setopt(_curl, CURLOPT_POSTFIELDSIZE, (long)[body length]);
			curl_easy_setopt(_curl, CURLOPT_COPYPOSTFIELDS, [body bytes]);
		}
		
		// Callback.
		curl_easy_setopt(_curl, CURLOPT_HEADERFUNCTION, header_callback);
		curl_easy_setopt(_curl, CURLOPT_HEADERDATA, (__bridge void *)self);

		curl_easy_setopt(_curl, CURLOPT_WRITEFUNCTION, write_callback);
		curl_easy_setopt(_curl, CURLOPT_WRITEDATA, (__bridge void *)self);
	}
	
	return self;
}

- (void)dealloc
{
	if (_curl)
		curl_easy_cleanup(_curl);
	
	if (_chunk)
		curl_slist_free_all(_chunk);
}


#pragma mark Loading

- (void)startLoading
{
	TPLogDebug("startLoading: request = '%@'", self.request.URL);
	
	[NSThread detachNewThreadSelector:@selector(curlThread:) toTarget:self withObject:nil];
}

- (void)stopLoading
{
	TPLogDebug("stopLoading: request = %@", self.request.URL);

	_canceled = YES;
}



/*
** SimpleHTTPProtocol - Curl
*/
#pragma mark SimpleHTTPProtocol  - Curl

#pragma mark Thread

- (void)curlThread:(id)ctx
{
	int res = curl_easy_perform(_curl);
	
	if (res != CURLE_OK)
	{
		NSError *error = [NSError errorWithDomain:@"SimpleHTTPProtocol" code:res userInfo:@{ @"curl" : [NSString stringWithFormat:@"curl_easy_perform() failed: %s", curl_easy_strerror(res)] }];
		
		[self.client URLProtocol:self didFailWithError:error];
	}
	else
	{
		[self.client URLProtocolDidFinishLoading:self];
	}
}


#pragma mark Callbacks

static size_t write_callback(char *ptr, size_t size, size_t nmemb, void *userdata)
{
	SimpleHTTPProtocol *http = (__bridge SimpleHTTPProtocol *)userdata;
	
	if (!ptr)
		return 0;
	
	if (http->_canceled)
		return 0;
	
	if (http->_headerHandled == NO)
	{
		// Prepare response.
		NSURL *url = http.request.URL;
		
		if (http->_httpVersion == nil)
			http->_httpVersion = @"HTTP/1.1";
		
		// Give response.
		NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:http->_httpCode HTTPVersion:http->_httpVersion headerFields:http->_headers];
		
		[http.client URLProtocol:http didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
		
		http->_headerHandled = YES;
	}
	
	// Give data.
	[http.client URLProtocol:http didLoadData:[NSData dataWithBytes:ptr length:(size * nmemb)]];
	
	return (nmemb * size);
}

static size_t header_callback(char *buffer, size_t size, size_t nitems, void *userdata)
{
	SimpleHTTPProtocol *http = (__bridge SimpleHTTPProtocol *)userdata;
	
	if (!buffer)
		return 0;
	
	if (http->_canceled)
		return 0;
	
	NSString *header = [[NSString alloc] initWithBytes:buffer length:(size * nitems) encoding:NSUTF8StringEncoding];
	
	if (http->_firstHeaderHandled == NO)
	{
		static NSRegularExpression	*regexp;
		static dispatch_once_t		onceToken;
		
		dispatch_once(&onceToken, ^{
			regexp = [NSRegularExpression regularExpressionWithPattern:@"([^ \t]+)[ \t]+([0-9]+)" options:0 error:nil];
		});
		
		[regexp enumerateMatchesInString:header options:0 range:NSMakeRange(0, header.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
			
			if ([result numberOfRanges] != 3)
				return;
			
			http->_httpVersion = [header substringWithRange:[result rangeAtIndex:1]];
			http->_httpCode = [[header substringWithRange:[result rangeAtIndex:2]] intValue];
		}];
		
		http->_firstHeaderHandled = YES;
	}
	else
	{
		static NSRegularExpression	*regexp;
		static dispatch_once_t		onceToken;
		
		dispatch_once(&onceToken, ^{
			regexp = [NSRegularExpression regularExpressionWithPattern:@"([^: \t]+)[ \t]*:[ \t]*(.*)" options:0 error:nil];
		});
		
		if (http->_headers == nil)
			http->_headers = [[NSMutableDictionary alloc] init];
		
		[regexp enumerateMatchesInString:header options:0 range:NSMakeRange(0, header.length) usingBlock:^(NSTextCheckingResult * _Nullable result, NSMatchingFlags flags, BOOL * _Nonnull stop) {
			
			if ([result numberOfRanges] != 3)
				return;
			
			NSString *key = [header substringWithRange:[result rangeAtIndex:1]];
			NSString *value = [[header substringWithRange:[result rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
			
			http->_headers[key] = value;
		}];
	}
	
	return nitems * size;
}

@end
