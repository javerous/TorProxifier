/*
 *  TPProcess.h
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

@import Foundation;


NS_ASSUME_NONNULL_BEGIN


/*
** TPProcess
*/
#pragma mark - TPProcess

@interface TPProcess : NSObject

// -- Instance --
- (instancetype)initWithPath:(NSString *)path;

// -- Life --
- (void)launchWithInjectedLibraries:(nullable NSArray *)libraries;
- (void)terminate;

// -- Steps --
- (void)launchStepping;

// -- Parent --
- (BOOL)parentOfPID:(pid_t)pid;

// -- Properties --
// Process.
@property (readonly) NSString	*path;

@property (readonly) NSString	*name;
@property (readonly) NSImage	*icon;

@property (readonly) pid_t pid;

// Status.
@property (assign) NSUInteger	launchSteps;
@property (strong) NSString		*launchError;

// -- Handlers --
@property (strong) void (^terminateHandler)(TPProcess *process, BOOL userAction);

@property (strong) void (^launchProgressHandler)(TPProcess *process, double progress);
@property (strong) void (^launchErrorHandler)(TPProcess *process, NSString *error);



@end


NS_ASSUME_NONNULL_END
