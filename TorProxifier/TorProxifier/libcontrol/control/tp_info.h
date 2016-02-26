/*
 *  tp_info.h
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
