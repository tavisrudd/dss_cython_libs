"""This module natively implements Lock from the threading module.

Derived from: http://aspn.activestate.com/ASPN/Cookbook/Python/Recipe/310792
Original Copyright. Nicolas Lehuen
"""

cdef class Lock:
    """A basic, non-reentrant Lock, implemented in Cython so it can be
    called from critical paths in other Cython code without the
    overhead of a python function call."""

    def __cinit__(self):
        self._lock = PyThread_allocate_lock()
        self._locked = False

    def __dealloc__(self):
        PyThread_free_lock(self._lock)

    cpdef bint locked(self):
        return self._locked

    cpdef int acquire(self, int blocking=1) except -1:
        """Lock the lock.

        With `blocking`=1, this blocks if the lock is already locked
        (even by the same thread), waiting for another thread to
        release the lock, and return 1 once the lock is acquired.
        With an argument, this will only block if the argument is
        true, and the return value reflects whether the lock is
        acquired.  The blocking operation is not interruptible."""
        cdef int result
        with nogil:
            result = PyThread_acquire_lock(self._lock, blocking)

        if result==1:
            self._locked = True
            return 1
        else:
            return 0

    cpdef int release(self) except -1:
        """Release the lock.

        The lock must be in the locked state, but it needn't be locked
        by the same thread that unlocks it."""
        if not self._locked:
            raise Exception('Error in lock.release(). This lock %r is not locked'%self)
        PyThread_release_lock(self._lock)
        self._locked = False
