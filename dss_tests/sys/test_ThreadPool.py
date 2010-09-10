from time import sleep
from dss.sys.services.ThreadPool import ThreadPool

# @@TR: Many more tests are needed here!

class DummyChannel(object):
    def debug(self, *args, **kws):
        pass

    def info(self, *args, **kws):
        pass

    def notice(self, *args, **kws):
        pass

    def warn(self, *args, **kws):
        pass

    def error(self, *args, **kws):
        pass

    def exception(self, *args, **kws):
        pass

def _run_counter_jobs(pool, n=20):
    out = []
    def job_callback():
        sleep(.0001)
        out.append(1)
    for _i in xrange(n):
        pool.add_job(job_callback)
        assert pool.min_threads <= pool.current_pool_size <= pool.max_threads
    while len(out) < n: # should use an event plus a timeout here
        sleep(.001)

def test_init_and_settings():
    for settings in [dict(max_threads=3,
                          min_threads=2,
                          initial_threads=2),
                     dict(max_threads=10,
                          min_threads=4,
                          initial_threads=5),
                     ]:
        settings['log_channel'] = DummyChannel()
        pool = ThreadPool(**settings)
        assert pool.max_threads == settings['max_threads']
        assert pool.min_threads == settings['min_threads']
        assert pool.initial_threads == settings['initial_threads']
        assert not pool.total_threads_ever_used

        assert not pool.running
        assert not pool.current_pool_size
        assert not pool.job_count
        assert not pool.active_thread_count
        assert not pool.used_threads
        assert not pool.stuck_threads
        assert not pool.total_threads_ever_used
        try:
            pool.start()
            assert pool.running
            assert pool.active_thread_count == 0
            assert not pool.used_threads
            assert not pool.busy_threads
            n = 20
            _run_counter_jobs(pool, n=n)
            assert pool.used_threads
            assert pool.job_count == n
            assert not pool.busy_threads
            assert pool.active_thread_count == 0
        finally:
            pool.stop()
