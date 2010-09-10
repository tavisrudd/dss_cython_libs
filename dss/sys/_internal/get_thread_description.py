import os
import commands
import thread
import threading

def get_thread_description():
    threadId = thread.get_ident()
    threadName = threading.currentThread().getName()
    out = 'name="%s" id=%s'%(threadName, threadId)
    if os.name == 'posix':
        shellProcessId = commands.getoutput('echo $$').strip()
        out = out+' processId=%s'%shellProcessId
    return out
