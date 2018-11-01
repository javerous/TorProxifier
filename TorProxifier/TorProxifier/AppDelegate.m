/*
 *  AppDelegate.m
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

#import <SMAssistant/SMAssistant.h>
#import <SMTor/SMTor.h>
#import <SMFoundation/SMFoundation.h>

#include <sys/socket.h>
#include <netinet/in.h>

#import "AppDelegate.h"

#import "TPMainWindowController.h"
#import "TPPreferencesWindowController.h"

#import "TPPanel_Welcome.h"
#import "TPConfiguration.h"


NS_ASSUME_NONNULL_BEGIN


/*
** Prototypes
*/
#pragma mark - Prototypes

static BOOL is_port_available(uint16_t port);



/*
** TPConfiguration (NSUserDefaults)
*/
#pragma mark - TPConfiguration (NSUserDefaults)

@interface TPConfiguration (NSUserDefaults)

- (nullable instancetype)initWithUserDefault:(NSUserDefaults *)userDefaults;

- (void)saveToUserDefaults:(NSUserDefaults *)userDefaults;

@end

@implementation TPConfiguration (NSUserDefaults)

- (nullable instancetype)initWithUserDefault:(NSUserDefaults *)userDefaults
{
	self = [super init];
	
	if (self)
	{
		if ([userDefaults boolForKey:@"settings_done"] == NO)
			return nil;
			
		self.bundled = [userDefaults boolForKey:@"bundled"];
		self.socksHost = [userDefaults valueForKey:@"host"];
		self.socksPort = [userDefaults integerForKey:@"port"];
		self.checkTor = [userDefaults boolForKey:@"check_tor"];
	}
	
	return self;
}

- (void)saveToUserDefaults:(NSUserDefaults *)userDefaults
{
	[userDefaults setBool:YES forKey:@"settings_done"];
	
	[userDefaults setBool:self.bundled forKey:@"bundled"];
	[userDefaults setValue:self.socksHost forKey:@"host"];
	[userDefaults setInteger:self.socksPort forKey:@"port"];
	[userDefaults setBool:self.checkTor forKey:@"check_tor"];
}

@end



/*
** AppDelegate
*/
#pragma mark - AppDelegate

@implementation AppDelegate
{
	TPMainWindowController *_mainController;
	
	SMTorManager	*_torManager;
	BOOL			_isTerminating;
	
	SMOperationsQueue *_gOperations;
	
	id <NSObject>	_configurationObserver;
	TPConfiguration *_configuration;
}


/*
** AppDelegate - NSApplicationDelegate
*/
#pragma mark - AppDelegate - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Create global operation queue.
	_gOperations = [[SMOperationsQueue alloc] initStarted];

	// Default settings.
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		@"settings_done": @NO,
		@"bundled" : @NO,
		@"host" : @"127.0.0.1",
		@"port" : @9150,
		@"check_tor" : @YES
	}];
	
	// Reset settings if wanted.
	NSUInteger flags = [NSEvent modifierFlags];
	
	if ((flags & NSEventModifierFlagOption) && (flags & NSEventModifierFlagCommand))
	{
		NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];
		
		if (identifier)
			[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:identifier];
	}
	
	// Create configuration.
	_configuration = [[TPConfiguration alloc] initWithUserDefault:[NSUserDefaults standardUserDefaults]];
	
	// Observe configuration change.
	__weak AppDelegate *weakSelf = self;
	
	_configurationObserver = [[NSNotificationCenter defaultCenter] addObserverForName:TPPreferencesWindowPreferencesDidChange object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		
		_configuration = [[TPConfiguration alloc] initWithUserDefault:[NSUserDefaults standardUserDefaults]];
		
		[weakSelf startWithConfiguration:_configuration];
	}];
	
	// Launch assistant.
	[_gOperations scheduleBlock:^(SMOperationsControl  _Nonnull ctrl) {
		
		// Check if settings was already done.
		if (_configuration)
		{
			ctrl(SMOperationsControlContinue);
			return;
		}
		
		// Start assistant.
		NSArray *pannels = @[ [TPPanel_Welcome class] ];
		
		[SMAssistantController startAssistantWithPanels:pannels completionHandler:^(SMAssistantCompletionType type, TPConfiguration *  _Nullable context) {
			
			switch (type)
			{
				case SMAssistantCompletionTypeCanceled:
					[[NSApplication sharedApplication] terminate:nil];
					break;
					
				case SMAssistantCompletionTypeDone:
					_configuration = context;
					
					[_configuration saveToUserDefaults:[NSUserDefaults standardUserDefaults]];
					
					ctrl(SMOperationsControlContinue);
					break;
			}
		}];
	}];
	
	// Start.
	[_gOperations scheduleBlock:^(SMOperationsControl  _Nonnull ctrl) {
		[self startWithConfiguration:_configuration];
		ctrl(SMOperationsControlContinue);
	}];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	_isTerminating = YES;
}



