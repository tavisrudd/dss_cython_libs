# Copyright (c) 2001-2006 Twisted Matrix Laboratories.
# See LICENSE for details.
# http://twistedmatrix.com/trac/browser/trunk/twisted/python/_epoll.pyx
"""
Interface to epoll I/O event notification facility.
"""

# NOTE: The version of Pyrex you are using probably _does not work_ with
# Python 2.5.  If you need to recompile this file, _make sure you are using
# a version of Pyrex which works with Python 2.5_.  I am using 0.9.4.1 from
# <http://codespeak.net/svn/lxml/pyrex/>. -exarkun
CTL_ADD = EPOLL_CTL_ADD
CTL_DEL = EPOLL_CTL_DEL
CTL_MOD = EPOLL_CTL_MOD

IN = EPOLLIN
OUT = EPOLLOUT
PRI = EPOLLPRI
ERR = EPOLLERR
HUP = EPOLLHUP
ET = EPOLLET

RDNORM = EPOLLRDNORM
RDBAND = EPOLLRDBAND
WRNORM = EPOLLWRNORM
WRBAND = EPOLLWRBAND
MSG = EPOLLMSG

cdef class _epoll:
    """
    Represent a set of file descriptors being monitored for events.
    """
    def __init__(self, int size):
        self.fd = epoll_create(size)
        if self.fd == -1:
            raise IOError(errno, strerror(errno))
        self.initialized = 1

    def __dealloc__(self):
        if self.initialized:
            close(self.fd)
            self.initialized = 0

    cpdef close(self):
        """
        Close the epoll file descriptor.
        """
        if self.initialized:
            if close(self.fd) == -1:
                raise IOError(errno, strerror(errno))
            self.initialized = 0

    cpdef int fileno(self):
        """
        Return the epoll file descriptor number.
        """
        return self.fd

    cpdef _control(self, int op, int fd, int events):
        """
        Modify the monitored state of a particular file descriptor.

        Wrap epoll_ctl(2).

        @type op: C{int}
        @param op: One of CTL_ADD, CTL_DEL, or CTL_MOD

        @type fd: C{int}
        @param fd: File descriptor to modify

        @type events: C{int}
        @param events: A bit set of IN, OUT, PRI, ERR, HUP, and ET.

        @raise IOError: Raised if the underlying epoll_ctl() call fails.
        """
        cdef int result
        cdef epoll_event evt
        evt.events = events
        evt.data.fd = fd
        result = epoll_ctl(self.fd, op, fd, &evt)
        if result == -1:
            raise IOError(errno, strerror(errno))

    cpdef wait(self, unsigned int maxevents, int timeout):
        """
        Wait for an I/O event, wrap epoll_wait(2).

        @type maxevents: C{int}
        @param maxevents: Maximum number of events returned.

        @type timeout: C{int}
        @param timeout: Maximum time waiting for events. 0 makes it return
            immediately whereas -1 makes it wait indefinitely.

        @raise IOError: Raised if the underlying epoll_wait() call fails.
        """
        cdef epoll_event *events
        cdef int result
        cdef int nbytes
        cdef int fd
        cdef PyThreadState *_save

        nbytes = sizeof(epoll_event) * maxevents
        events = <epoll_event*>malloc(nbytes)
        memset(events, 0, nbytes)
        try:
            fd = self.fd

            _save = PyEval_SaveThread()
            result = epoll_wait(fd, events, maxevents, timeout)
            PyEval_RestoreThread(_save)

            if result == -1:
                raise IOError(errno, strerror(errno))
            results = []
            for i from 0 <= i < result:
                results.append((events[i].data.fd, <int>events[i].events))
            return results
        finally:
            free(events)

# see http://twistedmatrix.com/trac/browser/trunk/twisted/internet/epollreactor.py
cdef class epoll:
    def __init__(self, sizehint=1024):
        self._epoll_internal = _epoll(sizehint)

    def register(self, fd, eventmask=None):
        # this can't be a cython cdef or cpdef method as it would
        # clash with the c 'register' keyword
        return self.register_fd(fd, eventmask)

    cpdef bool register_fd(self, object fd, object eventmask=None):
        op = CTL_ADD
        if eventmask is None:
            eventmask = (IN | OUT | PRI)
        return self._epoll_internal._control(op, fd, eventmask)

    cpdef bool unregister(self, object fd):
        op = CTL_DEL
        eventmask = (IN | OUT | PRI | ERR | HUP | ET)
        return self._epoll_internal._control(op, fd, eventmask)

    cpdef object poll(self, int timeout=-1, int maxevents=1024):
        return self._epoll_internal.wait(maxevents, timeout)
