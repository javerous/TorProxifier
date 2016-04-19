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
@import Darwin.POSIX.spawn;

#import <libproc.h>

#include <sys/sysctl.h>

#import "TPProcess.h"


NS_ASSUME_NONNULL_BEGIN


/*
** Prototypes
*/
#pragma mark - Prototypes

// Apple private
#define	CS_OPS_STATUS	0			/* return status */
#define CS_RESTRICT		0x0000800	/* tell dyld to treat restricted */

int csops(pid_t pid, unsigned int ops, void * useraddr, size_t usersize);



/*
** TPProcess
*/
#pragma mark - TPProcessglobal

@implementation TPProcess
{
	dispatch_queue_t	_localQueue;
	dispatch_queue_t	_externQueue;

	NSNumber			*_pid;
	dispatch_source_t	_pidWatcher;
	
	NSUInteger	_launchStep;
	NSString	*_launchError;
	void (^_launchProgressHandler)(TPProcess * _Nonnull, double);
	void (^_launchErrorHandler)(TPProcess * _Nonnull, NSString * _Nonnull);

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

		if (_pid)
			return;
		
		// Get final path.
		NSString *binPath = nil;
		NSBundle *bundle = [NSBundle bundleWithPath:_path];
		
		if (bundle)
			binPath = [bundle executablePath];
		
		if (!binPath)
			binPath = _path;
			
		// Create environment.
		NSMutableDictionary *environment = [NSMutableDictionary dictionary];
		const char			*envp[] = { NULL, NULL, NULL };
		
		if ([libraries count] > 0)
		{
			envp[0] = [NSString stringWithFormat:@"DYLD_INSERT_LIBRARIES=%@", [libraries componentsJoinedByString:@":"]].UTF8String;
			envp[1] = "DYLD_FORCE_FLAT_NAMESPACE=1";
		}
		
		TPLogDebug(@"Process environment: '%@'", environment);
		
		// Spawn the process.
		posix_spawnattr_t	attr;
		pid_t				pid;
		const char			*argv[] = { binPath.fileSystemRepresentation, NULL };
		int					result;
		
		posix_spawnattr_init(&attr);
		posix_spawnattr_setflags (&attr, POSIX_SPAWN_START_SUSPENDED);

		result = posix_spawn(&pid, binPath.fileSystemRepresentation, NULL, &attr, (char * const *)argv, (char * const *)envp);
		
		posix_spawnattr_destroy (&attr);
		
		if (result != 0)
		{
			[self handleTerminationFromUserAction:NO];
			return;
		}

		// Check if it's a restricted process.
		uint32_t flags;

		if (csops(pid, CS_OPS_STATUS, &flags, sizeof(flags)) != -1 && (flags & CS_RESTRICT))
		{
			// Process is restricted, so we can't inject our lib. There is 3 possibles reason to this restriction:
			//  - Restricted entitlement
			//  - setuid
			//  - Presence of __RESTRICT,__restrict section in the Mach-O.
			//
			// For the entitlement, it's possible to ask taskgated to don't enforce CS_RESTRICT by editing "/Library/Preferences/com.apple.security.coderequirements.plist" file, and set AllowUnsafeDynamicLinking to YES.
			
			TPLogDebug(@"Process is restricted !");
			
			self.launchError = NSLocalizedString(@"process_err_restricted", @"");
			
			// We have to resume before kill. That's stupid, but else we lock the process.
			kill(pid, SIGCONT);
			kill(pid, SIGKILL);

			[self handleTerminationFromUserAction:NO];
			
			return;
		}
		
		// Resume our process.
		kill(pid, SIGCONT);
		
		// Monitor exit.
		_pidWatcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, _localQueue);
		
		dispatch_source_set_event_handler(_pidWatcher, ^{
			
			TPProcess *strongSelf = weakSelf;
			
			if (!strongSelf)
				return;
			
			// Cancel.
			dispatch_source_cancel(strongSelf->_pidWatcher);
			
			strongSelf->_pidWatcher = nil;
			strongSelf->_pid = nil;
			
			// Notify.
			[strongSelf handleTerminationFromUserAction:NO];
		});
		
		dispatch_resume(_pidWatcher);
		
		// Handle pid.
		_pid = @(pid);
	});
}

