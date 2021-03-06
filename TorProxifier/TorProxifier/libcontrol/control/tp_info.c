/*
 *  tp_info.c
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

#include <string.h>
#include <stdlib.h>

#include <mach-o/dyld.h>
#include <mach/mach.h>

#include <sys/mman.h>

#include "tp_info.h"


/*
** Macros
*/
#pragma mark - Macros

#define SMRoundUp(Value, Round)		(((Value) + ((Round) - 1)) & ~((Round) - 1))
#define SMRoundDown(Value, Round)	((Value) & ~((Round) - 1))



/*
** Functions
*/
#pragma mark - Functions

boolean_t tp_get_process_info(tp_process_info *info)
{
	if (!info)
		return false;
	
	// Search main binary image.
	uint32_t cnt = _dyld_image_count();
	
	const void	*hdr = NULL;
	intptr_t	slide = 0;
	
	for (uint32_t i = 0; i < cnt; i++)
	{
		const struct mach_header *iheader = _dyld_get_image_header(i);
		
		if (iheader->filetype == MH_EXECUTE)
		{
			hdr = iheader;
			slide = _dyld_get_image_vmaddr_slide(i);
			break;
		}
	}
	
	if (!hdr)
		return false;
	
	// Parse header info.
	size_t		hdrSize = 0;
	uint32_t	hdrNcmds = 0;
	cpu_type_t	hdrCPU = 0;
	
	if (*((uint32_t *)hdr) == MH_MAGIC)
	{
		const struct mach_header *header = hdr;
		
		hdrSize = sizeof(struct mach_header);
		hdrNcmds = header->ncmds;
		hdrCPU = header->cputype;
	}
	else if (*((uint32_t *)hdr) == MH_MAGIC_64)
	{
		const struct mach_header_64 *header = hdr;
		
		hdrSize = sizeof(struct mach_header_64);
		hdrNcmds = header->ncmds;
		hdrCPU = header->cputype;
	}
	else
	{
		TPLogDebug("didn't found valid header");
		return false;
	}
	
	info->machHeader = (const void *)hdr;
	
	// Get page-size.
	vm_size_t hostPageSize = 0;
	
	if (host_page_size(mach_host_self(), &hostPageSize) != KERN_SUCCESS)
		hostPageSize = 4096;
	
	info->pageSize = hostPageSize;
	
	// Search for LC_MAIN or LC_UNIXTHREAD
	struct load_command	*lc = (struct load_command *)((char *)hdr + hdrSize);
	
	uint64_t	textFileOffset = 0;
	vm_prot_t	textInitProtect = 0;
	
	uint64_t	mainTextOffset = 0;
	uint64_t	mainTextAddress = 0;
	
	for (unsigned i = 0; i < hdrNcmds; i++, lc = (struct load_command *)((char *)lc + lc->cmdsize))
	{
		if (lc->cmd == LC_SEGMENT_64)
		{
			struct segment_command_64 *lcs = (struct segment_command_64 *)lc;
			
			if (strncmp(lcs->segname, "__TEXT", sizeof(lcs->segname)) == 0)
			{
				textFileOffset = lcs->fileoff;
				textInitProtect = lcs->initprot;
			}
		}
		else if (lc->cmd == LC_SEGMENT)
		{
			struct segment_command *lcs = (struct segment_command *)lc;
			
			if (strncmp(lcs->segname, "__TEXT", sizeof(lcs->segname)) == 0)
			{
				textFileOffset = lcs->fileoff;
				textInitProtect = lcs->initprot;
			}
		}
		else if (lc->cmd == LC_MAIN)
		{
			struct entry_point_command *lcep = (struct entry_point_command *)lc;
			
			mainTextOffset = lcep->entryoff;
		}
		else if (lc->cmd == LC_UNIXTHREAD)
		{
			struct thread_command *lct = (struct thread_command *)lc;
			
			if (hdrCPU == CPU_TYPE_I386 || hdrCPU == CPU_TYPE_X86_64)
			{
				struct x86_thread_state *thread = (struct x86_thread_state *)((char *)lct + sizeof(struct thread_command));
				
				if (thread->tsh.flavor == x86_THREAD_STATE64)
					mainTextAddress = thread->uts.ts64.__rip;
				else if (thread->tsh.flavor == x86_THREAD_STATE32)
					mainTextAddress = thread->uts.ts32.__eip;
			}
		}
	}
	
	// Compute ptr.
	uint64_t entryAddress = 0;
	
	if (mainTextOffset != 0)
		entryAddress = (uint64_t)hdr + textFileOffset + mainTextOffset;
	else if (mainTextAddress != 0)
		entryAddress = (mainTextAddress + slide);
	else
	{
		TPLogDebug("didn't found LC_MAIN or valid LC_UNIXTHREAD");
		return false;
	}
	
	info->entryPoint = entryAddress;
	info->entryPage = SMRoundDown(entryAddress, hostPageSize);
	
	// Convert protection.
	int pageProtection = 0;
	
	if (textInitProtect & VM_PROT_READ)
		pageProtection |= PROT_READ;
	if (textInitProtect & VM_PROT_WRITE)
		pageProtection |= PROT_WRITE;
	if (textInitProtect & VM_PROT_EXECUTE)
		pageProtection |= PROT_EXEC;
	
	info->entryProtection = pageProtection;
	
	return true;
}
