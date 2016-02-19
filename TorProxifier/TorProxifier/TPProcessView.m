/*
 *  TPProcessView.m
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

#import "TPProcessView.h"

#import "TPProcess.h"


NS_ASSUME_NONNULL_BEGIN


/*
** TPProcessView - Private
*/
#pragma mark - TPProcessView - Private

@interface TPProcessView ()

@property (strong) IBOutlet NSImageView *iconView;
@property (strong) IBOutlet NSTextField *nameField;

@property (strong) IBOutlet NSButton *terminateButton;


@end


/*
** TPProcessView
*/
#pragma mark - TPProcessView

@implementation TPProcessView


/*
** TPProcessView - Instance
*/
#pragma mark - TPProcessView - Instance

+ (instancetype)processViewWithProcess:(TPProcess *)process
{
	return [[TPProcessView alloc] initWithProcess:process];
}

- (instancetype)initWithProcess:(TPProcess *)process
{
	self = [super initWithNibName:@"ProcessView" bundle:nil];
	
	if (self)
	{
		NSAssert(process, @"process is nil");
		
		_process = process;
	}
	
	return self;
}



/*
** TPProcessView - NSViewController
*/
#pragma mark - TPProcessView - NSViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	_iconView.image = _process.icon;
	_nameField.stringValue = _process.name;
}



/*
** TPProcessView - IBAction
*/
#pragma mark - TPProcessView - IBAction

- (IBAction)doTerminate:(id)sender
{
	_terminateButton.enabled = NO;
	[_process terminate];
}

@end



/*
** TPProcessViewBackground
*/
#pragma mark - TPProcessViewBackground

@interface TPProcessViewBackground : NSView
{
	NSGradient *_gradient;
}

@end

@implementation TPProcessViewBackground

- (void)awakeFromNib
{
	NSColor *color1 = [NSColor colorWithRed:0.8 green:0.8 blue:0.8 alpha:1.0];
	NSColor *color2 = [NSColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0];
	
	_gradient = [[NSGradient alloc] initWithStartingColor:color1 endingColor:color2];
}

- (void)drawRect:(NSRect)dirtyRect
{
	// Draw gradient.
	[_gradient drawInRect:self.bounds angle:90];
	
	// Draw bottom line.
	NSBezierPath	*bezierPath = [[NSBezierPath alloc] init];
	NSColor			*color = [NSColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:1.0];

	[bezierPath moveToPoint:NSMakePoint(0, 0)];
	[bezierPath lineToPoint:NSMakePoint(self.bounds.size.width, 0)];
	
	[color set];
	[bezierPath stroke];
}

@end


NS_ASSUME_NONNULL_END
