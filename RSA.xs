#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <openssl/ssl.h>
#include <openssl/bn.h>

/* Key names for the rsa hash structure */

#define KEY_KEY "_Key"
#define PADDING_KEY "_Padding"
#define HASH_KEY "_Hash_Mode"

#define PACKAGE_NAME "Crypt::OpenSSL::RSA"

#define checkOpenSslCall( result ) if( ! ( result ) ) \
  croak( "OpenSSL error: %s", ERR_reason_error_string( ERR_get_error() ) );

/* convenience hv routines - I'm lazy */

void hvStore(HV* hv, char* key, SV* value)
{
    hv_delete(hv, key, strlen(key), G_DISCARD);

    if( hv_store(hv, key, strlen(key), value, 0) != NULL)
    {
        SvREFCNT_inc(value);
    }
}

SV** hvFetch(HV* hv, char* key)
{
    return hv_fetch(hv, key, strlen(key), 0);
}

/* Free the RSA key, if there is one */
void free_RSA_key(HV* rsa_HV)
{
    SV** rsa_ptr_SV_ptr;
    RSA* rsa;

    rsa_ptr_SV_ptr = hvFetch(rsa_HV, KEY_KEY);
    if( rsa_ptr_SV_ptr != NULL )
    {
        RSA_free ((RSA*) SvIV (*rsa_ptr_SV_ptr));
        hv_delete(rsa_HV, KEY_KEY, strlen(KEY_KEY), G_DISCARD);
    }
}

RSA* get_RSA_key(HV* rsa_HV)
{
    SV** rsa_ptr_SV_ptr;
    RSA* rsa;

    rsa_ptr_SV_ptr = hvFetch(rsa_HV, KEY_KEY);
    if( rsa_ptr_SV_ptr == NULL )
    {
        croak( "There is no key set" );
    }
    else
    {
        return (RSA*) SvIV (*rsa_ptr_SV_ptr);
    }
}

void set_RSA_key(HV* rsa_HV, RSA* rsa)
{
    hvStore( rsa_HV, KEY_KEY, sv_2mortal( newSViv( (IV)rsa ) ) );
}

int get_padding(HV* rsa_HV)
{
    SV** padding;

    padding = hvFetch(rsa_HV, PADDING_KEY);
    return padding == NULL ? -1 : SvIV(*padding);
}

void set_padding(HV* rsa_HV, int padding)
{
    hvStore( rsa_HV,
             PADDING_KEY,
             sv_2mortal( newSViv( (IV) padding ) ) );
}

int get_hash(HV* rsa_HV)
{
    SV** hash;

    hash = hvFetch(rsa_HV, HASH_KEY);
    return hash == NULL ? -1 : SvIV(*hash);
}

void set_hash(HV* rsa_HV, int hash)
{
    hvStore( rsa_HV, HASH_KEY, sv_2mortal( newSViv( (IV) hash ) ) );
}

char is_private(HV* rsa_HV)
{
    return( get_RSA_key(rsa_HV)->d != NULL );
}

SV* make_rsa_obj(SV* p_proto, RSA* p_rsa)
{
    RSA* rsa;
    HV* rsa_HV;
    rsa_HV = newHV();
    hvStore( rsa_HV, KEY_KEY, sv_2mortal( newSViv( (IV) p_rsa  ) ) );
    set_hash( rsa_HV, NID_sha1 );
    set_padding( rsa_HV, RSA_PKCS1_OAEP_PADDING );
    return sv_bless( newRV_noinc( (SV*) rsa_HV ),
                     ( SvROK( p_proto )
                       ? SvSTASH( SvRV( p_proto ) )
                       : gv_stashsv( p_proto, 1 ) ) );
}

int get_digest_length( int hash_method )
{
    switch( hash_method )
    {
        case NID_md5:
            return 16;
            break;
        case NID_sha1:
        case NID_ripemd160:
            return 20;
            break;
        default:
            croak( "Unknown digest hash code" );
            break;
    }
}

char* get_message_digest( SV* text_SV, int hash_method )
{
    int text_length;
    unsigned char* text;
    unsigned char* message_digest;

    text = SvPV(text_SV, text_length);

    if( New(0, message_digest, get_digest_length(hash_method), char) == NULL )
    {
        croak ( "unable to allocate buffer for message digest in package "
                PACKAGE_NAME );
    }

    switch( hash_method )
    {
        case NID_md5:
        {
            if( MD5(text, text_length, message_digest) == NULL )
            {
                croak( "failed to compute the MD5 message digest in package "
                       PACKAGE_NAME );
            }
            break;
        }

        case NID_sha1:
        {
            if( SHA1( text, text_length, message_digest ) == NULL )
            {
                croak( "failed to compute the SHA1 message digest in package "
                       PACKAGE_NAME );
            }
            break;
        }
        case NID_ripemd160:
        {
            if( RIPEMD160( text, text_length, message_digest ) == NULL )
            {
                croak( "failed to compute the SHA1 message digest in package "
                       PACKAGE_NAME );
            }
            break;
        }
        default:
        {
            croak( "Unknown digest hash code" );
            break;
        }
    }
    return message_digest;
}

