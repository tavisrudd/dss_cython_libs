import sys
import traceback

cdef class Service:
    """An abstract base class for all services.
    """

    def __init__(self, service_runner=None, parent_service=None, **settings):
        self.service_runner = service_runner
        self._parent_service = parent_service
        if not self._service_runner and parent_service:
            self.service_runner = parent_service.service_runner
        self._running = False
        self._child_services = []
        self._settings = {}
        self._initialize_settings()
        if settings:
            self._settings.update(settings)
        self._verbose = bool(self._settings.get('verbose'))

        self._initialize_log_channel()

    def _initialize_log_channel(self):
        log_channel = self._settings.get('log_channel', None)
        if isinstance(log_channel, basestring):
            log_manager = self._settings.get('log_manager', None)
            if not log_manager and self.service_runner:
                log_manager = self.service_runner.log_manager
            if log_manager:
                self._log_channel = log_manager.open_channel(self._settings['log_channel'])
            else:
                self._log_channel = None
        else:
            self._log_channel = log_channel

    def _initialize_settings(self):
        self._settings.update(dict(
            verbose=False,
            log_channel='dss.sys.services.Service',
            service_name=self.__class__.__name__))
        try:
            modName = self.__class__.__module__
            className = self.__class__.__name__
            self._settings.update(
                {'log_channel': (modName
                                 if modName.endswith(className)
                                 else '%s.%s'%(modName, className))})
        except:
            pass

    def service_name(self):
        return self._settings.get('service_name', repr(self))

    def _service_desc(self, service):
        return '%s (%s)'%(service.service_name(), id(service))

    def start(self):
        for child in self._child_services:
            service_desc = self._service_desc(child)
            try:
                if not child.running:
                    if self._settings['verbose']:
                        self._log_notice('Starting child service: %s'%service_desc)
                    child.start()
            except:
                self._log_exception('exception while starting child service: %s'%service_desc)
                raise
        self.running = True

    def stop(self, raise_exceptions=False):
        for child in reversed(self._child_services):
            service_desc = self._service_desc(child)
            try:
                if self._settings['verbose']:
                    self._log_notice('Stopping child service: %s'%service_desc)
                child.stop()
            except:
                self._log_exception('exception while stopping child service: %s'%service_desc)
                if raise_exceptions:
                    raise # for interactive debugging if needed,
                          # start() always raises which is why this is assymetrical
        self.running = False

    def restart(self):
        for child in self._child_services:
            try:
                child.restart()
            except:
                self._log_exception(
                    'exception while restarting child service: %s'%self._service_desc(child))
                raise

    def status(self):
        return (self._running and 'Running' or 'Stopped')

    property running:
        def __get__(self):
            return bool(self._running)

        def __set__(self, val):
            self._running = bool(val)

    property service_runner:
        def __get__(self):
            return self._service_runner

        def __set__(self, service_runner):
            self._service_runner = service_runner

    property parent_service:
        def __get__(self):
            return self._parent_service

        def __set__(self, parent_service):
            self._parent_service = parent_service

    def _add_child_service(self, child, set_parent=True):
        assert hasattr(child, 'running')
        assert hasattr(child, 'start')
        assert hasattr(child, 'stop')
        assert hasattr(child, 'restart')
        assert hasattr(child, 'service_name')
        self._child_services.append(child)
        if set_parent:
            child.parent_service = self
        if self.service_runner and not child.service_runner:
            child.service_runner = self.service_runner

    def _register_service(self, name, service=None, replace_existing=False):
        if service is None:
            service = self
        if (not replace_existing and name in self.service_runner.service_directory
            and self.service_runner.service_directory[name] is not service):
            raise Exception('A service named "%s" is already registered'%name)

        self.service_runner.service_directory[name] = service

    def _lookup_service(self, name):
        return self.service_runner.service_directory.get(name)

    ## logging

    def _log_exception(self, msg, **kws):
        if self._log_channel:
            self._log_channel.exception(msg, **kws)
        else:
            sys.stderr.write('>>>'+msg)
            traceback.print_exc()

    def _log_notice(self, msg, **kws):
        if self._log_channel:
            self._log_channel.notice(msg, **kws)
        else:
            pass
            #sys.stdout.write('>>>'+msg) # not safe if msg is unicode
            #that can't be encoded
