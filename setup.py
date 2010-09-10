#!/usr/bin/env python
import os.path
import commands
import itertools

from distutils.core import setup
from setuptools import find_packages
from dss.version import version
from distutils.extension import Extension
from Cython.Distutils import build_ext

##################################################
pxd_files = commands.getoutput('find dss -name "*pxd"').split()
extension_dependencies = {
    'dss.sys.Queue':['dss.sys.lock'],
    'dss.sys.LRUCache':[
        'dss.sys.lock',
        'dss.sys.time_of_day',
        ],

    'dss.net.NetworkService':[
        'dss.sys.services.Service',
        'dss.sys.services.ThreadPool',
        ],
    'dss.net.IOEventReactor':[
        'dss.sys.services.Service',
        'dss.sys.time_of_day',
        ],
    'dss.net.IOEventHandler':[],

    #
    'dss.net.Acceptor':[
        'dss.sys.services.Service',
        'dss.sys.services.ThreadPool',
        'dss.sys.time_of_day',
        ],
    #

    'dss.pubsub.MessageBus':[
        'dss.sys.time_of_day',
        'dss.sys.services.Service',
        'dss.sys.Queue',
        'dss.pubsub._Channel',
        ],

    'dss.pubsub.Subscripton':[
        'dss.sys.time_of_day',
        ],
    'dss.pubsub._Channel':[
        'dss.sys.time_of_day',
        'dss.pubsub.Subscription',
        'dss.pubsub.MessageBus',
        ],
    'dss.log.LogChannel':[
        'dss.pubsub._Channel',
        ],
    #
    'dss.dsl.Visitor':[
        'dss.dsl.Walker',
        'dss.dsl.VisitorMap',
        ],
    'dss.dsl.Walker':[
        'dss.dsl.Visitor',
        'dss.dsl.VisitorMap',
        ],
    'dss.dsl.Serializer':[
        'dss.dsl.Walker',
        'dss.dsl.Visitor',
        'dss.dsl.VisitorMap',
        'dss.dsl.safe_strings',
        'dss.dsl.xml.xml_escape_unicode',
        ],
    'dss.dsl.xml.serializers':[
        'dss.dsl.xml.coretypes',
        'dss.dsl.xml.xml_escape_unicode',
        'dss.dsl.safe_strings',
        'dss.dsl.Serializer',
        'dss.dsl.Walker',
        'dss.dsl.VisitorMap',
        'dss.dsl.Visitor'],

    #
    'dss.sys.services.ThreadPool':[
        'dss.sys.lock',
        'dss.sys.time_of_day',
        'dss.sys.services.Service',
        'dss.sys.Queue',
        ],
    }

c_src_files = {'dss.sys.time_of_day':['dss/sys/_time_of_day.c'],
               }

def get_src_file_paths(module_name):
    src_file_root = module_name.replace('.', os.path.sep)
    files = [src_file_root+'.pyx']
    if src_file_root+'.pxd' in pxd_files:
        files.append(src_file_root+'.pxd')
    if module_name in c_src_files:
        files.extend(c_src_files[module_name])
    return files

def get_dep_file_paths(module_name):
    deps_stack = extension_dependencies.get(module_name, [])
    final_deps = []
    while deps_stack:
        dep = deps_stack.pop()
        final_deps.append(dep)
        if dep in extension_dependencies:
            deps_stack.extend(extension_dependencies[dep])
    return list(itertools.chain(*[get_src_file_paths(dep_mod) for dep_mod in final_deps]))

def cython_ext(module_name):
    return Extension(
        module_name,
        get_src_file_paths(module_name),
        depends=get_dep_file_paths(module_name))

def get_cython_extensions():
    return [cython_ext(modname)
            for modname in
            [ln.strip() for ln in """
    dss.sys.time_of_day
    dss.sys.lock
    dss.sys.Queue
    dss.sys.LRUCache

    dss.dsl.safe_strings
    dss.dsl.Visitor
    dss.dsl.VisitorMap
    dss.dsl.Walker
    dss.dsl.Serializer
    dss.dsl.xml.xml_escape_unicode
    dss.dsl.xml.coretypes
    dss.dsl.xml.serializers

    dss.sys.services.ThreadPool
    dss.sys.services.Service

    dss.net.Acceptor
    dss.net.NetworkService
    #dss.net._epoll
    dss.net.IOEventReactor
    dss.net.IOEventHandler
    dss.net.BufferedSocketIOHandler

    dss.pubsub.MessageBus
    dss.pubsub.Subscription
    dss.pubsub._Channel
    dss.log.LogChannel

    """.splitlines() if not ln.strip().startswith('#')]
            if modname]

setup(name = "Damn Simple Systems - Core Modules",
      version = version,
      author = "Tavis Rudd (Damn Simple Solutions Ltd.)",
      author_email = "tavis@damnsimple.com",
      description = "Damn Simple Systems - Core Modules/Libraries",
      keywords = "",
      license = 'BSD',
      url = "http://damnsimple.com/",

      packages=['dss.'+p for p in find_packages('dss')],
      zip_safe=False,
      include_dirs=['dss/sys'],
      ext_modules=get_cython_extensions(),
      cmdclass={'build_ext': build_ext},
      )
