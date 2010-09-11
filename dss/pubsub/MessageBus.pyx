"""Provides MessageBus, the core public class of the dss.pubsub package.
"""

# cython imports
from dss.sys.time_of_day cimport time_of_day

# stdlib
import atexit
import traceback
import re
from threading import Thread, RLock, Lock, Event

def _get_internal_log_channel_class():
    # avoids circ. import issue, etc.
    from dss.log.LogChannel import LogChannel

################################################################################
# dispatch_thread_states:
cdef int _NOT_RUNNING=0, _WAITING=1, _DISPATCHING=2

RUNNING_MESSAGE_BUS_INSTANCES = []
def stop_all_message_buses():
    """Stop *every* active message bus running in the current process.
    """
    for bus in RUNNING_MESSAGE_BUS_INSTANCES[:]:
        # note the [:] to create a copy as
        # RUNNING_MESSAGE_BUS_INSTANCES changes size as a result of
        # this loop
        try:
            bus.stop()
        except:
            traceback.print_exc()
atexit.register(stop_all_message_buses) # this will only be called
                                        # after all non-daemon threads
                                        # have exited.  Thus, it's
                                        # still important to setDaemon(1) any
                                        # worker threads.

class InvalidChannelName(Exception): pass
class UnknownChannel(Exception): pass
class ChannelAlreadyExists(Exception): pass
class _ShutdownNow(Exception): pass
cdef object _shutdownMsg = _ShutdownNow() # cdef used to avoid module
                                        # dict lookup

