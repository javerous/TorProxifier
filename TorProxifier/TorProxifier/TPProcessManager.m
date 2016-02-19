/*
 *  TPProcessManager.m
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

#import "TPProcessManager.h"

#import "TPProcess.h"


NS_ASSUME_NONNULL_BEGIN


/*
** TPProcessManager
*/
#pragma mark - TPProcessManager

@implementation TPProcessManager
{
	dispatch_queue_t	_localQueue;
	NSMutableArray		*_processes;
	
	NSString			*_socksHost;
	uint16_t			_socksPort;
	
	id <NSObject>		_terminationObserver;

}


/*
** TPProcessManager - Instance
*/
#pragma mark - TPProcessManager - Instance

- (instancetype)initWithSocksHost:(nullable NSString *)socksHost socksPort:(uint16_t)socksPort
{
	self = [super init];
	
	if (self)
	{
		// Init vars.
		_localQueue = dispatch_queue_create("com.sourcemac.torproxifier.process_manager.local", DISPATCH_QUEUE_SERIAL);
		
		_processes = [[NSMutableArray alloc] init];
		
		// Handle socks parameters.
		_socksHost = socksHost;
		_socksPort = socksPort;
		
		// Listen to termination.
		_terminationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
			dispatch_sync(_localQueue, ^{
				for (TPProcess *process in _processes)
					[process terminate];
			});
		}];
	}
	
	return self;
}

- (void)dealloc
{
	// Stop notification.
	[[NSNotificationCenter defaultCenter] removeObserver:_terminationObserver];
}




/*
** TPProcessManager - Launch
*/
#pragma mark - TPProcessManager - Launch

- (void)launchProcessWithPath:(NSString *)path
{
	NSAssert(path, @"path is nil");
	
	[self launchProcessesWithPaths:@[ path ]];
}

- (void)launchProcessesWithPaths:(NSArray *)paths
{
	NSAssert(paths, @"paths is nil");
	
	dispatch_async(_localQueue, ^{
		
		// Create processes.
		NSMutableArray *processes = [[NSMutableArray alloc] init];
		
		for (NSString *path in paths)
		{
			TPProcess *process = [[TPProcess alloc] initWithPath:path socksHost:_socksHost socksPort:_socksPort];
			
			if (!process)
				continue;
			
			process.terminateHandler = ^(TPProcess *aProcess) {
				[self handleTerminale:aProcess];
			};
			
			[processes addObject:process];
		}
		
		// Add to list of process.
		[_processes addObjectsFromArray:processes];

		// Give List to user.
		void (^processesChangeHandler)(NSArray *processes, TPProcessChange change) = self.processesChangeHandler;
		
		if (processesChangeHandler)
			processesChangeHandler(processes, TPProcessChangeCreated);

		// Launch then.
		for (TPProcess *process in processes)
			[process launch];
	});
}



/*
** TPProcessManager - Helpers
*/
#pragma mark - TPProcessManager - Helpers

- (void)handleTerminale:(TPProcess *)process
{
	NSAssert(process, @"process is nil");
	
	dispatch_async(_localQueue, ^{

		// Remove process.
		NSUInteger index = [_processes indexOfObject:process];
		
		if (index == NSNotFound)
			return;
		
		[_processes removeObjectAtIndex:index];
		
		// Notify remove.
		void (^processesChangeHandler)(NSArray *processes, TPProcessChange change) = self.processesChangeHandler;
		
		if (processesChangeHandler)
			processesChangeHandler(@[ process ], TPProcessChangeRemoved);
	});
}

@end


NS_ASSUME_NONNULL_END

