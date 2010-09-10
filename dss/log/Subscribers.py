"""Provides the basic Subscriber classes for the dss.pubsub packackage.
"""
import sys
from uuid import uuid4
from time import strftime, localtime
from traceback import format_exception

from dss.log.levels import get_level_name

class Subscriber:
    """
    An optional abstract baseclass for Subscribers on `Channels` that
    """

    _uid = None
    _name = None

    def __init__(self, name=None, **settings):
        self._name = name or self.__class__.__name__
        self._uid = uuid4().get_hex()

    def __hash__(self):
        return hash(self._uid)

    def __call__(self, message):
        if not message.has_been_delivered_to(self._uid):
            if self._should_handle_message(message):
                self._handle_message(message)
            # @@TR: might want to add some concurrency locking here
            # though it's safe for now as only one thread is used for
            # broadcast.
            message.record_delivery(self._uid)

    def _should_handle_message(self, message): # pylint: disable-msg=W0613
        """This is called by __call__() to see if we actually want to
        _handle_message().  If it returns False the message is not delivered to
        _handle_message().
        """
        return True

    def _handle_message(self, message):
        raise NotImplementedError

    def __repr__(self):
        return '<subscriber name="%s" UID=%s>'%(self._name, self._uid)

class Formatter(object):
    """Formats a log message.  Owned and called by a Subscriber/Listener instance.
    """

    _format_str = "%(formatted_time)s %(channel)-19s  %(level_name)-5s - %(message)s"
    _time_format = "%Y-%m-%d %H:%M:%S"
    _sub_second_precision = 3

    def __init__(self, **kws):
        for k, v in kws.items():
            setattr(self, k, v)

    def format(self, message):
        if self._format_str.find('%(formatted_time)s') != -1:
            self._add_formatted_time(message)
        message['level_name'] = get_level_name(message['level'])
        output = self._format_str % message

        if 'exc_info' in message and 'exc_txt' not in message:
            # Cache the traceback text to avoid converting it multiple times
            # (it's constant anyway)
            message['exc_txt'] = self._format_exception(message['exc_info'])
        if 'exc_txt' in message:
            if output[-1] != "\n":
                output += "\n"
            output += self._format_traceback_str(message['exc_txt'])
        return output

    def _format_exception(self, ei):
        """
        Format and return the specified exception information as a string.

        This default implementation just uses
        traceback.print_exception()
        """
        out = format_exception(ei[0], ei[1], ei[2], None)
        if out[-1] == "\n":
            out = out[:-1]
        return self._format_traceback_str(out)

    def _format_traceback_str(self, traceback_str):
        return '\n:: '.join(traceback_str.splitlines())

    def _add_formatted_time(self, message):
        message_time = message['timestamp']
        message['formatted_time'] = (
            strftime(self._time_format,
                     localtime(message_time)) +
            ",%s" % self._format_subseconds(message_time))
    def _format_subseconds(self, message_time):
        return str(message_time%1)[2:self._sub_second_precision+2]

class LogListener(Subscriber):
    """
    Abstract baseclass for all types of Listeners
    """
    _formatter = None
    def __init__(self, name=None, **settings):
        Subscriber.__init__(self, name, **settings)

        self._name = name or self.__class__.__name__
        if settings.has_key('formatter'):
            self._formatter = settings['formatter']
        else:
            self._formatter = Formatter()

    def _should_handle_message(self, message):
        return True

class StdOutListener(LogListener):
    """
    Simple console loglistener. Prints every received
    message to STDOUT.

    Settings:

    - formatter
    """

    def __init__(self, name=None, **settings):
        LogListener.__init__(self, name, **settings)

    def _handle_message(self, message):
        print self._formatter.format(message)
        sys.stdout.flush()
