#include <metal_stdlib>
using namespace metal;

// Rotate right (portable)
inline uint rotr(uint x, uint n) {
    return (x >> n) | (x << (32 - n));
}

// SHA-256 logic functions
inline uint ssig0(uint x) { return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3); }
inline uint ssig1(uint x) { return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10); }
inline uint bsig0(uint x) { return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22); }
inline uint bsig1(uint x) { return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25); }

inline void sha256_compress(const threadgroup uint* K,
                            const threadgroup uint* tail32,
                            const constant uint* midstate,
                            uint nonce,
                            thread uint *output)
{
    uint w[64];

    // Load block tail into w[0..3]
    for (uint i = 0; i < 4; i++) {
        w[i] = tail32[i];
    }

    // Insert nonce at w[4]
    w[4] = nonce;
    w[5] = 0x80000000;
    for (uint i = 6; i < 15; i++) w[i] = 0;
    w[15] = 160;

    // Extend schedule
    #pragma unroll
    for (uint i = 16; i < 64; i++) {
        w[i] = ssig1(w[i-2]) + w[i-7] + ssig0(w[i-15]) + w[i-16];
    }

    // Initialize state
    uint a = midstate[0], b = midstate[1], c = midstate[2], d = midstate[3];
    uint e = midstate[4], f = midstate[5], g = midstate[6], h = midstate[7];

    // Main SHA-256 loop
    #pragma unroll
    for (uint i = 0; i < 64; i++) {
        uint T1 = h + bsig1(e) + ((e & f) ^ (~e & g)) + K[i] + w[i];
        uint T2 = bsig0(a) + ((a & b) ^ (a & c) ^ (b & c));
        h = g; g = f; f = e;
        e = d + T1;
        d = c; c = b; b = a;
        a = T1 + T2;
    }

    // Final state
    output[0] = a + midstate[0];
    output[1] = b + midstate[1];
    output[2] = c + midstate[2];
    output[3] = d + midstate[3];
    output[4] = e + midstate[4];
    output[5] = f + midstate[5];
    output[6] = g + midstate[6];
    output[7] = h + midstate[7];
}

kernel void mineKernel(const constant uint* midstate,
                       const constant uint* blockTail32,   // changed from uint8_t*
                       const constant uint8_t* targetBytes,
                       device atomic_uint* outputNonce,
                       device uint4* resultHashes,
                       constant uint& nonceBase,
                       uint thread_id [[thread_position_in_grid]],
                       uint tid_in_threadgroup [[thread_index_in_threadgroup]],
                       threadgroup uint* sharedK)  // shared[0..63] for K + [64..67] for tail
{
    threadgroup uint* sharedTail = sharedK + 64;
    threadgroup uint* sharedTarget = sharedTail + 4; // shared[68..75] reserved

    // Init K table once
    if (tid_in_threadgroup < 64) {
        constexpr uint k[64] = {
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
            0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
            0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
            0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
            0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
            0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
            0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
            0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
            0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        };
        sharedK[tid_in_threadgroup] = k[tid_in_threadgroup];
    }

    // Load tail32 and targetBytes into threadgroup memory (only 1st 8 threads)
    if (tid_in_threadgroup < 4) {
        sharedTail[tid_in_threadgroup] = blockTail32[tid_in_threadgroup];
    }

    if (tid_in_threadgroup < 8) {
        sharedTarget[tid_in_threadgroup] = ((uint)targetBytes[tid_in_threadgroup * 4 + 0] << 24) |
                                           ((uint)targetBytes[tid_in_threadgroup * 4 + 1] << 16) |
                                           ((uint)targetBytes[tid_in_threadgroup * 4 + 2] << 8) |
                                           ((uint)targetBytes[tid_in_threadgroup * 4 + 3]);
    }

    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Launch compression
    uint nonce = nonceBase + thread_id;
    uint hash[8];
    sha256_compress(sharedK, sharedTail, midstate, nonce, hash);

    // Write hash
    resultHashes[thread_id * 2 + 0] = uint4(hash[0], hash[1], hash[2], hash[3]);
    resultHashes[thread_id * 2 + 1] = uint4(hash[4], hash[5], hash[6], hash[7]);

    // Target check
    bool isValid = true;
    for (int i = 0; i < 8; i++) {
        if (hash[i] > sharedTarget[i]) { isValid = false; break; }
        if (hash[i] < sharedTarget[i]) break;
    }

    if (isValid) {
        atomic_exchange_explicit(outputNonce, nonce, memory_order_relaxed);
    }
}
