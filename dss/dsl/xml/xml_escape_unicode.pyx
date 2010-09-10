cpdef object xml_escape_unicode(s):
    """A 'partially' optimized replacement for `cgi.escape`.
    """
    cdef Py_UNICODE *inp = PyUnicode_AsUnicode(s)
    if inp is NULL:
        raise TypeError("xml_escape_unicode requires unicode not strings")

    cdef Py_ssize_t slen, i
    cdef bint gt, lt, amp, quot, apos
    cdef char c
    i = gt = lt = amp = quot = 0
    slen = PyUnicode_GetSize(s)

    for i from 0 <= i < slen:
        c = inp[i]
        if (amp and lt and gt and quot and apos):
            break
        elif c == c'&':
            amp = 1
        elif c == c'<':
            lt = 1
        elif c == c'>':
            gt = 1
        elif c == c'"':
            quot = 1
        elif c == c"'":
            apos = 1

    # @@TR: this could be optimized, but it would only make a
    # difference in cases where the string contains several of the
    # chars to be escaped.  In cases where the string contains nothing
    # to be escaped, our version is already fast enough.
    # see jinja2/_speedups.c
    # and
    # http://bzr.arbash-meinel.com/mirrors/bzr.dev/bzrlib/_rio_pyx.pyx
    # for ideas
    if amp: # must come first
        s = PyUnicode_Replace(s, "&", "&amp;", -1)
    if lt:
        s = PyUnicode_Replace(s, "<", "&lt;", -1)
    if gt:
        s = PyUnicode_Replace(s, ">", "&gt;", -1)
    if quot:
        s = PyUnicode_Replace(s, '"', "&#34;", -1)
    if apos:
        s = PyUnicode_Replace(s, "'", "&#39;", -1)
    return s
