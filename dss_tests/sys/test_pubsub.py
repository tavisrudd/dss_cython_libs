# pylint: disable-msg=W0212,R0912,R0914
from thread import get_ident as current_thread_id
from threading import Event, Thread
from time import time as time_of_day, sleep

from nose.tools import raises

from dss.pubsub.MessageBus import (
    MessageBus,
    InvalidChannelName,
    UnknownChannel,
    ChannelAlreadyExists,
    stop_all_message_buses, RUNNING_MESSAGE_BUS_INSTANCES)

class CollectingSubscriber(object):
    def __init__(self):
        self.messages = []
    def __call__(self, msg):
        self.messages.append(msg)

class SlowSubscriber(CollectingSubscriber):
    def __call__(self, msg):
        CollectingSubscriber.__call__(self, msg)
        sleep(.01)


@raises(UnknownChannel)
def get_nonexistent_channel(bus, cname):
    bus.get_channel(cname)

@raises(ChannelAlreadyExists)
def attempt_to_create_existing_channel(bus, cname):
    bus.create_new_channel(cname)

@raises(InvalidChannelName)
def get_invalid_channel(bus, cname):
    bus.get_channel(cname)

def test_channel_names():
    bus1 = MessageBus()
    bus2 = MessageBus(channel_name_separator='/')

    for name in ['..foo', '*', '/', '.', '.sub', '98', '98_', 'top.98']:
        get_invalid_channel(bus1, name)
        assert not bus1.is_valid_channel_name(name)

    for name in ['foo', 'foo2', 'foo_a',
                 '_foo','_', 'foo123',
                 'foo.bar', 'foo.bar.asdf',
                 'a.b.c.d'
                 ]:
        assert bus1.is_valid_channel_name(name)
        assert bus2.is_valid_channel_name(
            name.replace('.','/'))

    bus1.stop()
    bus2.stop()

def test_channel_management(use_dedicated_thread_mode=True):
    bus = MessageBus()

    initial_channel_count = len(bus.channels) # root channel, internal
                                        # log channel, etc.
    test_channels = {}

    bus.start() # The bus has already been started by __init__, but
                # this extra call should do no damage!

    if use_dedicated_thread_mode:
        bus.turn_on_dedicated_thread_mode()

    attempt_to_create_existing_channel(bus, 'root')
    assert bus.root_channel == bus.get_channel('root')

    def addchan(name, parent):
        get_nonexistent_channel(bus, name)
        test_channels[name] = chan = bus.create_new_channel(name)
        assert chan == bus.get_channel(name)
        assert chan.parent_channel == parent
        assert chan in parent.child_channels
        assert chan.name == name
        return chan

    for i in xrange(5):
        topname = 'top%i'%i
        topchan = addchan(topname, bus.root_channel)
        for j in xrange(5):
            subname = '%s.subchan%i'%(topname, j)
            subchan = addchan(subname, topchan)
            assert len(topchan.child_channels) == j+1
            assert '.'.join(subchan.name.split('.')[:-1])==topchan.name
            for k in xrange(5):
                subsubchan = addchan('%s.subsubchan%i'%(subname, k), subchan)
                assert len(subchan.child_channels) == k+1
                assert '.'.join(subsubchan.name.split('.')[:-1])==subchan.name

    assert len(bus.channels) == (len(test_channels)+initial_channel_count)
    assert len(bus.channels) == len(bus.get_open_channel_names())

    chanX = bus.create_new_channel('X')
    attempt_to_create_existing_channel(bus, 'X')
    assert chanX.parent_channel == bus.root_channel
    assert bus.get_channel('X') == chanX
    assert bus.create_new_channel('x') != chanX
    chanY = bus.create_new_channel('X.Y')
    assert chanY.parent_channel == chanX
    assert chanX.name in bus.channels
    assert chanY.name in bus.channels

    bus.stop()

def test_channel_management_nonthreaded():
    test_channel_management(use_dedicated_thread_mode=False)

