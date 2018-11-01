/*
 *  breaker_int.c
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
	This is 'breaker_int' - it's the breaker who works by writting a trap instruction at the entry-point.
 
 How-it-work ?
	We write an "int 3" instruction at the entry-point. When the CPU execute this instruction, it raises an exception forwarded
	as a SIGTRAP to our process. We catch this signal to remove our instruction (write back the original instruction), and
	rewind the "instruction pointer" (which is increased to the position after our "int 3" by the CPU).
	Once the signal handling is done, the CPU restart to the entry-point, and this time execute things as usual.
 
 Why ?
	The breaker allows us to do very last checking / changing (after all constructors), but before the app start to execute
	its main / start / whatever (the so-called "entry-point").
 
 Note :
	This breaker do the exact same job than 'breaker_prot', but with another mechanism. Choose the one you want to use, but don't use
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

static uint8_t			gInstruction = 0;



/*
** Prototypes
*/
#pragma mark - Prototypes

extern void tp_handle_bp(void); // have to be implemented somewhere.

static void sig_handler(int signal, siginfo_t *info, void *_ucontext);



/*
** Install entry-point breakpoint
*/
#pragma mark - Install entry-point breakpoint

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
	
	// Allow read & write.
	if (mprotect((void *)gProcessInfo.entryPage, (size_t)gProcessInfo.pageSize, PROT_READ | PROT_WRITE) != 0)
	{
		TPLogDebug("can't set rw protection to install breakpoint");
		return;
	}
	
	// Install breakpoint.
	uint8_t *code = (uint8_t *)gProcessInfo.entryPoint;
	
	gInstruction = code[0];
	code[0] = 0xCC; // "int 3" opcode
	
	// Reset protection.
	if (mprotect((void *)gProcessInfo.entryPage, (size_t)gProcessInfo.pageSize, gProcessInfo.entryProtection) != 0)
	{
		TPLogDebug("can't reset protection");
		return;
	}
	
	TPLogDebug("instruction \t 0x%02x", gInstruction);
	
	// Install signal.
	struct sigaction sig;
	
	sig.sa_sigaction = sig_handler;
	sig.sa_flags = SA_RESETHAND | SA_SIGINFO;
	
	sigaction(SIGTRAP, &sig, NULL);
}

static void sig_handler(int signal, siginfo_t *info, void *_ucontext)
{
	TPLogDebug("got signal %d", signal);
	
	ucontext_t *ucontext = _ucontext;
	
	// Check context.
	if (signal != SIGTRAP || gProcessInfoDone == false)
	{
		TPLogDebug("invalid signal or general context");
		return;
	}
	
	// Check user context.
	if (ucontext == NULL)
	{
		TPLogDebug("invalid user context");
		return;
	}
	
	// Get & check machine context.
	mcontext_t mcontext = ucontext->uc_mcontext;
	
	if (mcontext == NULL)
	{
		TPLogDebug("invalid machine context");
		return;
	}
	
#if defined(__LP64__)
	if (mcontext->__ss.__rip != gProcessInfo.entryPoint + 1) // RIP should point the data just after our "int 3" (which is 1 byte).
	{
		TPLogDebug("the rip register doesn't point to the expected address");
		return;
	}
#else
	if (mcontext->__ss.__eip != gProcessInfo.entryPoint + 1) // EIP should point the data just after our "int 3" (which is 1 byte).
	{
		TPLogDebug("the eip register doesn't point to the expected address");
		return;
	}
#endif
	
	// Change protection to write.
	if (mprotect((void *)gProcessInfo.entryPage, (size_t)gProcessInfo.pageSize, PROT_READ | PROT_WRITE) != 0)
	{
		TPLogDebug("can't set rw protection to remove breakpoint");
		return;
	}
	
	// Remove breakpoint.
	uint8_t *code = (uint8_t *)gProcessInfo.entryPoint;
	
	code[0] = gInstruction;
	
	// Reset protection.
	if (mprotect((void *)gProcessInfo.entryPage, (size_t)gProcessInfo.pageSize, gProcessInfo.entryProtection) != 0)
	{
		TPLogDebug("can't reset protection");
		return;
	}
	
	// Rewind to execute the original instruction.
#if defined(__LP64__)
	mcontext->__ss.__rip = gProcessInfo.entryPoint;
#else
	mcontext->__ss.__eip = (uint32_t)gProcessInfo.entryPoint;
#endif
	
	// Do our code in sync. Yes, in the signal handler, YOLO. Yes.
	tp_handle_bp();
}
