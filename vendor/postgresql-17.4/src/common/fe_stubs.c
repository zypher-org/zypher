/*
 * fe_stubs.c
 *   Stub implementations of backend symbols needed by frontend code.
 *
 * In a full PostgreSQL build, these are provided by the backend or by
 * frontend-specific implementations in libpgcommon/libpgport.
 */

#include "postgres_fe.h"
#include "mb/pg_wchar.h"
#include "common/fe_memutils.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <signal.h>
#include <stdint.h>

/* pg_encoding_to_char / pg_char_to_encoding are already in encnames.c */

/* unicode_normalize - referenced by saslprep.c */
/* Stub: returns a copy without normalization. In a real build this lives in
 * src/common/unicode/norm.c and is part of libpgcommon. */
int unicode_normalize(pg_wchar *dst, int dst_len, const pg_wchar *src, int src_len)
{
    if (src_len <= dst_len) {
        memcpy(dst, src, src_len * sizeof(pg_wchar));
        return src_len;
    }
    return 0;
}

/* Interrupt handling stubs */
volatile sig_atomic_t InterruptPending = 0;
void ProcessInterrupts(void) {}

/* Error reporting stubs */
void errstart(int elevel, const char *filename, int lineno, const char *funcname, const char *domain) {}
void errstart_cold(int elevel, const char *filename, int lineno, const char *funcname, const char *domain) {}
void errfinish(const char *filename, int lineno, const char *funcname) {}
char *errmsg(const char *fmt, ...) { return NULL; }
char *errmsg_internal(const char *fmt, ...) { return NULL; }
int errcode(int sqlerrcode) { return 0; }

/* psprintf - used by username.c */
char *psprintf(const char *fmt, ...)
{
    va_list args;
    char buf[1024];
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    return pg_strdup(buf);
}

/* MyProcPid - used by pqsignal.c */
int MyProcPid = 0;

/* pg_popcount_avx512 stubs - used by pg_bitutils.c */
int pg_popcount_avx512_available = 0;
uint64 pg_popcount_avx512(const char *buf, int bytes) { return 0; }
uint64 pg_popcount_masked_avx512(const char *buf, int bytes, uint8 mask) { return 0; }
