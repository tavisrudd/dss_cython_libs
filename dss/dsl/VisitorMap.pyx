import types

from dss.dsl._VisitorMapContextManager import _VisitorMapContextManager

cdef object _InstanceType = types.InstanceType # Avoid module dictionary lookup
cdef object Py_None = None       # Avoid module dictionary lookup

cdef class DEFAULT:
    pass

cdef class VisitorMap(dict):
    def __init__(self, map_or_seq=(), parent_map=None):
        super(VisitorMap, self).__init__(map_or_seq)
        self.parent_map = parent_map
        self._normalize_map()

    def as_context(self, walker, set_parent_map=True):
        return _VisitorMapContextManager(
            vmap=self, walker=walker, set_parent_map=set_parent_map)

    cpdef Visitor get_visitor(self, obj, int use_default=1):
        cdef PyTypeObject *ob_type =  (<PyObject *>obj).ob_type
        cdef PyObject* lookup_res = PyDict_GetItem(self, <object>ob_type)
        cdef Visitor result
        if lookup_res is not NULL:
            return <Visitor>lookup_res
        else:
            result = self._get_parent_type_visitor(obj, <object>ob_type)
            if result:
                return result
            elif self.parent_map is not Py_None:
                result = self.parent_map.get_visitor(obj, 0)
            if use_default and not result:
                result = self.get(DEFAULT)
                if not result and self.parent_map is not Py_None:
                    result = self.parent_map.get(DEFAULT)
            return result

    cpdef Visitor _get_parent_type_visitor(self, obj, obj_type):
        if obj_type is _InstanceType: # old style classes
            if obj.__class__ in self:
                return self[obj.__class__]
            else:
                m = [t for t in self if PyObject_IsInstance(obj, t)]
                for i, t in enumerate(m):
                    if not [t2 for t2 in m[i+i:] if t2
                            is not t and PyObject_IsSubclass(t2, t)]:
                        return self[t]
        else:
            for base in obj_type.__mro__:
                if base in self:
                    return self[base]

    cpdef Visitor _normalize_visitor(self, visitor):
        return (visitor if PyObject_IsInstance(visitor, Visitor)
                else CallbackVisitor(visitor))

    cpdef object _normalize_map(self):
        for k, v in self.iteritems():
            self[k] = self._normalize_visitor(v)

    def update(self, *args, **kws):
        super(VisitorMap, self).update(*args, **kws)
        self._normalize_map()

    def __setitem__(self, obj_type, visitor):
        super(VisitorMap, self).__setitem__(obj_type, self._normalize_visitor(visitor))

    def __delitem__(self, obj_type):
        del self[obj_type]

    def copy(self):
        # need to ensure that return type is an instance of VisitorMap
        # rather than dict.
        return self.__class__(super(VisitorMap, self).copy())
