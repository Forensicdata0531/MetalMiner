#include <metal_stdlib>
using namespace metal;

constant uint K[64] = {
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

inline uint rotr(uint x, uint n) {
    return (x >> n) | (x << (32 - n));
}

inline void sha256_compress(const device uint *midstate, device const uint8_t* tail, uint nonce, thread uint *output) {
    uint w[64];

    uint a = midstate[0];
    uint b = midstate[1];
    uint c = midstate[2];
    uint d = midstate[3];
    uint e = midstate[4];
    uint f = midstate[5];
    uint g = midstate[6];
    uint h = midstate[7];

    // Load the first 4 words (16 bytes) from tail, little-endian
    for (uint i = 0; i < 4; i++) {
        w[i] = ((uint)tail[i*4]) | ((uint)tail[i*4+1] << 8) | ((uint)tail[i*4+2] << 16) | ((uint)tail[i*4+3] << 24);
    }

    // Insert nonce at word index 4
    w[4] = nonce;

    // Padding according to SHA256 spec
    w[5] = 0x80000000;  // 1 bit followed by zeros
    for (uint i = 6; i < 15; i++) {
        w[i] = 0;
    }
    w[15] = 512 + 128;  // Length in bits of the message (512 + 128 bits)

    // Message schedule extension
    for (uint i = 16; i < 64; i++) {
        uint s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    // Compression function main loop
    for (uint i = 0; i < 64; i++) {
        uint S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        uint ch = (e & f) ^ ((~e) & g);
        uint temp1 = h + S1 + ch + K[i] + w[i];
        uint S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        uint maj = (a & b) ^ (a & c) ^ (b & c);
        uint temp2 = S0 + maj;

        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    }

    // Add the compressed chunk to current hash value
    output[0] = a + midstate[0];
    output[1] = b + midstate[1];
    output[2] = c + midstate[2];
    output[3] = d + midstate[3];
    output[4] = e + midstate[4];
    output[5] = f + midstate[5];
    output[6] = g + midstate[6];
    output[7] = h + midstate[7];
}

kernel void mineKernel(const device uint* midstate,
                       const device uint8_t* tail,
                       const device uint8_t* target,
                       device atomic_uint* outputNonce,
                       device uint8_t* resultHashes,
                       constant uint& nonceBase,
                       uint thread_id [[thread_position_in_grid]])
{
    uint nonce = nonceBase + thread_id;

    uint hash[8];
    sha256_compress(midstate, tail, nonce, hash);

    uint8_t hashBytes[32];
    for (int i = 0; i < 8; i++) {
        // Convert each 32-bit word from big-endian to bytes (Bitcoin format)
        hashBytes[i * 4 + 0] = (hash[i] >> 24) & 0xFF;
        hashBytes[i * 4 + 1] = (hash[i] >> 16) & 0xFF;
        hashBytes[i * 4 + 2] = (hash[i] >> 8) & 0xFF;
        hashBytes[i * 4 + 3] = hash[i] & 0xFF;
    }

    // Always write thread 0's hash to resultHashes buffer for UI sample display
    if (thread_id == 0) {
        for (uint i = 0; i < 32; i++) {
            resultHashes[i] = hashBytes[i];
        }
    }

    // Check if hash is less than or equal to target (target is big-endian)
    bool isValid = true;
    for (int i = 0; i < 32; i++) {
        if (hashBytes[i] > target[i]) {
            isValid = false;
            break;
        }
        if (hashBytes[i] < target[i]) break;
    }

    if (isValid) {
        // Atomically set outputNonce if not already set
        if (atomic_exchange_explicit(outputNonce, nonce, memory_order_relaxed) == 0) {
            // Write full valid hash at thread-specific offset in resultHashes buffer
            for (uint i = 0; i < 32; i++) {
                resultHashes[thread_id * 32 + i] = hashBytes[i];
            }
        }
    }
}
