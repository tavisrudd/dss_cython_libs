cdef extern from "Python.h":
    object PyDict_New()
    void * PyDict_GetItem(object d, object key)
    int PyDict_SetItem(object d, object key, object value) except -1
    int PyDict_Contains(object o, object key) except -1
    int PyDict_DelItem(object d, object key)  except -1
    int PyDict_Clear(object d) except -1
    int PyDict_Size(object d)

from dss.sys.time_of_day cimport time_of_day
from dss.sys.lock cimport Lock

cdef class CacheNode:
    cdef CacheNode prev
    cdef CacheNode next
    cdef object _key
    cdef object _value

    cdef double _creation_time
    cdef double _last_access_time
    cdef double _last_update_time
    cdef long _access_count
    cdef long _update_count
    cdef _record_access(self)

cdef class _NullCacheNode(CacheNode):
     pass

cdef class LRUCache:
    cdef public int _use_bulk_purge
    cdef public float _proportion_remaining_after_purge
    cdef public int _maxsize
    cdef public object _node_map
    cdef int be_thread_safe

    cdef CacheNode _youngest
    cdef CacheNode _oldest
    cdef Lock _lock

    cdef object c__delitem__(self, object key)
    cdef object _clear(self)
    cdef object _record_access(self, CacheNode node)
    cdef int _purge(self) except -1
