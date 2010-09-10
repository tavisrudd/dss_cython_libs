from dss.sys.LRUCache import LRUCache

# @@TR: these tests need better names, some concurrency checks, etc.

def ok(a, b):
    assert a == b, (a, b)

def test1():
    c = LRUCache(2, use_bulk_purge=False)
    ok(len(c), 0)
    c['a'] = 'a value'
    ok(c['a'], 'a value')
    c['b'] = 'b value'

    ok(c['a'], 'a value')
    ok(c['b'], 'b value')

    c['c'] = 'c value'
    try:
        c['a']
    except KeyError:
        pass
    except:
        raise
    else:
        raise Exception("expected exception not found")

    ok(c['c'], 'c value')
    ok(c['b'], 'b value')

    c['d'] = 'd value'
    ok(c['d'], 'd value')

    ok(len(c), 2)
    c['b'] = 'b value'

    try:
        c['c']
    except KeyError:
        pass
    else:
        raise Exception("expected exception not found")

    ok(c.has_key('b'), True)
    ok(c.has_key('c'), False)
    ok(len(c), 2)

def test2():
    c = LRUCache(4, use_bulk_purge=False)
    for i in range(1, 40):
        c[i] = i
        if i > 4:
            ok(len(c), 4)
            ok(c[i], i)
            ok(c[i-1], i-1)
            ok(c[i-2], i-2)
            ok(c[i-3], i-3)
            try:
                c[i-4]
            except KeyError:
                pass
            else:
                raise Exception("expected exception not found")

            ok(c[i-2], i-2)
            ok(c[i-1], i-1)
            ok(c[i], i)
        else:
            ok(c[i], i)
            ok(len(c), i)


def test3():
    c = LRUCache(4, use_bulk_purge=True, proportion_remaining_after_purge=.75)
    for i in range(1, 40):
        c[i] = i
        if i > 4:
            assert len(c) in [3, 4], 'i=%s, len=%s'%(i, len(c))
            try:
                c[i-len(c)]
            except KeyError:
                pass
            else:
                raise Exception("expected exception not found")

            s = range(i-len(c)+1, i+1)
            s.reverse()
            s.extend(range(i-len(c)+2, i+1))
            for j in s:
                ok(c[j], j)
        else:
            ok(c[i], i)
            ok(len(c), i)
