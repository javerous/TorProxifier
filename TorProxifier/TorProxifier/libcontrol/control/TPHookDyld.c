/*
 *  TPHookDyld.c
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


/*
 About:
	This file is there to hook _dyld functions, to hide ourself from _dyld functions.
 
 Why:
	Some shareware / commercial app scan for loaded images to check some memory integrity.
 */


#include <mach-o/dyld.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <stdlib.h>

#include "TPService.h"


/*
** Prototypes
*/
#pragma mark - Prototypes

// Hooks.
static uint32_t						p_dyld_image_count(void);
static const struct mach_header*	p_dyld_get_image_header(uint32_t image_index);
static intptr_t						p_dyld_get_image_vmaddr_slide(uint32_t image_index);
static const char*					p_dyld_get_image_name(uint32_t image_index);

// Helpers.
static boolean_t _stealth_info(uint32_t *index, uint32_t *count);



/*
** Interpose
*/
#pragma mark - Interpose

// From 'OS X Internal'
typedef struct interpose_s {
	void *new_func;
	void *origin_func;
} interpose_t;

// Hooks declaration.
__attribute__((used)) static const interpose_t interposers[] __attribute__((section("__DATA,__interpose"))) = {
	{ (void *)p_dyld_image_count, (void *)_dyld_image_count },
	{ (void *)p_dyld_get_image_header, (void *)_dyld_get_image_header },
	{ (void *)p_dyld_get_image_vmaddr_slide, (void *)_dyld_get_image_vmaddr_slide },
	{ (void *)p_dyld_get_image_name, (void *)_dyld_get_image_name },
};



/*
** Hooks
*/
#pragma mark - Hooks

static uint32_t p_dyld_image_count(void)
{
	uint32_t count = 0;
	
	if (_stealth_info(NULL, &count))
		return count;
	else
		return _dyld_image_count();
}

static const struct mach_header* p_dyld_get_image_header(uint32_t image_index)
{
	_stealth_info(&image_index, NULL);
	
	return _dyld_get_image_header(image_index);
}

static intptr_t p_dyld_get_image_vmaddr_slide(uint32_t image_index)
{
	_stealth_info(&image_index, NULL);
	
	return _dyld_get_image_vmaddr_slide(image_index);
}

static const char * p_dyld_get_image_name(uint32_t image_index)
{
	_stealth_info(&image_index, NULL);
	
	return _dyld_get_image_name(image_index);
}



/*
** Helpers
*/
#pragma mark - Helpers

// Compute stealth index map.
static boolean_t _stealth_info(uint32_t *index, uint32_t *count)
{
	if (index == NULL && count == NULL)
		return FALSE;
	
	// Mutex.
	static dispatch_once_t	onceToken;
	static pthread_mutex_t	mutex;
	
	dispatch_once(&onceToken, ^{
		pthread_mutex_init(&mutex, NULL);
	});
	
	// Cache.
	static uint32_t rcount = 0;
	
	static uint32_t *smap = NULL;
	static uint32_t scount = 0;
	
	boolean_t result = FALSE;
	
	pthread_mutex_lock(&mutex);
	do {
		// Rebuild table.
		if (rcount != _dyld_image_count())
		{
			rcount = _dyld_image_count();
			
			if (smap)
				free(smap);
			
			smap = (uint32_t *)malloc(rcount * sizeof(uint32_t));
			
			if (!smap)
				break;
			
			uint32_t i, j;
			
			for (i = 0, j = 0; i < rcount; i++, j++)
			{
				while (j < rcount)
				{
					const char *path = _dyld_get_image_name(j);
					
					if (!path)
						break;
					
					boolean_t isTPLib = FALSE;
					
					if (mig_client_is_tplibrary(service_port(), (char *)path, &isTPLib) != KERN_SUCCESS)
						break;
					
					if (isTPLib == FALSE)
						break;
					
					j++;
				}
				
				if (j >= rcount)
					break;
				
				smap[i] = j;
			}
			
			scount = i;
		}
		
		// Give mapped index if asked.
		if (index)
		{
			if (*index >= scount || smap == NULL)
				break;
			
			*index = smap[*index];
		}
		
		// Give mapped count if asked.
		if (count)
			*count = scount;
		
		result = TRUE;
	} while (0);
	pthread_mutex_unlock(&mutex);
	
	return result;
}
