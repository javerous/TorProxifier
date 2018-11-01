/*
 *  TPPreferencesWindowController.m
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

#import "TPPreferencesWindowController.h"


NS_ASSUME_NONNULL_BEGIN


/*
** TPPreferencesWindowController- Interface
*/
#pragma mark - TPPreferencesWindowController - Interface

@interface TPPreferencesWindowController () <NSWindowDelegate>
{
	IBOutlet NSMatrix *matrixView;
	
	IBOutlet NSTextField *hostTitle;
	IBOutlet NSTextField *hostField;
	IBOutlet NSTextField *portTitle;
	IBOutlet NSTextField *portField;
	
	IBOutlet NSButton *checkTorButton;
	
	id <NSObject> terminationObserver;
}

@property (assign) BOOL isTerminating;

@end



/*
** TPPreferencesWindowController
*/
#pragma mark - TPPreferencesWindowController

@implementation TPPreferencesWindowController


/*
** TPPreferencesWindowController - Instance
*/
#pragma mark - TPPreferencesWindowController - Instance

+ (instancetype)sharedController
{
	static TPPreferencesWindowController	*shr;
	static dispatch_once_t					onceToken;
	
	dispatch_once(&onceToken, ^{
		shr = [[TPPreferencesWindowController alloc] init];
	});
	
	return shr;
}

- (id)init
{
	self = [super initWithWindowNibName:@"PreferencesWindow"];
	
	if (self)
	{
	}
	
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:terminationObserver];
}



/*
** TPPreferencesWindowController - NSWindowController
*/
#pragma mark - TPPreferencesWindowController - NSWindowController

- (void)windowDidLoad
{
	[super windowDidLoad];
	
	// Place Window.
	[self.window center];
	[self setWindowFrameAutosaveName:@"Preferences"];
	
	// Delegation.
	self.window.delegate = self;
}

- (IBAction)showWindow:(nullable id)sender
{
	[super showWindow:sender];
	
	NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
	
	hostField.stringValue = (NSString *)[userDefault valueForKey:@"host"] ?: @"";
	portField.integerValue = [[userDefault valueForKey:@"port"] integerValue];

	if ([userDefault boolForKey:@"bundled"])
		[matrixView selectCellWithTag:1];
	else
		[matrixView selectCellWithTag:2];
	
	[self selectChange:matrixView];
	
	checkTorButton.state = ([userDefault boolForKey:@"check_tor"] ? NSOnState : NSOffState);
}



/*
** TPPreferencesWindowController - NSWindowDelegate
*/
#pragma mark - TPPreferencesWindowController - NSWindowDelegate

- (BOOL)windowShouldClose:(id)sender
{
	if ([self validateSettings])
		return YES;
	else
	{
		NSBeep();
		return NO;
	}
}

- (void)windowWillClose:(NSNotification *)notification
{
	if ([self validateSettings] == NO)
		return;
	
	// Save settings.
	NSUserDefaults *userDefault = [NSUserDefaults standardUserDefaults];
	
	if ([matrixView selectedTag] == 1)
	{
		[userDefault setBool:YES forKey:@"bundled"];
	}
	else
	{
		[userDefault setBool:NO forKey:@"bundled"];
		
		[userDefault setValue:hostField.stringValue forKey:@"host"];
		[userDefault setValue:@(portField.stringValue.integerValue) forKey:@"port"];
	}
	
	[userDefault setBool:(checkTorButton.state == NSOnState) forKey:@"check_tor"];
	
	// Notify.
	[[NSNotificationCenter defaultCenter] postNotificationName:TPPreferencesWindowPreferencesDidChange object:self];
}



/*
** TPPreferencesWindowController - IBAction
*/
#pragma mark - TPPreferencesWindowController - IBAction

- (IBAction)selectChange:(id)sender
{
	NSMatrix	*mtr = sender;
	NSCell		*obj = [mtr selectedCell];
	NSInteger	tag = [obj tag];
	
	hostTitle.enabled = (tag == 2);
	hostField.enabled = (tag == 2);
	
	portTitle.enabled = (tag == 2);
	portField.enabled = (tag == 2);
}



/*
** TPPreferencesWindowController - Helpers
*/
#pragma mark - TPPreferencesWindowController - Helpers

- (BOOL)validateSettings
{
	// XXX perhaps we can share code with TPPanel_Welcome.
	
	
	NSCell		*obj = [matrixView selectedCell];
	NSInteger	tag = [obj tag];
	
	if (tag == 1)
	{
		return YES;
	}
	else
	{
		// Validate host.
		NSString *hostValue = hostField.stringValue;
		
		NSArray *comps = [hostValue componentsSeparatedByString:@"."];
		
		if (comps.count != 4)
			return NO;
		
		for (NSString *comp in comps)
		{
			NSUInteger value;
			
			if ([self validateNumber:comp result:&value] == NO)
				return NO;
			
			if (value >= 255)
				return NO;
		}
		
		// Validate port.
		NSString	*portValue = portField.stringValue;
		NSUInteger	value;
		
		if ([self validateNumber:portValue result:&value] == NO)
			return NO;
		
		if (value == 0 || value > 65535)
			return NO;
		
		// Everything is ok.
		return YES;
	}
}

- (BOOL)validateNumber:(NSString *)value result:(NSUInteger *)result
{
	if (!result)
		return NO;
	
	if ([value rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location == NSNotFound)
		return NO;
	
	*result = [value integerValue];
	
	return YES;
}

@end


NS_ASSUME_NONNULL_END
