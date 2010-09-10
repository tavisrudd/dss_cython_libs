from dss.net.IOEventHandler cimport AbstractIOEventHandler

cdef class BufferedSocketIOHandler(AbstractIOEventHandler):
    cdef readonly int connected
    cdef public object creation_timestamp
    cdef public object socket
    cdef public object _reactor

    cdef public object _outgoing_msg_queue, _output_buffer, _output_buffer_offset, _msg_reader
    cpdef register_with_reactor(self, writable=*, reactor=*)
    cpdef fileno(self)
    cpdef write(self, _bytes, int flush=*)

    cpdef _handle_lost_connection(self, fd)
    cpdef _handle_message(self, msg)
    cpdef _init_buffers(self)
    cpdef _fill_output_buffer(self)
    cpdef _get_msg_reader(self, firstByte)
    cpdef _log_closure(self)
