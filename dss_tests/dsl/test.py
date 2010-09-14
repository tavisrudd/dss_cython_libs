# -*- coding: utf-8 -*-
# pylint: disable-msg=W0212,R0912,R0914

from decimal import Decimal

from dss.dsl.safe_strings import safe_unicode
from dss.dsl.Serializer import Serializer
from dss.dsl import html
from dss.dsl.xml.serializers import XmlSerializer
from dss.dsl.xml.serializers import (
    basic_default_visitors_map, xml_default_visitors_map)
from dss.dsl.xml import (
    XmlDoc,
    XmlCData,
    Comment,
    XmlName,
    XmlEntityRef,
    XmlAttribute,
    XmlAttributes,
    #XmlElement,
    #XmlElementProto,
    VisitorMap,
    )

################################################################################
## helper funcs
def _test_output(serializer, tree, expected_output):
    real_output = serializer.serialize(tree)
    if real_output != expected_output:
        raise AssertionError(
            '\n  when serializing %r with %r\n  want %r\n  got  %r'%(
                tree,
                serializer,
                expected_output,
                real_output))

def _test_output_set(serializers, data):
    if not isinstance(serializers, (list, tuple)):
        serializers = [serializers]
    for serializer in serializers:
        for tree, expected_output in data:
            _test_output(serializer, tree, expected_output)

def _make_wrapper_func(_in):
    def wrapper_func():
        return _in
    return wrapper_func

def _make_wrapper_method(_in):
    class Foo(object):
        def meth(self):
            return _in
    return Foo().meth

def _convert_test_set_to_func_calls(test_set):
    return tuple(
        [((lambda x: (lambda : x))(_in), out) # pylint: disable-msg=E0601
         for _in, out in test_set]
        +[(_make_wrapper_func(_in), out) for _in, out in test_set]
        +[(_make_wrapper_method(_in), out) for _in, out in test_set]
        )

################################################################################
## Test datasets

class _dummy_repr(object):
    def __repr__(self):
        return 'dummy_repr'

class _udummy_repr(object):
    def __repr__(self):
        return u'dummy_repr'

class _unsanitized_dummy_repr(object):
    def __repr__(self):
        return '&dummy_repr'

BASIC_TYPES_TEST_SET = (
    (True, u'True'),
    (False, u'False'),

    (1, u'1'),
    (1.0, u'1.0'),
    (Decimal('2.0'), u'2.0'),
    (complex(1,2), u'(1+2j)'),
    ((1,2,3), u'123'),
    ([1,2,3], u'123'),
    ([1,2,3,(4,5)], u'12345'),
    ([1,2,3,(4,5,(6.0))], u'123456.0'),
    (set([1]), u'1'),
    ('abc', u'abc'),
    (u'abc', u'abc'),

    (('a','b','c'), u'abc'),
    (_dummy_repr(), u'dummy_repr'),
    (_udummy_repr(), u'dummy_repr'),
    #(_unsanitized_dummy_repr(), u'&amp;dummy_repr'),

    )

escapings = {
    "&": u"&amp;",
    "<": u"&lt;",
    ">": u"&gt;",
    '"': u"&#34;",
    "'": u"&#39;"}

ESCAPING_TEST_SET = tuple(
    [(safe_unicode(k), k) for k in escapings]
    +[(k, v) for k, v in escapings.iteritems()]
    +[(k*200, v*200) for k, v in escapings.iteritems()]
    +[('--%s--'%k, '--%s--'%v) for k, v in escapings.iteritems()]
    +[('------%s'%k, '------%s'%v) for k, v in escapings.iteritems()]
    +[('--%s%s'%(k,k), '--%s%s'%(v,v)) for k, v in escapings.iteritems()]
    +[('&<>"\'&'*20, '&amp;&lt;&gt;&#34;&#39;&amp;'*20)]
    )

ENCODING_TEST_SET = tuple(
    [('金', unicode('金', 'utf-8'))]
    )

