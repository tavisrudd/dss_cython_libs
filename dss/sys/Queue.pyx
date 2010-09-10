# -*- python -*-
from dss.sys.lock cimport Lock

import collections

cdef class AbstractQueue:
    def __init__(self, maxsize=0):
        pass

    def __len__(self):
        raise NotImplementedError

    cpdef object put(self, object item):
        raise NotImplementedError

    cpdef object putmany(self, object items):
        raise NotImplementedError

    cpdef object putleft(self, object item, int respectmaxsize=1):
        raise NotImplementedError

    cpdef object get(self):
        raise NotImplementedError

    cpdef object getmany(self, int maxitems=0):
        raise NotImplementedError

    property maxsize:
        def __get__(self):
            raise NotImplementedError

    property is_full:
        def __get__(self):
            raise NotImplementedError

    property is_empty:
        def __get__(self):
            raise NotImplementedError

cdef class BlockingQueue(AbstractQueue):
    """A threadsafe blocking Queue.

    The underlying data structure is a `collections.deque` from the
    standard library.  Where `collections.deque` would raise an
    `IndexError` when empty this blocks.  Where `collections.deque`
    would drop elements when full, this blocks.

    This is implemented in Cython to avoid the overhead of python
    function calls when used in the critical paths of other Cython
    code.
    """
    def __init__(self, maxsize=0):
        """Initialize a queue object with a given maximum size.

        If maxsize is == 0, the queue size is infinite (to the limits
        of system memory) and put/putmany will never block.

        If maxsize is specified, put/putmany will block when the queue
        is full.
        """

        assert maxsize>=0
        self._maxsize = maxsize
        self._size = 0
        self._queue = collections.deque()
        self._mutex = Lock()
        self._esema = Lock()
        self._fsema = Lock()
        self._esema.acquire() # it's empty now!

        # shortcut the name lookups:
        self._put = self._queue.append
        self._extend = self._queue.extend
        self._putleft = self._queue.appendleft
        self._popleft = self._queue.popleft

    def __len__(self):
        #return len(self._queue)
        return self._size

    cpdef object put(self, object item):
        """Adds `item` to the right side of the deque. Equivalent to `deque.append(item)`

        Will block only if the queue has a `maxsize` and is
        currently full.
        """
        cdef int was_empty
        cdef object result

        if self._maxsize:
            self._fsema.acquire()
        self._mutex.acquire()
        was_empty = not self._size
        result = self._put(item)
        self._size += 1
        if was_empty:
            self._esema.release()
        if self._maxsize and self._size < self._maxsize:
            self._fsema.release()
        self._mutex.release()

        return result

    cpdef object putmany(self, object items):
        """Adds `items` to the right side of the deque. Equivalent to
        `deque.extend(items)`

        Will block only if the queue has a `maxsize` and is
        currently full.
        """
        cdef int was_empty
        cdef object result

        if self._maxsize:
            self._fsema.acquire()
        self._mutex.acquire()
        was_empty = not self._size
        result = self._extend(items)
        self._size += len(items)
        if was_empty and self._size:
            self._esema.release()
        if self._maxsize and self._size < self._maxsize:
            if self._fsema.locked(): # may not be locked
                self._fsema.release()
        self._mutex.release()

        return result

    cpdef object putleft(self, object item, int respectmaxsize=1):
        """Adds `item` to the left side of the deque.
        Equivalent to `deque.appendleft(item)`.

        If the queue has a `maxsize` and is full this will block,
        unless `respectmaxsize`=0.

        Note, `respectmaxsize` is provided so job queues (thread
        pools, etc.) using BlockingQueue can put important high
        priority jobs on the queue even when full.
        """
        cdef int was_empty
        cdef object result

        if respectmaxsize and self._maxsize:
            self._fsema.acquire()
        self._mutex.acquire()
        was_empty = not self._size
        result = self._putleft(item)
        self._size += 1
        if was_empty:
            self._esema.release()
        if self._maxsize and self._size < self._maxsize:
            if self._fsema.locked(): # may not be locked, due to respectmaxsize
                self._fsema.release()
        self._mutex.release()

        return result

    cpdef object get(self):
        """Gets one item from the left side of the deque.
        Equivalent to `deque.popleft`.

        Will block if the queue is empty.
        """
        cdef int was_full
        cdef object item

        self._esema.acquire()
        self._mutex.acquire()
        was_full = (self._maxsize and self._size >= self._maxsize)
        item = self._popleft()
        self._size -= 1
        if was_full:
            if self._size < self._maxsize and self._fsema.locked():
                self._fsema.release()
        if self._size:
            self._esema.release()
        self._mutex.release()
        return item

    cpdef object getmany(self, int maxitems=0):
        """Gets many items from the left side of the deque.
        Equivalent to `deque.popleft` call repeatedly.

        If `maxitems`=0, this will retrieve all items from the deque.
        Otherwise, it will attempt to retrieve up to `maxitems`, but
        will *not* block if fewer items are present.

        It will block if the queue is empty.
        """
        cdef int was_full, howmany, i
        cdef object item

        result = []

        self._esema.acquire()
        self._mutex.acquire()
        was_full = (self._maxsize and self._size >= self._maxsize)

        if maxitems:
            howmany = min(maxitems, self._size)
        else:
            howmany = self._size

        i = 0
        while i < howmany and self._size:
            result.append(self._popleft())
            self._size -= 1
            i += 1

        if was_full:
            if self._size < self._maxsize and self._fsema.locked():
                self._fsema.release()
        if self._size:
            self._esema.release()
        self._mutex.release()
        return result

    property maxsize:
        def __get__(self):
            return self._maxsize

    property is_full:
        def __get__(self):
            return (self._maxsize and self._size >= self._maxsize)

    property is_empty:
        def __get__(self):
            return not self._size

#cdef class SingleConsumer(BlockingQueue):
#    """@@TR: Needs re-testing!!!  Do not use until this docstring has
#    been updated.
#    """
#    def __init__(self):
#        BlockingQueue.__init__(self, maxsize=0)
#
#    def __len__(self):
#        return len(self._queue)
#
#    cpdef object put(self, object item):
#        cdef int was_empty
#        cdef object result
#
#        result = self._put(item)
#        self._mutex.acquire()
#        if self._esema._locked and len(self._queue):
#            self._esema.release()
#        self._mutex.release()
#        return result
#
#    cpdef object putmany(self, object items):
#        cdef int was_empty
#        cdef object result
#
#        result = self._extend(items)
#        self._mutex.acquire()
#        if self._esema._locked and len(self._queue):
#            self._esema.release()
#        self._mutex.release()
#        return result
#
#    cpdef object get(self):
#        cdef object item
#
#        self._esema.acquire()
#        item = self._popleft()
#        if len(self._queue):
#            self._mutex.acquire()
#            if self._esema._locked and len(self._queue):
#                self._esema.release()
#            self._mutex.release()
#        return item
#
#    cpdef object getmany(self, int howmany=0):
#        cdef int was_full, i, size
#        cdef object item
#
#        result = []
#
#        self._esema.acquire()
#        self._mutex.acquire()
#        was_full = (self._maxsize and len(self._queue) >= self._maxsize)
#
#        size = len(self._queue)
#        if howmany:
#            howmany = min(howmany, size)
#        else:
#            howmany = size
#
#        i = 0
#        while i < howmany:
#            result.append(self._popleft())
#            i = i + 1
#
#        if len(self._queue) and self._esema._locked:
#            self._esema.release()
#        self._mutex.release()
#        return result
#
##############
