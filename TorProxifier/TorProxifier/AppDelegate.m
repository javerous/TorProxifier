/*
 *  AppDelegate.m
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

@import SMAssistant;
@import SMTor;
@import SMFoundation;

@import Darwin.POSIX;

#import "AppDelegate.h"

#import "TPMainWindowController.h"

#import "TPPanel_Welcome.h"


NS_ASSUME_NONNULL_BEGIN


/*
** Prototypes
*/
#pragma mark - Prototypes

static BOOL is_port_available(uint16_t port);



/*
** AppDelegate
*/
#pragma mark - AppDelegate

@implementation AppDelegate
{
	SMTorManager *_torManager;
}


/*
** AppDelegate - NSApplicationDelegate
*/
#pragma mark - AppDelegate - NSApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	SMOperationsQueue *operations = [[SMOperationsQueue alloc] initStarted];
	
	// -- Reset settings.
	[operations scheduleBlock:^(SMOperationsControl _Nonnull ctrl) {
		NSUInteger flags = [NSEvent modifierFlags];
		
		if ((flags & NSAlternateKeyMask) && (flags & NSCommandKeyMask))
		{
			NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];
			
			if (identifier)
				[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:identifier];
		}
		
		[[NSUserDefaults standardUserDefaults] registerDefaults:@{
			@"settings_done": @NO,
			@"bundled" : @NO,
			@"host" : @"127.0.0.1",
			@"port" : @9150,
		}];
		
		ctrl(SMOperationsControlContinue);
	}];
	
	// -- Launch assistant.
	[operations scheduleBlock:^(SMOperationsControl  _Nonnull ctrl) {
		
		// Check if settings was already done.
		BOOL settingsDone = [[NSUserDefaults standardUserDefaults] boolForKey:@"settings_done"];

		if (settingsDone)
		{
			ctrl(SMOperationsControlContinue);
			return;
		}
		
		// Start assistant.
		NSArray *pannels = @[ [TPPanel_Welcome class] ];
		
		[SMAssistantController startAssistantWithPanels:pannels completionHandler:^(NSDictionary *  _Nullable context) {
			
			for (NSString *key in context)
				[[NSUserDefaults standardUserDefaults] setValue:context[key] forKey:key];
			
			[[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"settings_done"];
			
			ctrl(SMOperationsControlContinue);
		}];
	}];
	
	// -- Launch tor.
	__block NSUInteger	socksPort = NSNotFound;
	__block NSString	*socksHost = nil;
	
	[operations scheduleBlock:^(SMOperationsControl  _Nonnull ctrl) {

		BOOL bundledMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"bundled"];

		if (bundledMode == NO)
		{
			socksPort = [[NSUserDefaults standardUserDefaults] integerForKey:@"port"];
			socksHost = [[NSUserDefaults standardUserDefaults] valueForKey:@"host"];
			
			ctrl(SMOperationsControlContinue);
			return;
		}
		
		// Search free port (using bind with sin_port = 0 is not enough random).
		NSMutableIndexSet *portSet = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(1025, 64510)];
		
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
		
		// Set localhost.
		socksHost = @"127.0.0.1";
		
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
		SMTorConfiguration *configuration = [[SMTorConfiguration alloc] init];
		
		configuration.socksPort = socksPort;
		configuration.socksHost = socksHost;
		configuration.hiddenService = NO;
		
		configuration.dataPath = (NSString *)[[supportURL URLByAppendingPathComponent:@"tor-data"] path];
		configuration.binaryPath = (NSString *)[[supportURL URLByAppendingPathComponent:@"tor-binaries"] path];
		
		_torManager = [[SMTorManager alloc] initWithConfiguration:configuration];
		
		_torManager.logHandler = ^(SMTorManagerLogKind kind, NSString *log) {
#if defined(DEBUG) && DEBUG
			switch (kind)
			{
				case SMTorManagerLogStandard:
					NSLog(@"Tor: %@", log);
					break;
					
				case SMTorManagerLogError:
					NSLog(@"Tor-Error: %@", log);
					break;
			}
#endif
		};

		[SMTorWindowController startWithTorManager:_torManager infoHandler:^(SMInfo * _Nonnull startInfo) {
			
#if defined(DEBUG) && DEBUG
			NSLog(@"Starting: %@", [startInfo renderComplete]);
#endif
			
			if (startInfo.kind == SMInfoInfo)
			{
				 if (startInfo.code == SMTorManagerEventStartDone)
					 ctrl(SMOperationsControlContinue);
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
		
		BOOL bundledMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"bundled"];

		if (bundledMode == NO)
		{
			ctrl(SMOperationsControlContinue);
			return;
		}
		
		[_torManager checkForUpdateWithCompletionHandler:^(SMInfo * _Nonnull updateInfo) {
			
			// > Handle update.
			if (updateInfo.kind == SMInfoInfo && [updateInfo.domain isEqualToString:SMTorManagerInfoCheckUpdateDomain] && updateInfo.code == SMTorManagerEventCheckUpdateAvailable)
			{
				NSDictionary	*context = updateInfo.context;
				NSString		*oldVersion = context[@"old_version"];
				NSString		*newVersion = context[@"new_version"];
				
				[[SMTorUpdateWindowController sharedController] handleUpdateFromVersion:oldVersion toVersion:newVersion torManager:_torManager logHandler:^(SMInfo * _Nonnull info) {
#if defined(DEBUG) && DEBUG
					NSLog(@"Update: %@", [info renderComplete]);
#endif
				}];
			}
		}];
		
		// Don't wait for update result.
		ctrl(SMOperationsControlContinue);
	}];
	
	// -- Show main controller.
	[operations scheduleOnQueue:dispatch_get_main_queue() block:^(SMOperationsControl  _Nonnull ctrl) {
		[[TPMainWindowController sharedController] showWithSocksHost:socksHost socksPort:socksPort];
		ctrl(SMOperationsControlContinue);
	}];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
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
