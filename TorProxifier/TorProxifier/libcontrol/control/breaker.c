/*
 *  breaker.c
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <dlfcn.h>

#include <mach-o/dyld.h>
#include <mach/mach.h>

#include <sys/mman.h>



/*
** Macros
*/
#pragma mark - Macros

#define SMRoundUp(Value, Round)		(((Value) + ((Round) - 1)) & ~((Round) - 1))
#define SMRoundDown(Value, Round)	((Value) & ~((Round) - 1))



/*
** Globals
*/
#pragma mark - Globals

static vm_size_t	hostPageSize = 0;
static uint64_t		pageAddress = 0;
static int			pageProtection = 0;


/*
** Prototypes
*/
#pragma mark - Prototypes

extern void tp_handle_bp(void); // have to be implemented somewhere.

static void sig_handler(int s);



/*
** Install entry-point "breakpoint"
*/
#pragma mark - Install entry-point "breakpoint"

__attribute__((constructor))
void construct()
{
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
		return;
	
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
	}
	
	// Get page-size.
	if (host_page_size(mach_host_self(), &hostPageSize) != KERN_SUCCESS)
		hostPageSize = 4096;
	
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
		return;
	}
	
	pageAddress = SMRoundDown(entryAddress, hostPageSize);

	// Convert protection.
	if (textInitProtect & VM_PROT_READ)
		pageProtection |= PROT_READ;
	if (textInitProtect & VM_PROT_WRITE)
		pageProtection |= PROT_WRITE;
	if (textInitProtect & VM_PROT_EXECUTE)
		pageProtection |= PROT_EXEC;
	
	TPLogDebug("headerPtr \t %p", hdr);
	TPLogDebug("pagePtr \t 0x%llx", pageAddress);
	TPLogDebug("entryPtr \t 0x%llx", entryAddress);
	
	// Allow only read-write (x86_64) or nothing (i386), so it will "break" when executing entry point.
#if defined(__x86_64__)
	if (mprotect((void *)pageAddress, hostPageSize, (pageProtection & ~PROT_EXEC)) != 0)
#else
	if (mprotect((void *)pageAddress, hostPageSize, 0) != 0)
#endif
	{
		TPLogDebug("can't change protection");
		return;
	}
	
	// Activate signal.
	signal(SIGSEGV, sig_handler);
	signal(SIGBUS, sig_handler);
	
	TPLogDebug("breakpoint installed");
}

static void sig_handler(int s)
{
	TPLogDebug("got signal %d", s);

	if (s != SIGSEGV && s != SIGBUS)
		return;
	
	// Reset initial protection, so the app can continue normal operations.
	if (pageAddress != 0)
		mprotect((void *)pageAddress, hostPageSize, pageProtection);
	
	// Deactivates signals handling.
	signal(SIGSEGV, SIG_DFL);
	signal(SIGBUS, SIG_DFL);
	
	// Do our code in sync. Yes, in the signal handler, YOLO. Yes.
	tp_handle_bp();
}
