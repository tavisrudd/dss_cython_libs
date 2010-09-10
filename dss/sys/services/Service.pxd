cdef class Service:
    cdef int _running
    cdef public object _service_runner
    cdef public object _parent_service
    cdef public object _log_channel
    cdef public object _child_services

    cdef public object _settings
    cdef public int _verbose
    #cdef public object config # @@TR: I'm switching over to this from the
    #                         # _settingsManager stuff
