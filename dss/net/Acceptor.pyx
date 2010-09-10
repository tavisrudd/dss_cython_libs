from cpython.list cimport PyList_Append
from dss.sys.services.ThreadPool cimport ThreadPool, AbstractThreadPoolJob
from dss.net.IOEventHandler cimport IOEventHandlerInterface
from dss.net.IOEventReactor cimport IOEventReactorInterface

##
from errno import EWOULDBLOCK, EAGAIN
import socket
cdef object _socket_error = socket.error # shortcut the name lookups

cdef class _ThreadPoolJob(AbstractThreadPoolJob):
    cdef object handler
    cdef object sock

    def __init__(self, handler, sock):
        self.handler = handler
        self.sock = sock

    cpdef object run(self):
        self.handler(self.sock)

cdef class Acceptor(IOEventHandlerInterface):
    """An implementation of the `Acceptor/Listener Pattern`.
    It dispatches incoming connections and their service handler to
    the threadpool.

    See: http://www.scribd.com/doc/242551/Acceptor-Pattern-for-web-servers
    """
    cdef public object _socket
    cdef object _accept # _socket._sock.accept
    cdef ThreadPool _thread_pool
    cdef object _connection_handler
    cdef int _use_bulk_accept_pattern

    def __init__(self, socket, thread_pool, parent_service,
                 use_bulk_accept_pattern=True):
        self._connection_handler = parent_service.handle_connection
        self._socket = socket
        self._socket.setblocking(0)
        self._accept = self._socket._sock.accept
        self._thread_pool = thread_pool
        self._use_bulk_accept_pattern = int(use_bulk_accept_pattern)

    cpdef handle_event(self,
                       IOEventReactorInterface reactor,
                       object fd,
                       object event,
                       double timestamp):
        cdef int i, j
        connection_handler = self._connection_handler
        if self._use_bulk_accept_pattern:
            # we try to accept/dispatch new connections in big
            # batches, as this reduces the overhead involved,
            # particularly the need to lock the threadpool per
            # connection.  Micro-benchmarking it shows a significant
            # difference in some situations
            jobs = []
            accept = self._accept
            i = j = 0
            try:
                try:
                    while i < 200:
                        PyList_Append(jobs, _ThreadPoolJob(connection_handler, accept()[0]))
                        i += 1
                        j += 1
                        if (j > 50):
                            self._thread_pool.add_job_objects(jobs)
                            jobs = []
                            j = 0
                except _socket_error, why:
                    if why[0] in (EWOULDBLOCK, EAGAIN):
                        pass
                    else:
                        raise
            finally:
                if j:
                    self._thread_pool.add_job_objects(jobs)
        else:
            try:
                self._thread_pool.add_job_object(
                    _ThreadPoolJob(self._connection_handler, self._accept()[0]))
            except _socket_error, why:
                if why[0] in (EWOULDBLOCK, EAGAIN):
                    pass
                else:
                    raise

        return False  # keep registered with reactor
