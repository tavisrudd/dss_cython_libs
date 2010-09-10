# Py_UNICODE is implicit in recent cython versions
from cpython.unicode cimport PyUnicode_AsUnicode, PyUnicode_GetSize
cdef extern from "Python.h":
    # for some reason cython's standard python_unicode.pxd skips:
    object PyUnicode_Replace(object u, object substr, object replstr,  Py_ssize_t maxcount)

cpdef object xml_escape_unicode(s)
