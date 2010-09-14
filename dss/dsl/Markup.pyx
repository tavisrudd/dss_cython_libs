# -*- coding: utf-8 -*-
"""
This is a work-in-progress port of Armin's Markupsafe to Cython.  I'll
be pushing it upstream after adding tests, docs, and some tweaks to
its `setup.py` for graceful fallback to pure Python.

----------------------
    markupsafe
    ~~~~~~~~~~

    Implements a Markup string.

    :copyright: (c) 2010 by Armin Ronacher, Tavis Rudd
    :license: BSD, see LICENSE for more details.
"""

cdef extern from "Python.h":
    ctypedef class __builtin__.unicode [object PyUnicodeObject]:
        pass

import sys
import re
from itertools import imap

from markupsafe._constants import HTML_ENTITIES
from _make_unicode_meth_wrapper import make_wrapper as _make_wrapper

__all__ = ['Markup', 'EncodedMarkup', 'soft_unicode', 'escape', 'escape_silent']
_striptags_re = re.compile(r'(<!--.*?-->|<[^>]*>)')
_entity_re = re.compile(r'&([^;]+);')

cdef class MarkupBase(unicode):

    def __add__(self, other):
        if hasattr(other, '__html__') or isinstance(other, basestring):
            return self.__class__(unicode(self) + unicode(escape(other)))
        return NotImplemented

    def __radd__(self, other):
        if hasattr(other, '__html__') or isinstance(other, basestring):
            return self.__class__(unicode(escape(other)) + unicode(self))
        return NotImplemented

    def __mul__(self, num):
        if isinstance(num, (int, long)):
            return self.__class__(unicode.__mul__(self, num))
        return NotImplemented
    __rmul__ = __mul__

    def __mod__(self, arg):
        if isinstance(arg, tuple):
            arg = tuple(imap(_MarkupEscapeHelper, arg))
        else:
            arg = _MarkupEscapeHelper(arg)
        return self.__class__(unicode.__mod__(self, arg))

    def __repr__(self):
        return '%s(%s)' % (
            self.__class__.__name__,
            unicode.__repr__(self))

    def join(self, seq):
        return self.__class__(unicode.join(self, imap(escape, seq)))
    #join.__doc__ = unicode.join.__doc__

    def split(self, *args, **kwargs):
        return map(self.__class__, unicode.split(self, *args, **kwargs))
    #split.__doc__ = unicode.split.__doc__

    def rsplit(self, *args, **kwargs):
        return map(self.__class__, unicode.rsplit(self, *args, **kwargs))
    #rsplit.__doc__ = unicode.rsplit.__doc__

    def splitlines(self, *args, **kwargs):
        return map(self.__class__, unicode.splitlines(self, *args, **kwargs))
    #splitlines.__doc__ = unicode.splitlines.__doc__

    __getitem__ = _make_wrapper('__getitem__')
    capitalize = _make_wrapper('capitalize')
    zfill = _make_wrapper('zfill')
    swapcase = _make_wrapper('swapcase')
    expandtabs = _make_wrapper('expandtabs')
    translate = _make_wrapper('translate')
    strip = _make_wrapper('strip')
    center = _make_wrapper('center')
    rstrip = _make_wrapper('rstrip')
    lstrip = _make_wrapper('lstrip')
    rjust = _make_wrapper('rjust')
    ljust = _make_wrapper('ljust')
    replace = _make_wrapper('replace')
    upper = _make_wrapper('upper')
    lower = _make_wrapper('lower')
    title = _make_wrapper('title')

    # new in python 2.5
    if hasattr(unicode, 'partition'):
        def partition(self, sep):
            return tuple(map(self.__class__,
                             unicode.partition(self, escape(sep))))
        def rpartition(self, sep):
            return tuple(map(self.__class__,
                             unicode.rpartition(self, escape(sep))))

    # new in python 2.6
    if hasattr(unicode, 'format'):
        format = _make_wrapper('format')

    # not in python 3
    if hasattr(unicode, '__getslice__'):
        __getslice__ = _make_wrapper('__getslice__')

    ##################################################
    ## extensions to the `unicode` class api

    def __html__(self):
        return self

    @classmethod
    def escape(cls, s):
        rv = escape(s)
        if rv.__class__ is not cls:
            return cls(rv)
        return rv

    def unescape(self):
        def handle_match(m):
            name = m.group(1)
            if name in HTML_ENTITIES:
                return unichr(HTML_ENTITIES[name])
            try:
                if name[:2] in ('#x', '#X'):
                    return unichr(int(name[2:], 16))
                elif name.startswith('#'):
                    return unichr(int(name[1:]))
            except ValueError:
                pass
            return u''
        return _entity_re.sub(handle_match, unicode(self))

    def striptags(self):
        stripped = u' '.join(_striptags_re.sub('', self).split())
        return Markup(stripped).unescape()

    def encode(self, encoding=None, errors='strict'):
        em = EncodedMarkup(unicode.encode(self, encoding, errors))
        em.__markup_encoding__ = encoding or sys.getdefaultencoding()
        return em

class Markup(MarkupBase):
    def __cinit__(cls, base=u'', encoding=None, errors='strict'):
        if hasattr(base, '__html__'):
            base = base.__html__()
        if encoding is None:
            return unicode.__new__(cls, base)
        return unicode.__new__(cls, base, encoding, errors)

class EncodedMarkup(str):
    __markup_encoding__ = None

class _MarkupEscapeHelper(object):
    """Helper for Markup.__mod__"""

    def __init__(self, obj):
        self.obj = obj
    def __getitem__(s, x):
        return _MarkupEscapeHelper(s.obj[x])
    def __str__(s):
        return str(escape(s.obj))
    def __unicode__(s):
        return unicode(escape(s.obj))
    def __repr__(s):
        return str(escape(repr(s.obj)))
    def __int__(s):
        return int(s.obj)
    def __float__(s):
        return float(s.obj)

# we have to import it down here as the speedups and native
# modules imports the markup type which is define above.

try:
    from markupsafe._speedups import escape, escape_silent, soft_unicode
except ImportError:
    from markupsafe._native import escape, escape_silent, soft_unicode
