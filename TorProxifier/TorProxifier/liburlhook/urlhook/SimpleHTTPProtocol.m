/*
 *  SimpleHTTPProtocol.m
 *
 *  Copyright 2018 Avérous Julien-Pierre
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
** Globals
*/
#pragma mark - Globals

static NSString	*gRequestKey = @"SimpleHTTPProtocol-key";
static NSString	*gRequestValue = @"SimpleHTTPProtocol-value";



/*
** SimpleHTTPProtocol - Private
*/
#pragma mark SimpleHTTPProtocol - Private

@interface SimpleHTTPProtocol () <NSURLSessionDataDelegate>
@end



/*
** SimpleHTTPProtocol
*/
#pragma mark SimpleHTTPProtocol

@implementation SimpleHTTPProtocol

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

	if (([scheme compare:@"http" options:NSCaseInsensitiveSearch] == NSOrderedSame) || ([scheme compare:@"https" options:NSCaseInsensitiveSearch] == NSOrderedSame))
	{
		// If we initiated this request, then forward to next protocol able to handle HTTP.
		if ([NSURLProtocol propertyForKey:gRequestKey inRequest:request])
		{
			TPLogDebug("canInitWithRequest: forwarding request = %@", request.URL);
			return NO;
		}
		
		return YES;
	}

	return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request
{
	return request;
}


#pragma mark Loading

- (void)startLoading
{
	TPLogDebug("startLoading: request = %@", self.request.URL);

	// Mark this request as being initiated by ourself.
	NSMutableURLRequest *request = self.request.mutableCopy;
	
	[NSURLProtocol setProperty:gRequestValue forKey:gRequestKey inRequest:request];
	
	// Create a proxified session configuration.
	NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
	
	sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
	
	// > Set proxy.
	char buffer[1024] = { 0 };
	
	if (tpcontrol_get_url_config(buffer))
	{
		NSArray *components = [@(buffer) componentsSeparatedByString:@":"];
		
		if (components.count == 2)
		{
			NSString *socksHost = components[0];
			NSNumber *socksPort = @([components[1] intValue]);
			
			TPLogDebug(@"Use proxy '%s'", buffer);

			sessionConfiguration.connectionProxyDictionary = @{
				(__bridge id)kCFStreamPropertySOCKSVersion : (__bridge id)kCFStreamSocketSOCKSVersion5,
				(__bridge id)kCFStreamPropertySOCKSProxyHost : socksHost,
				(__bridge id)kCFStreamPropertySOCKSProxyPort : socksPort

				/*
				(__bridge id)kCFNetworkProxiesSOCKSEnable: @YES,
				(__bridge id)kCFNetworkProxiesSOCKSProxy : socksHost,
				(__bridge id)kCFNetworkProxiesSOCKSPort : socksPort,
				
				(__bridge id)kCFStreamPropertySOCKSProxyHost : socksHost,
				(__bridge id)kCFStreamPropertySOCKSProxyPort : socksPort
				*/
			};
		}
	}
	
	// Create session.
	_session = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:self delegateQueue:[NSOperationQueue currentQueue]];
	
	[[_session dataTaskWithRequest:request] resume];
}

- (void)stopLoading
{
	TPLogDebug("stopLoading: request = %@", self.request.URL);

	[_session invalidateAndCancel];
	_session = nil;
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
	[self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
	[self.client URLProtocol:self didLoadData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error
{
	if (error)
		[self.client URLProtocol:self didFailWithError:error];
	else
		[self.client URLProtocolDidFinishLoading:self];
}

@end
