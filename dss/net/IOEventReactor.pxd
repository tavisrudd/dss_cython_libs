from cpython.dict cimport PyDict_GetItem

from dss.sys.services.Service cimport Service
from dss.sys.time_of_day cimport time_of_day
#from dss.net._epoll cimport epoll as epoll_pyx

cdef class IOEventReactorInterface(Service) # forward declaration
cdef class IOEventReactor(IOEventReactorInterface)

from dss.net.IOEventHandler cimport IOEventHandlerInterface

cdef class IOEventReactorInterface(Service):
    cdef readonly unsigned long long event_count # enough for 10**10 events/sec for 55 years!
    cdef readonly double last_event_time

    cpdef object register_handler(self, fd, handler, eventmask=*)
    cpdef object unregister(self, fd, int flush=*)
    cpdef object get_handler(self, fd)

cdef class IOEventReactor(IOEventReactorInterface):
    cdef public object _start_time
    cdef public object _event_loop_thread, _interrupt
    cdef public object _fd_to_handler_map

    # cdef public object  _fd_to_orig_flags_map # @@TR: could be used
    # to reset fds back to their original flags when unregistering if
    # we were to manually fcntl.fcntl(fd, fcntl.F_SETFL,
    # os.O_NONBLOCK) when registering.  This isn't done in the reactor
    # at the moment and is the responsibility of the IOEventHandler
    # instead, which allows the reactor to be used for blocking io as
    # well.

    cdef public object _poll_factory
    cdef public object _poller

    cdef readonly int _reactor_state

    cpdef object _event_loop_inner(self)
    cpdef object _log_error(self, msg)
    cpdef object _cull_any_bad_descriptors(self)

    cpdef object _handle_exception(self, e, logMessage=*)
    cpdef object _handle_unregister_flush_event(self, reactor, fd, eventmask, timestamp)
    cpdef object _handle_interrupt_event(self, reactor, fd, eventmask, timestamp)
    cpdef object _handle_missing_handler(self, reactor, fd, eventmask, timestamp)
