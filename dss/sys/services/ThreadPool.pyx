# stdlib
import traceback
import threading
from threading import Thread, Event, currentThread
from thread import get_ident

# cython imports
from dss.sys.services.Service cimport Service
from dss.sys.Queue cimport BlockingQueue
from dss.sys.lock cimport Lock
# dss imports
from dss.sys._internal.get_thread_description import get_thread_description

# ints for faster lookup with no unboxing, etc. python values for export:
cdef int _WAITING=1, _HANDLING=2, _EXIT_REQUESTED=3, _EXITED=4, _CULLED=5
WORKER_WAITING = _WAITING
WORKER_HANDLING = _HANDLING
WORKER_EXIT_REQUESTED = _EXIT_REQUESTED
WORKER_EXITED = _EXITED
WORKER_CULLED = _CULLED

cdef class ThreadState:
    def __init__(self):
        self.state = 0
        self.job_count = 0
        self.last_job_start_time = 0
        self.last_job_end_time = 0
        self.last_job_duration = 0
        self.current_job = None

cdef class AbstractThreadPoolJob:
    # I want to extend this to support the following:
    # - an optional name/description for each job that can be used while
    #   investigating stuck jobs or in post-mortems.  provide means
    #   for setting these from within a running job: e.g. set the
    #   user / url / controller when handling a wsgi request
    # - a status indicator: expected run-time, stuck?, internal
    #   heartbeat, etc. I'd rather delegate status checks to the job
    #   types themselves than bake it into the pool class.

    # via sub-classes:
    # - have long-running jobs terminate or suspend gracefully when
    #   the process is being shutdown
    # - the ability to pause certain longer running, low priority jobs
    #   when the system load is high and resume them later when the
    #   load drops.  The job would have to wrap a generator object
    #   that yields control occasionally (co-operative
    #   multi-tasking).  I could define a pubsub channel for
    #   notifications about system load changes (moving from one state
    #   to another).  Jobs would subscribe to this channel and be
    #   responsible for figuring out how to to the right thing.  If a
    #   low-priority job was informed that system load was high, it
    #   could free up the thread it is using (return from run()) and
    #   later when the pubsub system calls its subscriber to say that
    #   the load is low again, it can stick itself back into the
    #   threadpool job queue.

    def __init__(self):
        pass

    cpdef object run(self):
        raise NotImplementedError

    def __call__(self):
        self.run()

cdef class PyCallbackThreadJob(AbstractThreadPoolJob):
    def __init__(self, callback):
        self.callback = callback

    cpdef object run(self):
        self.callback()

cdef AbstractThreadPoolJob _EXIT_NOW = AbstractThreadPoolJob()


# The underscored attrs below are used for fast cython-C access by ThreadPool and
# the properties are not used internally.  The properties are provided to allow
# access from Python code, should it be needed.

