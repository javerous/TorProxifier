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
	dispatch_queue_t	_externQueue;

	NSTask				*_task;
	
	NSUInteger	_launchStep;
	NSString	*_launchError;
	void (^_launchUpdateHandler)(TPProcess * _Nonnull, double);
}


/*
** TPProcess - Instance
*/
#pragma mark - TPProcess - Instance

- (instancetype)initWithPath:(NSString *)path
{
	self = [super init];
	
	if (self)
	{
		NSAssert(path, @"path is nil");
		
		_localQueue = dispatch_queue_create("com.sourcemac.torproxifier.process.local", DISPATCH_QUEUE_SERIAL);
		_externQueue = dispatch_queue_create("com.sourcemac.torproxifier.process.extern", DISPATCH_QUEUE_SERIAL);

		
		_path = path;
		_icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
		_name = [[NSFileManager defaultManager] displayNameAtPath:path];
	}
	
	return self;
}



/*
** TPProcess - Life
*/
#pragma mark - TPProcess - Life

- (void)launchWithInjectedLibraries:(nullable NSArray *)libraries
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
		
		if ([libraries count] > 0)
		{
			NSString *insertEnv = [libraries componentsJoinedByString:@":"];

			environment[@"DYLD_INSERT_LIBRARIES"] = insertEnv;
			environment[@"DYLD_FORCE_FLAT_NAMESPACE"] = @"1";
		}
		
		TPLogDebug(@"Process environment: '%@'", environment);
		
		[_task setEnvironment:environment];
		
		_task.terminationHandler = ^(NSTask *task) {
			
			TPProcess *strongSelf = weakSelf;
			
			if (!strongSelf)
				return;
			
			[strongSelf handleTerminationFromUserAction:NO];
		};
		
		@try {
			[_task launch];
		} @catch (NSException *exception) {
			[self handleTerminationFromUserAction:NO];
		}
	});
}

- (void)terminate
{
	dispatch_async(_localQueue, ^{
		if (_task.running)
			[_task terminate];
		else
			[self handleTerminationFromUserAction:YES];
	});
}



/*
** TPProcess - Steps
*/
#pragma mark - Steps

- (void)launchStepping
{
	dispatch_async(_localQueue, ^{

		if (_launchStep + 1 > _launchSteps)
			return;
		
		_launchStep++;
		
		[self handleLaunchProgress:((double)_launchStep / (double)_launchSteps)];
	});
}

- (void)handleLaunchProgress:(double)progress
{
	if (progress < 0.0 || progress > 1.0)
		return;
	
	dispatch_async(_externQueue, ^{
		
		void (^launchProgressHandler)(TPProcess *process, double progress) = self.launchProgressHandler;
		
		if (launchProgressHandler)
			launchProgressHandler(self, progress);
	});
}

- (void)setLaunchProgressHandler:(void (^)(TPProcess * _Nonnull, double))launchProgressHandler
{
	dispatch_async(_localQueue, ^{
		
		_launchUpdateHandler = launchProgressHandler;
		
		if (_launchSteps > 0)
			[self handleLaunchProgress:((double)_launchStep / (double)_launchSteps)];
		else
			[self handleLaunchProgress:0.0];
	});
}

- (void (^)(TPProcess * _Nonnull, double))launchProgressHandler
{
	__block void (^result)(TPProcess * _Nonnull, double);
	
	
	dispatch_sync(_localQueue, ^{
		result = _launchUpdateHandler;
	});
	
	return result;
}



/*
** TPProcess - Properties
*/
#pragma mark - TPProcess - Properties

#pragma mark Process

- (pid_t)pid
{
	__block pid_t pid;
	
	dispatch_sync(_localQueue, ^{
		pid = [_task processIdentifier];
	});
	
	return pid;
}


#pragma mark Launch Error

- (NSString *)launchError
{
	__block NSString *error;
	
	dispatch_sync(_localQueue, ^{
		error = _launchError;
	});
	
	return error;
}

- (void)setLaunchError:(NSString *)error
{
	if (!error)
		return;
	
	dispatch_async(_localQueue, ^{
		_launchError = error;
		
		void (^launchErrorHandler)(TPProcess *process, NSString *error) = self.launchErrorHandler;
		
		if (launchErrorHandler)
			launchErrorHandler(self, error);
	});
}



/*
** TPProcess - Helpers
*/
#pragma mark - TPProcess - Helpers

- (void)handleTerminationFromUserAction:(BOOL)userAction
{
	// Clean task.
	dispatch_async(_localQueue, ^{
		_task = nil;
	});

	// Notify.
	void (^terminateHandler)(TPProcess *process, BOOL userAction) = self.terminateHandler;

	if (terminateHandler)
	{
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			terminateHandler(self, userAction);
		});
	}
}

@end


NS_ASSUME_NONNULL_END
