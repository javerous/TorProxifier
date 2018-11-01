/*
 *  TPProcessManager.m
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

#import <Cocoa/Cocoa.h>

#include <servers/bootstrap.h>
#include <bsm/libbsm.h>

#import "TPProcessManager.h"

#import "TPProcess.h"
#import "TPConfiguration.h"

#import "controlServer.h"


NS_ASSUME_NONNULL_BEGIN


/*
** Globals
*/
#pragma mark - Globals

static uint8_t managerKey = 0;



/*
** TPProcessManager
*/
#pragma mark - TPProcessManager

@implementation TPProcessManager
{
	dispatch_queue_t	_localQueue;
	NSMutableArray		*_processes;
	
	id <NSObject>		_terminationObserver;

	mach_port_t			_migPort;
	dispatch_source_t	_migSource;
	
	TPConfiguration		*_configuration;
}


/*
** TPProcessManager - Instance
*/
#pragma mark - TPProcessManager - Instance

- (instancetype)init
{
	self = [super init];
	
	if (self)
	{
		// Init vars.
		_localQueue = dispatch_queue_create("com.sourcemac.torproxifier.process_manager.local", DISPATCH_QUEUE_SERIAL);
		
		_processes = [[NSMutableArray alloc] init];

		// Listen to termination.
		_terminationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
			dispatch_sync(_localQueue, ^{
				for (TPProcess *process in _processes)
					[process terminate];
			});
		}];
		
		// Configure MIG.
		[self configureMIG];
	}
	
	return self;
}

- (void)dealloc
{
	// Stop notification.
	[[NSNotificationCenter defaultCenter] removeObserver:_terminationObserver];
}



/*
** TPProcessManager - Configuration
*/
#pragma mark - TPProcessManager - Configuration

- (void)setConfiguration:(nullable TPConfiguration *)configuration
{
	TPConfiguration *copy = [configuration copy];
	
	dispatch_async(_localQueue, ^{
		// XXX do we terminate process as they are configured with obsoletes parameters ?
		_configuration = copy;
	});
}

- (nullable TPConfiguration *)configuration
{
	__block TPConfiguration *copy;
	
	dispatch_sync(_localQueue, ^{
		copy = [[self _configuration] copy];
	});
	
	return copy;
}

- (nullable TPConfiguration *)_configuration
{
	// > localQueue <
	
	return _configuration;
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
			TPProcess *process = [[TPProcess alloc] initWithPath:path];
			
			if (!process)
				continue;
			
			process.launchSteps = 1;
			
			process.terminateHandler = ^(TPProcess *aProcess, BOOL userAction) {
				[self handleTerminale:aProcess userAction:userAction];
			};
			
			[processes addObject:process];
		}
		
		// Add to list of process.
		[_processes addObjectsFromArray:processes];

		// Give list to user.
		void (^processesChangeHandler)(NSArray *processes, TPProcessChange change) = self.processesChangeHandler;
		
		if (processesChangeHandler)
			processesChangeHandler(processes, TPProcessChangeCreated);

		// Launch then.
		for (TPProcess *process in processes)
			[process launchWithInjectedLibraries:[self injectedLibraries]];
	});
}



/*
** TPProcessManager - Helpers
*/
#pragma mark - TPProcessManager - Helpers

