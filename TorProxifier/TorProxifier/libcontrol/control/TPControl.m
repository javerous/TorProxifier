/*
 *  TPControl.m
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

#import <Foundation/Foundation.h>

#import "TPNetworkHelper.h"

#include "TPService.h"
#include "TPEnvironmentHelper.h"


/*
** Prototypes
*/
#pragma mark - Prototypes

// Tools.
static NSDictionary * parse_json(NSData *);


/*
** Breakpoint
*/
#pragma mark - Breakpoint

void tp_handle_bp(void)
{
	// At this point in time, all libs are loaded & injected, and CPU have started to try to execute the first instruction at the entry point (main, _start, or whatever it can point to).
	
	TPLogDebug("***** handle-bp");
	
	// Gets settings.
	tp_value_t value = { 0 };
	
	mig_client_get_setting(service_port(), "check-tor", value);
	
	// Notify break.
	mig_client_notify(service_port(), "control-breaked", "");
	
	// Remove trace of injection, because some precess are checking for that.
	remove_dyld_insert();
	
	// Check tor connectivity.
	if (strcmp(value, "true") == 0)
	{
		TPLogDebug("check tor connectivity");
		
		signal(SIGPIPE, SIG_IGN);

		NSURL			*url = [NSURL URLWithString:@"https://check.torproject.org/api/ip"];
		NSURLRequest	*request = [[NSURLRequest alloc] initWithURL:url];
		
		// > Check socket.
		if ([[parse_json(data_with_socket(request)) objectForKey:@"IsTor"] boolValue])
			mig_client_notify(service_port(), "checked-tor-socket", "valid");
		else
		{
			mig_client_notify(service_port(), "checked-tor-socket", "invalid");
			thread_suspend(mach_thread_self()); // suspend ourself for eternity, and wait for a kill.
		}
		
		// > Check url-connection.
		if ([[parse_json(data_with_url_connection(request)) objectForKey:@"IsTor"] boolValue])
			mig_client_notify(service_port(), "checked-tor-urlconnection", "valid");
		else
		{
			mig_client_notify(service_port(), "checked-tor-urlconnection", "invalid");
			thread_suspend(mach_thread_self()); // suspend ourself for eternity, and wait for a kill.
		}

		// > Check url-session.
		if ([[parse_json(data_with_url_session(request)) objectForKey:@"IsTor"] boolValue])
			mig_client_notify(service_port(), "checked-tor-urlsession", "valid");
		else
		{
			mig_client_notify(service_port(), "checked-tor-urlsession", "invalid");
			thread_suspend(mach_thread_self()); // suspend ourself for eternity, and wait for a kill.
		}
		
		signal(SIGPIPE, SIG_DFL);

		TPLogDebug("checked tor connectivity");
	}
}



/*
** Tools
*/
#pragma mark - Tools

static NSDictionary * parse_json(NSData *data)
{
	if (!data)
		return nil;
	
	id result = nil;
	
	@try {
		result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	} @catch (NSException *exception) {
		return nil;
	}
	
	if ([result isKindOfClass:[NSDictionary  class]] == NO)
		return nil;
	
	return result;
}
