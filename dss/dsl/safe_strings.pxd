cdef extern from "Python.h":
    ctypedef class __builtin__.unicode [object PyUnicodeObject]:
        pass

    ctypedef class __builtin__.str [object PyStringObject]:
        pass

cdef class safe_bytes(str): pass
cdef class safe_unicode(unicode): pass
