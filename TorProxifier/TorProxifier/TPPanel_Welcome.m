/*
 *  TPPanel_Welcome.m
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

#import "TPPanel_Welcome.h"

#import "TPConfiguration.h"


NS_ASSUME_NONNULL_BEGIN


/*
** TPPanel_Welcome
*/
#pragma mark - TPPanel_Welcome

@implementation TPPanel_Welcome
{
	IBOutlet NSMatrix *matrixView;

	IBOutlet NSTextField *hostTitle;
	IBOutlet NSTextField *hostField;
	
	IBOutlet NSTextField *portTitle;
	IBOutlet NSTextField *portField;
	
	IBOutlet NSButton *checkTor;
}

@synthesize panelProxy;
@synthesize panelPreviousContent;


/*
** TPPanel_Welcome - SMAssistantPanel
*/
#pragma mark - TPPanel_Welcome - SMAssistantPanel

#pragma mark Panel Instance

+ (id <SMAssistantPanel>)panelInstance
{
	TPPanel_Welcome *ctrl = [[TPPanel_Welcome alloc] initWithNibName:@"TPPanel_Welcome" bundle:nil];
	
	NSAssert(ctrl, @"welcome panel controller is nil");
	
	return ctrl;
}


#pragma mark Panel properties

+ (NSString *)panelIdentifier
{
	return @"ac_welcome";
}

+ (NSString *)panelTitle
{
	return NSLocalizedString(@"ac_title_welcome", @"");
}

- (NSView *)panelView
{
	return self.view;
}


#pragma mark Panel content

- (nullable id)panelContent
{
	TPConfiguration *configuration = [[TPConfiguration alloc] init];
	
	NSCell		*obj = [matrixView selectedCell];
	NSInteger	tag = [obj tag];
	
	if (tag == 1)
		configuration.bundled = YES;
	else
	{
		configuration.bundled = NO;
		configuration.socksHost = hostField.stringValue;
		configuration.socksPort = portField.stringValue.integerValue;
	}
	
	configuration.checkTor = (checkTor.state == NSOnState);
	
	return configuration;
}


#pragma mark Panel life

- (void)panelDidAppear
{
}



/*
** TPPanel_Welcome - IBActions
*/
#pragma mark - TPPanel_Welcome - IBActions

- (IBAction)selectChange:(id)sender
{
	NSMatrix	*mtr = sender;
	NSCell		*obj = [mtr selectedCell];
	NSInteger	tag = [obj tag];
	
	hostTitle.enabled = (tag == 2);
	hostField.enabled = (tag == 2);

	portTitle.enabled = (tag == 2);
	portField.enabled = (tag == 2);
	
	[self validateNext];
}



/*
** TPPanel_Welcome - Delegation
*/
#pragma mark - TPPanel_Welcome - Delegation

- (void)controlTextDidChange:(NSNotification *)aNotification
{
	[self validateNext];
}



/*
** TPPanel_Welcome - Helpers
*/
#pragma mark - TPPanel_Welcome - Helpers

- (void)validateNext
{
	NSCell		*obj = [matrixView selectedCell];
	NSInteger	tag = [obj tag];
	
	if (tag == 1)
	{
		[self.panelProxy setDisableContinue:NO];
	}
	else
	{
		// Validate host.
		NSString *hostValue = hostField.stringValue;

		NSArray *comps = [hostValue componentsSeparatedByString:@"."];
		
		if (comps.count != 4)
		{
			[self.panelProxy setDisableContinue:YES];
			return;
		}
		
		for (NSString *comp in comps)
		{
			NSUInteger value;
			
			if ([self validateNumber:comp result:&value] == NO)
			{
				[self.panelProxy setDisableContinue:YES];
				return;
			}
			
			if (value >= 255)
			{
				[self.panelProxy setDisableContinue:YES];
				return;
			}
		}
		
		// Validate port.
		NSString	*portValue = portField.stringValue;
		NSUInteger	value;

		if ([self validateNumber:portValue result:&value] == NO)
		{
			[self.panelProxy setDisableContinue:YES];
			return;
		}
		
		if (value == 0 || value > 65535)
		{
			[self.panelProxy setDisableContinue:YES];
			return;
		}

		
		// Everything is ok.
		[self.panelProxy setDisableContinue:NO];
	}
}

- (BOOL)validateNumber:(NSString *)value result:(NSUInteger *)result
{
	if (!result)
		return NO;
	
	if ([value length] == 0)
		return NO;

	if ([value rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound)
		return NO;
	
	*result = [value integerValue];
	
	return YES;
}

@end


NS_ASSUME_NONNULL_END
