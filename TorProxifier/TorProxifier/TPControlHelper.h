/*
 *  TPControlHelper.h
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

#pragma once

#include <dlfcn.h>
#include <mach/mach.h>
#include <dispatch/dispatch.h>
#include <pthread.h>

// Helpers.
#define _tpcontrol_dlsym(Function)			\
({											\
	static dispatch_once_t	onceToken;		\
	static pthread_mutex_t	mutex;			\
	static void				*foo = NULL;	\
											\
	dispatch_once(&onceToken, ^{			\
		pthread_mutex_init(&mutex, NULL);	\
	});										\
											\
	pthread_mutex_lock(&mutex);				\
	if (foo == NULL)						\
		foo = dlsym(RTLD_DEFAULT, Function);\
	pthread_mutex_unlock(&mutex);			\
	foo;									\
})

// Functions.
#define tpcontrol_get_tsocks_config(Buffer)	\
({											\
	boolean_t	(*foo)(char buffer[1024]); 	\
	boolean_t	result = FALSE;				\
											\
	foo = _tpcontrol_dlsym("tpcontrol_get_tsocks_config");\
											\
	if (foo)								\
		result = foo(buffer);				\
	result;									\
})

#define tpcontrol_get_url_config(Buffer)	\
({											\
	boolean_t	(*foo)(char buffer[1024]); 	\
	boolean_t	result = FALSE;				\
											\
	foo = _tpcontrol_dlsym("tpcontrol_get_url_config");\
											\
	if (foo)								\
		result = foo(buffer);				\
	result;									\
})
