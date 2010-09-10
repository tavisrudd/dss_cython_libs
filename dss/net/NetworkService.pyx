import os
import sys
import socket
import select
try:
    import fcntl
except:
    fcntl = None

from dss.net.Acceptor import Acceptor

cdef class NetworkService(Service):
    def __init__(self, **kws):
        Service.__init__(self, **kws)
        self._acceptor = None
        self._connection_handler = self._settings['connection_handler']
        self._socket = None
        self._reactor = None

    def _initialize_settings(self):
        Service._initialize_settings(self)
        self._settings.update(
            dict(host_name='localhost',
                 listen_queue_limit=1024,
                 socket_options=[#e.g. (socket.SOL_SOCKET, socket.SO_REUSEADDR, 1),
                     ],
                 socket_family=socket.AF_INET,
                 socket_type=socket.SOCK_STREAM,
                 reactor_service='IOEventReactor',
                 thread_pool_service='ThreadPool',
                 connection_handler=None))

    def start(self):
        Service.start(self)
        # @@TR: next line blocks support for AF_UNIX
        self._address = (self._settings['host_name'], int(self._settings['port']))
        self._socket = self._get_socket(self._address)
        self._socket_description = self._describe_socket(self._socket)
        self._reactor = self._lookup_service(self._settings['reactor_service'])
        self._acceptor = self._create_acceptor()
        self._reactor.register_handler(
            self._socket,
            handler=self._acceptor.handle_event,
            eventmask=select.POLLIN)# | select.POLLNVAL
        self._log_channel.notice('listening on %s'%self._socket_description)

    def stop(self):
        Service.stop(self)
        try:
            self._reactor.unregister(self._socket.fileno())
        except:
            self._log_channel.exception('error unregistering socket')
        # @@TR: this can lead to race conditions with the event loop pollers:
        #if self._socket.family == socket.AF_UNIX:
        #    if os.path.exists(self._address):
        #        os.unlink(self._address)
        try:
            self._socket.close()
        except:
            pass
        self._log_channel.notice('Stopped listening on %s'%self._socket_description)

    def _describe_socket(self, sock):
        # @@TR: need to add ipv6 support, etc.
        if sock.family == socket.AF_INET:
            host_name, port_num = sock.getsockname()
            host_name = socket.gethostbyname(host_name)
            proto = {True:'TCP', False:'UDP'}[sock.type==socket.SOCK_STREAM]
            return '%s, %s port %s'%(host_name, proto, port_num)
        elif sock.family == socket.AF_UNIX:
            return 'unix socket "%s"'%sock.getsockname()

    def _get_socket(self, address):
        existing_socket = self._settings.get('existing_socket', None)
        if existing_socket:
            self._address = existing_socket.getsockname()
            return existing_socket
        else:
            if isinstance(address, basestring):
                # it's a unix domain socket
                self._settings['socket_family'] = socket.AF_UNIX

            return self._initialize_socket(
                sock=socket.socket(self._settings['socket_family'],
                                   self._settings['socket_type']),
                address=address,
                socket_options=self._settings['socket_options'],
                listen_queue_limit=self._settings['listen_queue_limit'])

    def _initialize_socket(self, sock, address,
                           socket_options=tuple(), listen_queue_limit=1024):
        for opt in socket_options:
            sock.setsockopt(opt[0], opt[1], opt[2])

        if sock.family == socket.AF_INET:
            if os.name == "posix" and sys.platform != "cygwin":
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        elif sock.family == socket.AF_UNIX:
            if os.path.exists(address):
                os.unlink(address)
        else:
            raise NotImplementedError

        if fcntl and hasattr(fcntl, 'FD_CLOEXEC'):
            old = fcntl.fcntl(sock.fileno(), fcntl.F_GETFD)
            fcntl.fcntl(
                sock.fileno(),
                fcntl.F_SETFD, old | fcntl.FD_CLOEXEC | os.O_NONBLOCK)
            # setting os.O_NONBLOCK here doesn't make any difference
            # if you have a single server socket sitting in your
            # reactor/poller, but it is fairer if you have multiple
            # server sockets registered in a single reactor and don't
            # want one to accidentally block the others.
        try:
            # try block needed to prevent process from hanging if
            # socket is already in use, I have not idea why, but it
            # makes a difference.
            if sock.type == socket.SOCK_STREAM:
                sock.bind(address)
                sock.listen(listen_queue_limit)
            else:
                sock.bind(address)
            return sock
        except socket.error, e:
            if e[0] == 98:
                self._log_channel.exception(
                    (" CAN'T START: One of the network ports %s we need is still in use. "
                    "Another process is probably bound to it. "
                    "Try again in 15 seconds.")%str(self._address))
            raise
        except:
            self._log_channel.exception(
                'unexpected exception binding to %r'%str(self._address))
            raise

    def _create_acceptor(self):
        return Acceptor(socket=self._socket,
                        thread_pool=self._lookup_service(self._settings['thread_pool_service']),
                        parent_service=self)

    def handle_connection(self, sock):
        if self._connection_handler:
            self._connection_handler(sock)
        else:
            raise NotImplementedError
