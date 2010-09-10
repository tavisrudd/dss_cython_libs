from dss.sys.services.Service cimport Service

cdef class NetworkService(Service):
    cdef public object _connection_handler
    cdef public object _acceptor
    cdef public object _reactor
    cdef public object _thread_pool

    cdef public object _address
    cdef public object _socket
    cdef public object _socket_description
