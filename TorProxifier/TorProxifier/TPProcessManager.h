/*
 *  TPProcessManager.h
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
** Formard
*/
#pragma mark - Forward

@class TPProcess;
@class TPConfiguration;



/*
** Types
*/
#pragma mark - Types

typedef enum
{
	TPProcessChangeCreated,
	TPProcessChangeRemoved
} TPProcessChange;


/*
** TPProcessManager
*/
#pragma mark - TPProcessManager

@interface TPProcessManager : NSObject

// -- Configuration --
@property (copy, nullable) TPConfiguration *configuration;

// -- Launch --
- (void)launchProcessWithPath:(NSString *)path;
- (void)launchProcessesWithPaths:(NSArray *)paths;

// -- Properties --
@property (strong) void (^processesChangeHandler)(NSArray *processes, TPProcessChange change);

@end

NS_ASSUME_NONNULL_END
