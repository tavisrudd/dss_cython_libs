"""Provides all html tags and character entities, with lowercase names.
"""
from dss.dsl.safe_strings import safe_unicode
from dss.dsl.xml.coretypes import (
    XmlCData, XmlName, XmlElement, XmlElementProto, XmlEntityRef, Comment)
from dss.dsl.html.character_entities import html_entities as _html_entities

class _GetAttrDict(dict):
    def __getattr__(self, k):
        return self[k]

entities = _GetAttrDict((alpha, XmlEntityRef(*(alpha, num, descr)))
                        for (alpha, num, descr) in _html_entities)

XHTML_xmlns = 'xmlns="http://www.w3.org/1999/xhtml'
XHTML_DTD = safe_unicode(
    '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"'
    ' "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">\n''')

_non_empty_html_tag_names = [
    'a','abbr','acronym','address','applet',
    'b','bdo','big','blockquote', 'body','button',
    'caption','center','cite','code','colgroup',
    'dd','dfn','div','dl','dt',
    'em',
    'fieldset','font','form','frameset',
    'h1','h2','h3','h4','h5','h6','head','html',
    'i','iframe','ins',
    'kbd',
    'label','legend','li',
    'menu',
    'noframes','noscript',
    'ol','optgroup','option',
    'pre',
    'q',
    's','samp', 'select','small','span','strike','strong','style','sub','sup',
    'table','tbody','td','textarea','tfoot','th','thead','title','tr','tt',
    'u','ul',
    'var']
_empty_html_tag_names = [
    'area', 'base', 'basefont', 'br', 'col', 'frame', 'hr',
    'img', 'input', 'isindex', 'link', 'meta', 'p', 'param', 'script']

class _Script(XmlElement):
    def __getitem__(self, children):
        self._add_children(['\n//', XmlCData(['\n', children, '\n//']), '\n'])
        return self

_htmltags = _GetAttrDict(
    [(n, XmlElementProto(XmlName(n), can_be_empty=False))
     for n in _non_empty_html_tag_names]
    + [(n, XmlElementProto(XmlName(n), can_be_empty=True)) for n in _empty_html_tag_names]
    + list(dict(comment=Comment,
                script=XmlElementProto(XmlName('script'), element_class=_Script),
                ln='\n').items()))

for k, v in _htmltags.iteritems():
    exec '%s = _htmltags["%s"]'%(k, k)

__all__ = _htmltags.keys() + [
    'entities', 'safe_unicode', 'XHTML_xmlns', 'XHTML_DTD', 'Comment']
