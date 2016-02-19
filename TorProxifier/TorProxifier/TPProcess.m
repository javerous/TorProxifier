/*
 *  TPProcess.m
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

@import Cocoa;

#import "TPProcess.h"


NS_ASSUME_NONNULL_BEGIN


/*
** TPProcess
*/
#pragma mark - TPProcess

@implementation TPProcess
{
	dispatch_queue_t	_localQueue;
	NSTask				*_task;
	
	NSString			*_socksHost;
	uint16_t			_socksPort;
}


/*
** TPProcess - Instance
*/
#pragma mark - TPProcess - Instance

- (instancetype)initWithPath:(NSString *)path socksHost:(nullable NSString *)socksHost socksPort:(uint16_t)socksPort
{
	self = [super init];
	
	if (self)
	{
		NSAssert(path, @"path is nil");
		
		_localQueue = dispatch_queue_create("com.sourcemac.torproxifier.process.local", DISPATCH_QUEUE_SERIAL);
		
		_path = path;
		_icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
		_name = [[NSFileManager defaultManager] displayNameAtPath:path];
		
		_socksHost = socksHost;
		_socksPort = socksPort;
	}
	
	return self;
}



/*
** TPProcess - Life
*/
#pragma mark - TPProcess - Life

- (void)launch
{
	__weak TPProcess *weakSelf = self;
	
	dispatch_async(_localQueue, ^{

		if (_task)
			return;
		
		// Get final path.
		NSString *binPath = nil;
		NSBundle *bundle = [NSBundle bundleWithPath:_path];
		
		if (bundle)
			binPath = [bundle executablePath];
		
		if (!binPath)
			binPath = _path;
			
		// Create task.
		NSMutableDictionary *environment = [NSMutableDictionary dictionary];
		
		_task = [[NSTask alloc] init];

		[_task setLaunchPath:binPath];
		
		if (_socksHost)
		{
			// > Get liburlhook path.
			NSString *liburlhookPath = [[NSBundle mainBundle] pathForResource:@"liburlhook" ofType:@"dylib"];
			
			if (!liburlhookPath)
			{
				[self handleTermination];
				return;
			}
			
			// > Get libtsocks path.
			NSString *libtsocksPath = [[NSBundle mainBundle] pathForResource:@"libtsocks" ofType:@"dylib"];
			
			if (!libtsocksPath)
			{
				[self handleTermination];
				return;
			}
			
			// > Build environment.
			// >> tsocks.
			NSMutableString *tsocksConf = [[NSMutableString alloc] init];
			
			[tsocksConf appendFormat:@"local = 127.0.0.0/255.0.0.0\n"];
			[tsocksConf appendFormat:@"server = %@\n", _socksHost];
			[tsocksConf appendFormat:@"server_port = %u\n", _socksPort];
			[tsocksConf appendFormat:@"server_type = 4\n"];

			environment[@"TSOCKS_CONF_DATA"] = tsocksConf;

			// >> urlhook.
			environment[@"URL_PROTOCOL_PROXY"] = [NSString stringWithFormat:@"socks4a://%@:%u", _socksHost, _socksPort];
			
			environment[@"URL_SESSION_PROXY_HOST"] = _socksHost;
			environment[@"URL_SESSION_PROXY_PORT"] = @(_socksPort);
			
			// >> dyld.
			environment[@"DYLD_INSERT_LIBRARIES"] = [NSString stringWithFormat:@"%@:%@", liburlhookPath, libtsocksPath];
			environment[@"DYLD_FORCE_FLAT_NAMESPACE"] = @"1";
		}
		
#if defined(DEBUG) && DEBUG
		NSLog(@"env: '%@'", environment);
#endif
		
		[_task setEnvironment:environment];
		
		_task.terminationHandler = ^(NSTask *task) {
			
			TPProcess *strongSelf = weakSelf;
			
			if (!strongSelf)
				return;
			
			[strongSelf handleTermination];
		};
		
		@try {
			[_task launch];
		} @catch (NSException *exception) {
			[self handleTermination];
		}
	});
}

- (void)terminate
{
	dispatch_async(_localQueue, ^{
		[_task terminate];
	});
}



/*
** TPProcess - Helpers
*/
#pragma mark - TPProcess - Helpers

- (void)handleTermination
{
	// Clean task.
	dispatch_async(_localQueue, ^{
		_task = nil;
	});
	
	// Notify.
	void (^terminateHandler)(TPProcess *process) = self.terminateHandler;

	if (terminateHandler)
	{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			terminateHandler(self);
		});
	}
}

@end


NS_ASSUME_NONNULL_END
