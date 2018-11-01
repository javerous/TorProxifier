/*
 *  TPConfiguration.m
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

#import "TPConfiguration.h"


/*
** TPConfiguration
*/
#pragma mark - TPConfiguration

@implementation TPConfiguration

- (id)copyWithZone:(nullable NSZone *)zone
{
	TPConfiguration *copy = [[TPConfiguration allocWithZone:zone] init];
	
	copy.bundled = _bundled;
	
	copy.socksHost = [_socksHost copy];
	copy.socksPort = _socksPort;
	
	copy.checkTor = _checkTor;
	
	return copy;
}

@end
