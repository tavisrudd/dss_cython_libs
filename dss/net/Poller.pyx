cdef class AbstractPoller:
    cpdef bint register_fd(self, object fd, object eventmask=None):
        raise NotImplementedError

    cpdef bint unregister_fd(self, object fd):
        raise NotImplementedError

    cpdef object poll(self, int timeout=-1, int maxevents=None):
        raise NotImplementedError
