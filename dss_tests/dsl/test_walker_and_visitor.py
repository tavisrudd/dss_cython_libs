# pylint: disable-msg=C0321,W0613
# various types used in registration tests:
from decimal import Decimal
from collections import deque
import datetime
from array import array

from nose.tools import raises

from dss.dsl.Walker import Walker, NoVisitorFound
from dss.dsl.Visitor import Visitor, CallbackVisitor
from dss.dsl.VisitorMap import DEFAULT
def list_sum(l):
    if isinstance(l, list):
        return sum(map(list_sum, l))    # pylint: disable-msg=W0141
    else:
        return l

def test_visitor_registration():
    # pylint: disable-msg=R0912,R0914
    output = []
    w = Walker()
    def test_walk(obj):
        output_before = output[:]
        w.walk(obj)
        assert output == output_before+[obj]

    def fail_before_reg_then_pass(obj, objtype, visitor):
        assert not w.visitor_map.get_visitor(obj), \
               'No visitor should be registered for %s type=%s'%(
            repr(obj), repr(objtype))
        @raises(NoVisitorFound)
        def fail():
            w.walk(obj)
        fail()
        w.visitor_map[objtype] = visitor
        test_walk(obj)

    ## basic usage with CallbackVisitor
    fail_before_reg_then_pass(123, int, lambda i, w: output.append(i))
    assert isinstance(w.visitor_map.get_visitor(123), CallbackVisitor)
    for i in xrange(20):
        test_walk(i)

    ## now various tests with a subclass of Visitor
    class NewVisitor(Visitor):
        def visit(self, obj, walker):
            output.append(obj)
    v = NewVisitor()
    class mystr(str): pass
    class mystr2(mystr): pass
    class myunicode(unicode): pass
    class myunicode2(myunicode): pass

    class newstyle(object): pass
    class newstyle2(newstyle): pass

    for obj in (
        mystr2('a2'), #subclass first
        mystr('a'),   # mystr will still fail despite reg for mystr2, etc.:
        myunicode2('b2'),
        myunicode('b'),
        'c',
        u'd',
        (1,2),
        [3,4],
        {'a':2},
        Decimal('2.2'),
        deque(),
        set([1,2,3]),
        datetime.datetime.now(),
        array('c'),
        newstyle2(),
        newstyle()
        ):

        fail_before_reg_then_pass(obj, type(obj), v)

    # make sure that old style classes / instances are handled correctly
    class oldstyle: pass
    class oldstyle2(oldstyle): pass
    fail_before_reg_then_pass(oldstyle2(), oldstyle2, v) # NOT type(oldstyle2)!
    fail_before_reg_then_pass(oldstyle(), oldstyle, v)

    # make sure subclass of long is handled with visitor reg'd on long
    sawlong = [False]
    def vlong(l, w):
        v.visit(l, w)
        sawlong[0] = True
    class mylong(long): pass
    fail_before_reg_then_pass(mylong(1L), long, vlong)
    assert sawlong[0]


def test_walk_nested_lists_of_ints():
    w = Walker()

    isum = [0]
    output = []
    def vint(i, w):
        isum[0] += i
        output.append(i)

    def vlist(l, w):
        for i in l:
            w.walk(i)

    w.visitor_map[int] = vint
    w.visitor_map[list] = vlist


    isum2 = [0]
    def test_walk(obj):
        isum2[0] += list_sum(obj)
        w.walk(obj)
        assert isum==isum2

    test_walk(123)
    test_walk([123, 9, 23])
    test_walk([123, 9, 23, 234, [[[[2, [[4, [5]]]]]]], 987])
    test_walk([123, 9, 23, 234, 987, [0, 1]])
    assert list_sum(output)==isum2[0]

    # testing with a subclass of int should also work:
    class subint(int):
        pass
    test_walk([subint(234)])
    assert list_sum(output)==isum2[0]

def test_default_visitor():
    w = Walker()
    assert not w.visitor_map.get(DEFAULT)
    out = []
    def default(obj, walker):
        assert walker is w
        out.append(obj)

    w.visitor_map[DEFAULT] = default
    assert isinstance(w.visitor_map.get(DEFAULT), CallbackVisitor)
    assert w.visitor_map.get(DEFAULT).callback == default
    data = range(10)+['a', 'b', 2.3, None] #various types
    for i in data:
        w.walk(i)
    assert out==data

def test_visitor_map_update():
    w = Walker()
    def visitor(obj, walker):
        pass
    type_list = [list, tuple, dict]
    w.visitor_map.update(dict((t, visitor) for t in type_list))
    for t in type_list:
        assert isinstance(w.visitor_map.get(t), CallbackVisitor)
        assert w.visitor_map.get(t).callback == visitor

def test_walker_subclass_with_emit():
    class NewWalker(Walker):
        def __init__(self):
            Walker.__init__(self)
            self.output = []

        def emit(self, output, typecode=0):
            self.output.append(output)

    w = NewWalker()
    def vlist(l, w):
        for i in l:
            w.walk(i)
    w.visitor_map[list] = vlist
    w.visitor_map[int] = (lambda i, w: w.emit(i))

    isum = [0]
    def test_walk(obj):
        isum[0] += list_sum(obj)
        w.walk(obj)
        assert isum[0]==list_sum(w.output)

    test_walk(1)
    test_walk([123, 9, 23, 234, [[[[2, [[4, [5]]]]]]], 987])
