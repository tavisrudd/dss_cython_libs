cdef class Visitor:
    cpdef visit(self, obj, Walker walker):
        raise NotImplementedError


cdef class CallbackVisitor(Visitor):
    def __init__(self, callback):
        Visitor.__init__(self)
        self.callback = callback

    cpdef visit(self, obj, Walker walker):
        self.callback(obj, walker)