BIGNUM* maybe_BN_dup(BIGNUM* bn)
{
    return bn != NULL ? BN_dup(bn) : NULL;
}

MODULE = Crypt::OpenSSL::RSA		PACKAGE = Crypt::OpenSSL::RSA
PROTOTYPES: DISABLE

BOOT:
    ERR_load_crypto_strings();

void _load_key(HV* rsa_HV, SV* private_flag_SV, SV* key_string_SV)
  PREINIT:
    int key_string_length;  /* Needed to pass to SvPV */
    char* key_string;
    char private_flag;
    RSA* rsa;
    BIO* stringBIO;
  CODE:
    /* First, remove any old rsa structures, to avoid leakage */
    free_RSA_key(rsa_HV);

    private_flag = SvTRUE( private_flag_SV );
    key_string = SvPV( key_string_SV, key_string_length );

    if( (stringBIO = BIO_new_mem_buf(key_string, key_string_length)) == NULL )
    {
        croak( "Failed to create memory BIO" );
    }

    rsa = private_flag
        ? PEM_read_bio_RSAPrivateKey( stringBIO, NULL, NULL, NULL )
        : PEM_read_bio_RSAPublicKey( stringBIO, NULL, NULL, NULL );

    BIO_set_close(stringBIO, BIO_CLOSE);
    BIO_free( stringBIO );

    if ( rsa == NULL )
    {
        croak( "Failed to read key" );
    }
    set_RSA_key(rsa_HV, rsa);

void _free_RSA_key(HV* rsa_HV)
  CODE:
    free_RSA_key( rsa_HV );

SV* _get_key_string(HV* rsa_HV, SV* private_flag_SV)
  PREINIT:
    BUF_MEM* bptr;
    BIO* stringBIO;
    RSA* rsa;
  CODE:
    stringBIO = BIO_new( BIO_s_mem() );
    if (stringBIO == NULL)
    {
        croak( "Failed to create memory BIO" );
    }

    rsa = get_RSA_key( rsa_HV );
    if( SvTRUE( private_flag_SV ) )
    {
      PEM_write_bio_RSAPrivateKey(stringBIO, rsa, NULL, NULL, 0, NULL, NULL);
    }
    else
    {
      PEM_write_bio_RSAPublicKey(stringBIO, rsa);
    }

    BIO_flush(stringBIO);
    BIO_get_mem_ptr(stringBIO, &bptr);

    RETVAL = newSVpv( bptr->data, bptr->length );

    BIO_set_close(stringBIO, BIO_CLOSE);
    BIO_free(stringBIO);
  OUTPUT:
    RETVAL

 #
 # Generate a new RSA key.  The optional third argument is a prime.
 # It defaults to 65535
 #

void _generate_key(HV* rsa_HV, SV* bitsSV, ...)
  PREINIT:
    RSA* rsa;
    unsigned long exponent;
  CODE:
    if (items > 3)
    {
        croak( "Usage: rsa->generate_key($bits [, $exponent])" );
    }

    exponent = ( items == 3 ) ? SvIV(ST(2)) : 65535;
    rsa = RSA_generate_key( SvIV(bitsSV), exponent, NULL, NULL );

    if(rsa == NULL)
    {
        croak( "OpenSSL error: %s",
               ERR_reason_error_string( ERR_get_error() ) );
    }

    set_RSA_key(rsa_HV, rsa);