def _test_subscriptions(async=False, threadlocal=False):
    bus = MessageBus(use_dedicated_thread_mode=async)
    bus.start()

    start_time = time_of_day()
    test_thread_id = current_thread_id()

    channels = {}
    channel_names = ('a', 'a.b', 'a.b.c', 'a.b.c.d', 'w.x.y.z')
    message_count = 200
    class Subscriber(object):
        def __init__(self, channel_name):
            self.channel_name = channel_name
            self.messages = []
            self.done = Event()

        def __call__(self, msg):
            self.messages.append((msg, current_thread_id()))
            # this is the thread_id where the message is received
            if msg[1] == message_count:
                self.done.set()
            elif msg[1] > message_count:
                raise ValueError(
                    ("Received a message index '%i' "
                     "higher than max message_count %i"%(
                         msg[1], message_count)))

    class WildcardSubscriber(object):
        def __init__(self, channel_name):
            self.channel_name = channel_name
            self.messages = []
            self.done = Event()

        def __call__(self, msg):
            if not self.done.isSet():
                # only expecting a single message
                self.messages.append((msg, current_thread_id()))
                self.done.set()
            else:
                raise Exception('Was only expecting a single message')

    ## setup non-wildcard subscriptions
    for channel_name in channel_names:
        channel = bus.create_new_channel(channel_name)
        subscriber = Subscriber(channel_name)
        subscription=bus.subscribe(
            channel_name, subscriber,
            async=async, thread_id=(threadlocal and test_thread_id or 0))
        channels[channel_name] = (channel, subscription)

        assert subscription.channel == channel
        assert subscription.subscriber == subscriber
        assert not subscription.include_subchannels
        assert subscription.message_count == 0
        assert subscription.timestamp >= start_time
        assert subscription.is_active
        assert subscription.async == async
        assert subscription.thread_id == (threadlocal and test_thread_id or 0)

        assert channel.has_subscriptions, channel_name
        assert channel.has_async_subscriptions == async, channel_name
        assert channel.has_synchronous_subscriptions != async, channel_name
        assert bool(channel.asynchronous_subscriptions) == async
        assert bool(channel.synchronous_subscriptions) != async


    for channel_name, (channel, subscription) in channels.iteritems():
        # pull the channel and subscription from the bus again
        assert channel == bus.get_channel(channel_name)
        if async:
            assert subscription == channel.asynchronous_subscriptions[0]
        else:
            assert subscription == channel.synchronous_subscriptions[0]

        ## send a batch of messages followed by a sentinel terminator message
        for i in xrange(message_count):
            channel.send((channel_name, i))
            if not async:
                assert channel.message_count == subscription.message_count == i+1
        channel.send((channel_name, message_count)) # terminator
                                        # message, which sets
                                        # subscriber.done event

        if threadlocal:
            # add some messages from another thread, which should *not*
            # be dispatched to the subscribers or appear in the subscriber.messages list
            def send_from_other_thread():
                channel.send(('%s - thread %s'%(channel_name, current_thread_id()), -99))
            t = Thread(target=send_from_other_thread)
            t.start()
            t.join()

        ## check the messages that were received
        subscriber = subscription.subscriber
        subscriber.done.wait(timeout=3)
        if not subscriber.done.isSet():
            raise Exception(
                ("Something went wrong on %r.  "
                 "Its subscriber hasn't finished processing all %i messages."
                 " %i processed. async=%r."
                 " subscriber=%r. threadlocal=%r."
                 " subscription=%r, msg_count=%i dispatch_count=%i")%(
                    channel, message_count,
                    len(subscriber.messages),
                    async,
                    subscriber,
                    threadlocal,
                    subscription.channel,
                    bus._dispatcher.message_count,
                    bus._dispatcher.dispatch_count,
                    ))
        for i, (msg, thread_id) in enumerate(subscriber.messages):
            assert (thread_id == test_thread_id) != async
            if msg[1] == -99:
                print '>>> threadlocal error async=%s'%async
                print '>>> The following message came from ',
                print 'another thread and should have been dropped:'
                print msg
                raise Exception(
                    'Messages from thread with no subscribers were not ignored properly')

            assert msg[0] == channel_name
            # we sent all messages from a single thread so they should
            # be in the correct order.  This would not be true if we
            # had sent msgs from multiple threads:
            assert msg[1] == i

        # final check of message counts:
        assert len(subscriber.messages) == (message_count+1), \
               (len(subscriber.messages), i)
        assert channel.message_count == subscription.message_count+[0, 1][threadlocal]

        ## make sure that unsubscription and parent channel wildcard
        ## subscriptions work correctly:

        parent = channel.parent_channel
        parent_wildcard_subs = []
        while parent:
            parent_wildcard_subs.append(parent.subscribe(
                WildcardSubscriber(parent.name),
                include_subchannels=True,
                async=async,
                thread_id=(threadlocal and test_thread_id or 0)))
            parent = parent.parent_channel
        # cancel the non-wildcard subscription
        subscription.cancel()
        assert not subscription.is_active
        # send a message that each wilcard subscriber should receive
        # once only
        channel.send((channel_name, 999))
        # cancel parent channel wildcard subs and check counts
        for parent_sub in parent_wildcard_subs:
            parent_sub.subscriber.done.wait(timeout=3)
            if not parent_sub.subscriber.done.isSet():
                raise Exception('Timed out waiting for parent_sub')

            assert parent_sub.message_count == 1
            assert len(parent_sub.subscriber.messages) == 1, \
                   parent_sub.subscriber.messages
            assert parent_sub.subscriber.messages[0][0][0] == channel_name, \
                   parent_sub.subscriber.messages
            assert channel.has_subscriptions
            if async:
                assert channel.has_async_subscriptions
            else:
                assert channel.has_synchronous_subscriptions
            assert parent_sub.channel.has_subscriptions
            parent_sub.cancel()
            assert not parent_sub.is_active
        #
        assert not channel.has_subscriptions

    bus.stop()

