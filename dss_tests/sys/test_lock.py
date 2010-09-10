from threading import Thread

from dss.sys.lock import Lock

def test_single_threaded():
    l = Lock()
    assert l.acquire() == 1
    assert l.locked()
    assert l.release() == 0

    assert l.acquire(blocking=1) == 1
    assert l.locked()
    for i in xrange(20):
        assert l.acquire(blocking=0) == 0
    assert l.locked()
    assert l.release() == 0

def test_create_destroy():
    for i in xrange(100):
        Lock()

def test_multi_threaded():
    l = Lock()
    output = []

    def run(i):
        try:
            l.acquire()
            old = output[:]
            del output[:]
            output.extend(old+[i])
        finally:
            l.release()

    runs = 20
    for i in xrange(runs):
        t = Thread(target=run, args=(i,))
        t.start()
        t.join()
    assert not l.locked()
    assert len(output) == runs
