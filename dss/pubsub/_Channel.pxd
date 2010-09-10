cdef extern from "pythread.h":
    long PyThread_get_thread_ident()

cdef class _Channel #forward declaration

from dss.pubsub.MessageBus cimport MessageBus
from dss.sys.time_of_day cimport time_of_day
from dss.pubsub.Subscription cimport Subscription

cdef class _Channel:
    # public attrs:
    cdef public object name
    cdef public object description
    cdef public unsigned long long message_count
    cdef public double last_message_timestamp

    # private attrs:
    cdef public object _child_channels
    cdef public object _subscriptions_mutex
    cdef public MessageBus _message_bus

    cdef int _has_synchronous_subscriptions
    cdef int _has_async_subscriptions
    cdef object _async_subscriptions
    cdef object _synchronous_subscriptions
    cdef _Channel _parent_channel

    # public methods:
    cpdef object subscribe(self, subscriber, include_subchannels=?, async=?, thread_id=?)
    cpdef object subscribe_this_thread_only(
        self, subscriber, include_subchannels=?, async=?)
    cpdef object unsubscribe(self, subscription)
    cpdef object send(self, message)

    # private methods:
    cpdef object _register_subscription(self, subscription)
    cpdef object _update_subscription_flags(self)
    cpdef object _spawn_subchannel(self, name)
    cpdef object _dispatch_msg(
        self, message, _Channel orig_channel, long orig_thread, bint async)
