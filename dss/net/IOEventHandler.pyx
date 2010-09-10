"""
Provides IOEventHandlerInterface and AbstractIOEventHandler for use in
conjunction with IOEventReactor.

IOEventReactor requires that event handlers have the call signature
``f(reactor, fd, eventmask) -> bool``, where the return value
indicates if the reactor should unregister the fd from its event loop
(True=unregister).  It will accept any callable with that signature
and does *not* require an instance of IOEventHandlerInterface or
AbstractIOEventHandler.

Handlers are responsible for handling *ALL* events related to
their fd's and must cleanup if they are stale or an error occurs.

The `eventmask` argument from the reactor is the same bitmask that the
underlying (e)poll implementation returns and uses the
select.(E)POLL___ flags.  If support for kqueues is added in the
future, the kqueue events will probably be exposed directly to
handlers rather than converting them into a synthetic eventmask that
uses the POLL___ flags (this needs more thought ... not a high
priority).

The event handling template defined by AbstractIOEventHandler is
an optional convenience.  If you wish to deviate from it, just make
sure that your handler is a good citizen by cleaning up stale fds and
handling IO errors correctly.

Concrete subclasses of AbstractIOEventHandler, such as
BufferedSocketIOHandler, just need to implement a few abstract
methods: _handle_write_event, _handle_read_event, etc.

IOEventHandlerInterface and AbstractIOEventHandler are designed to
allow one handler to deal with multiple descriptors (sockets, files,
etc.). Concrete handlers can choose to bind themselves to a single
descriptor.

Furthermore, IOEventHandlerInterface and AbstractIOEventHandler are
designed to work concurrently with 1 or more IOEventReactors, each
running in their own thread.  Each `fd` can only be registered with a
single reactor at a time, but implementors might choose to use
multiple reactors.  The assignment of fds to reactor might depend on
the type of the fd (for example normal priority connections for users
for vs high priority ones for admins) or the life stage of the
connection (fresh/active vs old/stale in a comet style web app).
Implementors are free to use any of the following configurations:

  - 1 fd per handler with all fds/handlers registered with a single
    reactor

  - 1 fd per handler but with several reactors handling different sets
    of fds/handlers.

  - many fds per handler with all fds/handlers registered with a
    single reactor.

  - many fds per handler but with fds registered in several reactors.

If a handler will be used with multiple fds or multiple reactors (and
thus threads), be careful to make the implementation reentrant and
threadsafe.

As each reactor runs in its own thread and the handlers are called in
that same thread, the reactor is out of service while the handlers do
their thing.  So do it fast or delegate to a threadpool!

"""
from threading import RLock
from dss.net.event_flags import (
    META_REACTOR_SHUTDOWN_EV
    , META_READ_EV
    , META_WRITE_EV
    , META_DISCONNECTED_EV
    , META_READABLE
    )

cdef class IOEventHandlerInterface:
    cpdef handle_event(self,
                       IOEventReactorInterface reactor,
                       object fd,
                       object eventmask,
                       double timestamp):
        """This is the only method that IOEventReactor cares about.

        The return value tells the reactor whether the file descriptor
        should be unregistered from its poll list. True=unregister.

        See the module docstring for more details.
        """
        raise NotImplementedError

    def __call__(self, reactor, fd, eventmask, timestamp):
        """See the docstring of ``handle_event``"""
        return self.handle_event(reactor, fd, eventmask, timestamp)

cdef class AbstractIOEventHandler(IOEventHandlerInterface):
    """
    AbstractIOEventHandler defines a minimal template for handling the
    events detected and dispatched by instances of IOEventReactor.

    See the module docstring for more details.
    """

    def __init__(self, log_channel=None):
        self.event_count = 0
        self.last_event_time = 0
        self._mutex = RLock()
        self._log_channel = log_channel

    cpdef handle_event(self,
                       IOEventReactorInterface reactor,
                       object fd,
                       object eventmask,
                       double timestamp):
        self.event_count += 1 # not synchronized, no need to be precise
        self.last_event_time = timestamp # ditto

        try:
            if eventmask & META_READ_EV:
                return self._handle_read_event(fd)
            elif eventmask & META_WRITE_EV:
                return self._handle_write_event(fd)
            elif eventmask & META_DISCONNECTED_EV:
                return self._handle_socket_error_event(fd, eventmask)
            elif eventmask == REACTOR_SHUTDOWN_EVENT:
                return self._handle_reactor_shutdown(reactor, fd)
            else:
                return self._handle_unknown_event(fd, eventmask)
        except:
            return self._handle_exception(fd)

    ## private methods:

    cpdef _handle_read_event(self, fd):
        raise NotImplementedError

    cpdef _handle_write_event(self, fd):
        raise NotImplementedError

    cpdef _handle_socket_error_event(self, fd, eventmask):
        if self._log_channel:
            self._log_channel.error('io error: %s'%eventmask, sendEmailAlert=False)
        return self._close_descriptor(fd)

    cpdef _handle_exception(self, fd):
        if self._log_channel:
            self._log_channel.exception('unexpected error: %r'%self, sendEmailAlert=False)

        return self._close_descriptor(fd)

    cpdef _handle_reactor_shutdown(self, IOEventReactorInterface reactor, fd):
        self._close_descriptor(fd)
        return True                     # unregister

    cpdef _handle_unknown_event(self, fd, eventmask):
        raise NotImplementedError
        #if self._log_channel:
        #    self._log_channel.exception('unexpected error: %r'%self, sendEmailAlert=False)
        #return self._close_descriptor(fd)

    cpdef _close_descriptor(self, fd):
        raise NotImplementedError

    cpdef _register_fd_with_reactor(self, fd, IOEventReactorInterface reactor, int writable=False):
        # @@TR: might want to check the fd is good before handing it to the reactor
        self._mutex.acquire()
        try:
            eventmask = META_READABLE
            if writable:
                # @@TR: should add special handling here for local unix domain
                # sockets, which are always writable and should not include
                # POLLOUT (META_WRITE_EV) in the eventmask.
                eventmask = eventmask | META_WRITE_EV
            if fd > 0:
                reactor.register_handler(fd, self, eventmask)
            else:
                raise Exception('invalid socket fileno: %s'%fd)
        finally:
            self._mutex.release()
