//
//  mach_helper.h
//  control
//
//  Created by Julien-Pierre Avérous on 26/02/2016.
//  Copyright © 2016 Julien-Pierre Avérous. All rights reserved.
//

#pragma mark once

#include <mach/mach.h>


/*
** Types
*/
#pragma mark - Types

typedef struct tp_process_info
{
	// mach_header.
	const void *machHeader;
	
	// Entry point.
	uint64_t	entryPoint;
	uint64_t	entryPage;
	int			entryProtection;

	// Host page size.
	uint64_t pageSize;
} tp_process_info;



/*
** Functions
*/
#pragma mark - Functions

boolean_t tp_get_process_info(tp_process_info *info);
