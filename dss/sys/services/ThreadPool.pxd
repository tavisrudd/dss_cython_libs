from cpython.list cimport PyList_Size, PyList_Append

from dss.sys.time_of_day cimport time_of_day
from dss.sys.services.Service cimport Service
from dss.sys.Queue cimport AbstractQueue
from dss.sys.lock cimport Lock

cdef class ThreadState:
    cdef public int state
    cdef public unsigned long long job_count
    cdef public double last_job_start_time
    cdef public double last_job_end_time
    cdef public double last_job_duration
    cdef public object current_job

cdef class AbstractThreadPoolJob:
    cpdef object run(self)

cdef class PyCallbackThreadJob(AbstractThreadPoolJob):
    cdef public object callback

cdef class ThreadPool(Service):

    ## pub:
    cpdef object add_job(self, callback)
    cpdef object add_jobs(self, callbacks)

    cpdef object add_job_object(self, AbstractThreadPoolJob job)
    cpdef object add_job_objects(self, jobs)
    #cpdef object add_high_priority_job(self, callback)

    cdef readonly int current_pool_size
    cdef readonly int initial_threads
    cdef readonly int max_threads
    cdef readonly int min_threads
    cdef readonly int active_thread_count
    cdef readonly long total_threads_ever_used
    cdef readonly unsigned long long job_count

    ## private:
    cdef AbstractQueue _job_queue
    cdef Lock _pool_management_lock
    cdef Lock _job_timing_stats_list_lock

    cdef public object _start_time, _shutdown_time

    cdef object _job_timing_stats_list
    cdef public int _job_timing_stats_list_max_size
    cdef public int _job_timing_stats_list_cull_size

    cdef public object _worker_thread_pool
    cdef public object _monitor_thread
    cdef public int _monitor_thread_active
    cdef public object _monitor_event

    cdef public object _worker_thread_exit_event

    cdef public object _recent_pool_size_changes_list
    cdef public int _recent_pool_size_changes_list_max_size
    cdef public int _recent_pool_size_changes_list_cull_size
    cdef public signed int _last_pool_size_change
    cdef public double _last_pool_size_change_time
    cdef public int _delay_between_pool_decreases

    cpdef object _get_used_threads(self)
    cpdef object _get_busy_threads(self, seconds_busy=?)
    cpdef object _get_summary_stats_since(self, double time)
    cpdef object _get_job_timing_stats_since(self, double time)

    cdef int _adjust_pool_size(self) except -1
    cdef signed int _calculate_pool_size_adjustment(self) except? -1
    cdef int _add_threads(self, signed int num) except -1
    cdef int _cull_threads(self, signed int num, double timeout=*) except -1
    cdef int _run_scheduled_tasks(self) except -1
    cdef int _record_pool_size_change(self, signed int change) except -1

    cdef object _scheduled_task_list
    cdef Lock _scheduled_task_list_lock
    cdef readonly double _next_scheduled_task_time
    cpdef int _update_scheduled_task_list(self) except -1
