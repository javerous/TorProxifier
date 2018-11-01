/*
 *  TPHookExec.c
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

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <spawn.h>

#include "TPEnvironmentHelper.h"


/*
 About:
	This file is there to hook exec functions, to re-install our injected libs.
 */


/*
** Prototypes
*/
#pragma mark - Prototypes

// Hooks.
static int p_execve(const char *path, char * const *argv, char * const *envp);
static int p_posix_spawn(pid_t * __restrict pid, const char * __restrict path, const posix_spawn_file_actions_t * file_actions, const posix_spawnattr_t * __restrict attrp, char *const __argv[ __restrict], char *const __envp[ __restrict]);

// Helpers.
static void free_array(char **array);



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
	{ (void *)p_execve, (void *)execve },
	{ (void *)p_posix_spawn, (void *)posix_spawn },
};



/*
** Hooks
*/
#pragma mark - Hooks

static int p_execve(const char *path, char * const *argv, char * const *envp)
{
	char **nenvp = NULL;
	
	restore_dyld_insert_buffer(envp, &nenvp);
	
#if defined(DEBUG) && DEBUG
	TPLogDebug("-- execve-env --");
	for (int i = 0; nenvp[i]; i++)
		TPLogDebug("-> '%s'", nenvp[i]);
#endif
	
	int result = execve(path, argv, nenvp);

	free_array(nenvp);

	return result;
}

static int p_posix_spawn(pid_t * __restrict pid, const char * __restrict path, const posix_spawn_file_actions_t * file_actions, const posix_spawnattr_t * __restrict attrp, char *const __argv[ __restrict], char *const __envp[ __restrict])
{
	char **nenvp = NULL;

	restore_dyld_insert_buffer(__envp, &nenvp);
	
#if defined(DEBUG) && DEBUG
	TPLogDebug("-- posix_spawn-env --");
	for (int i = 0; nenvp[i]; i++)
		TPLogDebug("-> '%s'", nenvp[i]);
#endif
	
	int result = posix_spawn(pid, path, file_actions, attrp, __argv, nenvp);
	
	free_array(nenvp);
	
	return result;
}



/*
** Helpers
*/
#pragma mark - Helpers

static void free_array(char **array)
{
	if (!array)
		return;
	
	int		i = 0;
	char	*item = NULL;
	
	while ((item = array[i++]))
		free(item);
	
	free(array);
}
