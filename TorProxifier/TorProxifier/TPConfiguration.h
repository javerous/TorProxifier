/*
 *  TPConfiguration.h
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


/*
** TPConfiguration
*/
#pragma mark - TPConfiguration

@interface TPConfiguration : NSObject

@property (assign, nonatomic) BOOL bundled;

@property (strong, nonatomic) NSString *socksHost;
@property (assign, nonatomic) uint16_t socksPort;

@property (assign, nonatomic) BOOL checkTor;

@end
