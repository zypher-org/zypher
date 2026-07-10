#include <ma_global.h>
#include <ma_sys.h>
#include <ma_common.h>
#include <ma_hash.h>
#include <ma_crypt.h>
#include <string.h>
#include <stdlib.h>

#define HASH_BLOCK_SIZE 64

struct hash_ctx {
    unsigned int algorithm;
    uint32_t state[16];
    uint64_t count;
    unsigned char buffer[HASH_BLOCK_SIZE];
};

static uint32_t rotl32(uint32_t x, int n) {
    return (x << n) | (x >> (32 - n));
}

static uint32_t rotr32(uint32_t x, int n) {
    return (x >> n) | (x << (32 - n));
}

static void sha1_transform(uint32_t state[5], const unsigned char block[HASH_BLOCK_SIZE]) {
    uint32_t w[80];
    uint32_t a, b, c, d, e, temp;
    int i;

    for (i = 0; i < 16; i++) {
        w[i] = ((uint32_t)block[i * 4] << 24) |
               ((uint32_t)block[i * 4 + 1] << 16) |
               ((uint32_t)block[i * 4 + 2] << 8)  |
               ((uint32_t)block[i * 4 + 3]);
    }
    for (i = 16; i < 80; i++) {
        w[i] = rotl32(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], 1);
    }

    a = state[0]; b = state[1]; c = state[2]; d = state[3]; e = state[4];

    for (i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20) {
            f = (b & c) | ((~b) & d);
            k = 0x5A827999;
        } else if (i < 40) {
            f = b ^ c ^ d;
            k = 0x6ED9EBA1;
        } else if (i < 60) {
            f = (b & c) | (b & d) | (c & d);
            k = 0x8F1BBCDC;
        } else {
            f = b ^ c ^ d;
            k = 0xCA62C1D6;
        }
        temp = rotl32(a, 5) + f + e + k + w[i];
        e = d;
        d = c;
        c = rotl32(b, 30);
        b = a;
        a = temp;
    }

    state[0] += a; state[1] += b; state[2] += c; state[3] += d; state[4] += e;
}

static const uint32_t sha256_k[64] = {
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
    0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
    0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
    0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
    0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
    0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
    0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
    0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
    0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
};

static uint32_t sha256_sigma0(uint32_t x) {
    return rotr32(x, 2) ^ rotr32(x, 13) ^ rotr32(x, 22);
}

static uint32_t sha256_sigma1(uint32_t x) {
    return rotr32(x, 6) ^ rotr32(x, 11) ^ rotr32(x, 25);
}

static uint32_t sha256_lower_sigma0(uint32_t x) {
    return rotr32(x, 7) ^ rotr32(x, 18) ^ (x >> 3);
}

static uint32_t sha256_lower_sigma1(uint32_t x) {
    return rotr32(x, 17) ^ rotr32(x, 19) ^ (x >> 10);
}

