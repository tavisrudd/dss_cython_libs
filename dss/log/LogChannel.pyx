import traceback
import sys
from dss.pubsub._Channel cimport _Channel

from dss.log.Message import Message
from dss.log.levels import (
    EMERG, ALERT, CRITICAL, ERROR,
    WARNING, NOTICE, INFO, DEBUG)

cdef class LogChannel(_Channel):
    cdef public object _default_encoding
    cdef public int trace_caller

    def __init__(self, message_bus, channel_name):
        super(LogChannel, self).__init__(message_bus, channel_name)
        self._default_encoding = 'UTF-8'
        self.trace_caller = False

    ##################################################
    ## variants of send() for quick logging, syslog style
    # @@TR: I plan on moving these to a logging specific subclass and
    ## keeping the core interface as simple as possible.
    def debug(self, msg_text, *args, **kws):
        self._log(DEBUG, msg_text, args, kws)

    def info(self, msg_text, *args, **kws):
        self._log(INFO, msg_text, args, kws)

    def notice(self, msg_text, *args, **kws):
        self._log(NOTICE, msg_text, args, kws)

    def warn(self, msg_text, *args, **kws):
        self._log(WARNING, msg_text, args, kws)

    def warning(self, msg_text, *args, **kws):
        self._log(WARNING, msg_text, args, kws)

    def error(self, msg_text, *args, **kws):
        self._log(ERROR, msg_text, args, kws)

    def exception(self, msg_text=None, *args, **kws):
        if 'exc_txt' not in kws:
            exctype, value = sys.exc_info()[:2]
            try:
                excdesc = '%s: %s'%(getattr(exctype, '__name__', str(exctype)), value)
            except:
                excdesc = '%s: %r'%(getattr(exctype, '__name__', str(exctype)), value)

            if not msg_text:
                msg_text = excdesc

            kws['exc_txt'] = '%s\n%s'%(excdesc, traceback.format_exc())

        if not msg_text:
            msg_text = 'exception caught'
        self._log(ERROR, msg_text, args, kws)

    def critical(self, msg_text, *args, **kws):
        self._log(CRITICAL, msg_text, args, kws)

    def alert(self, msg_text, *args, **kws):
        self._log(ALERT, msg_text, args, kws)

    def emerg(self, msg_text, *args, **kws):
        self._log(EMERG, msg_text, args, kws)

    ## private methods
    cpdef _log(self, level, msg_text, args=None, kws=None, MessageClass=Message):
        if self._has_async_subscriptions or self._has_synchronous_subscriptions:
            if not isinstance(msg_text, unicode):
                try:
                    msg_text = unicode(msg_text, kws.get('encoding', self._default_encoding))
                except UnicodeDecodeError:
                    # @@TR: should log something internally here
                    msg_text = unicode(msg_text,'raw-unicode-escape')

            message = MessageClass(kws or {})
            message.update({'message':msg_text,
                            'channel':self.name,
                            'level':level,
                            'args':args})
            if self.trace_caller:
                self._add_caller_trace(message, stack_depth=4)
            self.send(message)

    cpdef _add_caller_trace(self, message,
                          stack_depth=4,
                          _extract_stack=traceback.extract_stack):
        try:
            f = _extract_stack(limit=stack_depth)[0]
            message.update(
                {'line_num':f[1],
                 'src_file':f[0],
                 'caller':f[2],
                 'caller_code':f[3]})
        except:
            self._message_bus._log_internal_exception('error adding caller trace')