/*
** AppDelegate - IBActions
*/
#pragma mark - AppDelegate - IBActions

- (IBAction)doPreferences:(id)sender
{
	[[TPPreferencesWindowController sharedController] showWindow:nil];
}



/*
** AppDelegate - Helpers
*/
#pragma mark - AppDelegate - Helpers

- (void)startWithConfiguration:(TPConfiguration *)configuration
{
	if (!configuration)
		return;
	
	[_gOperations scheduleBlock:^(SMOperationsControl  _Nonnull opCtrl) {
		
		SMOperationsQueue *operations = [[SMOperationsQueue alloc] initStarted];
		
		// -- Hide main controller if necessary
		[operations scheduleOnQueue:dispatch_get_main_queue() block:^(SMOperationsControl  _Nonnull ctrl) {
			
			if (_mainController)
			{
				if (_torManager == nil && configuration.bundled)
					[_mainController.window orderOut:nil];
			}
			else
				_mainController = [[TPMainWindowController alloc] init];
			
			ctrl(SMOperationsControlContinue);
		}];
		
		// -- Stop tor if necessary.
		[operations scheduleBlock:^(SMOperationsControl  _Nonnull ctrl) {
			
			if (_torManager == nil || configuration.bundled)
			{
				ctrl(SMOperationsControlContinue);
				return;
			}
			
			[_torManager stopWithCompletionHandler:^{
				_torManager = nil;
				ctrl(SMOperationsControlContinue);
			}];
		}];
		
		// -- Launch tor if necessary.
		[operations scheduleBlock:^(SMOperationsControl  _Nonnull ctrl) {
			
			if (_torManager != nil || configuration.bundled == NO)
			{
				// Copy back the bundled tor configuration.
				if (_torManager != nil)
				{
					SMTorConfiguration *tconfiguration = [_torManager configuration];
					
					configuration.socksHost = tconfiguration.socksHost;
					configuration.socksPort = tconfiguration.socksPort;
				}
				
				ctrl(SMOperationsControlContinue);
				return;
			}
			
			// Close main window if opened.
			dispatch_async(dispatch_get_main_queue(), ^{
				
			});

			// Search free port (using bind with sin_port = 0 is not enough random).
			NSMutableIndexSet	*portSet = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(1025, 64510)];
			NSUInteger			socksPort = NSNotFound;

			while (1)
			{
				NSUInteger	firstIndex = [portSet firstIndex];
				NSUInteger	lastIndex = [portSet lastIndex];
				uint32_t	rnd = arc4random_uniform((uint32_t)(lastIndex - firstIndex));
				
				NSUInteger result;
				
				result = [portSet indexGreaterThanOrEqualToIndex:(firstIndex + rnd)];
				
				if (result == NSNotFound)
				{
					result = [portSet indexLessThanIndex:(firstIndex + rnd)];
					
					if (result == NSNotFound)
					{
						NSLog(@"Error: Can't found free port");
						break;
					}
				}
				
				if (is_port_available(result))
				{
					socksPort = result;
					break;
				}
				
				[portSet removeIndex:result];
			}
			
			if (socksPort == NSNotFound)
			{
				NSAlert *alert = [[NSAlert alloc] init];
				
				alert.informativeText = @"Unable to found any available port for tor SOCKS";
				
				[alert runModal];
				
				[[NSApplication sharedApplication] terminate:nil];
			}
			else
			{
				configuration.socksPort = socksPort;
				configuration.socksHost = @"127.0.0.1";
			}

			// Search standard paths.
			NSArray *possibleURLs = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask];
			NSURL	*supportURL = nil;
			
			if (possibleURLs.count == 0)
			{
				NSLog(@"Error: Can't found support directory.");
				return;
			}
			
			supportURL = [possibleURLs[0] URLByAppendingPathComponent:@"TorProxifier"];
			
			[[NSFileManager defaultManager] createDirectoryAtURL:supportURL withIntermediateDirectories:NO attributes:nil error:nil];
			
			
			// Configure tor.
			SMTorConfiguration *tconfiguration = [[SMTorConfiguration alloc] init];
			
			tconfiguration.socksHost = configuration.socksHost;
			tconfiguration.socksPort = configuration.socksPort;
			tconfiguration.hiddenService = NO;
			
			tconfiguration.dataPath = (NSString *)[[supportURL URLByAppendingPathComponent:@"tor-data"] path];
			tconfiguration.binaryPath = (NSString *)[[supportURL URLByAppendingPathComponent:@"tor-binaries"] path];
			
			_torManager = [[SMTorManager alloc] initWithConfiguration:tconfiguration];
			
			_torManager.logHandler = ^(SMTorLogKind kind, NSString *log, BOOL fatalLog) {
				
				switch (kind)
				{
					case SMTorLogStandard:
						TPLogDebug(@"Tor: %@", log);
						break;
						
					case SMTorLogError:
						TPLogDebug(@"Tor-Error: %@", log);
						break;
				}
			};
			
			[SMTorStartController startWithTorManager:_torManager infoHandler:^(SMInfo * _Nonnull startInfo) {
				
				TPLogDebug(@"Starting: %@", [startInfo renderComplete]);
				
				if (startInfo.kind == SMInfoInfo)
				{
					if (startInfo.code == SMTorEventStartDone)
						ctrl(SMOperationsControlContinue);
				}
				else if (startInfo.kind == SMInfoWarning)
				{
					if (startInfo.code == SMTorWarningStartCanceled)
					{
						ctrl(SMOperationsControlContinue);
					}
				}
				else if (startInfo.kind == SMInfoError)
				{
					NSAlert *alert = [[NSAlert alloc] init];
					
					alert.informativeText = @"Unable to start bundled tor binary";
					alert.messageText = [startInfo renderMessage];
					
					[alert runModal];
					
					[[NSApplication sharedApplication] terminate:nil];
				}
			}];
		}];
		
		// -- Update tor.
		[operations scheduleBlock:^(SMOperationsControl  _Nonnull ctrl) {
			
			if (configuration.bundled == NO)
			{
				ctrl(SMOperationsControlContinue);
				return;
			}
			
			[_torManager checkForUpdateWithInfoHandler:^(SMInfo * _Nonnull updateInfo) {
				
				// > Handle update.
				if (updateInfo.kind == SMInfoInfo && [updateInfo.domain isEqualToString:SMTorInfoCheckUpdateDomain] && updateInfo.code == SMTorEventCheckUpdateAvailable)
				{
					NSDictionary	*context = updateInfo.context;
					NSString		*oldVersion = context[@"old_version"];
					NSString		*newVersion = context[@"new_version"];
					
					[SMTorUpdateController handleUpdateWithTorManager:_torManager oldVersion:oldVersion newVersion:newVersion infoHandler:^(SMInfo * _Nonnull info) {
						TPLogDebug(@"Update: %@", [info renderComplete]);
					}];
				}
			}];
			
			// Don't wait for update result.
			ctrl(SMOperationsControlContinue);
		}];
		
		// -- Show main controller.
		[operations scheduleOnQueue:dispatch_get_main_queue() block:^(SMOperationsControl  _Nonnull ctrl) {
			
			[_mainController setConfiguration:configuration];
			[_mainController showWindow:nil];
			
			ctrl(SMOperationsControlContinue);
			opCtrl(SMOperationsControlContinue);
		}];
	}];
}

@end



/*
** C Tools
*/
#pragma mark - C Tools

static BOOL is_port_available(uint16_t port)
{
	// Create socket.
	int sockfd;
 
	sockfd = socket(AF_INET, SOCK_STREAM, 0);
	if (sockfd < 0)
		return NO;
	
	// Try to bind port.
	struct sockaddr_in addr;

	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = INADDR_ANY;
	addr.sin_port = htons(port);
	
	if (bind(sockfd, (struct sockaddr *)&addr, sizeof(addr)) < 0)
		return NO;
	
	close (sockfd);
	
	// This port was bindable, so it's available.
	return YES;
}


NS_ASSUME_NONNULL_END
