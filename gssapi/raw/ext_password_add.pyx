GSSAPI="BASE"  # This ensures that a full module is generated by Cythin

# Due to a bug in MIT Kerberos, add_cred_with_password was not properly
# exported for some time.  In order to work around this,
# add_cred_with_password is in its own file.  For more information, see:
# https://github.com/krb5/krb5/pull/244

from gssapi.raw.cython_types cimport *
from gssapi.raw.cython_converters cimport c_get_mech_oid_set
from gssapi.raw.cython_converters cimport c_create_oid_set
from gssapi.raw.cython_converters cimport c_py_ttl_to_c, c_c_ttl_to_py
from gssapi.raw.creds cimport Creds
from gssapi.raw.names cimport Name
from gssapi.raw.oids cimport OID

from gssapi.raw.misc import GSSError
from gssapi.raw.named_tuples import AddCredResult

cdef extern from "python_gssapi_ext.h":
    OM_uint32 gss_add_cred_with_password(OM_uint32 *min_stat,
                                         const gss_cred_id_t input_cred_handle,
                                         const gss_name_t desired_name,
                                         const gss_OID desired_mech,
                                         const gss_buffer_t password,
                                         gss_cred_usage_t cred_usage,
                                         OM_uint32 initiator_ttl,
                                         OM_uint32 acceptor_ttl,
                                         gss_cred_id_t *output_creds,
                                         gss_OID_set *actual_mechs,
                                         OM_uint32 *actual_init_ttl,
                                         OM_uint32 *actual_accept_ttl) nogil


def add_cred_with_password(Creds input_cred not None, Name name not None,
                           OID mech not None, password not None,
                           usage="initiate", init_lifetime=None,
                           accept_lifetime=None):

    """
    add_cred_with_password(input_cred, name, mech, password, \
usage='initiate', init_lifetime=None, accept_lifetime=None)
    Add a credential-element to a credential using provided password.

    This function is originally from Solaris and is not documented by either
    MIT or Heimdal.

    In general, it functions similarly to :func:`add_cred`.

    Args:
        input_cred (Creds): the credentials to add to
        name (~gssapi.raw.names.Name): the name to acquire credentials for
        mech (~gssapi.MechType): the desired mechanism.  Note that this is both
            singular and required
        password (bytes): the password used to acquire credentialss with
        usage (str): the usage type for the credentials: may be
            'initiate', 'accept', or 'both'
        init_lifetime (int): the lifetime for the credentials to remain valid
            when using them to initiate security contexts (or None for
            indefinite)
        accept_lifetime (int): the lifetime for the credentials to remain
            valid when using them to accept security contexts (or None for
            indefinite)

    Returns:
        AddCredResult: the actual mechanisms with which the credentials may be
        used, the actual initiator TTL, and the actual acceptor TTL (the TTLs
        may be None for indefinite or not supported)

    Raises:
        ~gssapi.exceptions.GSSError
    """

    cdef gss_buffer_desc password_buffer = gss_buffer_desc(len(password),
                                                           password)

    cdef gss_cred_usage_t c_usage
    if usage == "initiate":
        c_usage = GSS_C_INITIATE
    elif usage == "accept":
        c_usage = GSS_C_ACCEPT
    elif usage == 'both':
        c_usage = GSS_C_BOTH
    else:
        raise ValueError(f'Invalid usage "{usage}" - permitted values are '
                         '"initiate", "accept", and "both"')

    cdef OM_uint32 input_initiator_ttl = c_py_ttl_to_c(init_lifetime)
    cdef OM_uint32 input_acceptor_ttl = c_py_ttl_to_c(accept_lifetime)

    cdef gss_cred_id_t creds
    cdef gss_OID_set actual_mechs
    cdef OM_uint32 actual_initiator_ttl
    cdef OM_uint32 actual_acceptor_ttl

    cdef OM_uint32 maj_stat, min_stat

    with nogil:
        maj_stat = gss_add_cred_with_password(
            &min_stat, input_cred.raw_creds, name.raw_name, &mech.raw_oid,
            &password_buffer, c_usage, input_initiator_ttl,
            input_acceptor_ttl, &creds, &actual_mechs, &actual_initiator_ttl,
            &actual_acceptor_ttl)

    cdef Creds rc
    if maj_stat == GSS_S_COMPLETE:
        rc = Creds()
        rc.raw_creds = creds
        return AddCredResult(rc, c_create_oid_set(actual_mechs),
                             c_c_ttl_to_py(actual_initiator_ttl),
                             c_c_ttl_to_py(actual_acceptor_ttl))
    else:
        raise GSSError(maj_stat, min_stat)
