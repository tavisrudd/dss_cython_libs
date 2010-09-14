from dss.dsl.safe_strings import safe_unicode

cdef object Py_None = None     # Avoid dictionary lookups for 'None'

def _get_default_encoding():
    return 'utf-8'

cdef class XmlDoc:
    def __init__(self, version='1.0', encoding=None):
        self.children = []
        self.version = version
        self.encoding = encoding if encoding else _get_default_encoding()

    def _add_children(self, children):
        if isinstance(children, (tuple, list)):
            self.children.extend(children)
        else:
            self.children.append(children)

    def __getitem__(self, children):
        self._add_children(children)
        return self

cdef class XmlName:
    """An XML element or attribute name
    """
    def __init__(self, local, prefix=None):
        if ':' in local:
            prefix, local = local.split(':')
        self.local = local
        self.prefix = prefix

        ## an optimization for serializers/visitors:
        if prefix:
            # @@TR: might want to encode these properly:
            self._str = safe_unicode('%s:%s'%(prefix, local))
        else:
            self._str = safe_unicode(local)
        # internal cache to save time when serializing.  Obviously doesn't apply
        # to attrs:
        self._starttag = safe_unicode('<%s>'%self._str)
        self._endtag = safe_unicode('</%s>'%self._str)

    def __repr__(self):
        return '<xml name %s>'%self

    def __unicode__(self):
        return self._str

    def __str__(self):
        return self.__unicode__().encode(_get_default_encoding())

cdef class XmlEntityRef:
    def __init__(self, alpha, num, description):
        self.alpha, self.num, self.description = (alpha, num, description)
        ## an optimization for serializers/visitors:
        self._str = safe_unicode('&%s;'%self.alpha)

    def __repr__ (self):
        return '<xml entity ref %s>'%self

    def __unicode__(self):
        return self._str

    def __str__(self):
        return self._str

class XmlAttributes(list):
    __slots__ = []

cdef class XmlAttribute:
    def __init__(self, value, name=None):
        self.value = value
        self.name = name

cdef class XmlElement:
    def __init__(self, name):
        self._name = name
        self._has_attrs = 0
        self._has_children = 0

    property name:
        def __get__(self):
            return self._name

    ## DEPRECATED:
    def __str__(self):
        return self.__unicode__().encode(_get_default_encoding())

    def __unicode__(self):
        from dss.dsl.xml.serializers import XmlSerializer
        return XmlSerializer().serialize(self)

    def render(self, trans):
        """This is provide only for backwards compat with some of old Webware code.
        DO NOT USE IT!  IT WILL BE REMOVED.
        """
        trans.response.write(str(self))
    ##

    def __repr__(self):
        return '<%s object name=%s>'%(repr(self.__class__)[1:-1], self.name)

    def __call__(self, class_=None, **attrs):
        assert not self._has_attrs
        if class_ is not Py_None:
            attrs['class'] = class_
        self.attrs = self._normalize_attrs(attrs)
        if self.attrs:
            self._has_attrs = 1
        return self

    cpdef object _normalize_attrs(self, attrs):
        # @@TR: consider preserving ordering
        out = XmlAttributes()
        for n, v in attrs.items():
            if n.endswith('_'):
                n = n[:-1]
            if '_' in n:
                if '__' in n:
                    n = XmlName(n.replace('__',':'))
                elif 'http_' in n:
                    n = XmlName(n.replace('http_', 'http-'))
                else:
                    pass
            out.append(XmlAttribute(value=v, name=n))
        return out

    cpdef object _add_children(self, children):
        assert not self._has_children
        self.children = []
        if isinstance(children, (tuple, list)):
            self.children.extend(children)
        else:
            self.children.append(children)
        if self.children:
            self._has_children = 1

    def __getitem__(self, children):
        self._add_children(children)
        return self

cdef class XmlElementProto:
    def __init__(self, name, can_be_empty=True, element_class=XmlElement):
        self.name = name
        self.can_be_empty = can_be_empty
        self.element_class = element_class
        ## an optimization for serializers/visitors:
        if can_be_empty:
            self._tag = safe_unicode('<%s />'%self.name)
        else:
            self._tag = safe_unicode('<%s></%s>'%(self.name, self.name))

    def __call__(self, class_=None, **attrs):
        if class_ is not Py_None:
            attrs['class'] = class_
        return self.element_class(self.name)(**attrs)

    def __getitem__(self, children):
        return self.element_class(self.name)[children]

cdef class XmlCData:
    def __init__(self, content):
        self.content = content

cdef class Comment:
    def __init__(self, content):
        self.content = content
