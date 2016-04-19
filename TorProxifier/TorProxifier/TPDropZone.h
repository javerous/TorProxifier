/*
 *  TPDropZone.h
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

#import <Cocoa/Cocoa.h>


NS_ASSUME_NONNULL_BEGIN


/*
** TPDropZone
*/
#pragma mark - TPDropZone

@interface TPDropZone : NSView

// Properties.
@property (strong) NSImage				*dropImage;
@property (strong) NSAttributedString	*dropString;

@property (strong) NSColor *dashColor;

// Handler.
@property (strong) void (^droppedFilesHandler)(NSArray * _Nonnull files);

// Tools.
- (NSSize)computeSizeForSymmetricalDashesWithMinWidth:(CGFloat)minWidth minHeight:(CGFloat)minHeight;

@end


NS_ASSUME_NONNULL_END
