from time import time as _time
cdef inline double time_of_day():
    return _time_of_day()

def test_time_of_day():
    return time_of_day()
