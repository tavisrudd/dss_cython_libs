"""Provides the log level constants for the dss.pubsub packackage.
"""
EMERG = 80
ALERT = 70
CRITICAL = 60
ERROR = 50
WARNING = 40
NOTICE = 30
INFO = 20
DEBUG = 10
ALL = 0

_level_names = {
    EMERG    : 'EMERG',
    ALERT    : 'ALERT',
    CRITICAL : 'CRITICAL',
    ERROR    : 'ERROR',
    WARNING  : 'WARNING',
    NOTICE   : 'NOTICE',
    INFO     : 'INFO',
    DEBUG    : 'DEBUG',
    ALL      : 'ALL',
}

# return the string representation of a numeric log level
get_level_name = _level_names.get
