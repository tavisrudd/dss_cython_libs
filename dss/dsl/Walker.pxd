cdef class Walker # forward declaration, must before cimport Visitor
from dss.dsl.Visitor cimport Visitor, CallbackVisitor
from dss.dsl.VisitorMap cimport VisitorMap

cdef class Walker:
    cdef public char* input_encoding
    cdef public VisitorMap visitor_map
    cpdef walk(self, obj)
    cpdef emit(self, output, int typecode=*)
