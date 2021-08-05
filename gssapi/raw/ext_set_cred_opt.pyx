"""
gss_set_cred_option

Provides a way to set options on a credential based on the OID specified. A
common use case is to set the GSS_KRB5_CRED_NO_CI_FLAGS_X on a Kerberos
credential. This is used for interoperability with Microsoft's SSPI.

Note this function is commonly lumped with the GGF extensions but they are not
part of the GGF IETF draft so it's separated into it's own file.

Closest draft IETF document for the gss_set_cred_option can be found at
https://tools.ietf.org/html/draft-williams-kitten-channel-bound-flag-01
"""
GSSAPI="BASE"  # This ensures that a full module is generated by Cython

from gssapi.raw.cython_types cimport *
from gssapi.raw.ext_buffer_sets cimport *
from gssapi.raw.misc import GSSError
from gssapi.raw.oids cimport OID
from gssapi.raw.creds cimport Creds

cdef extern from "python_gssapi_ext.h":

    OM_uint32 gss_set_cred_option(OM_uint32 *minor_status,
                                  gss_cred_id_t *cred,
                                  const gss_OID desired_object,
                                  const gss_buffer_t value) nogil


def set_cred_option(OID desired_aspect not None, Creds creds=None, value=None):
    """
    set_cred_option(desired_aspect, creds=None, value=None)

    This method is used to set options of a :class:`Creds` object based on
    an OID key. The options that can be set depends on the mech the credentials
    were created with.

    An example of how this can be used would be to set the
    GSS_KRB5_CRED_NO_CI_FLAGS_X on a Kerberos credential. The OID string for
    this flag is '1.2.752.43.13.29' and it requires no value to be set. This
    must be set before the SecurityContext was initialised with the
    credentials.

    Args:
        desired_aspect (~gssapi.OID): the desired aspect of the Credential to
            set.
        cred_handle (Creds): the Credentials to set, or None to create a new
            credential.
        value (bytes): the value to set on the desired aspect of the Credential
            or None to send GSS_C_EMPTY_BUFFER.

    Returns:
        Creds: The output credential.

    Raises:
        ~gssapi.exceptions.GSSError
    """

    cdef gss_buffer_desc value_buffer
    if value is not None:
        value_buffer = gss_buffer_desc(len(value), value)
    else:
        # GSS_C_EMPTY_BUFFER
        value_buffer = gss_buffer_desc(0, NULL)

    cdef Creds output_creds = creds
    if output_creds is None:
        output_creds = Creds()

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_set_cred_option(&min_stat,
                                       &output_creds.raw_creds,
                                       &desired_aspect.raw_oid,
                                       &value_buffer)

    if maj_stat == GSS_S_COMPLETE:
        return output_creds
    else:
        raise GSSError(maj_stat, min_stat)