COMBINED_BASIC_TEST_SET = tuple(
    list(BASIC_TYPES_TEST_SET)
    +list(ESCAPING_TEST_SET)
    +list(ENCODING_TEST_SET)
    )

BASIC_FUNC_CALL_TEST_SET = _convert_test_set_to_func_calls(BASIC_TYPES_TEST_SET)
BASIC_FUNC_CALL_ESCAPED_TEST_SET = _convert_test_set_to_func_calls(ESCAPING_TEST_SET)

XML_NAMES_TEST_SET = (
    (XmlName('foo'), u'foo'),
    (XmlName('bar:foo'), u'bar:foo'),
    (XmlName(u'bar:foo'), u'bar:foo'),
    (XmlName(local='foo', prefix='bar'), u'bar:foo'),
    )

XML_COMMENTS_TEST_SET = (
    (Comment('foo bar'), u'<!--foo bar-->'),
    (Comment(['foo & bar', 1,2,3,(-1,-2)]), u'<!--foo & bar123-1-2-->'),
    (Comment('foo & bar'), u'<!--foo & bar-->'),
    (Comment('<!-- blah&blah<br /> -->'), # escape nested comments
     u'<!--<!-/- blah&blah<br /> -/->-->'),
    )

XML_CDATA_TEST_SET = (
    (XmlCData('foo bar'), u'<![CDATA[foo bar]]>'),
    (XmlCData(['a',1,'&']), u'<![CDATA[a1&]]>'),
    (XmlCData(['a',[1,2],'&']), u'<![CDATA[a12&]]>'),
    (XmlCData('foo & " bar'), u'<![CDATA[foo & " bar]]>'),
    (XmlCData('foo ]]> bar'), u'<![CDATA[foo ]-]-> bar]]>'),
    )

XML_ATTRIBUTES_TEST_SET = (
    [(XmlAttribute(name='foo', value='bar'), u' foo="bar"'),
     (XmlAttribute(name=XmlName('foo:bar'), value=1234),
      u' foo:bar="1234"'),
     (XmlAttributes([XmlAttribute(name='foo1', value='bar1'),
                  XmlAttribute(name='foo2', value='bar2')]),
      u' foo1="bar1" foo2="bar2"')]
    +[(XmlAttribute(name='foo', value=_in), u' foo="%s"'%out)
     for _in, out in COMBINED_BASIC_TEST_SET]
    )

BASIC_XMLDOC_TEST_SET = (
    (XmlDoc(version='1.0', encoding='UTF-8')[html.div],
     '<?xml version="1.0" encoding="UTF-8" ?><div></div>'),
    (XmlDoc(version='2.0', encoding='ISO-8859-1')[html.div],
     '<?xml version="2.0" encoding="ISO-8859-1" ?><div></div>'),
    )

HTML_EMPTY_TAGS_TEST_SET = tuple(
    [(getattr(html, tag), u'<%s></%s>'%(tag, tag))
     for tag in html._non_empty_html_tag_names]
    +[(getattr(html, tag), u'<%s />'%tag)
     for tag in html._empty_html_tag_names]
    )

HTML_ENTITIES_TEST_SET = tuple(
    (eref, u'&%s;'%eref.alpha)
    for name, eref in html.entities.iteritems())

TAG_ATTRIBUTES_TEST_SET = tuple(
    [(html.div(foo=_in), u'<div foo="%s"></div>'%out)
     for _in, out in COMBINED_BASIC_TEST_SET]
    )

TAG_CLASS_ATTRIBUTE_TEST_SET = tuple(
    [(html.div(_in), u'<div class="%s"></div>'%out)
     for _in, out in COMBINED_BASIC_TEST_SET]
    )

################################################################################
## test functions

