cdef extern from "Python.h":
    # without this bogus extern the required preprocessor DEFs in Python.h don't
    # get loaded and _time_of_day.c falls back on the safest version, which
    # won't match time.time(). bug in cython??
    pass

cdef extern from "_time_of_day.h":
    double _time_of_day()

cdef inline double time_of_day()
