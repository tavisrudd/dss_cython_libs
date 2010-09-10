from dss.sys.lock cimport Lock

cdef class AbstractQueue:
    cpdef object put(self, object item)
    cpdef object putmany(self, object items)
    cpdef object putleft(self, object item, int respectmaxsize=?)
    cpdef object get(self)
    cpdef object getmany(self, int maxitems=?)

cdef class BlockingQueue(AbstractQueue):
    cdef int _maxsize, _size
    cdef object _queue
    cdef public Lock _mutex
    cdef public Lock _esema
    cdef public Lock _fsema
    cdef object _put
    cdef object _extend
    cdef object _putleft
    cdef object _popleft

#cdef class SingleConsumer(BlockingQueue):
#     pass
