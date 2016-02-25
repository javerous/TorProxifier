/*
 *  urlhook.m
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

@import Foundation;
@import ObjectiveC.runtime;

#import <asl.h>

#import "SimpleHTTPProtocol.h"


/*
** Privates
*/
#pragma mark - Privates

@interface NSURLSessionConfiguration (Private)

+ (NSArray *)_defaultProtocolClasses;

@end



/*
** Hooks
*/
#pragma mark - Hooks

// Hook for defaults protocols method.
static NSArray * (*original_NSURLSessionConfiguration_defaultProtocolClasses)(Class self, SEL _cmd);

NSArray *replaced_NSURLSessionConfiguration_defaultProtocolClasses(Class self, SEL _cmd)
{
	NSArray *classes = original_NSURLSessionConfiguration_defaultProtocolClasses(self, _cmd);
	
	if (classes)
	{
		NSMutableArray	*hooked = [classes mutableCopy];
		NSUInteger		i, count = [hooked count];
		NSURLRequest	*fakeRequestHTTP = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://fakre_request.org"]];
		NSURLRequest	*fakeRequestHTTPS = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:@"https://fakre_request.org"]];

		for (i = 0; i < count; i++)
		{
			id item = hooked[i];
			
			if ([[item class] respondsToSelector:@selector(canInitWithRequest:)] == NO)
				continue;
			
			if ([[item class] canInitWithRequest:fakeRequestHTTP] || [[item class] canInitWithRequest:fakeRequestHTTPS])
				hooked[i] = [SimpleHTTPProtocol class];
		}
		
		classes = [hooked copy];
	}
	
	TPLogDebug(@"Default protocols: %@", classes);
	
	return classes;
}



/*
** "Constructor" class
*/
#pragma mark - "Constructor" class

@interface TPClass : NSObject
@end


@implementation TPClass

+ (void)load
{
	fprintf(stderr, "****** httphook loaded ******\n");
	
	// Redirect NSURL* HTTP requests.
	[SimpleHTTPProtocol registerClass];
	
	// Hook [NSURLSessionConfiguration _defaultProtocolClasse] to replace APple HTTP protocol by hour protocol. An alternative solution would be to hook connectionProxyDictionary of __NSCFURLSessionConfiguration.
	Method NSURLSessionConfiguration_connectionProxyDictionary = class_getClassMethod([NSURLSessionConfiguration class], @selector(_defaultProtocolClasses));
	
	original_NSURLSessionConfiguration_defaultProtocolClasses = (void *)method_setImplementation(NSURLSessionConfiguration_connectionProxyDictionary, (IMP)replaced_NSURLSessionConfiguration_defaultProtocolClasses);
}

@end
