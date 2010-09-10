cdef extern from "Python.h":
    # for some reason cython's standard python_unicode.pxd skips this:
    object PyUnicode_Join(object separator, object seq)

from cpython.list cimport PyList_New, PyList_Append

from dss.dsl.Walker cimport Walker
from dss.dsl.safe_strings cimport safe_unicode

cdef class Serializer(Walker):
    cdef object _safe_unicode_buffer
    cdef object _mixed_buffer
    cdef int _has_unserializable_output
    cpdef object _init_buffers(self)

    cpdef object emit_many(self, output_seq)
    cpdef object emit_unserializeable_object(self, obj)
    cpdef object serialize(self, obj)
