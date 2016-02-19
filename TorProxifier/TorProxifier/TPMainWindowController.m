/*
 *  TPMainWindowController.m
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

#import "TPMainWindowController.h"

#import "TPProcessManager.h"
#import "TPProcess.h"

#import "TPDropZone.h"
#import "TPProcessView.h"


NS_ASSUME_NONNULL_BEGIN


/*
** TPMainWindowController - Private
*/
#pragma mark - TPMainWindowController - Private

@interface TPMainWindowController ()
{
	TPDropZone			*_dropZone;
	TPProcessManager	*_processManager;
	
	NSMutableArray		*_changes;
	BOOL				_isChanging;
	
	NSMutableArray		*_processView;
	
	NSString			*_socksHost;
	uint16_t			_socksPort;

}

@property (strong) IBOutlet NSStackView *stackView;

@end



/*
** TPMainWindowController
*/
#pragma mark - TPMainWindowController

@implementation TPMainWindowController


/*
** TPMainWindowController - Instance
*/
#pragma mark - TPMainWindowController - Instance

+ (instancetype)sharedController
{
	static dispatch_once_t			onceToken;
	static TPMainWindowController	*shr;
	
	dispatch_once(&onceToken, ^{
		shr = [[TPMainWindowController alloc] init];
	});
	
	return shr;
}

- (id)init
{
	self = [super initWithWindowNibName:@"MainWindow"];
	
	if (self)
	{
		// Containers.
		_changes = [[NSMutableArray alloc] init];
		_processView = [[NSMutableArray alloc] init];
		

	}
	
	return self;
}



/*
** TPMainWindowController - Life
*/
#pragma mark - TPMainWindowController - Life

- (void)showWithSocksHost:(NSString *)host socksPort:(uint16_t)port
{
	NSAssert(host, @"host is nil");

	// Handle socks configuration.
	_socksHost = host;
	_socksPort = port;
	
	// Process manager.
	__weak TPMainWindowController *weakSelf = self;
	
	_processManager = [[TPProcessManager alloc] initWithSocksHost:_socksHost socksPort:_socksPort];
	
	_processManager.processesChangeHandler = ^(NSArray *processes, TPProcessChange change) {
		[weakSelf addChange:@{ @"processes" : processes, @"change" : @(change) }];
	};
	
	[self showWindow:nil];
}



/*
** TPMainWindowController - NSWindowController
*/
#pragma mark - TPMainWindowController - NSWindowController

- (void)windowDidLoad
{
	// Place Window.
	[self.window center];
	
	// Create drop zone.
	__weak TPProcessManager *weakPM = _processManager;
	
	_dropZone = [[TPDropZone alloc] initWithFrame:NSMakeRect(0, 0, 293, 180)];
	
	[_dropZone addConstraint:[NSLayoutConstraint constraintWithItem:_dropZone attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:293]];
	[_dropZone addConstraint:[NSLayoutConstraint constraintWithItem:_dropZone attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:180]];
	
	_dropZone.droppedFilesHandler = ^(NSArray * _Nonnull files) {
		[weakPM launchProcessesWithPaths:files];
	};
	
	
	
	// Add to drop zone.
	[self.stackView insertView:_dropZone atIndex:0 inGravity:NSStackViewGravityBottom];
}


/*
** TPMainWindowController - Changes
*/
#pragma mark - TPMainWindowController - Changes

- (void)addChange:(NSDictionary *)change
{
	if (!change)
		return;
	
	dispatch_async(dispatch_get_main_queue(), ^{
		if (_isChanging == NO)
			[self _handleChange:change];
		else
			[_changes addObject:change];
	});
}

- (void)nextChange
{
	dispatch_async(dispatch_get_main_queue(), ^{

		if ([_changes count] == 0)
		{
			_isChanging = NO;
			return;
		}
		
		NSDictionary *changeDescriptor = [_changes objectAtIndex:0];
		
		[_changes removeObjectAtIndex:0];
		
		[self _handleChange:changeDescriptor];
	});
}

- (void)_handleChange:(NSDictionary *)changeDescriptor
{
	dispatch_async(dispatch_get_main_queue(), ^{
		
		_isChanging = YES;
		
		NSArray			*processes = changeDescriptor[@"processes"];
		TPProcessChange	change = (TPProcessChange)[changeDescriptor[@"change"] intValue];
		
		switch (change)
		{
			// Handle change.
			case TPProcessChangeCreated:
			{
				NSMutableArray *views = [[NSMutableArray alloc] init];
				
				// > Add views.
				for (TPProcess *process in processes)
				{
					TPProcessView	*processView = [TPProcessView processViewWithProcess:process];
					NSView			*view = processView.view;
					
					[view setFrame:_dropZone.frame];
					[view setAlphaValue:0.0];
					
					[self.stackView insertView:view atIndex:0 inGravity:NSStackViewGravityTop];
					
					[views addObject:view];
					[_processView addObject:processView];
				}

				// > Animate adds.
				[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {

					context.duration = 0.4;
					context.allowsImplicitAnimation = YES;

					for (NSView *view in views)
						view.alphaValue = 1.0;
					
					[self.window layoutIfNeeded];
				}
				completionHandler:^{
					[self nextChange];
				}];
				
				return;
			}
			
			case TPProcessChangeRemoved:
			{
				// > Remove views.
				NSMutableArray *processViews = [[NSMutableArray alloc] init];
				
				for (TPProcess *process in processes)
				{
					[_processView enumerateObjectsUsingBlock:^(TPProcessView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
						
						if (obj.process != process)
							return;
						
						[processViews addObject:obj];
					}];
				}
				
				// > Animate removes.
				[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
					
					context.allowsImplicitAnimation = YES;
					
					for (TPProcessView *processView in processViews)
						[self.stackView removeView:processView.view];
					
					[self.window layoutIfNeeded];
				}
				completionHandler:^{
					
					dispatch_async(dispatch_get_main_queue(), ^{
						[_processView removeObjectsInArray:processViews];
					});
					
					[self nextChange];
				}];
				
				return;
			}
		}
	});
}

@end


NS_ASSUME_NONNULL_END
