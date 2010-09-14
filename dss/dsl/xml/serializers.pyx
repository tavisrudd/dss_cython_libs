from dss.dsl.Serializer import (basic_default_visitors_map, StrVisitor)
from dss.dsl.safe_strings import safe_unicode

cdef class XmlEscapingStrVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit(
            xml_escape_unicode(
                PyUnicode_FromEncodedObject(obj, walker.input_encoding, "strict")))

cdef class XmlEscapingUnicodeVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit(xml_escape_unicode(obj))

cdef class XmlNameVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit(PyObject_Unicode(obj))

cdef class XmlElementVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        cdef XmlElement elem = obj
        if elem._has_attrs:
            walker.emit('<')
            walker.emit(elem._name._str)
            for attr in elem.attrs:
                walker.walk(attr)
            walker.emit('>')
        else:
            walker.emit(elem._name._starttag)
        if elem._has_children:
            walker.walk(elem.children)
        walker.emit(elem._name._endtag)

cdef class XmlAttributeVisitor(Visitor):
    cpdef visit(self, attr, Walker walker):
        walker.emit(' ')
        walker.emit(PyObject_Unicode(attr.name))
        walker.emit('="')
        walker.walk(attr.value)
        walker.emit('"')

cdef class XmlElementProtoVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit(obj._tag)

cdef class XmlEntityRefVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit(obj._str)

class UnicodeSubStrReplaceVisitor(Visitor):
    def __init__(self, s, r):
        self.s = s
        self.r = r

    def visit(self, obj, walker):
        walker.emit(PyUnicode_Replace(obj, self.s, self.r, -1))

cdef class XmlCommentVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit('<!--')
        with VisitorMap({str: StrVisitor(),
                         unicode: UnicodeSubStrReplaceVisitor('--','-/-')}
                        ).as_context(walker):
            walker.walk(obj.content)
        walker.emit('-->')

cdef class XmlCDataVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        # @@TR: I also want to provide a visitor for the Script tag
        # that autowraps the contents in a cdata block
        walker.emit('<![CDATA[')
        # @@TR: need to find a better way to handle escaping, see
        # http://stackoverflow.com/questions/223652/is-there-a-way-to-escape-a-cdata-end-token-in-xml
        with VisitorMap({str: StrVisitor(),
                         unicode: UnicodeSubStrReplaceVisitor(']]>',']-]->')}
                        ).as_context(walker):
            walker.walk(obj.content)
        walker.emit(']]>')

cdef class XmlDocVisitor(Visitor):
    cpdef visit(self, obj, Walker walker):
        walker.emit('<?xml version="%s" encoding="%s" ?>'%(obj.version, obj.encoding))
        walker.walk(obj.children)

cdef class DictVisitor_ToHtml(Visitor):
    cpdef visit(self, obj, Walker walker):
        from dss.dsl.html import dl, dt, dd
        walker.walk(dl[[(dt[k], dd[v]) for k, v in obj.iteritems()]])

################################################################################
# these visitors aren't stateful so I can safely init them only once:

xml_default_visitors_map = basic_default_visitors_map.copy()
xml_default_visitors_map.update({
    str: XmlEscapingStrVisitor(),
    unicode: XmlEscapingUnicodeVisitor(),
    dict: DictVisitor_ToHtml(),
    XmlName: XmlNameVisitor(),
    XmlAttribute: XmlAttributeVisitor(),
    XmlElement: XmlElementVisitor(),
    XmlElementProto: XmlElementProtoVisitor(),
    XmlEntityRef: XmlEntityRefVisitor(),
    Comment: XmlCommentVisitor(),
    XmlDoc: XmlDocVisitor(),
    XmlCData: XmlCDataVisitor(),
    })

# @@TR: ideas for other visitors: cheetah templates, mx.DateTimes,
# RelativeDateTimes (relative to now()),  code-blocks to syntax highlight
################################################################################
cdef class XmlSerializer(Serializer):
    def __init__(self, visitor_map=None, input_encoding='utf-8'):
        super(XmlSerializer, self).__init__(
            visitor_map=(
                visitor_map if visitor_map is not None
                else xml_default_visitors_map.copy()),
            input_encoding=input_encoding)

################################################################################
cdef PyTypeObject *SANITIZED_UNICODE_TYPE = (<PyTypeObject *>safe_unicode)
cdef PyTypeObject *STR_TYPE = (<PyTypeObject *>str)
cdef PyTypeObject *INT_TYPE = (<PyTypeObject *>int)
cdef PyTypeObject *ELEMENT_TYPE = (<PyTypeObject *>XmlElement)
cdef PyTypeObject *ATTRIBUTE_TYPE = (<PyTypeObject *>XmlAttribute)

cdef class _OptimizedXmlSerializer(Serializer):
    """At the moment, this is just an experiment used for performance
    benchmarking and regression testing.  Don't use it unless you know
    what you're doing.  It is only 10% to 25% faster than the normal
    code, which shows that normal implementation is just
    fine. Pre-compiling snippets yields much bigger gains than hacks
    like this.
    """
    def __init__(self, visitor_map=None, input_encoding='utf-8'):
        super(_OptimizedXmlSerializer, self).__init__(
            visitor_map=(
                visitor_map if visitor_map is not None
                else xml_default_visitors_map.copy()),
            input_encoding=input_encoding)

    cpdef walk(self, obj):
        cdef PyTypeObject *ob_type =  (<PyObject *>obj).ob_type
        cdef XmlElement elem
        if ob_type == SANITIZED_UNICODE_TYPE:
            PyList_Append(self._safe_unicode_buffer, obj)
        elif ob_type == STR_TYPE:
            PyList_Append(self._safe_unicode_buffer,
                          xml_escape_unicode(PyUnicode_FromEncodedObject(
                              obj, self.input_encoding, "strict")))
        elif ob_type == INT_TYPE:
            PyList_Append(self._safe_unicode_buffer, PyObject_Str(obj))
        elif ob_type == ELEMENT_TYPE:
            elem = obj
            if elem._has_attrs:
                PyList_Append(self._safe_unicode_buffer, '<')
                PyList_Append(self._safe_unicode_buffer, elem._name._str)
                if elem._has_attrs:
                    for attr in elem.attrs:
                        self.walk(attr)
                PyList_Append(self._safe_unicode_buffer, '>')
            else:
                PyList_Append(self._safe_unicode_buffer, elem._name._starttag)
            if elem._has_children:
                self.walk(elem.children)
            PyList_Append(self._safe_unicode_buffer, elem._name._endtag)
        elif ob_type == ATTRIBUTE_TYPE:
            self._attribute_visitor.visit(obj, self)
        else:
            Serializer.walk(self, obj)