- (void)handleTerminale:(TPProcess *)process userAction:(BOOL)userAction
{
	NSAssert(process, @"process is nil");
	
	dispatch_async(_localQueue, ^{
		
		if (process.launchError && userAction == NO)
			return;

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

- (NSArray *)injectedLibraries
{
	static dispatch_once_t	onceToken;
	static NSMutableArray	*libs;
	
	dispatch_once(&onceToken, ^{
		
		libs = [[NSMutableArray alloc] init];
		
		// > urlhook
		NSString *liburlhookPath = [[NSBundle mainBundle] pathForResource:@"liburlhook" ofType:@"dylib"];
		
		if (liburlhookPath)
			[libs addObject:liburlhookPath];
		
		// > tsocks
		NSString *libtsocksPath = [[NSBundle mainBundle] pathForResource:@"libtsocks" ofType:@"dylib"];
		
		if (libtsocksPath)
			[libs addObject:libtsocksPath];
		
		// > control
		NSString *libcontrolPath = [[NSBundle mainBundle] pathForResource:@"libcontrol" ofType:@"dylib"];
		
		if (libcontrolPath)
			[libs addObject:libcontrolPath];
	});
	
	return libs;
}

- (BOOL)_isHandledPID:(pid_t)pid process:(TPProcess **)oprocess
{
	// > localQueue <
	
	for (TPProcess *process in _processes)
	{
		if (process.pid == pid)
		{
			if (oprocess)
				*oprocess = process;
			return YES;
		}
		
		if ([process parentOfPID:pid])
		{
			return YES;
		}
	}
	
#if defined(DEBUG) && DEBUG
	TPLogDebug(@"[MIG] invalid client - pid='%d'", pid);
	return YES;
#endif
	
	return NO;
}




/*
** TPProcessManager - MIG
*/
#pragma mark - TPProcessManager - MIG

#pragma Service
- (void)configureMIG
{
	kern_return_t	kr;
	name_t			name;
	
	// Check-in.
	strlcpy(name, TPControlServiceName, sizeof(name_t));
	
	kr = bootstrap_check_in(bootstrap_port, name, &_migPort);
	
	if (kr != KERN_SUCCESS)
	{
		NSLog(@"Can't check-in mach service");
		return;
	}
	
	// Configure queue.
	dispatch_queue_set_specific(_localQueue, &managerKey, (__bridge void *)self, NULL);
	
	// Get messages max size.
#pragma pack(4)
	typedef struct {
		mach_msg_header_t	Head;
		NDR_record_t		NDR;
	} mig_request_base_t;
#pragma pack()
	
	mach_msg_size_t maxRequestSize = (mach_msg_size_t)MAX(sizeof(mig_request_base_t), sizeof(union __RequestUnion__mig_server_mtp_subsystem)) + MAX_TRAILER_SIZE;
	mach_msg_size_t maxReplySize = (mach_msg_size_t)MAX(sizeof(mig_reply_error_t), sizeof(union __ReplyUnion__mig_server_mtp_subsystem)) + MAX_TRAILER_SIZE;

	// Create dispatch source.
	_migSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MACH_RECV, _migPort, 0, _localQueue);
	
	dispatch_source_set_event_handler(_migSource, ^{
		mach_msg_server_once(mtp_server, MAX(maxRequestSize, maxReplySize), _migPort, MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT) | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0));
	});
	
	dispatch_resume(_migSource);
}


#pragma mark Functions
kern_return_t mig_server_get_setting(mach_port_t port, audit_token_t audit, tp_key_t key, tp_value_t value)
{
	TPProcessManager	*manager = (__bridge TPProcessManager *)dispatch_get_specific(&managerKey);
	pid_t				pid = audit_token_to_pid(audit);
	TPProcess			*process = nil;
	
	// Check access.
	if ([manager _isHandledPID:pid process:&process] == NO)
		return KERN_NO_ACCESS;
	
	TPLogDebug(@"[MIG] 'get_setting': process asking for setting - pid=%d; key='%s'", pid, key);
	
	TPConfiguration *configuration = [manager _configuration];
	
	// Handle setting request.
	if (strcmp(key, "tsocks-config") == 0)
	{
		NSMutableString *tsocksConf = [[NSMutableString alloc] init];
		
		[tsocksConf appendFormat:@"local = 127.0.0.0/255.0.0.0\n"];
		[tsocksConf appendFormat:@"server = %@\n", configuration.socksHost];
		[tsocksConf appendFormat:@"server_port = %u\n", configuration.socksPort];
		[tsocksConf appendFormat:@"server_type = 5\n"];
		[tsocksConf appendFormat:@"default_user = no_user\n"];
		[tsocksConf appendFormat:@"default_pass = no_pass\n"];

		
		strlcpy(value, tsocksConf.UTF8String, sizeof(tp_value_t));
		
		return KERN_SUCCESS;
	}
	else if (strcmp(key, "url-config") == 0)
	{
		NSString *urlConf = [NSString stringWithFormat:@"%@:%u", configuration.socksHost, configuration.socksPort];
		
		strlcpy(value, urlConf.UTF8String, sizeof(tp_value_t));
		
		return KERN_SUCCESS;
	}
	else if (strcmp(key, "check-tor") == 0)
	{
		if (configuration.checkTor)
		{
			strlcpy(value, "true", sizeof(tp_value_t));
			process.launchSteps = 4;
		}
		else
			strlcpy(value, "false", sizeof(tp_value_t));

		return KERN_SUCCESS;
	}
	
	TPLogDebug(@"[MIG] 'get_setting': unknown setting key - key='%s'", key);

	return KERN_INVALID_ARGUMENT;
}

