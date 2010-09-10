"""See the module docstring of IOEventHandler.
"""
import sys
import select
import socket
import errno
from threading import Thread
from time import sleep
import traceback

from select import (POLLIN, POLLPRI, POLLOUT, POLLERR, POLLHUP, POLLNVAL)

from dss.sys._internal.PollableEvent import PollableEvent

################################################################################
POLLRDHUP = 0x2000
ERROR_EVENTS = (POLLERR | POLLHUP | POLLRDHUP | POLLNVAL)

cdef int _STOPPED=1, _POLLING=2, _DISPATCHING=3
(REACTOR_STOPPED, REACTOR_POLLING, REACTOR_DISPATCHING)=(_STOPPED, _POLLING, _DISPATCHING)
# python versions for export, underscored int versions to speedup lookups

from dss.net.event_flags import META_REACTOR_SHUTDOWN_EV
################################################################################

class _SelectPoller(object):
    """Emulate a Poll object when only `select` is available on the platform.

    This is inspired by the _Select class in
    http://github.com/facebook/tornado/blob/master/tornado/ioloop.py
    which is Copyright 2009 Facebook
    """
    _READ_EVENTS = (POLLIN | POLLPRI)
    _WRITE_EVENTS = POLLOUT
    _ERROR_EVENTS = ERROR_EVENTS

    def __init__(self):
        self.read_fds = set()
        self.write_fds = set()
        self.error_fds = set()
        self.fd_sets = (self.read_fds, self.write_fds, self.error_fds)

    def register(self, fd, events=None):
        if events is None:
            events = self._READ_EVENTS | self._WRITE_EVENTS | self._ERROR_EVENTS
        if events & self._READ_EVENTS:
            self.read_fds.add(fd)
        if events & self._WRITE_EVENTS:
            self.write_fds.add(fd)
        if events & self._ERROR_EVENTS:
            self.error_fds.add(fd)

    def unregister(self, fd):
        self.read_fds.discard(fd)
        self.write_fds.discard(fd)
        self.error_fds.discard(fd)

    def poll(self, timeout=None):
        readable, writeable, errors = select.select(
            self.read_fds, self.write_fds, self.error_fds, timeout)
        events = {} # fd:eventmask
        for fd in readable:
            events [fd] = events.get(fd, 0) | self._READ_EVENTS
        for fd in writeable:
            events [fd] = events.get(fd, 0) | self._WRITE_EVENTS
        for fd in errors:
            events [fd] = events.get(fd, 0) | self._ERROR_EVENTS
        return events.items()

if not hasattr(select, 'epoll'):
    try:
        import select26 as select
    except ImportError:
        pass
if hasattr(select, 'epoll'):
    _default_poll_factory = select.epoll
elif hasattr(select, 'poll'):
    _default_poll_factory = select.poll
else:
    _default_poll_factory = _SelectPoller

################################################################################
## and now the meat:

cdef class IOEventReactorInterface(Service):
    cpdef object register_handler(self, fd, handler, eventmask=None):
        """
        This isn't called `register` as that would clash with the C
        reserved keyword.
        """
        raise NotImplementedError

    cpdef object unregister(self, fd, int flush=True):
        raise NotImplementedError

    cpdef object get_handler(self, fd):
        raise NotImplementedError

