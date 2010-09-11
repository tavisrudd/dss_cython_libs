cdef class XmlDoc:
    cdef public object children, version, encoding

cdef class XmlName:
    cdef public object local, prefix
    cdef object _str
    cdef object _starttag
    cdef object _endtag

cdef class XmlEntityRef:
    cdef public object alpha, num, description
    cdef public object _str

cdef class XmlAttribute:
    cdef public object value, name

cdef class XmlElement:
    cdef public object attrs, children
    cdef public int _has_children, _has_attrs
    cdef XmlName _name

    cpdef object _normalize_attrs(self, attrs)
    cpdef object _add_children(self, children)

cdef class XmlElementProto:
    cdef public object name, element_class
    cdef public int can_be_empty
    cdef public object _tag

cdef class XmlCData:
    cdef public object content

cdef class Comment:
    cdef public object content
