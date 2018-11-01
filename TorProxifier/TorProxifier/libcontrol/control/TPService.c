/*
 *  TPService.c
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

#include <dispatch/dispatch.h>
#include <servers/bootstrap.h>
#include <stdlib.h>

#include "TPService.h"


/*
** Service Port
*/
#pragma mark - Service Port

mach_port_t service_port()
{
	static mach_port_t		servicePort = MACH_PORT_DEAD;
	static dispatch_once_t	onceToken;
	
	dispatch_once(&onceToken, ^{
		if (bootstrap_look_up(bootstrap_port, TPControlServiceName, &servicePort) != KERN_SUCCESS)
		{
			TPLogDebug("can't look-up service");
#if defined(DEBUG) == NO || DEBUG == 0
			exit(1);
#endif
		}
	});
	
	return servicePort;
}



/*
** Helper for liburlhook & libtsocks
*/
#pragma mark - Helper for liburlhook & libtsocks

boolean_t tpcontrol_get_tsocks_config(char buffer[1024])
{
	return mig_client_get_setting(service_port(), "tsocks-config", buffer) == KERN_SUCCESS;
}

boolean_t tpcontrol_get_url_config(char buffer[1024])
{
	return mig_client_get_setting(service_port(), "url-config", buffer) == KERN_SUCCESS;
}