################################################################################
cdef class MessageBus(Service):
    """A MessageBus manages a set of message channels, the subscriptions to
    those channels, and the messages that are published on those channels.
    """

    def __init__(self, internal_log_channel=None, **settings):
        """
        The subscriptions parameter allows you to initialize subcriptions before
        the the first messages are sent out on the Bus' internal
        channel. It should be a set of tuples in the form:
          (
            (channel_name, subscriber),
            (channel_name, subscriber)
          )
        """
        Service.__init__(self, **settings)
        self._mutex = RLock() # used for management ops: creating
                              # channels, etc., must be recursive
        self._subscriptions_mutex = Lock() # non-recursive lock
        self._channels = {} # name : channel-obj
        self._internal_log_channel = internal_log_channel
        self._dispatcher = None
        self.last_async_dispatch_time = 0
        self.start()

    def _initialize_settings(self):
        self._settings.update(dict(
            use_dedicated_thread_mode=False,
            max_queue_size=0,
            initial_subscriptions=(),
            channel_class=_Channel,
            channel_name_separator='.',
            channel_name_pattern=r'[a-zA-Z_][a-zA-Z_0-9]*',
            internal_channel_name='dss.pubsub'))

    def start(self):
        """Note that start() is called automatically from __init__()
        """
        self._mutex.acquire()
        try:
            if not self.running:
                if self not in RUNNING_MESSAGE_BUS_INSTANCES:
                    RUNNING_MESSAGE_BUS_INSTANCES.append(self)
                self.running = True
                self._start_time = time_of_day()
                self._channel_name_regex = re.compile(r'^(%s)(%s%s)*$'%(
                    self._settings['channel_name_pattern'],
                    _escape_regex_chars(self._settings['channel_name_separator']),
                    self._settings['channel_name_pattern']))

                self.root_channel = self.create_new_channel('root')

                if not self._internal_log_channel:
                    internal_channel_name = self._settings['internal_channel_name'].replace(
                        '.', self._settings['channel_name_separator'])
                    self._internal_log_channel = self.create_new_channel(
                        internal_channel_name)
                for channel_name, subscriber in self._settings['initial_subscriptions']:
                    self.subscribe(channel_name, subscriber)

                # default to non-async dispatcher, but need to document this well
                # if we were to default to a dedicated thread we'd need to
                # watch out for cron-jobs and scripts hanging
                if self._settings['use_dedicated_thread_mode']:
                    self._dispatcher = DedicatedThreadMsgDispather(
                        internal_log_channel=self._internal_log_channel,
                        max_queue_size=self._settings['max_queue_size'])
                else:
                    self._dispatcher = NonThreadedMsgDispather(
                        internal_log_channel=self._internal_log_channel,
                        max_queue_size=self._settings['max_queue_size'])
        finally:
            self._mutex.release()

    cpdef object is_valid_channel_name(self, channel_name):
        return self._channel_name_regex.match(channel_name)

    cpdef _Channel create_new_channel(self, channel_name, channel_class=None):
        """Should be called by publishers to open a *new* channel.

        Client code (message publishers or subscribers, etc.) wanting
        an existing channel should not call this method as that
        introduces the risk of creating invalid channels due to typos
        in the `channel_name`. Rather, they should use either
        `get_channel()` or an existing code reference to the channel
        object.

        It will raise `ChannelAlreadyExists` if a channel with
        `channel_name` has previously been created on this
        `MessageBus`.

        Wildcards are not allowed in `channel_name`.
        """
        if channel_name in self._channels:
            raise ChannelAlreadyExists(channel_name)
        elif not self.is_valid_channel_name(channel_name):
            raise InvalidChannelName(channel_name)
        else:
            return self._init_channel(channel_name, channel_class)

    cpdef _Channel _init_channel(self, channel_name, channel_class=None):
        channel_class = channel_class or self._settings['channel_class']
        channel_name_separator = self._settings['channel_name_separator']

        chunks = channel_name.split(channel_name_separator)
        chunks.reverse()
        if len(chunks) > 1 and chunks[-1].lower() == 'root':
            chunks.pop()

        ## start at the top and work down to the current subchannel
        channel = self.root_channel
        name = ''
        self._mutex.acquire()
        try:
            while chunks:
                if name:
                    name = name + channel_name_separator + chunks.pop()
                else:
                    name = chunks.pop()

                if name not in self._channels:
                    if channel:
                        channel = channel._spawn_subchannel(name)
                    else:
                        channel = channel_class(message_bus=self, channel_name=name)
                    self._channels[name] = channel
                else:
                    channel = self._channels[name]
        finally:
            self._mutex.release()

        return channel

    cpdef _Channel get_channel(self, channel_name):
        """Used to get a reference to an *existing* channel.

        The `channel_name` must be complete. Wildcards are not allowed
        here.

        """
        if channel_name in self._channels:
            return self._channels[channel_name]
        elif not self.is_valid_channel_name(channel_name):
            raise InvalidChannelName(channel_name)
        else:
            raise UnknownChannel(channel_name)

    cpdef is_channel_open(self, channel_name):
        return channel_name in self._channels

    cpdef get_open_channel_names(self):
        return self._channels.keys()

    cpdef Subscription subscribe(
        self, channel_name, subscriber,
        include_subchannels=False, async=True, thread_id=0):
        """
        Wildcards are allowed: top_channel.sub_channel.*
        """
        if channel_name == '*':
            channel_name = 'root'
            include_subchannels = True
        elif channel_name.endswith(self._settings['channel_name_separator']+'*'):
            include_subchannels = True
            channel_name = channel_name[:-len(self._settings['channel_name_separator']+'*')]

        if channel_name in self._channels:
            return self._channels[channel_name].subscribe(
                subscriber, include_subchannels=include_subchannels,
                async=async, thread_id=thread_id)
        else:
            raise UnknownChannel(channel_name)

    cpdef object _queue_msg_for_async_subs(self, msg,
                                           _Channel orig_channel,
                                           long orig_thread):
        """This is called by channels with async subscribers.
        They handle synchronous subscribers on their own without
        alerting the bus.
        """
        self.last_async_dispatch_time = time_of_day()
        self._dispatcher.queue_msg(msg, orig_channel, orig_thread)


    ##################################################
    ## @@TR: turn_on_dedicated_thread_mode should be replaced with
    ## set_dispatcher method that accepts either a dispatcher instance
    ## or a dispatcher class that should be instantiated.  When a new
    ## one is set, the existing dispatcher should be stopped.
    def turn_on_dedicated_thread_mode(self):
        self._mutex.acquire()
        try:
            self._dispatcher.stop()
            self._dispatcher = DedicatedThreadMsgDispather(
                internal_log_channel=self._internal_log_channel,
                max_queue_size=self._settings['max_queue_size'])
        finally:
            self._mutex.release()

    ##################################################

    def stop(self):
        """Always shut this service last or messages from other parts of the
        system will be lost.
        """
        self._mutex.acquire()
        try:
            if self.running:
                # if subscribers have special shutdown requirements they should
                # be added implemented as services and registered as child
                # services of either the ServiceRunner or the MessageBus instance
                for child_service in self._child_services:
                    if child_service.running:
                        try:
                            child_service.stop()
                        except:
                            self._log_internal_exception(
                                'error stopping child service %r'%child_service)

                self._dispatcher.stop()
                self.running = False
                RUNNING_MESSAGE_BUS_INSTANCES.remove(self)
        finally:
            self._mutex.release()

    property channels:
        def __get__(self):
            return self._channels.copy()


    ##################################################

    def _log_internal_error(self, msg, channel=None, exception=False):
        _log_internal_error(msg, source_channel=channel,
                            internal_log_channel=self._internal_log_channel,
                            exception=exception)

    def _log_internal_exception(self, msg, channel=None):
        self._log_internal_error(msg, channel, exception=True)

##

def _escape_regex_chars(
    txt, escape_re=re.compile(r'([\$\^\*\+\.\?\{\}\[\]\(\)\|\\])')):
    """Return a txt with all special regular expressions chars
    escaped."""
    return escape_re.sub(r'\\\1' , txt)

