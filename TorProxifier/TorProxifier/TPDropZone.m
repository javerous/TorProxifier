/*
 *  TPDropZone.m
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

#import "TPDropZone.h"


NS_ASSUME_NONNULL_BEGIN


/*
** TPDropZone
*/
#pragma mark - TPDropZone

@implementation TPDropZone


/*
** TPDropZone - Instance
*/
#pragma mark - TPDropZone - Instance

- (instancetype)initWithFrame:(NSRect)frameRect
{
	self = [super initWithFrame:frameRect];
	
	if (self)
	{
		[self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
	}
	
	return self;
}



/*
** TPDropZone - NSView
*/
#pragma mark - TPDropZone - NSView

- (void)drawRect:(NSRect)dirtyRect
{
	// Compute border.
	NSColor *borderColor = [NSColor colorWithRed:(155.0 / 255.0) green:(155.0 / 255.0) blue:(155.0 / 255.0) alpha:1.0];
	NSRect	borderFrame = NSIntegralRect(NSInsetRect([self bounds], 8.0, 8.0));
	CGFloat borderWidth	= 5.0f;
		
	NSRect insetFrame = NSInsetRect(borderFrame, borderWidth / 2, borderWidth / 2);
	
	// Create dashed line.
	CGFloat			pattern[2]	= { 24.0f, 14.0f };
	NSBezierPath	*border = [NSBezierPath bezierPathWithRoundedRect:insetFrame xRadius:(3.0 * borderWidth) yRadius:(3.0 * borderWidth)];
	
	[border setLineWidth:borderWidth];
	[border setLineDash:pattern count:2 phase:0.0];

	// Draw.
	[borderColor set];
	[border stroke];
	
	// Draw icon.
	static dispatch_once_t	onceToken;
	static NSImage			*icon;
	
	dispatch_once(&onceToken, ^{
		
		NSImage		*template = [NSImage imageNamed:@"app_template"];
		NSUInteger	size = 128;
		
		icon = [NSImage imageWithSize:NSMakeSize(size, size) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
			
			[template drawInRect:NSMakeRect(0, 0, size, size) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];

			[borderColor set];
			
			NSRectFillUsingOperation(NSMakeRect(0, 0, size, size), NSCompositeSourceAtop);
			
			return YES;
		}];
	});
	
	[icon drawInRect:NSMakeRect((borderFrame.size.width - 100.0) / 2.0, (borderFrame.size.height - 100.0) / 2.0, 100, 100) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0f];
}



/*
** TPDropZone - NSDraggingDestination
*/
#pragma mark - TPDropZone - NSView

- (NSDragOperation)draggingEntered:(id < NSDraggingInfo >)sender
{
	void (^droppedFilesHandler)(NSArray *files) = self.droppedFilesHandler;
	
	if (!droppedFilesHandler)
		return NSDragOperationNone;
	
	return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id < NSDraggingInfo >)sender
{
	NSPasteboard *pboard = [sender draggingPasteboard];
	void (^droppedFilesHandler)(NSArray *files) = self.droppedFilesHandler;
	
	if (!droppedFilesHandler)
		return NO;
	
	if ([[pboard types] containsObject:NSFilenamesPboardType])
	{
		NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];

		droppedFilesHandler(files);

		return YES;
	}
	
	return NO;
}

@end


NS_ASSUME_NONNULL_END