SV* _new_key_from_parameters(SV* proto, BIGNUM* n, BIGNUM* e, BIGNUM* d, BIGNUM* p, BIGNUM* q)
  PREINIT:
    RSA* rsa;
    BN_CTX* ctx;
    BIGNUM* bn;
    BIGNUM* p_minus_1;
    BIGNUM* q_minus_1;
  CODE:
{
    if( !( n && e ) )
    {
        croak("At least a modulous and public key must be provided");
    }
    rsa = RSA_new();
    rsa->n = n;
    rsa->e = e;
    if( p || q )
    {
        bn = BN_new();
        ctx = BN_CTX_new();
        if( ! p )
        {
            p = BN_new();
            checkOpenSslCall( BN_div( p, bn, n, q, ctx ) );
            if( ! BN_is_zero( bn ) )
            {
                croak("q does not divide n");
            }
        }
        else if( ! q )
        {
            q = BN_new();
            checkOpenSslCall( BN_div( q, bn, n, p, ctx ) );
            if( ! BN_is_zero( bn ) )
            {
                croak("p does not divide n");
            }
        }
        rsa->p = p;
        rsa->q = q;
        p_minus_1 = BN_new();
        checkOpenSslCall( BN_sub( p_minus_1, p, BN_value_one() ) );
        q_minus_1 = BN_new();
        checkOpenSslCall( BN_sub( q_minus_1, q, BN_value_one() ) );
        if( ! d )
        {
            d = BN_new();
            checkOpenSslCall( BN_mul( bn, p_minus_1, q_minus_1, ctx ) );
            checkOpenSslCall( BN_mod_inverse( d, e, bn, ctx ) );
        }
        rsa->d = d;
        rsa->dmp1 = BN_new();
        checkOpenSslCall( BN_mod( rsa->dmp1, d, p_minus_1, ctx ) );
        rsa->dmq1 = BN_new();
        checkOpenSslCall( BN_mod( rsa->dmq1, d, q_minus_1, ctx ) );
        rsa->iqmp = BN_new();
        checkOpenSslCall( BN_mod_inverse( rsa->iqmp, q, p, ctx ) );
        BN_clear_free(bn);
        BN_clear_free(p_minus_1);
        BN_clear_free(q_minus_1);
    }
    else
    {
        rsa->d = d;
    }
    RETVAL = make_rsa_obj(proto, rsa);
}
  OUTPUT:
    RETVAL

void _get_key_parameters(HV* rsa_HV)
PPCODE:
{
    RSA* rsa;
    rsa = get_RSA_key( rsa_HV );
    XPUSHs( sv_2mortal( newSViv( (IV) maybe_BN_dup(rsa->n) ) ) );
    XPUSHs( sv_2mortal( newSViv( (IV) maybe_BN_dup(rsa->e) ) ) );
    XPUSHs( sv_2mortal( newSViv( (IV) maybe_BN_dup(rsa->d) ) ) );
    XPUSHs( sv_2mortal( newSViv( (IV) maybe_BN_dup(rsa->p) ) ) );
    XPUSHs( sv_2mortal( newSViv( (IV) maybe_BN_dup(rsa->q) ) ) );
    XPUSHs( sv_2mortal( newSViv( (IV) maybe_BN_dup(rsa->dmp1) ) ) );
    XPUSHs( sv_2mortal( newSViv( (IV) maybe_BN_dup(rsa->dmq1) ) ) );
    XPUSHs( sv_2mortal( newSViv( (IV) maybe_BN_dup(rsa->iqmp) ) ) );
}

# Encrypt plain text into cipher text.  Returns the cipher text

SV* encrypt(HV* rsa_HV, SV* plaintext_SV, ...)
  PREINIT:
    int plaintext_length;
    unsigned char* plaintext;
    unsigned char* ciphertext;
    size_t size;
    int ciphertext_length;
    RSA* rsa;
  CODE:
    plaintext = SvPV(plaintext_SV, plaintext_length);

    rsa = get_RSA_key(rsa_HV);

    size = RSA_size(rsa);
    if( New( 0,ciphertext, size, char ) == NULL )
    {
        croak ( "unable to allocate buffer for ciphertext in package "
                PACKAGE_NAME );
    }

    ciphertext_length = RSA_public_encrypt( plaintext_length,
                                            plaintext,
                                            ciphertext,
                                            rsa,
                                            get_padding(rsa_HV) );

    if (ciphertext_length < 0)
    {
        Safefree(ciphertext);
        croak( "OpenSSL error: %s",
               ERR_reason_error_string( ERR_get_error() ) );
    }

    RETVAL = newSVpv( ciphertext, size );
  OUTPUT:
    RETVAL


# Decrypt cipher text into plain text.  Returns the plain text
SV* decrypt(HV* rsa_HV, SV* ciphertext_SV)
  PREINIT:
    int ciphertext_length;  /* Needed to pass to SvPV */
    int plaintext_length;
    char* plaintext;
    char* ciphertext;
    unsigned long size;
    RSA* rsa;
  CODE:
    if( ! is_private( rsa_HV ) )
    {
        croak("Public keys cannot decrypt messages.");
    }

    ciphertext = SvPV(ciphertext_SV, ciphertext_length);

    rsa = get_RSA_key(rsa_HV);
    size = RSA_size(rsa);
    if( New( 0, plaintext, size, char ) == NULL )
    {
        croak( "unable to allocate buffer for plaintext in package "
               PACKAGE_NAME );
    }

    plaintext_length = RSA_private_decrypt(size,
                                           ciphertext,
                                           plaintext,
                                           rsa,
                                           get_padding(rsa_HV) );
    if( plaintext_length < 0 )
    {
        Safefree(plaintext);
        croak( "OpenSSL error: %s",
               ERR_reason_error_string( ERR_get_error() ) );
    }

    RETVAL = newSVpv( plaintext, plaintext_length );
    Safefree(plaintext);
  OUTPUT:
    RETVAL

