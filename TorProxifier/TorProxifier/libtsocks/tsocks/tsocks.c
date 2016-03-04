/*

    TSOCKS - Wrapper library for transparent SOCKS 

    Copyright (C) 2000 Shaun Clowes 

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

*/

/* PreProcessor Defines */
#include "config.h"

#ifdef USE_GNU_SOURCE
#define _GNU_SOURCE
#endif

/* Global configuration variables */
char *progname = "libtsocks";         	   /* Name used in err msgs    */

/* Header Files */
#include <Block.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <string.h>
#include <strings.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/poll.h>
#include <sys/time.h>
#include <pwd.h>
#include <errno.h>
#include <fcntl.h>
#include "common.h"
#include <stdarg.h>
#ifdef USE_SOCKS_DNS
#include <resolv.h>
#endif
#include "parser.h"
#include "tsocks.h"
#include "dead_pool.h"


/* Global Declarations */
#ifdef USE_TOR_DNS
static dead_pool *pool = NULL;
#endif

static struct parsedfile *config;
static struct connreq *requests = NULL;
static int suid = 0;
static char *conffile = NULL;
static char *confdata = NULL;

/* Exported Function Prototypes */
int connect(CONNECT_SIGNATURE);
int select(SELECT_SIGNATURE);
int poll(POLL_SIGNATURE);
int close(CLOSE_SIGNATURE);
int getpeername(GETPEERNAME_SIGNATURE);
#ifdef USE_SOCKS_DNS
int res_init(void);
#endif
#ifdef USE_TOR_DNS
struct hostent *gethostbyname(GETHOSTBYNAME_SIGNATURE);
int getaddrinfo(GETADDRINFO_SIGNATURE);
struct hostent *getipnodebyname(GETIPNODEBYNAME_SIGNATURE);
#endif 

/* Private Function Prototypes */
static void _init(void);
static int get_config();
static int get_environment();
static int connect_server(struct connreq *conn);
static int send_socks_request(struct connreq *conn);
static struct connreq *new_socks_request(int sockid, struct sockaddr_in *connaddr, 
                                         struct sockaddr_in *serveraddr, 
                                         struct serverent *path);
static void kill_socks_request(struct connreq *conn);
static int handle_request(struct connreq *conn);
static struct connreq *find_socks_request(int sockid, int includefailed);
static int connect_server(struct connreq *conn);
static int send_socks_request(struct connreq *conn);
static int send_socksv4_request(struct connreq *conn);
static int send_socksv5_method(struct connreq *conn);
static int send_socksv5_connect(struct connreq *conn);
static int send_buffer(struct connreq *conn);
static int recv_buffer(struct connreq *conn);
static int read_socksv5_method(struct connreq *conn);
static int read_socksv4_req(struct connreq *conn);
static int read_socksv5_connect(struct connreq *conn);
static int read_socksv5_auth(struct connreq *conn);
#ifdef USE_TOR_DNS
static int deadpool_init();
static int send_socksv4a_request(struct connreq *conn, const char *onion_host);
#endif

// --JP/
#include "TPControlHelper.h"

static void __attribute((constructor)) tp_constructor()
{
	fprintf(stderr, "****** tsocks loaded ******\n");
	
	_init();
}
// --JP!

#ifdef USE_SOCKS_DNS
int p_res_init(void);
#endif
#if defined(USE_TOR_DNS) && USE_TOR_DNS
struct hostent *	p_gethostbyname(GETHOSTBYNAME_SIGNATURE);
int					p_getaddrinfo(GETADDRINFO_SIGNATURE);
struct hostent *	p_getipnodebyname(GETIPNODEBYNAME_SIGNATURE);
#endif

int p_connect(CONNECT_SIGNATURE);

int p_select(SELECT_SIGNATURE);
int p_poll(POLL_SIGNATURE);
int p_close(CLOSE_SIGNATURE);
int p_getpeername(GETPEERNAME_SIGNATURE);


// From 'OS X Internal'
typedef struct interpose_s {
	void *new_func;
	void *origin_func;
} interpose_t;

__attribute__((used)) static const interpose_t interposers[] __attribute__((section("__DATA,__interpose"))) = {
	
#if defined(USE_SOCKS_DNS) && USE_SOCKS_DNS
	{ (void *)p_res_init, (void *)res_init },
#endif
	
#if defined(USE_TOR_DNS) && USE_TOR_DNS
	{ (void *)p_gethostbyname, (void *)gethostbyname },
	{ (void *)p_getaddrinfo, (void *)getaddrinfo },
	{ (void *)p_getipnodebyname, (void *)getipnodebyname },
#endif

	{ (void *)p_connect, (void *)connect },
	{ (void *)p_select, (void *)select },
	{ (void *)p_poll, (void *)poll },
	{ (void *)p_close, (void *)close },
	{ (void *)p_getpeername, (void *)getpeername },
};
// --JP!


static void _init(void) {

	/* We could do all our initialization here, but to be honest */
	/* most programs that are run won't use our services, so     */
	/* we do our general initialization on first call            */

	/* Determine the logging level */
	suid = (getuid() != geteuid());
	
	get_environment();
	get_config();
	
#ifdef USE_TOR_DNS
     /* Unfortunately, we can't do this lazily because otherwise our mmap'd
        area won't be shared across fork()s. */
     deadpool_init();
#endif

}

static int get_environment() {
   static int done = 0;
   int loglevel = MSGERR;
   char *logfile = NULL;
   char *env;

   if (done)
      return(0);

   /* Determine the logging level */
#ifndef ALLOW_MSG_OUTPUT
   set_log_options(-1, stderr, 0);
#else
   if ((env = getenv("TSOCKS_DEBUG")))
      loglevel = atoi(env);
   if (((env = getenv("TSOCKS_DEBUG_FILE"))) && !suid)
      logfile = env;
   set_log_options(loglevel, logfile, 1);
#endif

   done = 1;

   return(0);
}

