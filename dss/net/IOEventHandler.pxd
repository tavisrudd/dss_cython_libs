cdef class IOEventHandlerInterface # forward declaration
cdef class AbstractIOEventHandler(IOEventHandlerInterface)

from dss.net.IOEventReactor cimport IOEventReactorInterface
from dss.net.IOEventReactor import REACTOR_SHUTDOWN_EVENT

cdef class IOEventHandlerInterface:
    cpdef handle_event(self,
                       IOEventReactorInterface reactor,
                       object fd,
                       object eventmask,
                       double timestamp)

cdef class AbstractIOEventHandler(IOEventHandlerInterface):
    cdef readonly unsigned long event_count
    cdef readonly double last_event_time
    cdef public object _mutex, _log_channel

    cpdef _handle_read_event(self, fd)
    cpdef _handle_write_event(self, fd)
    cpdef _handle_socket_error_event(self, fd, eventmask)
    cpdef _handle_reactor_shutdown(self, IOEventReactorInterface reactor, fd)
    cpdef _handle_unknown_event(self, fd, eventmask)
    cpdef _handle_exception(self, fd)
    cpdef _close_descriptor(self, fd)

    cpdef _register_fd_with_reactor(self, fd, IOEventReactorInterface reactor, int writable=*)
