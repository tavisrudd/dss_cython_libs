try:
    from markupsafe._speedups import escape
except ImportError:
    from markupsafe._native import escape

def make_wrapper(name):
    orig = getattr(unicode, name)
    def func(self, *args, **kwargs):
        args = _escape_argspec(list(args), enumerate(args))
        _escape_argspec(kwargs, kwargs.iteritems())
        return self.__class__(orig(self, *args, **kwargs))
    func.__name__ = orig.__name__
    func.__doc__ = orig.__doc__
    return func

def _escape_argspec(obj, iterable):
    """Helper for various string-wrapped functions."""
    for key, value in iterable:
        if hasattr(value, '__html__') or isinstance(value, basestring):
            obj[key] = escape(value)
    return obj
