/*
 *  TPPanel_Welcome.m
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

#import "TPPanel_Welcome.h"

#import "TPConfiguration.h"


NS_ASSUME_NONNULL_BEGIN


/*
** TPPanel_Welcome
*/
#pragma mark - TPPanel_Welcome

@implementation TPPanel_Welcome
{
	__weak id <SMAssistantProxy> _proxy;
	
	IBOutlet NSMatrix *matrixView;

	IBOutlet NSTextField *hostTitle;
	IBOutlet NSTextField *hostField;
	
	IBOutlet NSTextField *portTitle;
	IBOutlet NSTextField *portField;
	
	IBOutlet NSButton *checkTor;
}


/*
** TPPanel_Welcome - SMAssistantPanel
*/
#pragma mark - TPPanel_Welcome - SMAssistantPanel

+ (id <SMAssistantPanel>)panelWithProxy:(id <SMAssistantProxy>)proxy
{
	TPPanel_Welcome *panel = [[TPPanel_Welcome alloc] initWithNibName:@"TPPanel_Welcome" bundle:nil];
	
	panel->_proxy = proxy;
	
	return panel;
}

+ (NSString *)identifiant
{
	return @"ac_welcome";
}

+ (NSString *)title
{
	return NSLocalizedString(@"ac_title_welcome", @"");
}

- (nullable id)content
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

- (void)showPanel
{
	[_proxy setIsLastPanel:YES];
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
		[_proxy setDisableContinue:NO];
	}
	else
	{
		// Validate host.
		NSString *hostValue = hostField.stringValue;

		NSArray *comps = [hostValue componentsSeparatedByString:@"."];
		
		if (comps.count != 4)
		{
			[_proxy setDisableContinue:YES];
			return;
		}
		
		for (NSString *comp in comps)
		{
			NSUInteger value;
			
			if ([self validateNumber:comp result:&value] == NO)
			{
				[_proxy setDisableContinue:YES];
				return;
			}
			
			if (value >= 255)
			{
				[_proxy setDisableContinue:YES];
				return;
			}
		}
		
		// Validate port.
		NSString	*portValue = portField.stringValue;
		NSUInteger	value;

		if ([self validateNumber:portValue result:&value] == NO)
		{
			[_proxy setDisableContinue:YES];
			return;
		}
		
		if (value == 0 || value > 65535)
		{
			[_proxy setDisableContinue:YES];
			return;
		}

		
		// Everything is ok.
		[_proxy setDisableContinue:NO];
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
