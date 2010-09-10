import os
import select
import errno
from threading import Lock, Condition

class PollableEvent:
    """Provides an abstract object that can be used to resume select loops with
    indefinite waits from another thread or process. This mimics the standard
    threading.Event interface.

    Derived from:
    http://aspn.activestate.com/ASPN/Cookbook/Python/Recipe/498191
    David Wilson
    """
    def __init__(self):
        self._read_fd, self._write_fd = os.pipe()
        self._cond = Condition(Lock())
        self._flag = False

    def isSet(self):
        return self._flag

    def set(self):
        self._cond.acquire()
        try:
            if not self.isSet():
                os.write(self._write_fd, '1')
            self._flag = True
            self._cond.notifyAll()
        finally:
            self._cond.release()

    def clear(self):
        self._cond.acquire()
        try:
            if self.isSet():
                os.read(self._read_fd, 1)
            self._flag = False
        finally:
            self._cond.release()

    def _wait_standard(self, timeout=None):
        self._cond.acquire()
        try:
            if not self._flag:
                self._cond.wait(timeout)
        finally:
            self._cond.release()

    def _wait_selectbased(self, timeout=None):
        try:
            rfds, wfds, efds = select.select([self._read_fd], [], [], timeout)
        except select.error, v:
            if v[0] == errno.EINTR or v[0]==0:
                return
            else:
                raise


    def wait(self, timeout=None):
        if os.name=='posix':
            self._wait_selectbased(timeout)
        else:
            self._wait_standard(timeout)

    def fileno(self):
        """Return the FD number of the read side of the pipe, allows this object to
        be used with select.select()."""
        return self._read_fd

    def __int__(self):
        return self._read_fd

    def __del__(self):
        try:
            os.close(self._read_fd)
        except:
            pass
        try:
            os.close(self._write_fd)
        except:
            pass
