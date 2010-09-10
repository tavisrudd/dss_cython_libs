"""Provides the Message class and subclasses for the dss.pubsub packackage.
"""

from time import time as current_time
from thread import get_ident as get_thread_ident

from dss.log.levels import INFO

class Message(dict):
    """Messages explicitly meant for system logging rather than event
    notifications, etc.

    In addition to standard message data from the Message baseclass LogMessages
    contain the following:

    %(level)i           Numeric logging level for the message (10=DEBUG, 20=INFO,
                        30=WARN, 40=ERROR, 50=CRITICAL).
    %(level_name)s       Text logging level for the message ("DEBUG", "INFO",
                        "WARN", "ERROR", "CRITICAL")
    %(message)s         The plain message string
    %(channel)s         The name of the channel that created the message

    %(time_created)f     Time when the Message was created (time.time())
    %(asctime)s         Textual representation of message creation time
    %(originating_thread)d Tread ID (if available)

    %(src_file)s         Full pathname of the source file where the logging
                        call was issued (if available)
    %(line_num)d         Source line number where the logging call was issued
                        (if available)
    %(caller)s          The name of the function or method that where the
                        logging call was issued
    %(caller_code)s      The contents of the line of code on which the logging
                        call was issued
    """

    def __init__(self, data=None):
        super(Message, self).__init__(self._get_message_data_template())
        if data:
            self.update(data)
        self._has_been_delivered_to = {}

    def _get_message_data_template(self):
        return {'timestamp':current_time(),
                'thread_id':get_thread_ident(),

                'line_num':'?',
                'src_file':'?',
                'caller':'?',
                'caller_code':'?',

                # this is always provided, but set it just to be safe
                'level':INFO,
                'level_name':'INFO',

                # @@TR: consider adding messageUID if a use is found
                }

    def record_delivery(self, subscriberUID):
        self._has_been_delivered_to[subscriberUID] = True

    def has_been_delivered_to(self, subscriberUID):
        return subscriberUID in self._has_been_delivered_to

    def __repr__(self):
        return ('<LogMessage: channel="%(channel)s", '
                'level=%(level)s, message="%(message)s">')%self
