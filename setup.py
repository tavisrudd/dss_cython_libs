#!/usr/bin/env python
import os.path
import itertools
import sys

from dss.version import version

################################################################################
## This unfortunate hack required by setuptools comes from lxml's setup.py
extra_options = {}

try:
    if os.path.exists('_pretend_no_cython'):
        print '*** building without cython support ***'
        raise ImportError
    from Cython.Distutils import build_ext
    CYTHON_INSTALLED = True
    extra_options['cmdclass'] = {'build_ext': build_ext}
    # work around stupid setuptools hack by providing a fake Pyrex
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "fake_pyrex"))
except ImportError:
    CYTHON_INSTALLED = False

try:
    import pkg_resources
    try:
        pkg_resources.require("setuptools>=0.6c5")
    except pkg_resources.VersionConflict:
        from ez_setup import use_setuptools
        use_setuptools(version="0.6c5")
    #pkg_resources.require("Cython==0.9.6.10")
    from setuptools import setup
    extra_options["zip_safe"] = False
except ImportError:
    # no setuptools installed
    from distutils.core import setup

from distutils.extension import Extension

# @@TR: see http://pyyaml.org/browser/pyyaml/trunk/setup.py for more ideas

################################################################################
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
        'dss.dsl.xml.xml_escape_unicode',
        ],
    'dss.dsl.xml.serializers':[
        'dss.dsl.xml.coretypes',
        'dss.dsl.xml.xml_escape_unicode',
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
    if CYTHON_INSTALLED:
        files = [src_file_root+'.pyx']
        if os.path.exists(src_file_root+'.pxd'):
            files.append(src_file_root+'.pxd')
    else:
        files = [src_file_root+'.c']

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
    dss.dsl.Markup
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

setup(name="Damn Simple Solutions - Cython Libs",
      version=version,
      author="Tavis Rudd (Damn Simple Solutions Ltd.)",
      author_email="tavis@damnsimple.com",
      description="Damn Simple Solutions - Misc. Cython Libraries",
      keywords="",
      license='BSD',
      url="http://damnsimple.com/",
      packages=[
          'dss.sys',
          'dss.sys.services',
          'dss.sys._internal'
          'dss.pubsub',
          'dss.log',
          'dss.net',
          'dss.dsl',
          'dss.dsl.html',
          'dss.dsl.xml',
          ],
      include_dirs=['dss/sys'],
      ext_modules=get_cython_extensions(),
      **extra_options)
