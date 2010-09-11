#from dss.dsl.default_visitors import basic_default_visitors_map

cdef class Serializer(Walker):
    def __init__(self, visitor_map=None, input_encoding='utf-8'):
        super(Serializer, self).__init__(
            visitor_map=(visitor_map if visitor_map is not None
                         else basic_default_visitors_map.copy()),
            input_encoding=input_encoding)
        self._safe_unicode_buffer = PyList_New(0)
        self._mixed_buffer = PyList_New(0)

    cpdef _init_buffers(self):
        self._has_unserializable_output = 0
        self._safe_unicode_buffer = PyList_New(0)
        self._mixed_buffer = PyList_New(0)

    cpdef serialize(self, obj):
        """Serialize an object, and its children, into sanitized
        (i.e. escaped if needed) unicode.
        """
        self._init_buffers()
        self.walk(obj)
        result = safe_unicode(PyUnicode_Join('', self._safe_unicode_buffer))
        if self._has_unserializable_output:
            if result:
                PyList_Append(self._mixed_buffer, result)
            return self._mixed_buffer
        else:
            return result

    cpdef object emit(self, output, int typecode=0):
        PyList_Append(self._safe_unicode_buffer, output)

    cpdef object emit_many(self, output_seq):
        self._safe_unicode_buffer.extend(output_seq)

    cpdef object emit_unserializeable_object(self, obj):
        self._has_unserializable_output = 1
        unicode_output = PyUnicode_Join('', self._safe_unicode_buffer)
        if unicode_output:
            PyList_Append(self._mixed_buffer, safe_unicode(unicode_output))
        self._safe_unicode_buffer = PyList_New(0)
        PyList_Append(self._mixed_buffer, obj)

################################################################################
# default serialization visitors:
import types
from decimal import Decimal
from collections import deque
import time
import datetime
from array import array

from dss.dsl.VisitorMap import DEFAULT
## cimports:
from cpython.unicode cimport PyUnicode_FromEncodedObject
from cpython.object cimport PyObject_Str, PyObject_Unicode

from dss.dsl.Walker cimport Walker
from dss.dsl.Visitor cimport Visitor
from dss.dsl.VisitorMap cimport VisitorMap

from dss.dsl.safe_strings import safe_bytes, safe_unicode

cdef class NoneVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        pass

cdef class BooleanVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.walk(PyObject_Str(obj))

cdef class ReprObjVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.walk(repr(obj))

cdef class StrVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.walk(PyUnicode_FromEncodedObject(obj, walker.input_encoding, "strict"))

cdef class UnicodeVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit(obj)

SafeUnicodeVisitor = UnicodeVisitor

cdef class SafeBytesVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit(PyUnicode_FromEncodedObject(obj, walker.input_encoding, "strict"))

cdef class NumberVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit(PyObject_Str(obj))

cdef class SequenceVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        for item in obj:
            walker.walk(item)

cdef class DictVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        for key, value in obj.iteritems():
            walker.walk(key)
            walker.emit(': ')
            walker.walk(value)
            walker.emit('\n')

cdef class PyFuncVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.walk(obj())

cdef class ConvertObjToUnicodeVisitor(Visitor):
    """Used for types that should just be converted to unicode and
    then sanitized if needed. E.g. unicode(datetime.datetime())
    """
    cpdef visit(self, obj, Walker walker):
        walker.walk(PyObject_Unicode(obj))

cdef class UnserializeableVisitor(Visitor):
    """Used with precompilers that defer serialization to unicode
    until a later pass of the serializer.
    """
    cpdef visit(self, obj, Walker walker):
        walker.emit_unserializeable_object(obj)

################################################################################
# these visitors aren't stateful so I can safely init them only once:
number_types = (int, long, Decimal, float, complex)
func_types = (types.FunctionType, types.BuiltinMethodType, types.MethodType)
sequence_types = (tuple, list, deque, set, frozenset, xrange, array, types.GeneratorType)

basic_default_visitors_map = VisitorMap({
    str: StrVisitor(),
    unicode: UnicodeVisitor(),
    safe_bytes: SafeBytesVisitor(),
    safe_unicode: SafeUnicodeVisitor(),

    types.NoneType: NoneVisitor(),
    bool: BooleanVisitor(),
    type: ConvertObjToUnicodeVisitor(),
    dict: DictVisitor(),
    datetime.datetime: ConvertObjToUnicodeVisitor(),
    datetime.date: ConvertObjToUnicodeVisitor(),
    DEFAULT: ReprObjVisitor()})

for typeset, visitor in ((number_types, NumberVisitor()),
                         (sequence_types, SequenceVisitor()),
                         (func_types, PyFuncVisitor())):
    for type_ in typeset:
        basic_default_visitors_map[type_] = visitor
