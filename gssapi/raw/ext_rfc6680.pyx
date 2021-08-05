GSSAPI="BASE"  # This ensures that a full module is generated by Cython

from gssapi.raw.cython_types cimport *
from gssapi.raw.ext_buffer_sets cimport *
from gssapi.raw.names cimport Name
from gssapi.raw.oids cimport OID

from gssapi.raw.misc import GSSError
from gssapi.raw.named_tuples import InquireNameResult, GetNameAttributeResult

cdef extern from "python_gssapi_ext.h":
    OM_uint32 gss_display_name_ext(OM_uint32 *min_stat, gss_name_t name,
                                   gss_OID name_type,
                                   gss_buffer_t output_name) nogil

    OM_uint32 gss_inquire_name(OM_uint32 *min_stat, gss_name_t name,
                               int *name_is_mn, gss_OID *mech_type,
                               gss_buffer_set_t *attrs) nogil

    OM_uint32 gss_get_name_attribute(OM_uint32 *min_stat, gss_name_t name,
                                     gss_buffer_t attr, int *authenticated,
                                     int *complete, gss_buffer_t value,
                                     gss_buffer_t display_value,
                                     int *more) nogil

    OM_uint32 gss_set_name_attribute(OM_uint32 *min_stat, gss_name_t name,
                                     int complete, gss_buffer_t attr,
                                     gss_buffer_t value) nogil

    OM_uint32 gss_delete_name_attribute(OM_uint32 *min_stat, gss_name_t name,
                                        gss_buffer_t attr) nogil

    OM_uint32 gss_export_name_composite(OM_uint32 *min_stat, gss_name_t name,
                                        gss_buffer_t exported_name) nogil

    # GSS_C_NT_COMPOSITE_EXPORT lives in ext_rfc6680_comp_oid.pyx


def display_name_ext(Name name not None, OID name_type not None):
    """
    display_name_ext(name, name_type)
    Display the given Name using the given name type.

    This method attempts to display the given Name using the syntax of
    the given name type.  If this is not possible, an appropriate error
    will be raised.

    Args:
        name (~gssapi.raw.names.Name): the name to display
        name_type (~gssapi.OID): the name type (see NameType) to use to
            display the given name

    Returns:
        bytes: the displayed name

    Raises:
        ~gssapi.exceptions.OperationUnavailableError: the given name could not
            be displayed using the given name type
    """

    # GSS_C_EMPTY_BUFFER
    cdef gss_buffer_desc output_name = gss_buffer_desc(0, NULL)

    cdef OM_uint32 maj_stat, min_stat

    maj_stat = gss_display_name_ext(&min_stat, name.raw_name,
                                    &name_type.raw_oid, &output_name)

    if maj_stat == GSS_S_COMPLETE:
        name_text = (<char*>output_name.value)[:output_name.length]
        gss_release_buffer(&min_stat, &output_name)
        return name_text
    else:
        raise GSSError(maj_stat, min_stat)


def inquire_name(Name name not None, mech_name=True, attrs=True):
    """
    inquire_name(name, mech_name=True, attrs=True)
    Get information about a Name.

    This method retrives information about the given name, including
    the set of attribute names for the given name, as well as whether or
    not the name is a mechanism name.  Additionally, if the given name is
    a mechanism name, the associated mechansim is returned as well.

    Args:
        name (~gssapi.raw.names.Name): the name about which to inquire
        mech_name (bool): whether or not to retrieve if this name
            is a mech_name (and the associate mechanism)
        attrs (bool): whether or not to retrieve the attribute name list

    Returns:
        InquireNameResult: the set of attribute names for the given name,
            whether or not the name is a Mechanism Name, and potentially
            the associated mechanism if it is a Mechanism Name

    Raises:
        ~gssapi.exceptions.GSSError
    """

    cdef int *name_is_mn_ptr = NULL
    cdef gss_OID *mn_mech_ptr = NULL
    cdef gss_buffer_set_t *attr_names_ptr = NULL

    cdef gss_buffer_set_t attr_names = GSS_C_NO_BUFFER_SET
    if attrs:
        attr_names_ptr = &attr_names

    cdef int name_is_mn = 0
    cdef gss_OID mn_mech
    if mech_name:
        name_is_mn_ptr = &name_is_mn
        mn_mech_ptr = &mn_mech

    cdef OM_uint32 maj_stat, min_stat

    maj_stat = gss_inquire_name(&min_stat, name.raw_name, name_is_mn_ptr,
                                mn_mech_ptr, attr_names_ptr)

    cdef int i
    cdef OID py_mech = None
    if maj_stat == GSS_S_COMPLETE:
        py_attr_names = []

        if attr_names != GSS_C_NO_BUFFER_SET:
            for i in range(attr_names.count):
                attr_name = attr_names.elements[i]
                py_attr_names.append(
                    (<char*>attr_name.value)[:attr_name.length]
                )

            gss_release_buffer_set(&min_stat, &attr_names)

        if name_is_mn:
            py_mech = OID()
            py_mech.raw_oid = mn_mech[0]

        return InquireNameResult(py_attr_names, <bint>name_is_mn, py_mech)
    else:
        raise GSSError(maj_stat, min_stat)