- (void)terminate
{
	dispatch_async(_localQueue, ^{
		
		if (_pid)
			kill(_pid.intValue, SIGKILL);
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

		// Check border.
		if (_launchStep + 1 > _launchSteps)
			return;
		
		// Increase step.
		_launchStep++;

		// Notify.
		void (^launchProgressHandler)(TPProcess *process, double progress) = _launchProgressHandler;
		double progress = (double)_launchStep / (double)_launchSteps;
		
		if (launchProgressHandler && progress >= 0 && progress <= 1.0)
			dispatch_async(_externQueue, ^{ launchProgressHandler(self, progress); });
	});
}



/*
** TPProcess - Parent
*/
#pragma mark - TPProcess - Parent

- (BOOL)parentOfPID:(pid_t)pid
{
	// XXX perhaps we can use a cache. The problem with a cache is to clean it, because pid can cycle.
	
	pid_t rpid = self.pid;
	
	while (1)
	{
		pid = [[self class] PPIDForPID:pid];
		
		if (pid <= 0)
			return NO;
		
		if (pid == rpid)
			return YES;
	}
	
	return NO;
}

+ (pid_t)PPIDForPID:(pid_t)pid
{
	struct kinfo_proc info;
	size_t	length = sizeof(struct kinfo_proc);
	int		mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
	
	if (sysctl(mib, 4, &info, &length, NULL, 0) < 0)
		return -1;
	
	if (length == 0)
		return -1;
	
	return info.kp_eproc.e_ppid;
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
		if (_pid)
			pid = [_pid intValue];
		else
			pid = -1;
	});
	
	return pid;
}


#pragma mark Launch Progress Handler

- (void)setLaunchProgressHandler:(void (^)(TPProcess * _Nonnull, double))launchProgressHandler
{
	dispatch_async(_localQueue, ^{
		
		_launchProgressHandler = launchProgressHandler;
		
		if (launchProgressHandler)
		{
			double progress;
			
			if (_launchSteps > 0)
				progress = (double)_launchStep / (double)_launchSteps;
			else
				progress = 0.0;
			
			if (progress >= 0.0 && progress <= 1.0)
				dispatch_async(_externQueue, ^{ launchProgressHandler(self, progress); });
		}
	});
}

- (void (^)(TPProcess * _Nonnull, double))launchProgressHandler
{
	__block void (^result)(TPProcess * _Nonnull, double);
	
	dispatch_sync(_localQueue, ^{
		result = _launchProgressHandler;
	});
	
	return result;
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
		
		// Handle error.
		_launchError = error;
		
		// Notify.
		void (^launchErrorHandler)(TPProcess *process, NSString *error) = _launchErrorHandler;

		if (launchErrorHandler && error)
			dispatch_async(_externQueue, ^{ launchErrorHandler(self, error); });
	});
}


#pragma mark Launch Error Handler

- (void)setLaunchErrorHandler:(void (^)(TPProcess * _Nonnull, NSString * _Nonnull))launchErrorHandler
{
	dispatch_async(_localQueue, ^{
		
		_launchErrorHandler = launchErrorHandler;
		
		if (launchErrorHandler && _launchError)
		{
			NSString *error = _launchError;
			
			dispatch_async(_externQueue, ^{ launchErrorHandler(self, error); });
		}
	});
}

- (void (^)(TPProcess * _Nonnull, NSString * _Nonnull))launchErrorHandler
{
	__block void (^result)(TPProcess * _Nonnull, NSString * _Nonnull);
	
	dispatch_sync(_localQueue, ^{
		result = _launchErrorHandler;
	});
	
	return result;
}



/*
** TPProcess - Helpers
*/
#pragma mark - TPProcess - Helpers

- (void)handleTerminationFromUserAction:(BOOL)userAction
{
	// Notify.
	void (^terminateHandler)(TPProcess *process, BOOL userAction) = self.terminateHandler;

	if (terminateHandler)
	{
		dispatch_async(_externQueue, ^{
			terminateHandler(self, userAction);
		});
	}
}

@end


NS_ASSUME_NONNULL_END