static int get_config () {
   static int done = 0;

   if (done)
      return(0);

	/* Read in the config file */
	config = malloc(sizeof(*config));
	if (!config)
		return(0);
	
   /* Determine the location of the config file */
	line_enumerator liner = NULL;
	
#ifdef ALLOW_ENV_CONFIG
   if (!suid)
   {
	   // --JP/
	   confdata = getenv("TSOCKS_CONF_DATA");
	   
	   if (confdata)
		   liner = line_enumerator_buffer(confdata);
	   else
	   {
		   conffile = getenv("TSOCKS_CONF_FILE");

		   if (conffile)
			   liner = line_enumerator_file(conffile);
		   else
			   liner = line_enumerator_file(CONF_FILE);
	   }
   }
#else
	char buffer[1024] = { 0 };
	
	tpcontrol_get_tsocks_config(buffer);

#if defined(DEBUG) && DEBUG
	fprintf(stderr, "[tsocks] Use tsocks config: %s\n", buffer);
#endif
	liner = line_enumerator_buffer(buffer);
	
	(void)conffile;
	(void)confdata;

#endif
	
   read_config(liner, config);
	
   if (liner)
      Block_release(liner);
	// --JP!
	
   if (config->paths)
      show_msg(MSGDEBUG, "First lineno for first path is %d\n", config->paths->lineno);

   done = 1;

   return(0);
}

