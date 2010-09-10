from threading import Thread, Event
from time import time
from collections import deque

from nose.tools import raises

from dss.sys.Queue import (AbstractQueue, BlockingQueue)

def test_abstractqueue():
    q = AbstractQueue()

    @raises(NotImplementedError)
    def _test(func):
        func()

    for f in [lambda: len(q),
              lambda: q.is_empty,
              lambda: q.is_full,
              lambda: q.get(),
              lambda: q.getmany(),
              lambda: q.getmany(20),
              lambda: q.put(1),
              lambda: q.putmany([1,2,3]),
              lambda: q.putleft(1),
              ]:
        _test(f)

def test_get_put_nomaxsize():
    q = BlockingQueue()
    assert q.is_empty
    assert len(q) == 0

    items = range(20)
    for i in items:
        q.put(i)
        assert len(q) == 1
        assert q.get() == i
        assert len(q) == 0

def test_putmany_getmany():
    q = BlockingQueue()

    # empty putmany calls should have no effect
    q.putmany([])
    q.putmany(tuple())
    q.putmany(deque())
    assert q.is_empty
    assert q._esema.locked()            # pylint: disable-msg=W0212

    for i in xrange(1, 10):
        q.putmany([1]*i)
        assert len(q) == i
        q.putmany(tuple(q.getmany()))
        q.putmany(deque(q.getmany()))
        assert len(q.getmany(i)) == i
        assert q.is_empty

    items = range(20)
    q.putmany(items)
    assert q.getmany() == items
    q.putmany(items)
    assert q.getmany(5) == items[:5]
    assert q.getmany(5) == items[5:10]
    assert q.getmany(5) == items[10:15]
    assert q.getmany(5) == items[15:]
    assert len(q) == 0
    assert q.is_empty

def test_putleft():
    q = BlockingQueue()
    items = range(20)
    for i in items:
        q.putleft(i)
        assert len(q) == i+1
        assert q.get() == i
        assert len(q) == i
        q.putleft(i)
    assert q.getmany() == list(reversed(items))
    assert len(q) == 0


def test_maxsize(maxsize=5):
    q = BlockingQueue(maxsize=maxsize)
    assert q.maxsize == maxsize
    for i in xrange(maxsize):
        assert not q.is_full
        q.put(i)

    assert q.is_full
    assert len(q.getmany()) == maxsize
    assert not q.is_full

    q.putmany(range(maxsize))
    assert q.is_full
    q.putleft(99, respectmaxsize=0)
    assert q.is_full
    assert len(q) == maxsize+1
    assert q.get() == 99
    assert q.is_full
    assert q._fsema.locked()            # pylint: disable-msg=W0212

    assert len(q.getmany()) == maxsize
    assert not q.is_full
    assert q.is_empty

def test_maxsize_1():
    test_maxsize(1)

def test_maxsize_2():
    test_maxsize(2)

def test_maxsize_20():
    test_maxsize(20)

def test_multiple_threads(iterations=120, num_consumers=30):
    q = BlockingQueue(iterations)
    woken_thread_event = Event()
    threads = []
    times = []

    def _get(iters, ev):
        start = time()
        for _i in xrange(iters):
            q.get()
            ev.set()
            woken_thread_event.set()
        end = time()
        times.append(end-start)

    iters_per_consumer = iterations/num_consumers
    for _i in range(num_consumers):
        ev = Event()
        tc = Thread(target=_get, args=(iters_per_consumer, ev))
        tc.setDaemon(1)
        tc.event = ev
        threads.append(tc)

    for t in threads:
        t.start()

    assert not times
    for i in xrange(iterations):
        q.put(i)
        woken_thread_event.wait(1)
        woken_thread_event.clear()
        woken_threads = [t for t in threads if t.event.isSet()]
        assert len(woken_threads) == 1, woken_threads
        woken_threads[0].event.clear()

    for t in threads:
        t.join(1)
        assert not t.isAlive()
    assert len(times) == len(threads)
    #duration = max(times)
    #print duration
    #print duration/iterations
