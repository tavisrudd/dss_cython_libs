cdef class safe_bytes(str):
    """Subclass of str that has been sanitized (xml escaped, etc.)
    and should not be sanitized further.
    """
    def decode(self, *args, **kws):
        return safe_unicode(super(safe_bytes, self).encode(*args, **kws))

    def __add__(x, y):
        if isinstance(x, safe_bytes):
            res = super(safe_bytes, x).__add__(y)
            if isinstance(y, safe_unicode):
                return safe_unicode(res)
            elif isinstance(y, safe_bytes):
                return safe_bytes(res)
            else:
                return res
        else:
            # x isn't sanitized, but y is:
            return x.__add__(str(y))

cdef class safe_unicode(unicode):
    """Subclass of unicode that has been sanitized (xml escaped, etc.)
    and should not be sanitized further.
    """
    def encode(self, *args, **kws):
        return safe_bytes(super(safe_unicode, self).encode(*args, **kws))

    def __add__(x, y):
        if isinstance(x, safe_unicode):
            res = super(safe_unicode, x).__add__(y)
            if isinstance(y, safe_unicode):
                return safe_unicode(res)
            else:
                return res
        else:
            # x isn't sanitized, but y is:
            return x.__add__(unicode(y))
