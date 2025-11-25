#include "../lib.c"   // keep if your build flow expects it

// Memory-mapped UART address used by RSD
#define UART_ADDR ((volatile char*)0x40002000)

/* ------------ basic serial helpers ------------ */

static inline void putc(char c) {
    *UART_ADDR = c;
}

static void puts(const char *s) {
    while (*s) {
        putc(*s++);
    }
}

// print one byte as 2 hex digits (uppercase)
static void print_hex2(unsigned char b) {
    static const char hex[] = "0123456789ABCDEF";
    putc(hex[(b >> 4) & 0xF]);
    putc(hex[b & 0xF]);
}

/* ------------ SHA-256 implementation ------------ */

typedef unsigned int  u32;
typedef unsigned char u8;

#define SHA256_BLOCK_SIZE 32  // bytes

typedef struct {
    u8  data[64];
    u32 datalen;
    u32 bitlen[2];   // 64-bit length as two 32-bit words
    u32 state[8];
} SHA256_CTX;

#define ROTRIGHT(a,b) (((a) >> (b)) | ((a) << (32-(b))))

#define CH(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))

#define EP0(x) (ROTRIGHT((x), 2) ^ ROTRIGHT((x),13) ^ ROTRIGHT((x),22))
#define EP1(x) (ROTRIGHT((x), 6) ^ ROTRIGHT((x),11) ^ ROTRIGHT((x),25))
#define SIG0(x) (ROTRIGHT((x), 7) ^ ROTRIGHT((x),18) ^ ((x) >> 3))
#define SIG1(x) (ROTRIGHT((x),17) ^ ROTRIGHT((x),19) ^ ((x) >>10))