def _log_internal_error(msg, source_channel=None, internal_log_channel=None, exception=False):
    try:
        if (internal_log_channel and source_channel is not internal_log_channel
            and internal_log_channel.has_subscriptions):
            # if exceptions are being raised by the
            # internal_log_channel itself we must not get stuck in
            # a loop
            if exception:
                internal_log_channel.exception(msg)
            else:
                internal_log_channel.error(msg)
        else:
            print 'ERROR >>>', msg
            if exception:
                traceback.print_exc()
    except:
        pass

def _log_internal_exception(msg, source_channel=None, internal_log_channel=None):
    _log_internal_error(msg, source_channel=source_channel,
                        internal_log_channel=internal_log_channel,
                        exception=True)

################################################################################
## Dispatchers
## I plan to add a zeromq and threadpool dispatcher as well.
cdef class AbstractAsyncMsgDispatcher:

    def __init__(self, internal_log_channel, max_queue_size=0):
        self._internal_log_channel = internal_log_channel
        self._max_queue_size = max_queue_size
        self._mutex = RLock()
        self.last_dispatch_time = 0
        self.message_count = 0
        self._dispatch_count = 0 # for debugging
        self._running = False

    # __init__() handles start()
    def stop(self):
        pass

    cpdef queue_msg(self, msg, _Channel orig_channel, long orig_thread):
        raise NotImplementedError

    def _log_internal_error(self, msg, channel=None, exception=False):
        _log_internal_error(msg, source_channel=channel,
                            internal_log_channel=self._internal_log_channel,
                            exception=exception)

    def _log_internal_exception(self, msg, channel=None):
        self._log_internal_error(msg, channel, exception=True)

cdef class NonThreadedMsgDispather(AbstractAsyncMsgDispatcher):
    cpdef queue_msg(self, msg, _Channel orig_channel, long orig_thread):
        self.last_dispatch_time = time_of_day()
        self.message_count += 1
        orig_channel._dispatch_msg(msg, orig_channel, orig_thread, True)

cdef class DedicatedThreadMsgDispather(AbstractAsyncMsgDispatcher):

    def __init__(self, internal_log_channel, max_queue_size=0):
        super(DedicatedThreadMsgDispather,
              self).__init__(internal_log_channel, max_queue_size)

        self._msg_queue = BlockingQueue(self._max_queue_size)
        self._running = True
        self._dispatch_thread_state = _NOT_RUNNING
        self._dispatch_thread_exit_event = Event()
        self._dispatch_thread = Thread(target=self._dispatch_thread_loop)
        self._dispatch_thread.setDaemon(1)
        self._dispatch_thread.start()

    cpdef queue_msg(self, msg, _Channel orig_channel, long orig_thread):
        if self._running:
            self.message_count += 1
            self._msg_queue.put((msg, orig_channel, orig_thread))
        else:
            orig_channel._dispatch_msg(msg, orig_channel, orig_thread, True)

    def _dispatch_thread_loop(self):
        """Dispatches messages from the queue to the channels that received the messages.
        """
        cdef BlockingQueue msg_queue
        cdef _Channel channel

        self._dispatch_thread_exit_event.clear()
        msg_queue = self._msg_queue
        while self._running:
            self._dispatch_thread_state = _WAITING
            try:
                items = msg_queue.getmany(0)
                self.last_dispatch_time = time_of_day()
                self._dispatch_thread_state = _DISPATCHING
                for item in items:
                    try:
                        msg, channel, orig_thread = item
                        if msg is _shutdownMsg:
                            raise _ShutdownNow()
                        else:
                            channel._dispatch_msg(msg, channel, orig_thread, True)
                            # i.e. (msg, orig_channel, orig_thread, async)
                            self._dispatch_count += 1
                    except _ShutdownNow:
                        raise
                    except:
                        if msg is _shutdownMsg:
                            # for some reason the except clause
                            # above doesn't always catch it
                            raise _ShutdownNow()
                        errorMsg = ('exception while dispatching'
                                    ' message %r to channel "%r"'%(msg, channel))
                        self._log_internal_exception(errorMsg, channel=channel)
            except _ShutdownNow:
                break
            except:
                self._log_internal_exception(
                    'Unhandled error in async dispatch thread')

        self._dispatch_thread_state = _NOT_RUNNING
        self._dispatch_thread_exit_event.set()

    def stop(self, timeout=2):
        self._mutex.acquire()
        try:
            if self._dispatch_thread_state:
                self._msg_queue.put(
                    (_shutdownMsg, self._internal_log_channel, 0))
                if self._dispatch_thread_state:
                    self._dispatch_thread_exit_event.wait(timeout)
                if self._dispatch_thread_state:
                    msg = ('Dispatch thread still has not exited.'
                           ' Letting it die in daemon mode.')
                    self._log_internal_error(msg)
                    self._dispatch_thread_state = _NOT_RUNNING

                self._dispatch_thread = None
            self._running = False       # must come last
        finally:
            self._mutex.release()