cdef class ThreadPool(Service):
    # @@TR: split the stats collection and pool adjustment strategy
    # out into a helper as this class does too much.

    def __init__(self, **kws):
        Service.__init__(self, **kws)

        # the thread pool itself:
        self.initial_threads = self._settings['initial_threads']
        self.max_threads = self._settings['max_threads']
        self.min_threads = self._settings['min_threads']
        self.current_pool_size = 0
        self.total_threads_ever_used = 0
        self.active_thread_count = 0
        self._worker_thread_pool = []
        self._worker_thread_exit_event = Event()

        # job queue:
        self._job_queue = BlockingQueue(self._settings['job_queue_maxsize'])
        self.job_count = 0 # note, access is not synchronized!

        # monitoring:
        self._monitor_thread = None
        self._monitor_thread_active = False
        self._monitor_event = Event()

        # pool size management
        self._pool_management_lock = Lock()
        self._delay_between_pool_decreases = self._settings['delay_between_pool_decreases']
        self._last_pool_size_change = 0
        self._last_pool_size_change_time = 0
        self._recent_pool_size_changes_list = []
        self._recent_pool_size_changes_list_max_size = self._settings[
            'recent_pool_size_changes_list_max_size']
        self._recent_pool_size_changes_list_cull_size = self._settings[
            'recent_pool_size_changes_list_cull_size']

        # task scheduling
        self._scheduled_task_list = [] # [(nextRuntime, task)]
        self._scheduled_task_list_lock = Lock()
        self._next_scheduled_task_time = 0

        # job timing stats
        self._job_timing_stats_list_lock = Lock()
        self._job_timing_stats_list = []
        self._job_timing_stats_list_max_size = self._settings[
            'job_timing_stats_list_max_size']
        self._job_timing_stats_list_cull_size = self._settings[
            'job_timing_stats_list_cull_size']

    def _initialize_settings(self):
        Service._initialize_settings(self)
        self._settings.update(dict(
            log_channel='dss.threadpool',
            register_as_main_thread_pool=True,
            job_queue_maxsize=1024,

            min_threads=3,
            initial_threads=5,
            max_threads=80,
            daemonize_workers=True,

            seconds_before_considered_stuck=10,

            delay_between_pool_decreases=3, #seconds
            recent_pool_size_changes_list_max_size=500,
            recent_pool_size_changes_list_cull_size=200,
            job_timing_stats_list_max_size=5000,
            job_timing_stats_list_cull_size=2500,

            monitor_interval=1, # seconds
            ))

    def start(self):
        if self._settings['register_as_main_thread_pool']:
            if self.service_runner:
                self._register_service('dss.main_thread_pool')
        self._running = 1
        self._start_time = time_of_day()
        self._log_channel.notice('Starting with %d initial threads'%self.initial_threads)

        self._pool_management_lock.acquire()
        try:
            self._add_threads(self.initial_threads)
        finally:
            self._pool_management_lock.release()

        self._monitor_thread = Thread(target=self._monitor_loop, name='monitor thread')
        self._monitor_thread.start()

    def stop(self):
        cdef ThreadState thread_state
        self._running = 0
        self._shutdown_time = time_of_day()
        self._log_channel.notice('Stopping ThreadPool')
        self._monitor_event.set()
        if self._monitor_thread:
            self._monitor_thread.join()

        self._pool_management_lock.acquire()
        try:
            successful = self._cull_threads(len(self._worker_thread_pool)*2, 5)
        finally:
            self._pool_management_lock.release()

        if not successful:
            self.service_runner.mark_unclean_shutdown()
            for t in self.busy_threads:
                thread_state = t.state
                print thread_state.current_job
            # @@TR: could add a special wedged thread handler

    cpdef object add_job(self, callback):
        self._job_queue.put((PyCallbackThreadJob(callback), time_of_day()))

    cpdef object add_jobs(self, callbacks):
        cdef double t = time_of_day()
        self._job_queue.putmany(
            [(PyCallbackThreadJob(cback), t) for cback in callbacks])

    cpdef object add_job_object(self, AbstractThreadPoolJob job):
        self._job_queue.put((job, time_of_day()))

    cpdef object add_job_objects(self, jobs):
        cdef double t = time_of_day()
        self._job_queue.putmany([(job, t) for job in jobs])

    #cpdef object add_high_priority_job(self, callback):
    #    self._job_queue.putleft(
    #          (PyCallbackThreadJob(callback), time_of_day()), 0)   # respectmaxsize=0

    def schedule_task(self, task, when):
        self._scheduled_task_list_lock.acquire()
        try:
            self._scheduled_task_list.append((when, task))
            self._update_scheduled_task_list()
            self._monitor_event.set()
        finally:
            self._scheduled_task_list_lock.release()

    def _handle_exception(self, e, logMessage='exception'):
        if self.service_runner.is_fatal_error(e):
            self.service_runner.handle_fatal_error(e)
        else:
            try:
                self._log_channel.exception(logMessage)
            except:
                traceback.print_exc()

    ## thread initization methods
    def _init_thread(self):
        if self._settings.get('enable_com', False):
            import pythoncom
            pythoncom.CoInitializeEx(pythoncom.COINIT_MULTITHREADED)

    def _del_thread(self):
        if self._settings.get('enable_com', False):
            import pythoncom
            pythoncom.CoUninitialize()

    def _worker_loop(self):
        cdef ThreadState thread_state
        cdef BlockingQueue queue
        cdef AbstractThreadPoolJob job
        cdef double job_request_time, job_wait_time, start_time
        cdef int active_thread_count_after_wait

        self._init_thread() # enabling COM, etc.
        if self._verbose:
            self._log_channel.debug('Started worker thread (%s)'%get_thread_description())

        thread = currentThread()
        thread_state = thread.state
        thread._thread_id = get_ident()


        queue = thread.job_queue

        job_timing_stats = self._job_timing_stats_list
        job_timing_stats_list_max_size = self._job_timing_stats_list_max_size

        while self._running:
            try:
                thread_state.state = _WAITING
                job, job_request_time = queue.get()
                if job is _EXIT_NOW:
                    break

                thread_state.state = _HANDLING
                self.job_count += 1
                self.active_thread_count += 1 # not synchronized

                if (not self._monitor_thread_active
                    and self.current_pool_size < self.max_threads
                    and self.active_thread_count > self.current_pool_size*0.66):
                    # @@TR: the .66 threshold above should be soft-coded
                    self._monitor_event.set()

                start_time = time_of_day()
                thread_state.job_count += 1
                thread_state.last_job_start_time = start_time
                active_thread_count_after_wait = self.active_thread_count
                thread_state.current_job = job

                try:
                    job.run()
                except Exception, e:
                    self._handle_exception(e, 'exception while processing job')

                thread_state.last_job_end_time = time_of_day()
                thread_state.last_job_duration = (
                    thread_state.last_job_end_time - start_time)
                thread_state.current_job = None
                PyList_Append(job_timing_stats,
                              (job_request_time,
                               (start_time - job_request_time),
                               active_thread_count_after_wait,
                               thread_state.last_job_duration))
                self.active_thread_count -= 1 # not synchronized
            except Exception, e:
                self._handle_exception(e, 'exception while processing job')

        thread_state.state = _EXITED
        self._worker_thread_exit_event.set()
        if self._verbose:
            self._log_channel.debug('Stopped worker thread (%s)'%get_thread_description())
        self._del_thread()

    def _monitor_loop(self):
        cdef unsigned long long job_count_at_end_of_last_cycle
        cdef double time_at_end_of_last_cycle

        self._init_thread()
        interval = self._settings['monitor_interval']
        wait = self._monitor_event.wait

        job_timing_stats = self._job_timing_stats_list
        job_timing_stats_list_max_size = self._job_timing_stats_list_max_size
        scheduled_task_list = self._scheduled_task_list
        while self._running:
            try:
                # @@TR: add a sleep mode to this so it consumes less cpu time
                # when the server is idle
                job_count_at_end_of_last_cycle = self.job_count
                time_at_end_of_last_cycle = time_of_day()
                timeout = interval
                if self._next_scheduled_task_time:
                    time_till_next_task = (
                        self._next_scheduled_task_time - time_at_end_of_last_cycle)
                    timeout = min(time_till_next_task, interval)
                if timeout > 0:
                    wait(timeout)

                if not self._running:
                    break
                self._monitor_thread_active = True

                if (self.job_count > job_count_at_end_of_last_cycle
                    or (self.current_pool_size != self.min_threads)
                    # for when minthreads and sudden surge:
                    or (self.current_pool_size < self.max_threads
                        and self.active_thread_count >
                        (self.current_pool_size*0.66))
                    ):

                    self._adjust_pool_size()

                if (self.job_count > job_count_at_end_of_last_cycle):
                    if PyList_Size(job_timing_stats) > job_timing_stats_list_max_size:
                        self._job_timing_stats_list_lock.acquire()
                        try:
                            del job_timing_stats[:-self._job_timing_stats_list_cull_size]
                        finally:
                            self._job_timing_stats_list_lock.release()

                self._monitor_event.clear()
                self._run_scheduled_tasks()
                self._monitor_thread_active = False
            except Exception, e:
                self._handle_exception(e, 'exception in monitor thread')
        self._del_thread()

    cpdef int _update_scheduled_task_list(self) except -1:
        if self._scheduled_task_list:
            self._scheduled_task_list.sort()
            self._next_scheduled_task_time = self._scheduled_task_list[0][0]
        else:
            self._next_scheduled_task_time = 0

    cdef int _run_scheduled_tasks(self) except -1:
        if (self._next_scheduled_task_time
            and self._next_scheduled_task_time <= time_of_day()):
            tasks_to_run = []
            self._scheduled_task_list_lock.acquire()
            scheduled_task_list = self._scheduled_task_list
            try:
                while scheduled_task_list:
                    when, task = scheduled_task_list[0]
                    if when <= time_of_day():
                        del scheduled_task_list[0]
                        tasks_to_run.append(task)
                    else:
                        break
            finally:
                self._update_scheduled_task_list()
                self._scheduled_task_list_lock.release()

            for task in tasks_to_run:
                try:
                    task()
                    # @@TR: reconsider this ...
                    # We run them in this thread immediately instead of adding
                    # them to the job_queue as scheduled health-check tasks must
                    # execute immediately even when the job_queue is maxed out or
                    # all worker threads are wedged.  However, tasks should be
                    # good citizens and do any longer jobs work asynchronously
                    # if possible.
                    # Tasks are responsible for rescheduling themselves
                except Exception, e:
                    self._handle_exception(e, 'exception running task: %r'%task)


        # 1) warn about thresholds: wedged threads, long queue,
        #   long job wait times, etc.
        # 2) collect and log stats, etc

        # task types:
        #  - to run once at a specific time
        #  - to run once when server load is low (can be implemented as
        #    a periodic task that checks to see if it should execute and
        #    reschedules itself if the load is still too high))
        #  - to run periodically:
        #    - interval timer
        #    - cron-like timer, periodic at specific times
        #           (lowest priority for implementation)

    cdef int _adjust_pool_size(self) except -1:
        cdef signed int adjustment = 0
        self._pool_management_lock.acquire()
        try:
            adjustment = self._calculate_pool_size_adjustment()
            if adjustment > 0:
                if (self.current_pool_size + adjustment) > self.max_threads:
                    self._log_channel.warn(
                        'calculated thread adjustment of %i is too large'%adjustment)
                    return 0
                else:
                    self._add_threads(adjustment)
            elif adjustment < 0:
                if (self.current_pool_size + adjustment) < self.min_threads:
                    self._log_channel.warn(
                        'calculated thread adjustment of %i is too large'%adjustment)
                    return 0
                else:
                    self._cull_threads(+adjustment, 10)

            if adjustment:
                adjustment_str = (adjustment>0 and '+%i'%adjustment or str(adjustment))
                self._log_channel.notice(
                    '%s threads (new_pool_size=%i active_threads=%i)'%(
                    adjustment_str, self.current_pool_size,
                    self.active_thread_count))

        finally:
            self._pool_management_lock.release()

    cdef signed int _calculate_pool_size_adjustment(self) except? -1:
        """Returns a relative pool size adjustment, positive or negative.

        This is designed to scale threads up quickly when load spikes and lower
        them slowly, and smoothly, as the usage average comes back
        down.

        # @@TR: I will eventually factor this out into a separate
        # `strategy` object that allows different strategies to be
        # experimented with, etc.
        """
        cdef double _30secs_ago = (time_of_day() - 30)
        cdef double stats_start_time
        cdef double ave_wait_time
        cdef double max_wait_time
        cdef int ave_active_threads
        cdef int max_active_threads
        cdef int delay_between_decreases
        # @@TR: there are some hardcoded factors below that should be soft-coded

        if self.active_thread_count > (self.current_pool_size * 0.8):
            # no need for fancy stats, just double the threads pool immediately
            return min(self.current_pool_size,
                       (self.max_threads-self.current_pool_size))

        elif self.current_pool_size < self.min_threads:
            # should be able to get here!
            self._log_channel.warn(
                'Thread pool dropped below min allowed pool size. Increasing')
            return self.min_threads-self.current_pool_size

        if (self._last_pool_size_change < 0
            and self._last_pool_size_change_time > _30secs_ago):
            # last change was a decrease, use last change time to avoid
            # oscillations from a moving average
            stats_start_time = self._last_pool_size_change_time
        else:
            stats_start_time = _30secs_ago

        (job_count,
         ave_wait_time,
         max_wait_time,
         ave_active_threads,
         max_active_threads) = self._get_summary_stats_since(stats_start_time)

        if self._verbose:
            self._log_channel.debug(
              ('stats last 30 seconds: '
               'jobs=%i, ave_active_threads=%i, '
               'max_active_threads=%i, current queue size=%i')%(
              job_count, ave_active_threads, max_active_threads, len(self._job_queue)))

        if ((ave_active_threads >= (self.current_pool_size * 0.6))
            or (max_active_threads > self.current_pool_size * 0.8)):

            if self.current_pool_size >= self.max_threads:
                adj = 0
            elif max_active_threads > (self.current_pool_size * 0.8):
                adj = max_active_threads*2
            elif ave_active_threads < (self.max_threads/10):
                adj = int(ave_active_threads*.05)
            else:
                adj = ave_active_threads

            return min(adj, (self.max_threads-self.current_pool_size))

        elif ave_active_threads < (self.current_pool_size * 0.35):
            delay_between_decreases = self._delay_between_pool_decreases
            if self._last_pool_size_change > 0:
                delay_between_decreases = delay_between_decreases * 3

            if self.current_pool_size == self.min_threads:
                return 0
            elif ((time_of_day() - self._last_pool_size_change_time)
                  < delay_between_decreases):
                return 0
            elif self.current_pool_size > self.min_threads:
                if (self.min_threads - self.current_pool_size) == -1:
                    return -1
                else:
                    adj = -min(((self.current_pool_size-self.min_threads)/2), 20)
                    return adj
            else:
                return 0
        else:
            return 0

    cpdef object _get_summary_stats_since(self, double time):
        """Returns a tuple
           (job_count, ave_wait_time, max_wait_time,
            ave_active_threads, max_active_threads)
        """
        cdef double request_time
        cdef double wait, sum_wait_time, max_wait_time
        cdef int i, stats_list_len
        cdef int active_threads, sum_active_threads, max_active_threads

        self._job_timing_stats_list_lock.acquire()
        try:
            stats = self._job_timing_stats_list
            stats_list_len = PyList_Size(stats)
            if stats_list_len == 0 or stats[-1][0]< time:
                return (0, 0,0, 0,0)

            sum_wait_time = 0
            max_wait_time = 0
            sum_active_threads = 0
            max_active_threads = 0
            i = 1
            while i <= stats_list_len:
                (request_time, wait, active_threads, duration) = stats[-i]
                if i==stats_list_len or request_time < time:
                    return (i, # num of jobs
                            (sum_wait_time/i), # ave wait time
                            max_wait_time,
                            (sum_active_threads/i), # ave active threads
                            max_active_threads
                            )
                else:
                    sum_wait_time = sum_wait_time + wait
                    sum_active_threads = sum_active_threads + active_threads
                    if wait > max_wait_time:
                        max_wait_time = wait
                    if active_threads > max_active_threads:
                       max_active_threads = active_threads
                i = i + 1
        finally:
            self._job_timing_stats_list_lock.release()

    cpdef object _get_job_timing_stats_since(self, double time):
        cdef double request_time
        cdef int i, stats_list_len

        self._job_timing_stats_list_lock.acquire()
        try:
            stats = self._job_timing_stats_list
            stats_list_len = PyList_Size(stats)
            i = 1
            while i <= stats_list_len:
                (request_time, wait, active_threads, duration) = stats[-i]
                if request_time < time:
                    return self._job_timing_stats_list[-i:]
                i = i + 1
            return []
        finally:
            self._job_timing_stats_list_lock.release()

    def get_summary_stats(self, seconds=60):
        return self._get_summary_stats_since((time_of_day() - seconds))

    def get_job_timing_stats(self, seconds=60):
        """Returns a list of job stats in the form
          [(request_time, waitTime, active_threads, duration), ...]
          with one tuple for each job in the previous ``seconds``.
        """
        return self._get_job_timing_stats_since((time_of_day() - seconds))

    cdef int _add_threads(self, signed int num) except -1:
        cdef ThreadState state
        if not self._running:
            self._log_channel.warn("Threadpool is not running. Can't add threads!")
            return 0

        for i from 0 <= i < num:
            self.total_threads_ever_used = self.total_threads_ever_used +1
            t = Thread(
                target=self._worker_loop, name='Worker %i'%self.total_threads_ever_used)
            if self._settings['daemonize_workers']:
                t.setDaemon(True)
            state = ThreadState()
            state.state = _WAITING
            t.state = state
            t.lock = threading.Lock()
            t.job_queue = self._job_queue  # this is done to allow for
                                        # a separate queue per thread
                                        # if ever needed (I have
                                        # experimented with it - see
                                        # the hg logs)
            PyList_Append(self._worker_thread_pool, t)
            t.start()

        self._record_pool_size_change(num)

    cdef int _cull_threads(self, signed int num, double timeout=15) except -1:
        """

        - self._pool_management_lock must be acquired prior to calling
          this method.
        """
        cdef int wedge_warning_issued = 0
        cdef int exits_requested = 0
        cdef int pool_size_before_cull = len(self._worker_thread_pool)
        cdef double cull_start_time = time_of_day()
        cdef double timeout_at = cull_start_time + timeout
        cdef double cull_warning_time = min(cull_start_time+15, timeout_at)

        num = min(abs(num), pool_size_before_cull)

        for i from 0 <= i < num:
            exits_requested = i
            self._job_queue.putleft((_EXIT_NOW, 0), 1)

        culled = []
        while PyList_Size(culled) < num:
            self._worker_thread_exit_event.wait(1)
            for t in self._worker_thread_pool:
                if (<ThreadState>(t.state)).state == _EXITED:
                    t.join()
                    (<ThreadState>(t.state)).state = _CULLED
                    PyList_Append(culled, t)

            if self._worker_thread_exit_event.isSet():
                self._worker_thread_exit_event.clear()
            elif PyList_Size(culled) < num and time_of_day() > cull_warning_time:
                if not wedge_warning_issued:
                    wedge_warning_issued = True
                    self._log_channel.warn("We've been waiting a long time for some"
                                          " threads to exit. They may be wedged.")
                if time_of_day() > timeout_at:
                    self._log_channel.error("thread cull timeout")
                    break

        new_pool = []
        for t in self._worker_thread_pool:
            if (<ThreadState>(t.state)).state != _EXITED and t not in culled:
                PyList_Append(new_pool, t)

        if len(culled) != num:
            self._log_channel.warn(
                'wrong number of threads culled:'
                ' %i at start, cull of %i requested, %i culled, %i remaining'%(
                pool_size_before_cull, num, len(culled), len(new_pool)))

        self._worker_thread_pool = new_pool
        self._record_pool_size_change(-num)
        return len(culled) == num

    cdef int _record_pool_size_change(self, signed int change) except -1:
        self.current_pool_size = PyList_Size(self._worker_thread_pool)
        self._last_pool_size_change = change
        self._last_pool_size_change_time = time_of_day()
        PyList_Append(self._recent_pool_size_changes_list,
                      (self._last_pool_size_change_time, change))
        if (PyList_Size(self._recent_pool_size_changes_list)
            > self._recent_pool_size_changes_list_max_size):
            del self._recent_pool_size_changes_list[
                :self._recent_pool_size_changes_list_cull_size]

    cpdef object _get_used_threads(self):
        matches = []
        add = matches.append
        for t in self._worker_thread_pool:
            if (<ThreadState>(t.state)).job_count:
                add(t)
        return matches

    cpdef object _get_busy_threads(self, seconds_busy=0):
        cdef double min_start_time = time_of_day() - seconds_busy
        matches = []
        for t in self._worker_thread_pool:
            if ((<ThreadState>(t.state)).state==_HANDLING
                and (<ThreadState>(t.state)).last_job_start_time < min_start_time):
                matches.append(t)
        return matches

    property used_threads:
        def __get__(self):
            return self._get_used_threads()

    property busy_threads:
        def __get__(self):
            return self._get_busy_threads(0)

    property stuck_threads:
        def __get__(self):
            return self._get_busy_threads(self._settings['seconds_before_considered_stuck'])
