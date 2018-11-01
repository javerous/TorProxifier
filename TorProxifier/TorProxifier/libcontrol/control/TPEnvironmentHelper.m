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

#import <Foundation/Foundation.h>

#include "TPEnvironmentHelper.h"

#include "TPService.h"


/*
** Globals
*/
#pragma mark - Globals

static NSMutableArray *gRemovedInsert = nil;



/*
** Functions
*/
#pragma mark - Functions

void remove_dyld_insert(void)
{
	// XXX not thread-safe.
	
	@autoreleasepool {
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
			
			if (gRemovedInsert == nil)
				gRemovedInsert = [[NSMutableArray alloc] init];
			
			[gRemovedInsert addObject:path];
		}];
		
		[dyld_inserts removeObjectsAtIndexes:tpLibIndexes];
		
		
		// Build new environement.
		NSString *new_dyld_insert = [dyld_inserts componentsJoinedByString:@":"];
		
		if (new_dyld_insert.length > 0)
			setenv("DYLD_INSERT_LIBRARIES", new_dyld_insert.UTF8String, 1);
		else
			unsetenv("DYLD_INSERT_LIBRARIES");
	}
}

void restore_dyld_insert_buffer(char * const *envp, char ***out_envp)
{
	// XXX not thread-safe with 'remove_dyld_insert', but thread-safe else.
	
	if (!out_envp)
		return;
	
	@autoreleasepool {
		NSMutableDictionary *envs = [[NSMutableDictionary alloc] init];
		NSMutableArray		*envs_keys = [[NSMutableArray alloc] init];
		
		// Copy current envp.
		if (envp)
		{
			const char	*cenv;
			int			i = 0;
			
			while ((cenv = envp[i++]))
			{
				NSString	*env = @(cenv);
				NSRange		rg = [env rangeOfString:@"="];
				
				if (rg.location == NSNotFound)
					continue;
				
				NSString *name = [env substringToIndex:rg.location];
				NSString *value = [env substringFromIndex:rg.location + rg.length];
				
				envs[name] = value;
				[envs_keys removeObject:name];
				[envs_keys addObject:name];
			}
		}
		
		// Fix "DYLD_INSERT_LIBRARIES".
		NSString *curr_dyld_insert = envs[@"DYLD_INSERT_LIBRARIES"];
		NSString *new_dyld_insert = [gRemovedInsert componentsJoinedByString:@":"];
		
		if (curr_dyld_insert)
			envs[@"DYLD_INSERT_LIBRARIES"] = [NSString stringWithFormat:@"%@:%@", new_dyld_insert, curr_dyld_insert];
		else
		{
			envs[@"DYLD_INSERT_LIBRARIES"] = new_dyld_insert;
			[envs_keys addObject:@"DYLD_INSERT_LIBRARIES"];
		}
		
		// Build output.
		char **cenvs = calloc(envs_keys.count + 1, sizeof(char *));
		
		[envs_keys enumerateObjectsUsingBlock:^(NSString *  _Nonnull key, NSUInteger idx, BOOL * _Nonnull stop) {
			NSString *env = [NSString stringWithFormat:@"%@=%@", key, envs[key]];
			
			cenvs[idx] = strdup(env.UTF8String);
		}];
		
		*out_envp = cenvs;
	}
}