def set_name_attribute(Name name not None, attr not None, value not None,
                       bint complete=False):
    """
    set_name_attribute(name, attr, value, complete=False)
    Set the value(s) of a name attribute.

    This method sets the value(s) of the given attribute on the given name.

    Note that this functionality more closely matches the pseudo-API
    presented in RFC 6680, not the C API (which uses multiple calls to
    add multiple values).  However, multiple calls to this method will
    continue adding values, so :func:`delete_name_attribute` must be
    used in between calls to "clear" the values.

    Args:
        name (~gssapi.raw.names.Name): the Name on which to set the attribute
        attr (bytes): the name of the attribute
        value (list): a list of bytes objects to use as the value(s)
        complete (bool): whether or not to mark this attribute's value
            set as being "complete"

    Raises:
        ~gssapi.exceptions.OperationUnavailableError: the given attribute name
            is unknown or could not be set
    """

    cdef gss_buffer_desc attr_buff = gss_buffer_desc(len(attr), attr)
    cdef gss_buffer_desc val_buff

    cdef OM_uint32 maj_stat, min_stat

    cdef size_t value_len = len(value)
    cdef size_t i
    for val in value:
        val_buff = gss_buffer_desc(len(val), val)
        i += 1
        if i == value_len:
            maj_stat = gss_set_name_attribute(&min_stat, name.raw_name,
                                              complete, &attr_buff, &val_buff)
        else:
            maj_stat = gss_set_name_attribute(&min_stat, name.raw_name, 0,
                                              &attr_buff, &val_buff)

        if maj_stat != GSS_S_COMPLETE:
            raise GSSError(maj_stat, min_stat)


def get_name_attribute(Name name not None, attr not None, more=None):
    """
    get_name_attribute(name, attr, more=None)
    Get the value(s) of a name attribute.

    This method retrieves the value(s) of the given attribute
    for the given Name.

    Note that this functionality matches pseudo-API presented
    in RFC 6680, not the C API (which uses a state variable and
    multiple calls to retrieve multiple values).

    Args:
        name (~gssapi.raw.names.Name): the Name from which to get the attribute
        attr (bytes): the name of the attribute

    Returns:
        GetNameAttributeResult: the raw version of the value(s),
        the human-readable version of the value(s), whether
        or not the attribute was authenticated, and whether or
        not the attribute's value set was marked as complete

    Raises:
        ~gssapi.exceptions.OperationUnavailableError: the given attribute is
            unknown or unset
    """
    cdef gss_buffer_desc attr_buff = gss_buffer_desc(len(attr), attr)

    cdef gss_buffer_desc val_buff = gss_buffer_desc(0, NULL)
    cdef gss_buffer_desc displ_val_buff = gss_buffer_desc(0, NULL)
    cdef int complete
    cdef int authenticated

    cdef int more_val = -1
    py_vals = []
    py_displ_vals = []

    cdef OM_uint32 maj_stat, min_stat

    while more_val != 0:
        maj_stat = gss_get_name_attribute(&min_stat, name.raw_name,
                                          &attr_buff,
                                          &authenticated, &complete,
                                          &val_buff, &displ_val_buff,
                                          &more_val)

        if maj_stat == GSS_S_COMPLETE:
            py_vals.append((<char*>val_buff.value)[:val_buff.length])
            py_displ_vals.append(
                (<char*>displ_val_buff.value)[:displ_val_buff.length])

            gss_release_buffer(&min_stat, &val_buff)
            gss_release_buffer(&min_stat, &displ_val_buff)
        else:
            raise GSSError(maj_stat, min_stat)

    return GetNameAttributeResult(py_vals, py_displ_vals, <bint>authenticated,
                                  <bint>complete)


def delete_name_attribute(Name name not None, attr not None):
    """
    delete_name_attribute(name, attr)
    Remove an attribute from a name.

    This method removes an attribute from a Name.  This method may be
    used before :func:`set_name_attribute` clear the values of an attribute
    before setting a new value (making the latter method work like a 'set'
    operation instead of an 'add' operation).

    Note that the removal of certain attributes may not be allowed.

    Args:
        name (~gssapi.raw.names.Name): the name to remove the attribute from
        attr (bytes): the name of the attribute

    Raises:
        ~gssapi.exceptions.OperationUnavailableError
        ~gssapi.exceptions.UnauthorizedError
    """

    cdef gss_buffer_desc attr_buff = gss_buffer_desc(len(attr), attr)

    cdef OM_uint32 maj_stat, min_stat

    maj_stat = gss_delete_name_attribute(&min_stat, name.raw_name,
                                         &attr_buff)

    if maj_stat != GSS_S_COMPLETE:
        raise GSSError(maj_stat, min_stat)


def export_name_composite(Name name not None):
    """
    export_name_composite(name)
    Export a name, preserving attribute information.

    This method functions similarly to :func:`export_name`, except that
    it preserves attribute information.  The resulting bytes may be imported
    using :func:`import_name` with the :attr:`NameType.composite_export`
    name type.

    Note:
        Some versions of MIT Kerberos require you to either canonicalize a name
        once it has been imported with composite-export name type, or to import
        using the normal export name type.

    Args:
        name (~gssapi.raw.names.Name): the name to export

    Returns:
        bytes: the exported composite name

    Raises:
        ~gssapi.exceptions.GSSError
    """

    cdef gss_buffer_desc res = gss_buffer_desc(0, NULL)

    cdef OM_uint32 maj_stat, min_stat

    maj_stat = gss_export_name_composite(&min_stat, name.raw_name, &res)

    if maj_stat == GSS_S_COMPLETE:
        py_res = (<char*>res.value)[:res.length]
        gss_release_buffer(&min_stat, &res)
        return py_res
    else:
        raise GSSError(maj_stat, min_stat)
