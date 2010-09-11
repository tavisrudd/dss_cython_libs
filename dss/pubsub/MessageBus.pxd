# -*- python -*-
from dss.sys.services.Service cimport Service
from dss.sys.Queue cimport BlockingQueue

cdef class MessageBus(Service) # forward declaration

from dss.pubsub._Channel cimport _Channel
from dss.pubsub.Subscription cimport Subscription

cdef class AbstractAsyncMsgDispatcher:
    cdef object _internal_log_channel
    cdef public int _running
    cdef public object _mutex
    cdef readonly int _max_queue_size
    cdef readonly double last_dispatch_time
    cdef readonly long long message_count # set on queuing of new msg
    cdef readonly long long _dispatch_count # set after successful
                                        # dispatch of msg, used for debugging

    cpdef queue_msg(self, msg, _Channel orig_channel, long orig_thread)

cdef class NonThreadedMsgDispather(AbstractAsyncMsgDispatcher):
    pass

cdef class DedicatedThreadMsgDispather(AbstractAsyncMsgDispatcher):
    cdef public BlockingQueue _msg_queue
    cdef public object _dispatch_thread, _dispatch_thread_exit_event
    cdef public int _dispatch_thread_state

cdef class MessageBus(Service):
    cdef public object _start_time
    cdef public object _channels, _channel_name_regex, _channel_class
    cdef public _Channel root_channel
    cdef public _Channel _internal_log_channel
    cdef public object _subscriptions_mutex
    cdef public object _mutex
    cdef public object _dispatcher
    # used by automated health-checks from other threads that monitor the bus to
    # see if it has gotten wedged:
    cdef readonly double last_async_dispatch_time

    # public methods
    cpdef _Channel create_new_channel(self, channel_name, channel_class=?)
    cpdef _Channel get_channel(self, channel_name)
    cpdef Subscription subscribe(self, channel_name, subscriber,
                           include_subchannels=?, async=?, thread_id=?)
    cpdef object get_open_channel_names(self)
    cpdef object is_valid_channel_name(self, channel_name)
    cpdef object is_channel_open(self, channel_name)

    # private methods
    cpdef _Channel _init_channel(self, channel_name, channel_class=?)
    cpdef object _queue_msg_for_async_subs(
        self, msg, _Channel orig_channel, long orig_thread)
