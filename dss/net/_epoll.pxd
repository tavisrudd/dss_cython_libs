# Copyright (c) 2001-2006 Twisted Matrix Laboratories.
# See LICENSE for details.
cdef extern from "stdio.h":
    cdef extern void *malloc(int)
    cdef extern void free(void *)
    cdef extern int close(int)

cdef extern from "errno.h":
    cdef extern int errno
    cdef extern char *strerror(int)

cdef extern from "string.h":
    cdef extern void *memset(void* s, int c, int n)

cdef extern from "stdint.h":
    ctypedef unsigned long uint32_t
    ctypedef unsigned long long uint64_t

cdef extern from "sys/epoll.h":

    cdef enum:
        EPOLL_CTL_ADD = 1
        EPOLL_CTL_DEL = 2
        EPOLL_CTL_MOD = 3

    cdef enum EPOLL_EVENTS:
        EPOLLIN = 0x001
        EPOLLPRI = 0x002
        EPOLLOUT = 0x004
        EPOLLRDNORM = 0x040
        EPOLLRDBAND = 0x080
        EPOLLWRNORM = 0x100
        EPOLLWRBAND = 0x200
        EPOLLMSG = 0x400
        EPOLLERR = 0x008
        EPOLLHUP = 0x010
        EPOLLET = (1 << 31)

    ctypedef union epoll_data_t:
        void *ptr
        int fd
        uint32_t u32
        uint64_t u64

    cdef struct epoll_event:
        uint32_t events
        epoll_data_t data

    int epoll_create(int size)
    int epoll_ctl(int epfd, int op, int fd, epoll_event *event)
    int epoll_wait(int epfd, epoll_event *events, int maxevents, int timeout)

cdef extern from "Python.h":
    ctypedef struct PyThreadState
    cdef extern PyThreadState *PyEval_SaveThread()
    cdef extern void PyEval_RestoreThread(PyThreadState*)

cdef class _epoll:
    """
    Represent a set of file descriptors being monitored for events.
    """

    cdef int fd
    cdef int initialized
    cpdef int fileno(self)
    cpdef close(self)
    cpdef _control(self, int op, int fd, int events)
    cpdef wait(self, unsigned int maxevents, int timeout)

cdef class epoll:
    cdef object _epoll_internal
    cpdef bool register_fd(self, object fd, object eventmask=*)
    cpdef bool unregister(self, object fd)
    cpdef object poll(self, int timeout=*, int maxevents=*)