def test_init_serializer():
    s1 = Serializer()
    assert s1.input_encoding == 'utf-8'
    assert s1.visitor_map is not basic_default_visitors_map
    assert s1.visitor_map == basic_default_visitors_map

    s2 = XmlSerializer()
    assert s2.input_encoding == 'utf-8'
    assert s2.visitor_map is not xml_default_visitors_map
    assert s2.visitor_map == xml_default_visitors_map


    vmap = VisitorMap()
    s3 = XmlSerializer(vmap)
    assert s3.input_encoding == 'utf-8'
    assert s3.visitor_map is vmap
    assert not s3.visitor_map.get_visitor(1)
    vmap.parent_map = basic_default_visitors_map
    assert (s3.visitor_map.get_visitor(1) ==
            basic_default_visitors_map[int])
    vmap[int] = basic_default_visitors_map[bool]
    assert (s3.visitor_map.get_visitor(1) ==
            basic_default_visitors_map[bool])
    assert s3.visitor_map == vmap

    for ser_class in (Serializer, XmlSerializer):
        assert (
            ser_class(vmap, 'latin-1').input_encoding
            == 'latin-1')
        assert (
            ser_class(vmap, input_encoding='latin-1').input_encoding
            == 'latin-1')

    Serializer(vmap)
    XmlSerializer(vmap)

def test_basic_types():
    _test_output_set((Serializer(), XmlSerializer()), BASIC_TYPES_TEST_SET)

def test_encoding():
    _test_output_set((Serializer(), XmlSerializer()), ENCODING_TEST_SET)

def test_escaping():
    _test_output_set(XmlSerializer(), ESCAPING_TEST_SET) # not Serializer

def test_basic_func_call():
    _test_output_set((Serializer(), XmlSerializer()), BASIC_FUNC_CALL_TEST_SET)

def test_basic_func_call_escaped():
    _test_output_set(XmlSerializer(), BASIC_FUNC_CALL_ESCAPED_TEST_SET)

def test_name_objects():
    _test_output_set(XmlSerializer(), XML_NAMES_TEST_SET)

def test_xml_comment():
    _test_output_set(XmlSerializer(), XML_COMMENTS_TEST_SET)

def test_xml_cdata():
    _test_output_set(XmlSerializer(), XML_CDATA_TEST_SET)

def test_xml_attributes():
    _test_output_set(XmlSerializer(), XML_ATTRIBUTES_TEST_SET)

def test_xmldoc():
    _test_output_set(XmlSerializer(), BASIC_XMLDOC_TEST_SET)

def test_xhtml_dtd():
    _test_output(XmlSerializer(), html.XHTML_DTD, html.XHTML_DTD)

def test_xhtml_entities():
    e1 = XmlEntityRef(alpha='abc', num=123, description='boo')
    e2 = XmlEntityRef('abc', 123, 'boo')
    assert e1.num == e2.num == 123
    assert e1.alpha == e2.alpha == 'abc'
    assert e1.description == e2.description == 'boo'
    assert str(e1)==str(e2)=='&abc;'
    _test_output_set(XmlSerializer(), HTML_ENTITIES_TEST_SET)

def test_basic_xhtml_tags():
    _test_output_set(XmlSerializer(), HTML_EMPTY_TAGS_TEST_SET)

def test_tag_attributes():
    _test_output_set(XmlSerializer(), TAG_ATTRIBUTES_TEST_SET)

def test_tag_class_attribute():
    _test_output_set(XmlSerializer(), TAG_CLASS_ATTRIBUTE_TEST_SET)

def test_xhtml_simpletable():
    _test_output(
        XmlSerializer(),
        html.table(cellpadding=1)[html.tr[html.td[1], html.td[2]],
                   html.tr[html.td[1], html.td[2]],
                   ],
        unicode('<table cellpadding="1"><tr><td>1</td><td>2</td></tr>'
                '<tr><td>1</td><td>2</td></tr></table>'))

def test_xhtml_script_tag():
    _test_output(
        XmlSerializer(),
        html.script['function() { return "&"; }'],
u'''<script>
//<![CDATA[
function() { return "&"; }
//]]>
</script>''')
