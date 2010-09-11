cdef extern from "Python.h":
    # for some reason cython's standard python_unicode.pxd skips these:
    object PyUnicode_Join(object separator, object seq)
    object PyUnicode_Replace(object u, object substr, object replstr,  Py_ssize_t maxcount)

from cpython.list cimport PyList_New, PyList_Append
from cpython.string cimport (PyString_Check, PyString_GET_SIZE, PyString_AS_STRING)
from cpython.unicode cimport PyUnicode_Check, PyUnicode_FromEncodedObject
from cpython.object cimport PyObject_Str, PyObject_Unicode

from dss.dsl.Walker cimport Walker
from dss.dsl.Visitor cimport Visitor
from dss.dsl.VisitorMap cimport VisitorMap
from dss.dsl.Serializer cimport Serializer
from dss.dsl.xml.xml_escape_unicode cimport xml_escape_unicode
from dss.dsl.xml.coretypes cimport (
    XmlDoc, XmlName, XmlElement, XmlElementProto, XmlAttribute,
    XmlEntityRef, XmlCData, Comment)

cdef class XmlSerializer(Serializer):
    pass

################################################################################
cdef extern from "Python.h":
    ctypedef struct PyTypeObject:
        void *tp_mro
    ctypedef struct PyObject:
        PyTypeObject *ob_type

cdef class _OptimizedXmlSerializer(Serializer):
    pass
    #cdef Visitor _element_visitor, _attribute_visitor, _str_visitor