def _test_subscriptions_from_multiple_threads(async=False, threadlocal=False):
    exceptions_raised_in_threads = []
    def test():
        try:
            _test_subscriptions(async=async, threadlocal=threadlocal)
        except:
            exceptions_raised_in_threads.append(True)
            raise

    threads = []
    for _i in xrange(3):
        t = Thread(target=test)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()

    assert not exceptions_raised_in_threads

def _test_subscriptions_from_single_and_multithreads(async, threadlocal):
    _test_subscriptions(async=async, threadlocal=threadlocal)
    _test_subscriptions_from_multiple_threads(async=async, threadlocal=threadlocal)

def test_subscriptions_sync():
    _test_subscriptions_from_single_and_multithreads(async=False, threadlocal=False)

def test_subscriptions_sync_threadlocal():
    _test_subscriptions_from_single_and_multithreads(async=False, threadlocal=True)

def test_subscriptions_async():
    _test_subscriptions_from_single_and_multithreads(async=True, threadlocal=False)

def test_subscriptions_async_threadlocal():
    _test_subscriptions_from_single_and_multithreads(async=True, threadlocal=True)

def test_various_message_types():
    bus = MessageBus()
    chan = bus.root_channel
    subscriber = CollectingSubscriber()
    chan.subscribe(subscriber, async=True)
    messages = ('a', u'asdf', {'a':1234}, 2.2, set((1, 2)), [1, 2], (1, 2))
    for msg in messages:
        chan.send(msg)

    bus.stop()
    assert tuple(subscriber.messages) == messages

def test_full_message_queue():
    bus = MessageBus(max_queue_size=1)
    bus.turn_on_dedicated_thread_mode()
    chan = bus.root_channel
    subscriber = CollectingSubscriber()

    chan.subscribe(subscriber, async=True)
    for i in range(6):
        chan.send(i)

    slow_subscriber = SlowSubscriber()
    chan.subscribe(slow_subscriber, async=True)
    for i in range(6):
        # will block till the slow subscriber has finished handling
        # the previous one
        chan.send(i)
    bus.stop()

#def test_channel_subclasses():
#    bus = MessageBus()

#def test_internal_log_channel_from_other_bus():
#    bus = MessageBus()

def test_stop_all_message_buses():
    if RUNNING_MESSAGE_BUS_INSTANCES:
        # clear up from previous failed tests that didn't stop their buses
        stop_all_message_buses()

    buses = []
    for _i in xrange(20):
        buses.append(MessageBus(use_dedicated_thread_mode=True))
    for bus in buses:
        assert bus.running
        assert bus._start_time

    assert len(buses) == len(RUNNING_MESSAGE_BUS_INSTANCES)

    stop_all_message_buses()
    for bus in buses:
        assert not bus.running, RUNNING_MESSAGE_BUS_INSTANCES