cdef class IOEventReactor(IOEventReactorInterface):
    """See the module doctring.
    """
    def __init__(self,
                 log_channel='dss.net.Reactor',
                 parent_service=None,
                 service_runner=None,
                 _poll_factory=_default_poll_factory):
        super(IOEventReactor, self).__init__(
            parent_service=parent_service,
            service_runner=service_runner,
            log_channel=log_channel)
        self._fd_to_handler_map = {}
        self._interrupt = PollableEvent() # this is polled so we can't
                                        # use threading.Event, which has
                                        # no fd
        self._reactor_state = REACTOR_STOPPED
        self.register_handler(self._interrupt, self._handle_interrupt_event)
        self.event_count = 0
        self._event_loop_thread = None
        self._poll_factory = _poll_factory
        self._poller = None

    def start(self):
        self._running = 1
        self._start_time = time_of_day()
        if self._log_channel:
            self._log_channel.notice('Starting IOEventReactor (%s)'%self._poll_factory.__name__)
        self._poller = self._poll_factory()
        self._poller.register(self._interrupt)

        # @@TR: might also want to add a way to run this in the main thread
        self._event_loop_thread = Thread(target=self._event_loop, name='event loop thread')
        self._event_loop_thread.start()

        for fd, (handler, eventmask) in self._fd_to_handler_map.iteritems():
            self.register_handler(fd, handler, eventmask)

        # @@TR: add a scheduled-recurring task to the threadPool to monitor things here
        # staleness, etc.

    def stop(self):
        self._running = 0
        self._reactor_state = REACTOR_STOPPED
        self._interrupt.set()
        if self._log_channel:
            self._log_channel.notice('Stopping IOEventReactor (%s)'%self._poll_factory.__name__)
        if self._event_loop_thread:
            self._event_loop_thread.join()
            self._event_loop_thread = None
        self._poller = None

        current_time = time_of_day()
        for fd, (handler, eventmask) in self._fd_to_handler_map.iteritems():
            try:
                handler(self, fd, META_REACTOR_SHUTDOWN_EV, current_time)
            except Exception, e:
                self._handle_exception(e)
        self._fd_to_handler_map.clear()

    cpdef object register_handler(self, fd, handler, eventmask=None):
        """
        `handler` can either be an instance of IOEventHandlerInterface
        or any other callable that has the same call:
            `f(reactor, fd, eventmask) -> bool`
            where the return value indicates if the reactor should
            unregister the fd from its event loop (True=unregister)
        Generic callables will be wrapped internally by instances
        of _IOEventHandlerCallbackWrapper.
        """
        if not isinstance(fd, int):
            if hasattr(fd, 'fileno'):
                fd = fd.fileno()
            else:
                raise ValueError('invalid file descriptor: %r'%fd)
        if fd < 1:
            raise ValueError('invalid file descriptor: %r'%fd)

        if not isinstance(handler, IOEventHandlerInterface):
            handler = _IOEventHandlerCallbackWrapper(handler)

        self._fd_to_handler_map[fd] = (handler, eventmask)
        if self._running:
            try:
                if eventmask is not None:
                    self._poller.register(fd, eventmask | ERROR_EVENTS)
                else:
                    self._poller.register(fd)
            except IOError, e:
                if getattr3(e, 'errno', None) == errno.EEXIST:
                    pass
            self._interrupt.set() # required!

    cpdef object get_handler(self, fd):
        # raise KeyError if fd not registered
        return self._fd_to_handler_map[fd][0] # ignore the eventmask

    cpdef object unregister(self, fd, int flush=True):
        try:
            try:
                if self._poller:
                    self._poller.unregister(fd)
            except:
                self._log_error('error unregistering %r'%fd)
            if flush and self._running:
                # now we have to trigger a false event so we can flush it out of the
                # current poll() call and delete our ref to the handler
                self._fd_to_handler_map[fd] = (self._handle_unregister_flush_event, None)
                self._interrupt.set()
            self._handle_unregister_flush_event(self, fd, None, 0)
        except:
            self._log_error('error unregistering %r'%fd)

    ## private methods:
    def _event_loop(self):
        while self._running:
            try:
                self._event_loop_inner()
            except (ValueError, TypeError), e:
                if self._reactor_state == _POLLING:
                    self._handle_exception(e, 'Polled something invalid, '
                        'such as a socket with a negative fd.'
                        '  Culling bad descriptors now.')
                    # maybe switch this to 'self._log_error(...)' instead
                    self._cull_any_bad_descriptors()
                else:
                    self._handle_exception(e, 'Unexpected exception in event loop')
            except (select.error, socket.error, IOError), e:
                if (e[0] == errno.EINTR or e[0]==0):
                    pass # the interrupt will be caught and handled elsewhere
                elif e[0] == errno.EBADF:
                    self._handle_exception(e, 'Unexpected socket error')
                    self._cull_any_bad_descriptors()
                else:
                    self._handle_exception(e, 'Unexpected exception in event loop')
            except Exception, e:
                self._handle_exception(e, 'Unexpected exception in event loop')

    cpdef object _event_loop_inner(self):
        # we hand off as quickly as possible so we can go back to polling
        # for new events should the handler dispatch to another
        # thread. The handler controls what happens next!
        cdef void *handler_lookup_res
        cdef IOEventHandlerInterface handler
        cdef int unregister
        cdef double timestamp

        poll = self._poller.poll
        fd_to_handler_map = self._fd_to_handler_map

        while self._running:
            self._reactor_state = _POLLING
            r = poll()
            if r and self._running:
                self.last_event_time = timestamp = time_of_day()
                self._reactor_state = _DISPATCHING
                for fd, eventmask in r:
                    self.event_count += 1
                    handler_lookup_res = PyDict_GetItem(fd_to_handler_map, fd)
                    if handler_lookup_res is NULL:
                        unregister = <int>bool(
                            self._handle_missing_handler(
                                self, fd, eventmask, timestamp))
                    else:
                        unregister = <int>bool(
                            (<object>handler_lookup_res)[0].handle_event(
                                self, fd, eventmask, timestamp))

                    if unregister:
                        self.unregister(fd, flush=False)


    cpdef object _log_error(self, msg):
        # @@TR: should add churning detection
        if self._log_channel:
            self._log_channel.error(msg)
        else:
            sys.stderr.write('>>> IOEventReactor ERROR: %s\n'%msg)
            sys.stderr.flush()

    cpdef object _handle_exception(self, e, logMessage='exception'):
        if self._service_runner and self._service_runner.is_fatal_error(e):
            self._service_runner.handle_fatal_error(e)
            sleep(.05) # to prevent needless churning
        else:
            if self._log_channel:
                try:
                    self._log_channel.exception(logMessage)
                except:
                    traceback.print_exc()
            else:
                traceback.print_exc()

    cpdef object _handle_missing_handler(self, reactor, fd, eventmask, timestamp):
        if self._log_channel:
            self._log_channel.info(
                'no handler found for fd=%r (eventmask: %s); unregistering'%(fd, eventmask))
        return True # unregister

    cpdef object _handle_unregister_flush_event(self, reactor, fd, eventmask, timestamp):
        """A dummy handler used during the unregistration of a ``fd``.
        """
        if fd in self._fd_to_handler_map:
            try:
                del self._fd_to_handler_map[fd]
            except:
                pass
        return False # as we don't want unregister(fd) called a second time

    cpdef object _handle_interrupt_event(self, reactor, fd, eventmask, timestamp):
        """Used to clear self._interrupt event when set.
        """
        self._interrupt.clear()

    cpdef object _cull_any_bad_descriptors(self):
        for fd, (handler, mask) in self._fd_to_handler_map.items():
            # @@TR: might be better to work from a list of likely suspects
            try:
                select.select([fd], [fd], [fd], 0)
            except:
                try:
                    del self._fd_to_handler_map[fd]
                except:
                    pass
                try:
                    # allow the handler to cleanup
                    handler(self, fd, POLLNVAL, time_of_day())
                except:
                    if self._log_channel:
                        self._log_channel.exception()

cdef class _IOEventHandlerCallbackWrapper(IOEventHandlerInterface):
    """This simple wrapper is used to adapt generic python callables
    to the IOEventHandlerInterface that IOEventReactor expects
    internally.
    """
    cdef object callback

    def __init__(self, callback):
        self.callback = callback

    cpdef handle_event(self,
                       IOEventReactorInterface reactor,
                       object fd,
                       object eventmask,
                       double timestamp):
        return self.callback(reactor, fd, eventmask, timestamp)