kern_return_t mig_server_is_tplibrary(mach_port_t port, audit_token_t audit, tp_path_t path, boolean_t *tplib)
{
	TPProcessManager	*manager = (__bridge TPProcessManager *)dispatch_get_specific(&managerKey);
	pid_t				pid = audit_token_to_pid(audit);
	
	// Check access.
	if ([manager _isHandledPID:pid process:nil] == NO)
		return KERN_NO_ACCESS;
	
	NSString *opath = @(path);
	
	*tplib = (opath && [[manager injectedLibraries] containsObject:opath]);

	return KERN_SUCCESS;
}

kern_return_t mig_server_notify(mach_port_t port, audit_token_t audit, tp_key_t key, tp_value_t value)
{
	TPProcessManager	*manager = (__bridge TPProcessManager *)dispatch_get_specific(&managerKey);
	pid_t				pid = audit_token_to_pid(audit);
	TPProcess			*process = nil;
	
	// Check access.
	if ([manager _isHandledPID:pid process:&process] == NO)
		return KERN_NO_ACCESS;
	
	// Handle notify.
	if (strcmp(key, "control-breaked") == 0)
	{
		TPLogDebug(@"[MIG] 'notify': client breaked in control - pid='%d'", pid);
		
		[process launchStepping];

		return KERN_SUCCESS;
	}
	else if (strcmp(key, "checked-tor-socket") == 0)
	{
		TPLogDebug(@"[MIG] 'notify': checked socket - pid='%d'; status:'%s'", pid, value);
		
		if (strcmp(value, "valid") == 0)
		{
			[process launchStepping];
		}
		else
		{
			process.launchError = NSLocalizedString(@"process_err_tor_socket", @"");
			[process terminate];
		}
		
		return KERN_SUCCESS;
	}
	else if (strcmp(key, "checked-tor-urlconnection") == 0)
	{
		TPLogDebug(@"[MIG] 'notify': checked NSURLConnection - pid='%d'; status:'%s'", pid, value);
		
		if (strcmp(value, "valid") == 0)
		{
			[process launchStepping];
		}
		else
		{
			process.launchError = NSLocalizedString(@"process_err_tor_nsurlconnection", @"");
			[process terminate];
		}
		
		return KERN_SUCCESS;
	}
	else if (strcmp(key, "checked-tor-urlsession") == 0)
	{
		TPLogDebug(@"[MIG] 'notify': checked NSURLSession - pid='%d'; status:'%s'", pid, value);
		
		if (strcmp(value, "valid") == 0)
		{
			[process launchStepping];
		}
		else
		{
			process.launchError = NSLocalizedString(@"process_err_tor_nsurlsession", @"");
			[process terminate];
		}
		
		return KERN_SUCCESS;
	}
	
	return KERN_INVALID_ARGUMENT;
}

@end

NS_ASSUME_NONNULL_END

