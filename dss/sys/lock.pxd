# -*- python -*-
cdef extern from "pythread.h":
    ctypedef void* PyThread_type_lock
    PyThread_type_lock PyThread_allocate_lock()
    void  PyThread_free_lock(PyThread_type_lock lock)
    int PyThread_acquire_lock(PyThread_type_lock lock, int mode) nogil
    void PyThread_release_lock(PyThread_type_lock lock)

cdef class Lock:
    cdef PyThread_type_lock _lock
    cdef bint _locked
    cpdef bint locked(self)
    cpdef int acquire(Lock, int blocking=?) except -1
    cpdef int release(Lock) except -1
