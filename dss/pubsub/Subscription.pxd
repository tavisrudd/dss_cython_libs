from dss.sys.time_of_day cimport time_of_day

cdef class Subscription:
    cdef public bint is_active
    cdef public object channel
    cdef public object subscriber
    cdef public int include_subchannels
    cdef public bint async
    cdef public long thread_id
    cdef public double timestamp
    cdef public unsigned long long message_count
