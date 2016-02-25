/*
 *  TPEnvironmentHelper.m
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

#include "TPEnvironmentHelper.h"

#include "TPService.h"


void remove_dyld_insert(void)
{
	const char *dyld_insert_c = getenv("DYLD_INSERT_LIBRARIES");
	
	if (!dyld_insert_c)
		return;
	
	// Remove our libs from the libs of injected libs.
	NSMutableArray		*dyld_inserts = [[@(dyld_insert_c) componentsSeparatedByString:@":"] mutableCopy];
	NSMutableIndexSet	*tpLibIndexes = [[NSMutableIndexSet alloc] init];
	
	[dyld_inserts enumerateObjectsUsingBlock:^(NSString *  _Nonnull path, NSUInteger idx, BOOL * _Nonnull stop) {
		
		boolean_t isTPLib = FALSE;
		
		if (mig_client_is_tplibrary(service_port(), (char *)path.fileSystemRepresentation, &isTPLib) != KERN_SUCCESS)
			return;
		
		if (isTPLib == FALSE)
			return;
		
		[tpLibIndexes addIndex:idx];
	}];
	
	[dyld_inserts removeObjectsAtIndexes:tpLibIndexes];
	
	
	// Build new environement.
	NSString *new_dyld_insert = [dyld_inserts componentsJoinedByString:@":"];
	
	if (new_dyld_insert.length > 0)
		setenv("DYLD_INSERT_LIBRARIES", new_dyld_insert.UTF8String, 1);
	else
	{
		unsetenv("DYLD_INSERT_LIBRARIES");
		unsetenv("DYLD_FORCE_FLAT_NAMESPACE");
	}
}
