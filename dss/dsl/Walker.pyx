class NoVisitorFound(TypeError):
    pass

cdef class Walker:
    def __init__(self, visitor_map=None, input_encoding='utf-8'):
        if visitor_map is None:
            visitor_map = VisitorMap()
        self.visitor_map = visitor_map
        self.input_encoding = input_encoding

    cpdef walk(self, obj):
        cdef Visitor visitor = self.visitor_map.get_visitor(obj)
        if visitor:
            visitor.visit(obj, self)
        else:
            # call repr first here instead of using '%r' in case obj is a
            # sequence or dict, etc.
            raise NoVisitorFound('No visitor found for %s'%repr(obj))

    cpdef emit(self, output, int typecode=0):
        raise NotImplementedError