static void sha256_transform(uint32_t state[8], const unsigned char block[HASH_BLOCK_SIZE]) {
    uint32_t w[64];
    uint32_t a, b, c, d, e, f, g, h, t1, t2;
    int i;

    for (i = 0; i < 16; i++) {
        w[i] = ((uint32_t)block[i * 4] << 24) |
               ((uint32_t)block[i * 4 + 1] << 16) |
               ((uint32_t)block[i * 4 + 2] << 8)  |
               ((uint32_t)block[i * 4 + 3]);
    }
    for (i = 16; i < 64; i++) {
        w[i] = sha256_lower_sigma1(w[i-2]) + w[i-7] + sha256_lower_sigma0(w[i-15]) + w[i-16];
    }

    a = state[0]; b = state[1]; c = state[2]; d = state[3];
    e = state[4]; f = state[5]; g = state[6]; h = state[7];

    for (i = 0; i < 64; i++) {
        t1 = h + sha256_sigma1(e) + ((e & f) ^ ((~e) & g)) + sha256_k[i] + w[i];
        t2 = sha256_sigma0(a) + ((a & b) ^ (a & c) ^ (b & c));
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }

    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

static void hash_init(struct hash_ctx *ctx, unsigned int algorithm) {
    ctx->algorithm = algorithm;
    ctx->count = 0;
    if (algorithm == MA_HASH_SHA1) {
        ctx->state[0] = 0x67452301;
        ctx->state[1] = 0xEFCDAB89;
        ctx->state[2] = 0x98BADCFE;
        ctx->state[3] = 0x10325476;
        ctx->state[4] = 0xC3D2E1F0;
    } else {
        ctx->state[0] = 0x6A09E667; ctx->state[1] = 0xBB67AE85;
        ctx->state[2] = 0x3C6EF372; ctx->state[3] = 0xA54FF53A;
        ctx->state[4] = 0x510E527F; ctx->state[5] = 0x9B05688C;
        ctx->state[6] = 0x1F83D9AB; ctx->state[7] = 0x5BE0CD19;
    }
}

static void hash_update(struct hash_ctx *ctx, const unsigned char *data, size_t len) {
    size_t idx;

    idx = (size_t)(ctx->count & 0x3F);
    ctx->count += len;

    if (idx) {
        size_t fill = HASH_BLOCK_SIZE - idx;
        if (len < fill) {
            memcpy(ctx->buffer + idx, data, len);
            return;
        }
        memcpy(ctx->buffer + idx, data, fill);
        if (ctx->algorithm == MA_HASH_SHA1) {
            sha1_transform(ctx->state, ctx->buffer);
        } else {
            sha256_transform(ctx->state, ctx->buffer);
        }
        data += fill;
        len -= fill;
    }

    while (len >= HASH_BLOCK_SIZE) {
        if (ctx->algorithm == MA_HASH_SHA1) {
            sha1_transform(ctx->state, data);
        } else {
            sha256_transform(ctx->state, data);
        }
        data += HASH_BLOCK_SIZE;
        len -= HASH_BLOCK_SIZE;
    }

    if (len > 0) {
        memcpy(ctx->buffer, data, len);
    }
}

static void hash_final(struct hash_ctx *ctx, unsigned char *digest) {
    uint64_t bits = ctx->count * 8;
    size_t idx = (size_t)(ctx->count & 0x3F);
    int i, n;

    ctx->buffer[idx++] = 0x80;

    if (idx > 56) {
        memset(ctx->buffer + idx, 0, HASH_BLOCK_SIZE - idx);
        if (ctx->algorithm == MA_HASH_SHA1) {
            sha1_transform(ctx->state, ctx->buffer);
        } else {
            sha256_transform(ctx->state, ctx->buffer);
        }
        idx = 0;
    }
    memset(ctx->buffer + idx, 0, 56 - idx);

    for (i = 0; i < 8; i++) {
        ctx->buffer[56 + i] = (unsigned char)(bits >> (56 - i * 8));
    }

    if (ctx->algorithm == MA_HASH_SHA1) {
        sha1_transform(ctx->state, ctx->buffer);
        n = 5;
    } else {
        sha256_transform(ctx->state, ctx->buffer);
        n = 8;
    }

    for (i = 0; i < n; i++) {
        digest[i * 4]     = (unsigned char)(ctx->state[i] >> 24);
        digest[i * 4 + 1] = (unsigned char)(ctx->state[i] >> 16);
        digest[i * 4 + 2] = (unsigned char)(ctx->state[i] >> 8);
        digest[i * 4 + 3] = (unsigned char)(ctx->state[i]);
    }
}

MA_HASH_CTX *ma_hash_new(unsigned int algorithm) {
    struct hash_ctx *ctx;

    if (algorithm != MA_HASH_SHA1 && algorithm != MA_HASH_SHA256) {
        return NULL;
    }
    ctx = (struct hash_ctx *)calloc(1, sizeof(struct hash_ctx));
    if (!ctx) return NULL;
    hash_init(ctx, algorithm);
    return (MA_HASH_CTX *)ctx;
}

void ma_hash_free(MA_HASH_CTX *ctx) {
    if (ctx) free(ctx);
}

void ma_hash_input(MA_HASH_CTX *ctx, const unsigned char *buffer, size_t len) {
    hash_update((struct hash_ctx *)ctx, buffer, len);
}

void ma_hash_result(MA_HASH_CTX *ctx, unsigned char *digest) {
    hash_final((struct hash_ctx *)ctx, digest);
}

const char *_mariadb_compression_algorithm_str(enum enum_ma_compression_algorithm algorithm) {
    (void)algorithm;
    return "none";
}
