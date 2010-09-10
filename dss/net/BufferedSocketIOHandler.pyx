import errno
import socket
from collections import deque
from dss.sys.time_of_day cimport time_of_day

class AWAITING_MORE_BYTES: pass
cdef class BufferedSocketIOHandler(AbstractIOEventHandler):
    """WORK IN PROGRESS ...

    - only for connected sockets, not for listening server sockets
    - socket.accept()/connect() stage has already been handled
    - they can be moved between various IOEventReactors
    - one handler per socket
    """
    def __init__(self, sock, log_channel=None):
        AbstractIOEventHandler.__init__(self, log_channel)
        self.socket = sock
        self.creation_timestamp = time_of_day()
        self._reactor = None
        self.connected = True
        self._outgoing_msg_queue = None
        self._output_buffer = None
        self._output_buffer_offset = None
        self._msg_reader = None

    cpdef _init_buffers(self):
        """Called on demand
        """
        self._outgoing_msg_queue = deque()
        self._output_buffer = None
        self._output_buffer_offset = None # bytes remaining

    cpdef fileno(self):
        return self.socket.fileno()

    def __str__(self):
        return ('<%s timestamp=%s connected=%s>')%(
            self.__class__.__name__,
            self.creation_timestamp, self.connected)

    cpdef register_with_reactor(self, writable=False, reactor=None):
        """Register this socket with the reactor event loop.
        """
        if reactor:
            # need to guard against unregistering without cleaning up
            # the poll list
            self._reactor = reactor
        self._register_fd_with_reactor(self.fileno(), self._reactor)

    cpdef _handle_socket_error_event(self, fd, flags):
        if self.connected:
            if self._log_channel:
                self._log_channel.error('socket exception: %s'%flags, sendEmailAlert=False)
            return self._close_descriptor(fd)
        else:
            return True

    cpdef _handle_exception(self, fd):
        if self._log_channel:
            self._log_channel.exception('unexpected error: %r'%self, sendEmailAlert=False)
        return self._close_descriptor(fd)

    cpdef _handle_write_event(self, fd):
        self._fill_output_buffer()
        try:
            while self._output_buffer_offset:
                bytes_sent = self.socket.send(
                    self._output_buffer[-self._output_buffer_offset:])
                if not bytes_sent:
                    # socket closed
                    # return self._handle_lost_connection(fd)
                    break # let

                else:
                    self._output_buffer_offset = self._output_buffer_offset - bytes_sent
                    if self._output_buffer_offset:
                        break # it blocked, can't send more now
                    else:
                        # there may be more messages ready to send
                        self._fill_output_buffer()
        except socket.error, se:
            if se[0] == errno.EINTR:
                return self._handle_write_event(fd)
            elif se[0] in (errno.EWOULDBLOCK, errno.ENOBUFS):
                pass
            else:
                return self._handle_lost_connection(fd)

        if not self._output_buffer_offset and not self._outgoing_msg_queue:
            self.register_with_reactor(writable=False)
        else:
            return False

    cpdef _fill_output_buffer(self):
        if not self._output_buffer_offset:
            self._mutex.acquire()
            try:
                msgs = []
                while self._outgoing_msg_queue:
                    msg = self._outgoing_msg_queue.popleft()
                    msgs.append(msg)
                if msgs:
                    self._output_buffer = ''.join(msgs)
                    self._output_buffer_offset = len(self._output_buffer)
                else:
                    self._output_buffer = self._output_buffer_offset = None
            finally:
                self._mutex.release()

    cpdef _handle_read_event(self, fd):
        if not self._msg_reader:
            firstByte = self.socket.recv(1)
            if not firstByte:
                # a closed connection is indicated by signaling
                # a read condition, and having recv() return 0.
                return self._handle_lost_connection(fd)
            self._msg_reader = self._get_msg_reader(firstByte)

        msg = self._msg_reader.next()
        if msg is AWAITING_MORE_BYTES:
            return False
        else:
            self._msg_reader = None
            return self._handle_message(msg)

    cpdef _handle_lost_connection(self, fd):
        return self._close_descriptor(fd)

    cpdef _get_msg_reader(self, firstByte):
        pass

    cpdef _handle_message(self, msg):
        pass

    ##
    cpdef write(self, _bytes, int flush=True):
        if not self.connected:
            raise Exception('socket is no longer connected')
        self._mutex.acquire()
        try:
            if self._outgoing_msg_queue is None:
                self._init_buffers()
            self._outgoing_msg_queue.append(_bytes)
            if flush:
                self.register_with_reactor(writable=True)
        finally:
            self._mutex.release()

    cpdef _close_descriptor(self, fd):
        if self.connected:
            self.last_event_time = time_of_day()
            self.connected = False
            try:
                self.socket.shutdown(1)
            except:
                pass
            self.socket.close()
            self._log_closure()
        return True

    cpdef _log_closure(self):
        if self._log_channel:
            self._log_channel.info('socket closed %r'%self)

# @@TR: Work In Progress:
#class Protocol(object):
#    ## implements twisted.internet.interfaces.IProtocol
#    transport = None
#    connected = 0
#
#    def makeConnection(self, transport):
#        self.connected = 1
#        self.transport = transport
#        self.connectionMade()
#
#    def connectionMade(self):
#        pass
#
#    def dataReceived(self, data):
#        pass
#
#    def connectionLost(self, reason):
#        pass
#
#
#class StreamSocketTransport(object):
#    ## implements twisted.internet.interfaces.ITransport
#    _sock =None
#
#    def __init__(self, sock, protocol, reactor=None):
#        self._sock = sock
#
#    def write(self, data):
#        pass
#
#    def writeSequence(data):
#        pass
#
#    def loseConnection(self):
#        pass
#
#    def getPeer(self):
#        pass
#
#    def getHost(self):
#        pass
