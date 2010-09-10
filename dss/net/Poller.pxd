cdef class AbstractPoller:
    cpdef bint register_fd(self, object fd, object eventmask=*)
    cpdef bint unregister_fd(self, object fd)
    cpdef object poll(self, int timeout=*, int maxevents=*)
