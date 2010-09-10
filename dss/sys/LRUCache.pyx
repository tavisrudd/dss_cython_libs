from dss.sys.time_of_day cimport time_of_day
from dss.sys.lock cimport Lock
from dss.sys.Unspecified import Unspecified

cdef class CacheNode:
    def __init__(self, key, val):
        self._key = key
        self._value = val
        self._creation_time = self._last_update_time = self._last_access_time = time_of_day()
        self._access_count = self._update_count = 0
        self.next = _NULLNODE
        self.prev = _NULLNODE

    def __nonzero__(self):
        return 1

    cdef _record_access(self):
        self._last_access_time = time_of_day()
        self._access_count = self._access_count + 1

    property key:
        def __get__(self):
            return self._key

    property value:
        def __get__(self):
            return self._value

        def __set__(self, value):
            self._value = value
            self._last_update_time = time_of_day()
            self._update_count = self._update_count + 1

        def __del__(self):
            self._value = None

    property access_count:
        def __get__(self):
            return self._access_count

    property update_count:
        def __get__(self):
            return self._update_count

    property creation_time:
        def __get__(self):
            return self._creation_time

    property last_access_time:
        def __get__(self):
            return self._last_access_time

    property last_update_time:
        def __get__(self):
            return self._last_update_time

cdef class _NullCacheNode(CacheNode):
    def __init__(self):
        self.next = self
        self.prev = self

    def __nonzero__(self):
        return 0

cdef CacheNode _NULLNODE
_NULLNODE = _NullCacheNode()

cdef class LRUCache:
    """
    A Least Recently Used Cache implementation that provides a dictionary-like
    interface.

    It uses a linked list internally.

    Use:
      val = cache.get(key, default)
      if val is default:
          val = cache[key] = ... create it

    rather than:
      if key in cache:
          val = cache[key]
      else:
          val = cache[key] = ... create it

    The latter is not completely thread-safe.

    It's based on ideas from
    http://aspn.activestate.com/ASPN/Cookbook/Python/Recipe/252524
    and
    http://aspn.activestate.com/ASPN/Cookbook/Python/Recipe/302997
    """


    def __init__(self, int maxsize=1024,
                 int use_bulk_purge=1,
                 float proportion_remaining_after_purge=.9,
                 int be_thread_safe=1
                 ):
        self._node_map = PyDict_New()
        self._oldest = _NULLNODE
        self._youngest = _NULLNODE

        self._use_bulk_purge = use_bulk_purge
        self._maxsize = maxsize
        self._proportion_remaining_after_purge = proportion_remaining_after_purge

        self.be_thread_safe = be_thread_safe
        self._lock = <Lock>Lock()

    def __contains__(self, key):
        return PyDict_Contains(self._node_map, key)

    def has_key(self, key):
        return PyDict_Contains(self._node_map, key)

    def get(self, key, default=Unspecified):
        try:
            return self.__getitem__(key)
        except KeyError:
            if default is not Unspecified:
                return default
            else:
                raise

    def __getitem__(self, key):
        cdef void *nodepointer
        cdef CacheNode node
        if self.be_thread_safe: self._lock.acquire()
        try:
            nodepointer = PyDict_GetItem(self._node_map, key)
            if nodepointer is NULL:
                raise KeyError(key)
            node = <CacheNode>nodepointer
            node._record_access()
            self._record_access(node)
            return node.value
        finally:
            if self.be_thread_safe: self._lock.release()

    def __setitem__(self, key, val):
        if self.be_thread_safe:
            self._lock.acquire()
        try:
            if PyDict_Contains(self._node_map, key):
                node = self._node_map[key]
                node.value = val
            else:
                node = CacheNode(key, val)
                PyDict_SetItem(self._node_map, key, node)

            self._record_access(node)

            if PyDict_Size(self._node_map) > self._maxsize:
                self._purge()
        finally:
            if self.be_thread_safe:
                self._lock.release()

    def __delitem__(self, key):
        self.c__delitem__(key)

    def __len__(self):
        if self.be_thread_safe: self._lock.acquire()
        try:
            return PyDict_Size(self._node_map)
        finally:
            if self.be_thread_safe: self._lock.release()

    def keys(self):
        return self._node_map.keys()

    def clear(self):
        """ Clears the cache """
        self._clear()

    cdef object c__delitem__(self, object key):
        cdef void *nodepointer
        cdef CacheNode node

        if self.be_thread_safe: self._lock.acquire()
        try:
            nodepointer = PyDict_GetItem(self._node_map, key)
            if nodepointer is NULL: raise KeyError(key)
            node = <CacheNode>nodepointer

            if node is self._oldest:
                self._oldest = node.next
            else:
                node.prev.next = node.next

            if node is self._youngest:
                self._youngest = node.prev
            else:
                node.next.prev = node.prev

            PyDict_DelItem(self._node_map, key)
            node.next = _NULLNODE
            node.prev = _NULLNODE
            node.value = None
        finally:
            if self.be_thread_safe: self._lock.release()

    cdef object _clear(self):
        cdef CacheNode node, nextNode

        if self.be_thread_safe:
            self._lock.acquire()
        try:
            node = self._oldest
            self._youngest = _NULLNODE
            self._oldest = _NULLNODE
            self._node_map.clear()
            while node:
                nextNode = node.next
                node.next = _NULLNODE
                node.prev = _NULLNODE
                node.value = None
                node = nextNode
        finally:
            if self.be_thread_safe:
                self._lock.release()

    cdef object _record_access(self, CacheNode node):
        " Internal use only, must be invoked within a thread lock."""
        if node is self._youngest:
            return self._youngest

        if not self._oldest:
            self._oldest = node
        elif node is self._oldest and node.next:
            self._oldest = node.next

        if node.prev:
            node.prev.next = node.next
        if node.next:
            node.next.prev = node.prev

        node.prev = self._youngest
        node.next = _NULLNODE
        if self._youngest:
            self._youngest.next = node
        self._youngest = node

    cdef int _purge(self) except -1:
        " Internal use only, must be invoked within a thread lock."""
        cdef int how_many_to_purge, purged_cache_size
        cdef CacheNode orig_oldest_node

        if self._use_bulk_purge:
            purged_cache_size = int(self._maxsize * self._proportion_remaining_after_purge)
            how_many_to_purge = PyDict_Size(self._node_map)-purged_cache_size
        else:
            how_many_to_purge = 1

        for i from 0 <= i < how_many_to_purge:
            orig_oldest_node = self._oldest
            self._oldest = orig_oldest_node.next
            orig_oldest_node.prev = _NULLNODE
            orig_oldest_node.next.prev = _NULLNODE
            orig_oldest_node.next = _NULLNODE
            PyDict_DelItem(self._node_map, orig_oldest_node.key)
