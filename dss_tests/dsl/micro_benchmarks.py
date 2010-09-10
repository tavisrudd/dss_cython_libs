# -*- coding: utf-8 -*-
from time import time
from dss.dsl.safe_strings import safe_unicode
from dss.dsl.Serializer import Serializer
from dss.dsl.Serializer import (
    #basic_default_visitors_map,
    func_types, UnserializeableVisitor)

from dss.dsl.xml.serializers import (
    XmlSerializer,
    _OptimizedXmlSerializer,
    xml_default_visitors_map)
from dss.dsl.html import (html, head, title, body, span, div, table, tr, td)

from dss.dsl import html_pure_python as pure_python

def purepy_serialize(obj):
    return pure_python.Serializer(pure_python.xml_default_visitors_map).serialize(obj)
for k, v in pure_python.htmltags.iteritems():
    exec '%s = htmltags["%s"]'%(k, k) in pure_python.__dict__

################################################################################
premap = xml_default_visitors_map.copy()
premap[int] = UnserializeableVisitor()
premap[str] = UnserializeableVisitor()
for _type in func_types:
    premap[_type] = UnserializeableVisitor()
precompiler = XmlSerializer(premap)

def benchmark_serialization(obj, label=None, iterations=1000):
    print '-'*80
    if label:
        print label
    expected = XmlSerializer().serialize(obj)
    def timeit(serialize, obj, iterations=iterations):
        if unicode(expected) != unicode(serialize(obj)):
            print serialize(obj), expected

        start = time()
        for _i in xrange(iterations):
            serialize(obj)
        end = time()
        return end-start

    def format_time(t):
        return '%0.4f msec/iter'%((t/iterations)*1000)
    def format_result(title, t, comparison_time=None):
        return ' '.join(
            ('%-15s:'%title,
             format_time(t),
             (('%0.2fx more iter/time'%((comparison_time/t)-1)
               +' %0.1f%% less time/iter'%(((comparison_time-t)/comparison_time)*100))
              if comparison_time else '')
             ))

    normal = timeit(XmlSerializer().serialize, obj)
    if label in pure_python_data:
        py = timeit(purepy_serialize, pure_python_data[label])
        print format_result('pure-py', py)
        normal = py

    baseclass = timeit(Serializer(visitor_map=xml_default_visitors_map).serialize, obj)
    optimized = timeit(_OptimizedXmlSerializer().serialize, obj)
    compiled = timeit(XmlSerializer().serialize, precompiler.serialize(obj))
    both = timeit(_OptimizedXmlSerializer().serialize, precompiler.serialize(obj))
    print format_result('normal', normal)
    print format_result('baseclass', baseclass, normal)
    print format_result('optimized', optimized, normal)
    print format_result('compiled', compiled, normal)
    print format_result('compiled + opt', both, normal)

################################################################################
#rows = [dict(a=1, b=2, c=3, d=4, e=5, f=6, g=7, h=8, i=9, j=10) for x in range(600)]
#rows = [xrange(10) for x in range(500)]
rows = [['abcdefghij']*10 for x in range(100)]

pure_python_data = {
    'random divs, ints, strs, and nested lists':
    [[pure_python.div[999], 'p', 1234,
      [1, ['abc', ['asdf 北京天'], [[[1234,1234]]]]]],
     '11234', pure_python.safe_unicode('as df'), ['1234','1234',1234]]*5,

    'big list of divs, with lambda':[[
        (lambda : pure_python.div[1234, 1234]),
        1234, pure_python.div, pure_python.div[1234, 1234]]*10],
    'Massive table':pure_python.table[[
        pure_python.tr[[pure_python.td[col] for col in row]] for row in rows]],

    'Massive table in lambda':pure_python.table[
        lambda : [pure_python.tr[[pure_python.td[col] for col in row]]
                  for row in rows]],
    }

benchmark_serialization(
    [[div[999], 'p', 1234,
      [1, ['abc', ['asdf 北京天'], [[[1234,1234]]]]]],
     '11234', safe_unicode('as df'), ['1234','1234',1234]]*5,
    label='random divs, ints, strs, and nested lists')

benchmark_serialization(
    [[(lambda : div[1234, 1234]), 1234, div, div[1234, 1234]]*10],
    label='big list of divs, with lambda')

benchmark_serialization(
    html[
        head[title[safe_unicode('10 times benchmark'), '北京天']],
        body[[div[span[safe_unicode('this is a test')]]]*10]],
    label='10 times html with safe_unicode')

benchmark_serialization(
    html[
        head[title['10 times benchmark', '北京天']],
        body[[div[span['this is a test']]]*10]],
    label='10 times html with strs')


benchmark_serialization(
    table[[tr[[td[col] for col in row]] for row in rows]],
    iterations=20,
    label='Massive table')

benchmark_serialization(
    lambda : table[[tr[[td[col] for col in row]] for row in rows]],
    iterations=20,
    label='Massive table in lambda')

su = safe_unicode
tbs, tbe = su('<table>'), su('</table>')
trs, tre = su('<tr>'), su('</tr>')
tds, tde = su('<td>'), su('</td>')
benchmark_serialization(
    lambda : (
        tbs,((trs, ((tds, col, tde) for col in row), tre) for row in rows), tbe),
    iterations=20,
    label='Massive table in lambda 2')

def bench_django(iterations=50):
    from django.conf import settings
    from django.template import Context, Template
    settings.configure(TEMPLATE_DEBUG=False)
    src = """<tabls>
    {% for row in rows %}
     <tr>{% for col in row %}<td>{{ col }}</td>{% endfor %}</tr>
    {% endfor %}
    </table>"""
    t = Template(src)
    c = Context(dict(rows=rows))
    #print t.render(c)
    start = time()
    for _i in xrange(iterations):
        #t = Template(src)
        #t.render(Context(dict(rows=rows)))
        t.render(c)
    end = time()
    duration = end-start

    print 'django %0.4f msec/iter'%((duration/iterations)*1000)

bench_django()

def bench_cheetah(iterations=50):
    from Cheetah.Template import Template
    src = """
    #def render(rows)
    <tabls>
    #for row in $rows
     <tr>#for col in row#<td>$col</td>#end for#</tr>
    #end for
    </table>
    #end def"""
    compilerSettings = dict(useNamemapper=False,
                            useSearchList=False,
                            useFilters=False)
    T = Template.compile(src, compilerSettings=compilerSettings)
    #print T().render(rows)
    t = T()
    start = time()
    for _i in xrange(iterations):
        #str(Template(src, namespaces=[dict(rows=rows)]))
        t.render(rows)
    end = time()
    duration = end-start
    print '%0.4f msec/iter'%((duration/iterations)*1000)
bench_cheetah()
