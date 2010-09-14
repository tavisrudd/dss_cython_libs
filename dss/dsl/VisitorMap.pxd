cdef extern from "Python.h":
    ctypedef struct PyTypeObject:
        void *tp_mro
    ctypedef struct PyObject:
        PyTypeObject *ob_type

    # cython's compiler complains about this already being a cython
    # builtin type, but it appears to be valid and is the only way I
    # can find to subclass a builtin.  Note, this approach is *invalid*
    # for `tuples` and `str`:
    # http://www.mail-archive.com/cython-dev@codespeak.net/msg04858.html
    ctypedef class __builtin__.dict [object PyDictObject]:
        pass

    # use this rather than python_dict.pxd's copy because of our use
    # of PyObject.ob_type:
    PyObject* PyDict_GetItem(object d, object key)

from cpython.type cimport PyType_Check
from cpython.object cimport PyObject_IsSubclass, PyObject_IsInstance

cdef class DEFAULT:
    pass

cdef class VisitorMap(dict)
# forward declarations, must before cimport Visitor
from dss.dsl.Visitor cimport Visitor, CallbackVisitor

cdef class VisitorMap(dict):
    cdef public VisitorMap parent_map

    cpdef object _normalize_map(self)
    cpdef Visitor _normalize_visitor(self, visitor)
    cpdef Visitor _get_parent_type_visitor(self, obj, obj_type)
    # public methods
    cpdef Visitor get_visitor(self, obj, int use_default=*)