int p_connect(CONNECT_SIGNATURE) {
	struct sockaddr_in *connaddr;
	struct sockaddr_in peer_address;
	struct sockaddr_in server_address;
	int gotvalidserver = 0, rc;
	socklen_t namelen = sizeof(peer_address);
	int sock_type = -1;
	socklen_t sock_type_len = sizeof(sock_type);
	unsigned int res = -1;
	struct serverent *path;
   struct connreq *newconn;

   get_environment();
	
	char *ipstr;
	
	connaddr = (struct sockaddr_in *) __addr;
	ipstr = inet_ntoa(connaddr->sin_addr); // return the IP
	
  	show_msg(MSGDEBUG, "Got connection request (%s).\n", ipstr);


	/* Get the type of the socket */
	getsockopt(__fd, SOL_SOCKET, SO_TYPE, 
		   (void *) &sock_type, &sock_type_len);

	/* If this isn't an INET socket for a TCP stream we can't  */
	/* handle it, just call the real connect now               */
   if ((connaddr->sin_family != AF_INET) ||
       (sock_type != SOCK_STREAM)) {
      show_msg(MSGDEBUG, "Connection isn't a TCP stream ignoring (sin_family=%d; sock_type=%d)\n", connaddr->sin_family, sock_type);
		return(connect(__fd, __addr, __len));
   }

   /* If we haven't initialized yet, do it now */
   get_config();

   /* Are we already handling this connect? */
   if ((newconn = find_socks_request(__fd, 1))) {
      if (memcmp(&newconn->connaddr, connaddr, sizeof(*connaddr))) {
         /* Ok, they're calling connect on a socket that is in our
          * queue but this connect() isn't to the same destination, 
          * they're obviously not trying to check the status of 
          * they're non blocking connect, they must have close()d 
          * the other socket and created a new one which happens
          * to have the same fd as a request we haven't had the chance
          * to delete yet, so we delete it here. */
         show_msg(MSGDEBUG, "Call to connect received on old "
                            "tsocks request for socket %d but to "
                            "new destination, deleting old request\n",
                  newconn->sockid);
         kill_socks_request(newconn);
      } else {
         /* Ok, this call to connect() is to check the status of 
          * a current non blocking connect(). */
         if (newconn->state == FAILED) {
            show_msg(MSGDEBUG, "Call to connect received on failed "
                               "request %d, returning %d\n",
                     newconn->sockid, newconn->err);
            errno = newconn->err;
            rc = -1;
         } else if (newconn->state == DONE) {
            show_msg(MSGERR, "Call to connect received on completed "
                             "request %d\n",
                     newconn->sockid, newconn->err);
            rc = 0;
         } else {
            show_msg(MSGDEBUG, "Call to connect received on current request %d\n",
                     newconn->sockid);
            rc = handle_request(newconn);
            errno = rc;
         }
         if ((newconn->state == FAILED) || (newconn->state == DONE))
            kill_socks_request(newconn);
         return((rc ? -1 : 0));
      }
   }

   /* If the socket is already connected, just call connect  */
   /* and get its standard reply                             */
   if (!getpeername(__fd, (struct sockaddr *) &peer_address, &namelen)) {
      show_msg(MSGDEBUG, "Socket is already connected, defering to "
                         "real connect\n");
		return(connect(__fd, __addr, __len));
   }
     
   show_msg(MSGDEBUG, "Got connection request for socket %d to "
                      "%s\n", __fd, inet_ntoa(connaddr->sin_addr));

   /* If the address is local call realconnect */
#ifdef USE_TOR_DNS
   if (!(is_local(config, &(connaddr->sin_addr))) && 
       !is_dead_address(pool, connaddr->sin_addr.s_addr)) {
#else 
   if (!(is_local(config, &(connaddr->sin_addr)))) {
#endif
      show_msg(MSGDEBUG, "Connection for socket %d is local\n", __fd);
      return(connect(__fd, __addr, __len));
   }

   /* Ok, so its not local, we need a path to the net */
   pick_server(config, &path, &(connaddr->sin_addr), ntohs(connaddr->sin_port));

   show_msg(MSGDEBUG, "Picked server %s for connection\n",
            (path->address ? path->address : "(Not Provided)"));
   if (path->address == NULL) {
      if (path == &(config->defaultserver)) 
         show_msg(MSGERR, "Connection needs to be made "
                          "via default server but "
                          "the default server has not "
                          "been specified\n");
      else 
         show_msg(MSGERR, "Connection needs to be made "
                          "via path specified at line "
                          "%d in configuration file but "
                          "the server has not been "
                          "specified for this path\n",
                  path->lineno);
   } else if ((res = resolve_ip(path->address, 0, HOSTNAMES)) == -1) {
      show_msg(MSGERR, "The SOCKS server (%s) listed in the configuration "
                       "file which needs to be used for this connection "
                       "is invalid\n", path->address);
   } else {	
      /* Construct the addr for the socks server */
      server_address.sin_family = AF_INET; /* host byte order */
      server_address.sin_addr.s_addr = res;
      server_address.sin_port = htons(path->port);
      bzero(&(server_address.sin_zero), 8);

      /* Complain if this server isn't on a localnet */
      if (is_local(config, &server_address.sin_addr)) {
         show_msg(MSGERR, "SOCKS server %s (%s) is not on a local subnet!\n", 
                  path->address, inet_ntoa(server_address.sin_addr));
      } else 
         gotvalidserver = 1;
   }

   /* If we haven't found a valid server we return connection refused */
   if (!gotvalidserver || 
       !(newconn = new_socks_request(__fd, connaddr, &server_address, path))) {
      errno = ECONNREFUSED;
      return(-1);
   } else {
      /* Now we call the main function to handle the connect. */
      rc = handle_request(newconn);
      /* If the request completed immediately it mustn't have been
       * a non blocking socket, in this case we don't need to know
       * about this socket anymore. */
      if ((newconn->state == FAILED) || (newconn->state == DONE))
         kill_socks_request(newconn);
      errno = rc;
      return((rc ? -1 : 0));
   }
}

int p_select(SELECT_SIGNATURE) {
   int nevents = 0;
   int rc = 0;
   int setevents = 0;
   int monitoring = 0;
   struct connreq *conn, *nextconn;
   fd_set mywritefds, myreadfds, myexceptfds;

   /* If we're not currently managing any requests we can just 
    * leave here */
   if (!requests) {
      show_msg(MSGDEBUG, "No requests waiting, calling real select\n");
      return(select(n, readfds, writefds, exceptfds, timeout));
   }

   get_environment();

   show_msg(MSGDEBUG, "Intercepted call to select with %d fds, "
            "0x%08x 0x%08x 0x%08x, timeout %08x\n", n, 
            readfds, writefds, exceptfds, timeout);

   for (conn = requests; conn != NULL; conn = conn->next) {
      if ((conn->state == FAILED) || (conn->state == DONE))
         continue;
      conn->selectevents = 0;
      show_msg(MSGDEBUG, "Checking requests for socks enabled socket %d\n",
               conn->sockid);
      conn->selectevents |= (writefds ? (FD_ISSET(conn->sockid, writefds) ? WRITE : 0) : 0);
      conn->selectevents |= (readfds ? (FD_ISSET(conn->sockid, readfds) ? READ : 0) : 0);
      conn->selectevents |= (exceptfds ? (FD_ISSET(conn->sockid, exceptfds) ? EXCEPT : 0) : 0);
      if (conn->selectevents) {
         show_msg(MSGDEBUG, "Socket %d was set for events\n", conn->sockid);
         monitoring = 1;
      }
   }

   if (!monitoring)
      return(select(n, readfds, writefds, exceptfds, timeout));

   /* This is our select loop. In it we repeatedly call select(). We 
    * pass select the same fdsets as provided by the caller except we
    * modify the fdsets for the sockets we're managing to get events
    * we're interested in (while negotiating with the socks server). When
    * events we're interested in happen we go off and process the result
    * ourselves, without returning the events to the caller. The loop
    * ends when an event which isn't one we need to handle occurs or 
    * the select times out */
   do {
      /* Copy the clients fd events, we'll change them as we wish */
      if (readfds)
         memcpy(&myreadfds, readfds, sizeof(myreadfds));
      else
         FD_ZERO(&myreadfds);
      if (writefds)
         memcpy(&mywritefds, writefds, sizeof(mywritefds));
      else
         FD_ZERO(&mywritefds);
      if (exceptfds)
         memcpy(&myexceptfds, exceptfds, sizeof(myexceptfds));
      else
         FD_ZERO(&myexceptfds);

      /* Now enable our sockets for the events WE want to hear about */
      for (conn = requests; conn != NULL; conn = conn->next) {
         if ((conn->state == FAILED) || (conn->state == DONE) ||
             (conn->selectevents == 0))
            continue;
         /* We always want to know about socket exceptions */
         FD_SET(conn->sockid, &myexceptfds);
         /* If we're waiting for a connect or to be able to send
          * on a socket we want to get write events */
         if ((conn->state == SENDING) || (conn->state == CONNECTING))
            FD_SET(conn->sockid,&mywritefds);
         else
            FD_CLR(conn->sockid,&mywritefds);
         /* If we're waiting to receive data we want to get 
          * read events */
         if (conn->state == RECEIVING)
            FD_SET(conn->sockid,&myreadfds);
         else
            FD_CLR(conn->sockid,&myreadfds);
      }

      nevents = select(n, &myreadfds, &mywritefds, &myexceptfds, timeout);
      /* If there were no events we must have timed out or had an error */
      if (nevents <= 0)
         break;

      /* Loop through all the sockets we're monitoring and see if 
       * any of them have had events */
      for (conn = requests; conn != NULL; conn = nextconn) {
         nextconn = conn->next;
         if ((conn->state == FAILED) || (conn->state == DONE))
            continue;
         show_msg(MSGDEBUG, "Checking socket %d for events\n", conn->sockid);
         /* Clear all the events on the socket (if any), we'll reset
          * any that are necessary later. */
         setevents = 0;
         if (FD_ISSET(conn->sockid, &mywritefds))  {
            nevents--;
            setevents |= WRITE;
            show_msg(MSGDEBUG, "Socket had write event\n");
            FD_CLR(conn->sockid, &mywritefds);
         }
         if (FD_ISSET(conn->sockid, &myreadfds))  {
            nevents--;
            setevents |= READ;
            show_msg(MSGDEBUG, "Socket had write event\n");
            FD_CLR(conn->sockid, &myreadfds);
         }
         if (FD_ISSET(conn->sockid, &myexceptfds))  {
            nevents--;
            setevents |= EXCEPT;
            show_msg(MSGDEBUG, "Socket had except event\n");
            FD_CLR(conn->sockid, &myexceptfds);
         }

         if (!setevents) {
            show_msg(MSGDEBUG, "No events on socket %d\n", conn->sockid);
            continue;
         }

         if (setevents & EXCEPT) {
            conn->state = FAILED;
         } else {
            rc = handle_request(conn);
         }
         /* If the connection hasn't failed or completed there is nothing
          * to report to the client */
         if ((conn->state != FAILED) && 
             (conn->state != DONE))  
            continue;

         /* Ok, the connection is completed, for good or for bad. We now
          * hand back the relevant events to the caller. We don't delete the
          * connection though since the caller should call connect() to 
          * check the status, we delete it then */

         if (conn->state == FAILED) {
            /* Damn, the connection failed. Whatever the events the socket
             * was selected for we flag */
            if (conn->selectevents & EXCEPT) {
               FD_SET(conn->sockid, &myexceptfds);
               nevents++;
            }
            if (conn->selectevents & READ) {
               FD_SET(conn->sockid, &myreadfds);
               nevents++;
            }
            if (conn->selectevents & WRITE) {
               FD_SET(conn->sockid, &mywritefds);
               nevents++;
            }
            /* We should use setsockopt to set the SO_ERROR errno for this 
             * socket, but this isn't allowed for some silly reason which 
             * leaves us a bit hamstrung.
             * We don't delete the request so that hopefully we can 
             * return the error on the socket if they call connect() on it */
         } else {
            /* The connection is done,  if the client selected for 
             * writing we can go ahead and signal that now (since the socket must
             * be ready for writing), otherwise we'll just let the select loop
             * come around again (since we can't flag it for read, we don't know
             * if there is any data to be read and can't be bothered checking) */
            if (conn->selectevents & WRITE) {
               FD_SET(conn->sockid, &mywritefds);
               nevents++;
            }
         }
      }
   } while (nevents == 0);

   show_msg(MSGDEBUG, "Finished intercepting select(), %d events\n", nevents);

   /* Now copy our event blocks back to the client blocks */
   if (readfds)
      memcpy(readfds, &myreadfds, sizeof(myreadfds));
   if (writefds)
      memcpy(writefds, &mywritefds, sizeof(mywritefds));
   if (exceptfds)
      memcpy(exceptfds, &myexceptfds, sizeof(myexceptfds));

   return(nevents);
}

int p_poll(POLL_SIGNATURE) {
   int nevents = 0;
   int rc = 0, i;
   int setevents = 0;
   int monitoring = 0;
   struct connreq *conn, *nextconn;

   /* If we're not currently managing any requests we can just 
    * leave here */
   if (!requests)
      return(poll(ufds, nfds, timeout));

   get_environment();

   show_msg(MSGDEBUG, "Intercepted call to poll with %d fds, "
            "0x%08x timeout %d\n", nfds, ufds, timeout);

   for (conn = requests; conn != NULL; conn = conn->next)
      conn->selectevents = 0;

   /* Record what events on our sockets the caller was interested
    * in */
   for (i = 0; i < nfds; i++) {
      if (!(conn = find_socks_request(ufds[i].fd, 0)))
         continue;
      show_msg(MSGDEBUG, "Have event checks for socks enabled socket %d\n",
               conn->sockid);
      conn->selectevents = ufds[i].events;
      monitoring = 1;
   }

   if (!monitoring)
      return(poll(ufds, nfds, timeout));

   /* This is our poll loop. In it we repeatedly call poll(). We 
    * pass select the same event list as provided by the caller except we
    * modify the events for the sockets we're managing to get events
    * we're interested in (while negotiating with the socks server). When
    * events we're interested in happen we go off and process the result
    * ourselves, without returning the events to the caller. The loop
    * ends when an event which isn't one we need to handle occurs or 
    * the poll times out */
   do {
      /* Enable our sockets for the events WE want to hear about */
      for (i = 0; i < nfds; i++) {
         if (!(conn = find_socks_request(ufds[i].fd, 0)))
            continue;

         /* We always want to know about socket exceptions but they're 
          * always returned (i.e they don't need to be in the list of 
          * wanted events to be returned by the kernel */
         ufds[i].events = 0;

         /* If we're waiting for a connect or to be able to send
          * on a socket we want to get write events */
         if ((conn->state == SENDING) || (conn->state == CONNECTING))
            ufds[i].events |= POLLOUT;
         /* If we're waiting to receive data we want to get 
          * read events */
         if (conn->state == RECEIVING)
            ufds[i].events |= POLLIN;
      }

      nevents = poll(ufds, nfds, timeout);
      /* If there were no events we must have timed out or had an error */
      if (nevents <= 0)
         break;

      /* Loop through all the sockets we're monitoring and see if 
       * any of them have had events */
      for (conn = requests; conn != NULL; conn = nextconn) {
         nextconn = conn->next;
         if ((conn->state == FAILED) || (conn->state == DONE))
            continue;

         /* Find the socket in the poll list */
         for (i = 0; ((i < nfds) && (ufds[i].fd != conn->sockid)); i++)
            /* Empty Loop */;
         if (i == nfds) 
            continue;

         show_msg(MSGDEBUG, "Checking socket %d for events\n", conn->sockid);

         if (!ufds[i].revents) {
            show_msg(MSGDEBUG, "No events on socket\n");
            continue;
         }

         /* Clear any read or write events on the socket, we'll reset
          * any that are necessary later. */
         setevents = ufds[i].revents;
         if (setevents & POLLIN) {
            show_msg(MSGDEBUG, "Socket had read event\n");
            ufds[i].revents &= ~POLLIN;
            nevents--;
         }
         if (setevents & POLLOUT) {
            show_msg(MSGDEBUG, "Socket had write event\n");
            ufds[i].revents &= ~POLLOUT;
            nevents--;
         }
         if (setevents & (POLLERR | POLLNVAL | POLLHUP)) 
            show_msg(MSGDEBUG, "Socket had error event\n");

         /* Now handle this event */
         if (setevents & (POLLERR | POLLNVAL | POLLHUP)) {
            conn->state = FAILED;
         } else {
            rc = handle_request(conn);
         }
         /* If the connection hasn't failed or completed there is nothing
          * to report to the client */
         if ((conn->state != FAILED) && 
             (conn->state != DONE))  
            continue;

         /* Ok, the connection is completed, for good or for bad. We now
          * hand back the relevant events to the caller. We don't delete the
          * connection though since the caller should call connect() to 
          * check the status, we delete it then */

         if (conn->state == FAILED) {
            /* Damn, the connection failed. Just copy back the error events 
             * from the poll call, error events are always valid even if not
             * requested by the client */
            /* We should use setsockopt to set the SO_ERROR errno for this 
             * socket, but this isn't allowed for some silly reason which 
             * leaves us a bit hamstrung.
             * We don't delete the request so that hopefully we can 
             * return the error on the socket if they call connect() on it */
         } else {
            /* The connection is done,  if the client polled for 
             * writing we can go ahead and signal that now (since the socket must
             * be ready for writing), otherwise we'll just let the select loop
             * come around again (since we can't flag it for read, we don't know
             * if there is any data to be read and can't be bothered checking) */
            if (conn->selectevents & WRITE) {
               setevents |= POLLOUT; 
               nevents++;
            }
         }
      }
   } while (nevents == 0);

   show_msg(MSGDEBUG, "Finished intercepting poll(), %d events\n", nevents);

   /* Now restore the events polled in each of the blocks */
   for (i = 0; i < nfds; i++) {
      if (!(conn = find_socks_request(ufds[i].fd, 1)))
         continue;

      ufds[i].events = conn->selectevents;
   }

   return(nevents);
}

int p_close(CLOSE_SIGNATURE) {
   int rc;
   struct connreq *conn;

   show_msg(MSGDEBUG, "Call to close(%d)\n", fd);

   rc = close(fd);

   /* If we have this fd in our request handling list we 
    * remove it now */
   if ((conn = find_socks_request(fd, 1))) {
      show_msg(MSGDEBUG, "Call to close() received on file descriptor "
                         "%d which is a connection request of status %d\n",
               conn->sockid, conn->state);
      kill_socks_request(conn);
   }

   return(rc);
}

/* If we are not done setting up the connection yet, return
 * -1 and ENOTCONN, otherwise call getpeername
 *
 * This is necessary since some applications, when using non-blocking connect,
 * (like ircII) use getpeername() to find out if they are connected already.
 *
 * This results in races sometimes, where the client sends data to the socket
 * before we are done with the socks connection setup.  Another solution would
 * be to intercept send().
 * 
 * This could be extended to actually set the peername to the peer the
 * client application has requested, but not for now.
 *
 * PP, Sat, 27 Mar 2004 11:30:23 +0100
 */
int p_getpeername(GETPEERNAME_SIGNATURE) {
   struct connreq *conn;
   int rc;

   show_msg(MSGDEBUG, "Call to getpeername for fd %d\n", __fd);

   rc = getpeername(__fd, __name, __namelen);
   if (rc == -1)
       return rc;

   /* Are we handling this connect? */
   if ((conn = find_socks_request(__fd, 1))) {
       /* While we are at it, we might was well try to do something useful */
       handle_request(conn);

       if (conn->state != DONE) {
           errno = ENOTCONN;
           return(-1);
       }
   }
   return rc;
}

static struct connreq *new_socks_request(int sockid, struct sockaddr_in *connaddr, 
                                         struct sockaddr_in *serveraddr, 
                                         struct serverent *path) {
   struct connreq *newconn;

   if ((newconn = malloc(sizeof(*newconn))) == NULL) {
      /* Could not malloc, we're stuffed */
      show_msg(MSGERR, "Could not allocate memory for new socks request\n");
      return(NULL);
   }

   /* Add this connection to be proxied to the list */
   memset(newconn, 0x0, sizeof(*newconn));
   newconn->sockid = sockid;
   newconn->state = UNSTARTED;
   newconn->path = path;
   memcpy(&(newconn->connaddr), connaddr, sizeof(newconn->connaddr));
   memcpy(&(newconn->serveraddr), serveraddr, sizeof(newconn->serveraddr));
   newconn->next = requests;
   requests = newconn;
   
   return(newconn);
}

static void kill_socks_request(struct connreq *conn) {
   struct connreq *connnode;

   if (requests == conn)
      requests = conn->next;
   else {
      for (connnode = requests; connnode != NULL; connnode = connnode->next) {
         if (connnode->next == conn) {
            connnode->next = conn->next;
            break;
         }
      }
   }

   free(conn);
}

static struct connreq *find_socks_request(int sockid, int includefinished) {
   struct connreq *connnode;

   for (connnode = requests; connnode != NULL; connnode = connnode->next) {
      if (connnode->sockid == sockid) {
         if (((connnode->state == FAILED) || (connnode->state == DONE)) && 
             !includefinished)
            break;
         else 
            return(connnode);
      }
   }

   return(NULL);
}

static int handle_request(struct connreq *conn) {
   int rc = 0;
   int i = 0;

   show_msg(MSGDEBUG, "Beginning handle loop for socket %d\n", conn->sockid);

   while ((rc == 0) && 
          (conn->state != FAILED) &&
          (conn->state != DONE) && 
          (i++ < 20)) {
      show_msg(MSGDEBUG, "In request handle loop for socket %d, "
                         "current state of request is %d\n", conn->sockid, 
                         conn->state);
      switch(conn->state) {
         case UNSTARTED:
         case CONNECTING:
            rc = connect_server(conn);
            break;
         case CONNECTED:
            rc = send_socks_request(conn);
            break;
         case SENDING:
            rc = send_buffer(conn);
            break;
         case RECEIVING:
            rc = recv_buffer(conn);
            break;
         case SENTV4REQ:
            show_msg(MSGDEBUG, "Receiving reply to SOCKS V4 connect request\n");
            conn->datalen = sizeof(struct sockrep);
            conn->datadone = 0;
            conn->state = RECEIVING;
            conn->nextstate = GOTV4REQ;
            break;
         case GOTV4REQ:
            rc = read_socksv4_req(conn);
            break;
         case SENTV5METHOD:
            show_msg(MSGDEBUG, "Receiving reply to SOCKS V5 method negotiation\n");
            conn->datalen = 2;
            conn->datadone = 0;
            conn->state = RECEIVING;
            conn->nextstate = GOTV5METHOD;
            break;
         case GOTV5METHOD:
            rc = read_socksv5_method(conn);
            break;
         case SENTV5AUTH:
            show_msg(MSGDEBUG, "Receiving reply to SOCKS V5 authentication negotiation\n");
            conn->datalen = 2;
            conn->datadone = 0;
            conn->state = RECEIVING;
            conn->nextstate = GOTV5AUTH;
            break;
         case GOTV5AUTH:
            rc = read_socksv5_auth(conn);
            break;
         case SENTV5CONNECT:
            show_msg(MSGDEBUG, "Receiving reply to SOCKS V5 connect request\n");
            conn->datalen = 10;
            conn->datadone = 0;
            conn->state = RECEIVING;
            conn->nextstate = GOTV5CONNECT;
            break;
         case GOTV5CONNECT:
            rc = read_socksv5_connect(conn);
            break;
      }

      conn->err = errno;
   }

   if (i == 20)
      show_msg(MSGERR, "Ooops, state loop while handling request %d\n", 
               conn->sockid);

   show_msg(MSGDEBUG, "Handle loop completed for socket %d in state %d, "
                      "returning %d\n", conn->sockid, conn->state, rc);
   return(rc);
}

static int connect_server(struct connreq *conn) {
   int rc;

	/* Connect this socket to the socks server */
   show_msg(MSGDEBUG, "Connecting to %s port %d\n", 
            inet_ntoa(conn->serveraddr.sin_addr), ntohs(conn->serveraddr.sin_port));

   rc = connect(conn->sockid, (CONNECT_SOCKARG) &(conn->serveraddr),
                    sizeof(conn->serveraddr));

   show_msg(MSGDEBUG, "Connect returned %d, errno is %d\n", rc, errno); 
   if (rc) {
      if (errno != EINPROGRESS) {
         show_msg(MSGERR, "Error %d attempting to connect to SOCKS "
                  "server (%s)\n", errno, strerror(errno));
         conn->state = FAILED;
      } else {
         show_msg(MSGDEBUG, "Connection in progress\n");
         conn->state = CONNECTING;
      }
   } else {
      show_msg(MSGDEBUG, "Socket %d connected to SOCKS server\n", conn->sockid);
      conn->state = CONNECTED;
   }

   return((rc ? errno : 0));
}

static int send_socks_request(struct connreq *conn) {
	int rc = 0;

#ifdef USE_TOR_DNS
    if (conn->path->type == 4) {
        char *name = get_pool_entry(pool, &(conn->connaddr.sin_addr));
        if(name != NULL) {
            rc = send_socksv4a_request(conn,name);
        } else {
            rc = send_socksv4_request(conn);
        }
#else 
    if (conn->path->type == 4) {
      rc = send_socksv4_request(conn);
#endif
    } else {
	  rc = send_socksv5_method(conn);
	}
   return(rc);
}			

#ifdef USE_TOR_DNS
static int send_socksv4a_request(struct connreq *conn,const char *onion_host) 
{
  struct passwd *user;
  struct sockreq *thisreq;
  int endOfUser;
  /* Determine the current username */
  user = getpwuid(getuid());	

  thisreq = (struct sockreq *) conn->buffer;
  endOfUser=sizeof(struct sockreq) +
  (user == NULL ? 0 : (int)strlen(user->pw_name)) + 1;

  /* Check the buffer has enough space for the request  */
  /* and the user name                                  */
  conn->datalen = endOfUser+ 
                  (onion_host == NULL ? 0 : (int)strlen(onion_host)) + 1;
  if (sizeof(conn->buffer) < conn->datalen) {
      show_msg(MSGERR, "The SOCKS username is too long");
      conn->state = FAILED;
      return(ECONNREFUSED);
  }

  /* Create the request */
  thisreq->version = 4;
  thisreq->command = 1;
  thisreq->dstport = conn->connaddr.sin_port;
  thisreq->dstip   = htonl(1);

  /* Copy the username */
  strcpy((char *) thisreq + sizeof(struct sockreq), 
         (user == NULL ? "" : user->pw_name));

  /* Copy the onion host */
  strcpy((char *) thisreq + endOfUser,
         (onion_host == NULL ? "" : onion_host));

  conn->datadone = 0;
  conn->state = SENDING;
  conn->nextstate = SENTV4REQ;

  return(0);   
}
#endif /* USE_TOR_DNS */

static int send_socksv4_request(struct connreq *conn) {
	struct passwd *user;
	struct sockreq *thisreq;
	
	/* Determine the current username */
	user = getpwuid(getuid());	

   thisreq = (struct sockreq *) conn->buffer;

   /* Check the buffer has enough space for the request  */
   /* and the user name                                  */
   conn->datalen = sizeof(struct sockreq) + 
                   (user == NULL ? 0 : (int)strlen(user->pw_name)) + 1;
   if (sizeof(conn->buffer) < conn->datalen) {
      show_msg(MSGERR, "The SOCKS username is too long");
      conn->state = FAILED;
      return(ECONNREFUSED);
   }

	/* Create the request */
	thisreq->version = 4;
	thisreq->command = 1;
	thisreq->dstport = conn->connaddr.sin_port;
	thisreq->dstip   = conn->connaddr.sin_addr.s_addr;

	/* Copy the username */
	strcpy((char *) thisreq + sizeof(struct sockreq), 
	       (user == NULL ? "" : user->pw_name));

   conn->datadone = 0;
   conn->state = SENDING;
   conn->nextstate = SENTV4REQ;

	return(0);   
}			

static int send_socksv5_method(struct connreq *conn) {
   char verstring[] = { 0x05,    /* Version 5 SOCKS */
                        0x02,    /* No. Methods     */
                        0x00,    /* Null Auth       */
                        0x02 };  /* User/Pass Auth  */

   show_msg(MSGDEBUG, "Constructing V5 method negotiation\n");
   conn->state = SENDING;
   conn->nextstate = SENTV5METHOD;
   memcpy(conn->buffer, verstring, sizeof(verstring)); 
   conn->datalen = sizeof(verstring);
   conn->datadone = 0;

   return(0);
}			

static int send_socksv5_connect(struct connreq *conn) {
#ifdef USE_TOR_DNS
   int namelen = 0;
   char *name = NULL;
#endif
   char constring[] = { 0x05,    /* Version 5 SOCKS */
                        0x01,    /* Connect request */
                        0x00,    /* Reserved        */
                        0x01 };  /* IP Version 4    */

   show_msg(MSGDEBUG, "Constructing V5 connect request\n");
   conn->datadone = 0;
   conn->state = SENDING;
   conn->nextstate = SENTV5CONNECT;
   memcpy(conn->buffer, constring, sizeof(constring)); 
   conn->datalen = sizeof(constring);

#ifdef USE_TOR_DNS
   show_msg(MSGDEBUG, "send_socksv5_connect: looking for: %s\n",
            inet_ntoa(conn->connaddr.sin_addr));

   name = get_pool_entry(pool, &(conn->connaddr.sin_addr));
   if(name != NULL) {
       namelen = (int)strlen(name);
       if(namelen > 255) {  /* "Can't happen" */
           name = NULL;
       }
   }
   if(name != NULL) {
       show_msg(MSGDEBUG, "send_socksv5_connect: found it!\n");
       /* Substitute the domain name from the pool into the SOCKS request. */
       conn->buffer[3] = 0x03;  /* Change the ATYP field */
       conn->buffer[4] = namelen;  /* Length of name */
       conn->datalen++;
       memcpy(&conn->buffer[conn->datalen], name, namelen);
       conn->datalen += namelen;
   } else {
       show_msg(MSGDEBUG, "send_socksv5_connect: ip address not found\n");
#endif
       /* Use the raw IP address */
       memcpy(&conn->buffer[conn->datalen], &(conn->connaddr.sin_addr.s_addr), 
              sizeof(conn->connaddr.sin_addr.s_addr));
       conn->datalen += sizeof(conn->connaddr.sin_addr.s_addr);
#ifdef USE_TOR_DNS
   }
#endif
   memcpy(&conn->buffer[conn->datalen], &(conn->connaddr.sin_port), 
        sizeof(conn->connaddr.sin_port));
   conn->datalen += sizeof(conn->connaddr.sin_port);

   return(0);
}			

static int send_buffer(struct connreq *conn) {
   int rc = 0;

   show_msg(MSGDEBUG, "Writing to server (sending %d bytes)\n", conn->datalen);
   while ((rc == 0) && (conn->datadone != conn->datalen)) {
      rc = (int)send(conn->sockid, conn->buffer + conn->datadone,
                conn->datalen - conn->datadone, 0);
      if (rc > 0) {
         conn->datadone += rc;
         rc = 0;
      } else {
         if (errno != EWOULDBLOCK)
            show_msg(MSGDEBUG, "Write failed, %s\n", strerror(errno));
         rc = errno;
      }
   }

   if (conn->datadone == conn->datalen)
      conn->state = conn->nextstate;

   show_msg(MSGDEBUG, "Sent %d bytes of %d bytes in buffer, return code is %d\n",
            conn->datadone, conn->datalen, rc);
   return(rc);
}

static int recv_buffer(struct connreq *conn) {
   int rc = 0;

   show_msg(MSGDEBUG, "Reading from server (expecting %d bytes)\n", conn->datalen);
   while ((rc == 0) && (conn->datadone != conn->datalen)) {
      rc = (int)recv(conn->sockid, conn->buffer + conn->datadone,
                conn->datalen - conn->datadone, 0);
      if (rc > 0) {
         conn->datadone += rc;
         rc = 0;
      } else if (rc == 0) {
         show_msg(MSGDEBUG, "Peer has shutdown but we only read %d of %d bytes.\n",
            conn->datadone, conn->datalen);
         rc = ENOTCONN; /* ENOTCONN seems like the most fitting error message */
      } else {
         if (errno != EWOULDBLOCK)
            show_msg(MSGDEBUG, "Read failed, %s\n", strerror(errno));
         rc = errno;
      }
   }

   if (conn->datadone == conn->datalen)
      conn->state = conn->nextstate;

   show_msg(MSGDEBUG, "Received %d bytes of %d bytes expected, return code is %d\n",
            conn->datadone, conn->datalen, rc);
   return(rc);
}

static int read_socksv5_method(struct connreq *conn) {
	struct passwd *nixuser;
	char *uname, *upass;

	/* See if we offered an acceptable method */
	if (conn->buffer[1] == '\xff') {
		show_msg(MSGERR, "SOCKS V5 server refused authentication methods\n");
      conn->state = FAILED;
		return(ECONNREFUSED);
	}

	/* If the socks server chose username/password authentication */
	/* (method 2) then do that                                    */
	if ((unsigned short int) conn->buffer[1] == 2) {
		show_msg(MSGDEBUG, "SOCKS V5 server chose username/password authentication\n");

		/* Determine the current *nix username */
		nixuser = getpwuid(getuid());	

		if (((uname = conn->path->defuser) == NULL) &&
          ((uname = getenv("TSOCKS_USERNAME")) == NULL) &&
		    ((uname = (nixuser == NULL ? NULL : nixuser->pw_name)) == NULL)) {
			show_msg(MSGERR, "Could not get SOCKS username from "
				   "local passwd file, tsocks.conf "
				   "or $TSOCKS_USERNAME to authenticate "
				   "with"); 
         conn->state = FAILED;
			return(ECONNREFUSED);
		} 

		if (((upass = getenv("TSOCKS_PASSWORD")) == NULL) &&
          ((upass = conn->path->defpass) == NULL)) {
			show_msg(MSGERR, "Need a password in tsocks.conf or "
				   "$TSOCKS_PASSWORD to authenticate with");
         conn->state = FAILED;
			return(ECONNREFUSED);
		} 

		/* Check that the username / pass specified will */
		/* fit into the buffer				                */
		if ((3 + strlen(uname) + strlen(upass)) >= sizeof(conn->buffer)) {
			show_msg(MSGERR, "The supplied socks username or "
				   "password is too long");
         conn->state = FAILED;
			return(ECONNREFUSED);
		}
		
		conn->datalen = 0;
		conn->buffer[conn->datalen] = '\x01';
		conn->datalen++;
		conn->buffer[conn->datalen] = (int8_t) strlen(uname);
		conn->datalen++;
		memcpy(&(conn->buffer[conn->datalen]), uname, strlen(uname));
		conn->datalen = conn->datalen + (int)strlen(uname);
		conn->buffer[conn->datalen] = (int8_t) strlen(upass);
		conn->datalen++;
		memcpy(&(conn->buffer[conn->datalen]), upass, strlen(upass));
		conn->datalen = conn->datalen + (int)strlen(upass);

      conn->state = SENDING;
      conn->nextstate = SENTV5AUTH;
      conn->datadone = 0;
	} else
      return(send_socksv5_connect(conn));

   return(0);
}

static int read_socksv5_auth(struct connreq *conn) {

   if (conn->buffer[1] != '\x00') {
      show_msg(MSGERR, "SOCKS authentication failed, check username and password\n");
      conn->state = FAILED;
      return(ECONNREFUSED);
   }
		
   /* Ok, we authenticated ok, send the connection request */
   return(send_socksv5_connect(conn));
}

static int read_socksv5_connect(struct connreq *conn) {

	/* See if the connection succeeded */
	if (conn->buffer[1] != '\x00') {
		show_msg(MSGERR, "SOCKS V5 connect failed: ");
      conn->state = FAILED;
		switch ((int8_t) conn->buffer[1]) {
			case 1:
				show_msg(MSGERR, "General SOCKS server failure\n");
				return(ECONNABORTED);
			case 2:
				show_msg(MSGERR, "Connection denied by rule\n");
				return(ECONNABORTED);
			case 3:
				show_msg(MSGERR, "Network unreachable\n");
				return(ENETUNREACH);
			case 4:
				show_msg(MSGERR, "Host unreachable\n");
				return(EHOSTUNREACH);
			case 5:
				show_msg(MSGERR, "Connection refused\n");
				return(ECONNREFUSED);
			case 6: 
				show_msg(MSGERR, "TTL Expired\n");
				return(ETIMEDOUT);
			case 7:
				show_msg(MSGERR, "Command not supported\n");
				return(ECONNABORTED);
			case 8:
				show_msg(MSGERR, "Address type not supported\n");
				return(ECONNABORTED);
			default:
				show_msg(MSGERR, "Unknown error\n");
				return(ECONNABORTED);
		}	
	} 

   conn->state = DONE;

   return(0);
}

static int read_socksv4_req(struct connreq *conn) {
   struct sockrep *thisrep;

   thisrep = (struct sockrep *) conn->buffer;

   if (thisrep->result != 90) {
      show_msg(MSGERR, "SOCKS V4 connect rejected:\n");
      conn->state = FAILED;
      switch(thisrep->result) {
         case 91:
            show_msg(MSGERR, "SOCKS server refused connection\n");
            return(ECONNREFUSED);
         case 92:
            show_msg(MSGERR, "SOCKS server refused connection "
                  "because of failed connect to identd "
                  "on this machine\n");
            return(ECONNREFUSED);
         case 93:
            show_msg(MSGERR, "SOCKS server refused connection "
                  "because identd and this library "
                  "reported different user-ids\n");
            return(ECONNREFUSED);
         default:
            show_msg(MSGERR, "Unknown reason\n");
            return(ECONNREFUSED);
      }
   }

   conn->state = DONE;

   return(0);
}

#ifdef USE_SOCKS_DNS
int p_res_init(void) {
        int rc;
        
	/* Call normal res_init */
	rc = res_init();

   /* Force using TCP protocol for DNS queries */
   _res.options |= RES_USEVC;

   return(rc);
}
#endif

#ifdef USE_TOR_DNS
static int deadpool_init()
{
  if(!pool) {
      get_environment();
      get_config();
      if(config->tordns_enabled) {
          pool = init_pool(
              config->tordns_cache_size, 
              config->tordns_deadpool_range->localip, 
              config->tordns_deadpool_range->localnet, 
              config->defaultserver.address,
              config->defaultserver.port
          );
          if(!pool) {
              show_msg(MSGERR, "failed to initialize deadpool: tordns disabled\n");
          }
      }
  }
  return 0;
}

struct hostent *p_gethostbyname(GETHOSTBYNAME_SIGNATURE)
{
  if(pool) {
      return our_gethostbyname(pool, name);
  } else {
      return gethostbyname(name);
  }  
}

int p_getaddrinfo(GETADDRINFO_SIGNATURE)
{
  if(pool) {
      return our_getaddrinfo(pool, node, service, hints, res);
  } else {
      return getaddrinfo(node, service, hints, res);
  }
}

struct hostent *p_getipnodebyname(GETIPNODEBYNAME_SIGNATURE)
{
  if(pool) {
      return our_getipnodebyname(pool, name, af, flags, error_num);
  } else {
      return getipnodebyname(name, af, flags, error_num);
  }
}

#endif 

