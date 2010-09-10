import traceback
import sys

# also see cython imports in the .pxd file

cdef class _Channel:
    """

    aka 'Topic', 'Message Box'

    .. note:: Channels should *not* be instantiated directly from client code.
    Rather, channels should be created and retrieved from a `MessageBus`.
    """
    def __init__(self, message_bus, channel_name):
        self.name = channel_name
        self.description = None # must be set explicitly by client code
        self._message_bus = message_bus

        # all channels on a message bus share a single subscriptions_mutex:
        self._subscriptions_mutex = message_bus._subscriptions_mutex

        self.message_count = 0
        self._child_channels = []

        self._async_subscriptions = []
        self._synchronous_subscriptions = []

        self._has_synchronous_subscriptions = False
        self._has_async_subscriptions = False

    cpdef subscribe(self, subscriber, include_subchannels=False,
                    async=True, thread_id=0):
        subscription = Subscription(
            channel=self,
            subscriber=subscriber,
            include_subchannels=include_subchannels,
            async=async,
            thread_id=thread_id)
        self._register_subscription(subscription)
        return subscription

    cpdef subscribe_this_thread_only(self, subscriber,
                                     include_subchannels=False, async=True):
        return self.subscribe(
            subscriber=subscriber,
            include_subchannels=include_subchannels,
            async=async, thread_id=PyThread_get_thread_ident())

    cpdef _register_subscription(self, subscription):
        # @@TR: should add protection against duplicate subscriptions,
        # but am not sure how to hash them for uniqueness
        try:
            self._subscriptions_mutex.acquire()
            if subscription.async:
                self._async_subscriptions.append(subscription)
            else:
                self._synchronous_subscriptions.append(subscription)
            self._update_subscription_flags()
        finally:
            self._subscriptions_mutex.release()

    cpdef _update_subscription_flags(self):
        cdef _Channel child, parent
        cdef Subscription sub
        self._has_async_subscriptions = bool(self._async_subscriptions)
        self._has_synchronous_subscriptions = bool(self._synchronous_subscriptions)

        parent = self._parent_channel
        while parent and not (
            self._has_async_subscriptions and self._has_synchronous_subscriptions):
            if not self._has_async_subscriptions:
                self._has_async_subscriptions = bool(
                    [sub for sub in parent._async_subscriptions
                     if sub.include_subchannels])
            if not self._has_synchronous_subscriptions:
                self._has_synchronous_subscriptions = bool(
                    [sub for sub in parent._synchronous_subscriptions
                     if sub.include_subchannels])
            parent = parent.parent_channel

        # @@TR: add thread_id list for thread-local subscribers + a map of
        # subscribers per thread
        for child in self._child_channels:
            child._update_subscription_flags()

    cpdef unsubscribe(self, subscription):
        if subscription.async:
            subscriptions_list = self._async_subscriptions
        else:
            subscriptions_list = self._synchronous_subscriptions
        try:
            self._subscriptions_mutex.acquire()
            if subscription in subscriptions_list:
                subscriptions_list.remove(subscription)
            self._update_subscription_flags()
        finally:
            self._subscriptions_mutex.release()

    cpdef _spawn_subchannel(self, name):
        cdef _Channel subchannel
        subchannel = self.__class__(message_bus=self._message_bus, channel_name=name)
        subchannel._parent_channel = self
        subchannel._has_async_subscriptions = self._has_async_subscriptions
        subchannel._has_synchronous_subscriptions = self._has_synchronous_subscriptions
        self._child_channels.append(subchannel)
        return subchannel

    cpdef send(self, message):
        """Send/Publish a message to the channel, which then gets
        routed to subscribers/listeners.
        """
        cdef long orig_thread
        if self._has_async_subscriptions or self._has_synchronous_subscriptions:
            orig_thread = PyThread_get_thread_ident()

            self.message_count += 1 # access is not synchronized
            self.last_message_timestamp = time_of_day()

            if self._has_synchronous_subscriptions:
                self._dispatch_msg(message, self, orig_thread, False)

            if self._has_async_subscriptions:
                self._message_bus._queue_msg_for_async_subs(message, self, orig_thread)

    cpdef _dispatch_msg(self, message, _Channel orig_channel,
                        long orig_thread, bint async):
        """Dispatch the message to all Subscribers of this Channel and
        then to subscribers on the parent channel that want to recieve
        messages from sub-channels.

        This style of message bubbling is used rather than statically
        linking subscribers to subchannels during the initial subscription
        because further subchannels might be created after the initial
        subscription.

        Subscribers are responsible for implementing once-and-only-once delivery
        if desired.

        Calling scenarios:
        _dispatch_msg(message, orig_channel=self, orig_thread=?, async=False)
           is *only* called from the current channel
        _dispatch_msg(message, orig_channel=self, orig_thread=?, async=True)
           is *only* called from MessageBus's thread loop
        _dispatch_msg(message, orig_channel=<not self>, orig_thread=?, async=?)
           is *only* called from sub channels
        """
        cdef Subscription sub
        cdef bint from_subchannel = (orig_channel != self)
        if async:
            subscriptions = self._async_subscriptions
        else:
            subscriptions = self._synchronous_subscriptions

        # @@TR: this could be optimized by maintaining
        # a flag _has_thread_local_subscriptions
        subscriptions = [
            sub for sub in subscriptions
            if not sub.thread_id or sub.thread_id == orig_thread]

        for sub in subscriptions:
            if not from_subchannel or sub.include_subchannels:
                try:
                    sub.subscriber(message)
                    sub.message_count += 1
                except:
                    self._message_bus._log_internal_exception(
                        'error passing message %r to subscriber %r'%(
                            message, sub.subscriber))

        if self._parent_channel:
            self._parent_channel._dispatch_msg(
                message, self, orig_thread, async)

    ##################################################

    def __str__(self):
        return '<%s name=%s>'%(self.__class__.__name__, self.name)

    def __repr__(self):
        return str(self)

    property has_subscriptions:
        def __get__(self):
            return self._has_async_subscriptions or self._has_synchronous_subscriptions

    property has_async_subscriptions:
        def __get__(self):
            return self._has_async_subscriptions

    property has_synchronous_subscriptions:
        def __get__(self):
            return self._has_synchronous_subscriptions

    property asynchronous_subscriptions:
        def __get__(self):
            return tuple(self._async_subscriptions)

    property synchronous_subscriptions:
        def __get__(self):
            return tuple(self._synchronous_subscriptions)

    property parent_channel:
        def __get__(self):
            return self._parent_channel

    property child_channels:
        def __get__(self):
            return tuple(self._child_channels)
