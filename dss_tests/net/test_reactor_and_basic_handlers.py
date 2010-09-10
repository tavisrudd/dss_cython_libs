from __future__ import with_statement
# pylint: disable-msg=W0613,W0212
#import socket
#import select
from threading import Event
from nose.tools import raises

#from dss.sys.log import StdOutListener

from dss.pubsub.MessageBus import MessageBus
from dss.net.IOEventReactor import (
    IOEventReactor
    , REACTOR_STOPPED
    , REACTOR_POLLING
    , REACTOR_DISPATCHING
    )
from dss.net.event_flags import (
    META_REACTOR_SHUTDOWN_EV
    , META_READ_EV
    , META_WRITE_EV
    , META_DISCONNECTED_EV
    , POLLIN
    , POLLPRI
    , POLLOUT
    , POLLNVAL
    , POLLERR
    , POLLHUP
    )

from dss.net.IOEventHandler import AbstractIOEventHandler
from dss.sys._internal.PollableEvent import PollableEvent

from dss.log.Subscribers import Formatter
from dss.log.LogChannel import LogChannel

class LoggingContext(object):
    def __init__(self, channel_name='Test'):
        self.bus = MessageBus(
            channel_class=LogChannel,
            use_dedicated_thread_mode=True)
        self.log_channel = self.bus.create_new_channel(channel_name)
        self.messages = []
        self.log_channel.subscribe(lambda msg: self.messages.append(msg))

    def __enter__(self):
        self.bus.start()
        return self

    def __exit__(self, exc_type=None, exc_val=None, exc_tb=None):
        self.bus.stop()
        formatter = Formatter()
        for msg in self.messages:
            print formatter.format(msg)

class ThreadSynchronizer(object):
    def __init__(self):
        self.event_pipe = PollableEvent()
        self.reverse_sync_event = Event()

    def sync_from_main(self, callback=None):
        """Each call will trigger a read event (POLLIN) on event_pipe.
        """
        self.event_pipe.set()
        if callback:
            callback()
        self.reverse_sync_event.wait(2)
        assert self.reverse_sync_event.isSet()
        self.reverse_sync_event.clear()
        assert not self.event_pipe.isSet()
        assert not self.reverse_sync_event.isSet()

    def sync_from_reactor_thread(self):
        self.event_pipe.clear()
        self.reverse_sync_event.set()

def test_with_dummy_handler():
    with LoggingContext() as logger:
        chan = logger.log_channel
        def once():
            synchronizer = ThreadSynchronizer()
            try:
                reactor = IOEventReactor(log_channel=chan)
                assert not reactor._event_loop_thread
                assert not reactor._poller
                assert not reactor.running
                assert reactor._reactor_state == REACTOR_STOPPED
                reactor.start()

                event_log = []
                def handle_event(reactor, fd, eventmask, timestamp):
                    event_log.append((reactor, fd, eventmask))
                    if fd is synchronizer.event_pipe.fileno():
                        synchronizer.sync_from_reactor_thread()
                    if eventmask & META_READ_EV:
                        chan.debug('read event (reactor state=%i)'%reactor._reactor_state)
                        return False
                    elif eventmask & META_WRITE_EV:
                        chan.debug(
                            'write event (reactor state=%i)'%reactor._reactor_state)
                    elif eventmask & META_DISCONNECTED_EV:
                        chan.debug(
                            'disconnected (reactor state=%i)'%reactor._reactor_state)
                        return True
                    elif eventmask == META_REACTOR_SHUTDOWN_EV:
                        chan.debug(
                            'shutdown event (reactor state=%i)'%reactor._reactor_state)
                        return True
                    else:
                        chan.error(
                            'unknown event (reactor state=%i)'%reactor._reactor_state)
                        return True
                reactor.register_handler(synchronizer.event_pipe, handle_event)
                #

                synchronizer.sync_from_main()
                assert len(event_log) == 1
                x = 15
                for _i in xrange(x):
                    synchronizer.sync_from_main()

                assert len(event_log) == x+1, len(event_log)

                assert reactor._reactor_state in (REACTOR_POLLING, REACTOR_DISPATCHING)
                assert reactor.running
                synchronizer.sync_from_main()
                assert reactor._reactor_state in (REACTOR_POLLING, REACTOR_DISPATCHING)
                for _reactor, fd, eventmask in event_log:
                    assert _reactor is reactor
                    assert fd is synchronizer.event_pipe.fileno()
                    assert eventmask is POLLIN
            finally:
                synchronizer.sync_from_main(callback=lambda : reactor.stop())
                assert reactor._reactor_state == REACTOR_STOPPED
                assert event_log[-1][-1] == META_REACTOR_SHUTDOWN_EV

        for _i in xrange(5):
            once()



def test_with_abstract_handler():
    reactor = IOEventReactor()
    handler = AbstractIOEventHandler()

    assert not reactor.running
    assert handler.event_count == 0
    assert handler.last_event_time == 0

    @raises(NotImplementedError)
    def test_abstract_meth(meth, *args, **kws):
        meth(*args, **kws)

    for i, event in enumerate((POLLIN, POLLPRI,
                               POLLOUT,
                               POLLHUP, POLLNVAL, POLLERR,
                               (POLLHUP | POLLNVAL),
                               )):
        args = dict(reactor=None, fd=1, eventmask=event, timestamp=1)
        test_abstract_meth(handler, **args) # __call__ alias
        test_abstract_meth(handler.handle_event, **args)
        assert handler.event_count == (i+1)*2
        assert handler.last_event_time

    test_abstract_meth(handler._handle_read_event, 0)
    test_abstract_meth(handler._handle_write_event, 0)
    test_abstract_meth(handler._close_descriptor, 0)

    for fd in xrange(1, 10):
        handler._register_fd_with_reactor(fd=fd, reactor=reactor)
        assert reactor.get_handler(fd) == handler
        reactor.unregister(fd) # this is raising and handling
                               # exceptions internally, as the reactor
                               # hasn't been started
        try:
            reactor.get_handler(fd)
        except KeyError:
            pass

    for fd in xrange(1, 10):
        handler._register_fd_with_reactor(fd=fd, reactor=reactor)
    reactor._cull_any_bad_descriptors()

################################################################################

#class SyncEvHandler(AbstractIOEventHandler):
#    def _handle_read_event(self, fd):
#        # called when sync_event1 is set
#        chan.debug('read ev (reactor state=%i)'%reactor._reactor_state)
#        sync_event1.clear()
#        reverse_sync_event.set()
#        return False
#
#    def _close_descriptor(self, fd):
#        chan.debug(
#           '_close_descriptor (reactor state=%i)'%reactor._reactor_state)
#        return True
#
#sync_event_handler = SyncEvHandler(log_channel=chan)
#sync_event_handler._register_fd_with_reactor(
#    fd=sync_event1.fileno(), reactor=reactor)
