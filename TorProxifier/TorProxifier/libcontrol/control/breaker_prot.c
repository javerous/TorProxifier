/*
 *  breaker_prot.c
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
	This is 'breaker_prot' - it's the breaker who works by removing execution privilege on the page which covers the entry-point code.
 
 How-it-work ?
	When the CPU try to execute the instruction at the entry-point, it raises an exception because the protection doesn't allow it.
	This exception is forwarded as a SIGBUS / SIGSEGV to our process. We catch this signal to reset the original protection to the
	entry-point page. Once the signal handling is done, the CPU restart to the entry-point, and this time execute things as usual.
 
 Why ?
	The breaker allows us to do very last checking / changing (after all constructors), but before the app start to execute
	its main / start / whatever (the so-called "entry-point").
 
 Note :
	This breaker do the exact same job than 'breaker_int', but with another mechanism. Choose the one you want to use, but don't use
	the two at the same time (that's to say : don't compile & link the two breakers in the final lib).
 
	The two breakers are included in the project just to show two possible technic, and to let the choice between them.
 */


#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <stdbool.h>

#include <sys/mman.h>

#include "tp_info.h"


/*
** Globals
*/
#pragma mark - Globals

static tp_process_info	gProcessInfo = { 0 };
static boolean_t		gProcessInfoDone = false;



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
static void construct()
{
	// Search info.
	if (tp_get_process_info(&gProcessInfo) == false)
	{
		TPLogDebug("can't obtain process info; don't break");
		return;
	}
	
	gProcessInfoDone = true;
	
	// Debug-log info.
	TPLogDebug("headerPtr \t %p", gProcessInfo.machHeader);
	TPLogDebug("pagePtr \t 0x%llx", gProcessInfo.entryPage);
	TPLogDebug("entryPtr \t 0x%llx", gProcessInfo.entryPoint);
	
	// Allow only read-write (x86_64) or nothing (i386), so it will "break" when executing entry points.
	//   Note the protection is not the same between x86_64 & i386, because i386 doesn't allow fine grained protection.
#if defined(__x86_64__)
	if (mprotect((void *)gProcessInfo.entryPage, gProcessInfo.pageSize, (gProcessInfo.entryProtection & ~PROT_EXEC)) != 0)
#else
	if (mprotect((void *)gProcessInfo.entryPage, (size_t)gProcessInfo.pageSize, 0) != 0)
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

	if ((s != SIGSEGV && s != SIGBUS) || gProcessInfoDone == false)
	{
		TPLogDebug("invalid signal or general context");
		return;
	}
	
	// Reset initial protection, so the app can continue normal operations.
	if (gProcessInfo.entryPage != 0)
		mprotect((void *)gProcessInfo.entryPage, (size_t)gProcessInfo.pageSize, gProcessInfo.entryProtection);
	
	// Deactivates signals handling.
	signal(SIGSEGV, SIG_DFL);
	signal(SIGBUS, SIG_DFL);
	
	// Do our code in sync. Yes, in the signal handler, YOLO. Yes.
	tp_handle_bp();
}