int size(HV* rsa_HV)
  CODE:
    RETVAL = RSA_size( get_RSA_key( rsa_HV ) );
  OUTPUT:
    RETVAL

int check_key(HV* rsa_HV)
  CODE:
    RETVAL = RSA_check_key( get_RSA_key( rsa_HV ) );
  OUTPUT:
    RETVAL

 # Seed the PRNG with user-provided bytes; returns true if the
 # seeding was sufficient.

int _random_seed(SV* random_bytes_SV)
  PREINIT:
    int random_bytes_length;
    char* random_bytes;
  CODE:
    random_bytes = SvPV(random_bytes_SV, random_bytes_length);
    RAND_seed(random_bytes, random_bytes_length);
    RETVAL = RAND_status();
  OUTPUT:
    RETVAL

 # Returns true if the PRNG has enough seed data

int _random_status()
  CODE:
    RETVAL = RAND_status();
  OUTPUT:
    RETVAL

# Sign text. Returns the signature.

void use_md5_hash(HV* rsa_HV)
  CODE:
    set_hash( rsa_HV, NID_md5 );

void use_sha1_hash(HV* rsa_HV)
  CODE:
    set_hash( rsa_HV, NID_sha1 );

void use_ripemd160_hash(HV* rsa_HV)
  CODE:
    set_hash( rsa_HV, NID_ripemd160 );

void use_no_padding(HV* rsa_HV)
  CODE:
    set_padding(rsa_HV, RSA_NO_PADDING);

void use_pkcs1_padding(HV* rsa_HV)
  CODE:
    set_padding(rsa_HV, RSA_PKCS1_PADDING);

void use_pkcs1_oaep_padding(HV* rsa_HV)
  CODE:
    set_padding(rsa_HV, RSA_PKCS1_OAEP_PADDING);

void use_sslv23_padding(HV* rsa_HV)
  CODE:
    set_padding(rsa_HV, RSA_SSLV23_PADDING);

SV* sign (HV* rsa_HV, SV* text_SV, ...)
  PREINIT:
    unsigned char* signature;
    char* digest;
    int signature_length;
    int hash;
    RSA* rsa;
  CODE:
    if( ! is_private( rsa_HV ) )
    {
        croak("Public keys cannot sign messages.");
    }

    rsa = get_RSA_key( rsa_HV );

    if( New( 0, signature, RSA_size(rsa), char ) == NULL)
    {
        croak( "unable to allocate buffer for ciphertext in package "
               PACKAGE_NAME );
    }

    hash = get_hash( rsa_HV );
    digest = get_message_digest( text_SV, hash );
    if ( ! RSA_sign( hash,
                     digest,
                     get_digest_length( hash ),
                     signature,
                     &signature_length,
                     rsa ) )
    {
        croak( "OpenSSL error: %s",
               ERR_reason_error_string( ERR_get_error() ) );
    }
    Safefree(digest);
    RETVAL = newSVpvn( signature, signature_length );
    Safefree( signature );
  OUTPUT:
    RETVAL

# Verify signature. Returns 1 if correct, 0 otherwise.

void verify (HV* rsa_HV, SV* text_SV, SV* sig_SV, ...)
PPCODE:
{
    unsigned char* sig;
    char* digest;
    RSA* rsa;
    int sig_length;
    int hash;
    int result;

    if( is_private( rsa_HV ) )
    {
        croak("Secret keys should not check signatures.");
    }

    sig = SvPV( sig_SV, sig_length );
    rsa = get_RSA_key(rsa_HV);
    if (RSA_size(rsa) < sig_length)
    {
        croak( "Signature longer than key" );
    }

    hash = get_hash( rsa_HV );
    digest = get_message_digest( text_SV, hash );
    result = RSA_verify( hash,
                         digest,
                         get_digest_length( hash ),
                         sig,
                         sig_length,
                         rsa );
    Safefree( digest );
    switch( result )
    {
        case 0: /* FIXME - could there be an error in this case? */
            XSRETURN_NO;
            break;
        case 1:
            XSRETURN_YES;
            break;
        default:
            croak ( "something went wrong in " PACKAGE_NAME );
            break;
    }
}
