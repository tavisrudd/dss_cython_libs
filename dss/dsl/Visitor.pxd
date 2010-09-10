cdef class Visitor # forward declaration
cdef class CallbackVisitor(Visitor) # forward declaration

from dss.dsl.Walker cimport Walker

cdef class Visitor:
    cpdef visit(self, obj, Walker walker)

cdef class CallbackVisitor(Visitor):
    cdef public object callback
