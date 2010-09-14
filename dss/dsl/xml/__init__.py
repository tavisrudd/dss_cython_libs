"""Provides an s-expression like syntax for creating XML documents and
fragments in pure Python.

This was inspired by Stan (and Breve), but is far simpler and more
flexible.
"""
from dss.dsl.VisitorMap import VisitorMap
from dss.dsl.safe_strings import safe_unicode
from dss.dsl.xml.coretypes import (
    XmlDoc, XmlName, XmlEntityRef, XmlAttributes, XmlAttribute,
    XmlElement, XmlElementProto, XmlCData, Comment)

from dss.dsl.xml.serializers import XmlSerializer
from dss.dsl.Serializer import Serializer

# silence pyflakes:
(
    VisitorMap,
    Serializer, XmlSerializer,
    safe_unicode,
    XmlDoc, XmlName, XmlEntityRef, XmlAttributes, XmlAttribute,
    XmlElement, XmlElementProto, XmlCData, Comment)

def serialize(o):
    return XmlSerializer().serialize(o)
