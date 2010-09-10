class _Unspecified:
    """A placeholder used as default argument to certain methods. It enables
    None to be used as a non-default value.  This is quite useful in methods
    that build searches/queries.
    """

    def __repr__(self):
        return 'Unspecified'

    def __str__(self):
        return 'Unspecified'

    def __nonzero__(self):
        return False
    
Unspecified = _Unspecified()