static const u32 k[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,
    0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
    0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
    0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,
    0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
    0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
    0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,
    0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
    0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

static void sha256_transform(SHA256_CTX *ctx, const u8 data[])
{
    u32 a,b,c,d,e,f,g,h,i,j,t1,t2,m[64];

    // message schedule
    for (i = 0, j = 0; i < 16; ++i, j += 4) {
        m[i]  = ((u32)data[j]     << 24);
        m[i] |= ((u32)data[j + 1] << 16);
        m[i] |= ((u32)data[j + 2] << 8);
        m[i] |= ((u32)data[j + 3]);
    }
    for ( ; i < 64; ++i) {
        m[i] = SIG1(m[i-2]) + m[i-7] + SIG0(m[i-15]) + m[i-16];
    }

    a = ctx->state[0];
    b = ctx->state[1];
    c = ctx->state[2];
    d = ctx->state[3];
    e = ctx->state[4];
    f = ctx->state[5];
    g = ctx->state[6];
    h = ctx->state[7];

    for (i = 0; i < 64; ++i) {
        t1 = h + EP1(e) + CH(e,f,g) + k[i] + m[i];
        t2 = EP0(a) + MAJ(a,b,c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

static void sha256_init(SHA256_CTX *ctx)
{
    ctx->datalen   = 0;
    ctx->bitlen[0] = 0;
    ctx->bitlen[1] = 0;

    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
}

static void sha256_update(SHA256_CTX *ctx, const u8 data[], u32 len)
{
    u32 i;

    for (i = 0; i < len; ++i) {
        ctx->data[ctx->datalen] = data[i];
        ctx->datalen++;
        if (ctx->datalen == 64) {
            sha256_transform(ctx, ctx->data);

            // bit length += 512
            if (ctx->bitlen[1] > 0xFFFFFC00) {
                ctx->bitlen[0]++;
                ctx->bitlen[1] -= 0x40000000;
            }
            ctx->bitlen[1] += 512;

            ctx->datalen = 0;
        }
    }
}

static void sha256_final(SHA256_CTX *ctx, u8 hash[])
{
    u32 i;

    // compute total bits
    if (ctx->bitlen[1] > 0xFFFFFC00) {
        ctx->bitlen[0]++;
        ctx->bitlen[1] -= 0x40000000;
    }
    ctx->bitlen[1] += ctx->datalen * 8;

    // pad with one '1' bit and zeros
    ctx->data[ctx->datalen] = 0x80;
    ctx->datalen++;

    if (ctx->datalen > 56) {
        while (ctx->datalen < 64) {
            ctx->data[ctx->datalen++] = 0x00;
        }
        sha256_transform(ctx, ctx->data);
        ctx->datalen = 0;
    }

    while (ctx->datalen < 56) {
        ctx->data[ctx->datalen++] = 0x00;
    }

    // append length (big endian)
    ctx->data[63] = (u8)(ctx->bitlen[1]      );
    ctx->data[62] = (u8)(ctx->bitlen[1] >> 8 );
    ctx->data[61] = (u8)(ctx->bitlen[1] >> 16);
    ctx->data[60] = (u8)(ctx->bitlen[1] >> 24);
    ctx->data[59] = (u8)(ctx->bitlen[0]      );
    ctx->data[58] = (u8)(ctx->bitlen[0] >> 8 );
    ctx->data[57] = (u8)(ctx->bitlen[0] >> 16);
    ctx->data[56] = (u8)(ctx->bitlen[0] >> 24);

    sha256_transform(ctx, ctx->data);

    // copy state to hash (big endian)
    for (i = 0; i < 4; ++i) {
        hash[i]      = (u8)((ctx->state[0] >> (24 - i * 8)) & 0xFF);
        hash[i + 4]  = (u8)((ctx->state[1] >> (24 - i * 8)) & 0xFF);
        hash[i + 8]  = (u8)((ctx->state[2] >> (24 - i * 8)) & 0xFF);
        hash[i + 12] = (u8)((ctx->state[3] >> (24 - i * 8)) & 0xFF);
        hash[i + 16] = (u8)((ctx->state[4] >> (24 - i * 8)) & 0xFF);
        hash[i + 20] = (u8)((ctx->state[5] >> (24 - i * 8)) & 0xFF);
        hash[i + 24] = (u8)((ctx->state[6] >> (24 - i * 8)) & 0xFF);
        hash[i + 28] = (u8)((ctx->state[7] >> (24 - i * 8)) & 0xFF);
    }
}

/* ------------ main test ------------ */

int main(void)
{
    // Test message: "abc"
    const u8 msg[] = { 'a', 'b', 'c' };
    u8 hash[SHA256_BLOCK_SIZE];
    u8 expected[SHA256_BLOCK_SIZE] = {
        // SHA-256("abc") =
        // ba7816bf8f01cfea414140de5dae2223
        // b00361a396177a9cb410ff61f20015ad
        0xBA,0x78,0x16,0xBF,0x8F,0x01,0xCF,0xEA,
        0x41,0x41,0x40,0xDE,0x5D,0xAE,0x22,0x23,
        0xB0,0x03,0x61,0xA3,0x96,0x17,0x7A,0x9C,
        0xB4,0x10,0xFF,0x61,0xF2,0x00,0x15,0xAD
    };

    int i;
    int ok = 1;
    SHA256_CTX ctx;

    puts("SHA256 test start\n");
    puts("Message:\n");
    puts("abc\n");

    sha256_init(&ctx);
    sha256_update(&ctx, msg, (u32)(sizeof(msg)));
    sha256_final(&ctx, hash);

    puts("Digest:\n");
    for (i = 0; i < SHA256_BLOCK_SIZE; i++) {
        print_hex2(hash[i]);
    }
    putc('\n');

    // compare with expected
    for (i = 0; i < SHA256_BLOCK_SIZE; i++) {
        if (hash[i] != expected[i]) {
            ok = 0;
            break;
        }
    }

    if (ok) {
        puts("SHA OK\n");
    } else {
        puts("SHA FAIL\n");
    }

    return 0;
}
