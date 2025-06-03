#include "sha256_compress.hpp"
#include <array>
#include <cstdint>
#include <cstring>

// Compute SHA256 hash given a midstate and tail (last 64 bytes + padding)
void sha256_from_midstate(const std::array<uint32_t, 8>& midstate, const uint8_t tail[64], uint8_t hash_out[32]) {
    std::array<uint32_t, 8> state = midstate;
    sha256_compress(tail, state);

    for (int i = 0; i < 8; i++) {
        hash_out[i * 4 + 0] = (state[i] >> 24) & 0xff;
        hash_out[i * 4 + 1] = (state[i] >> 16) & 0xff;
        hash_out[i * 4 + 2] = (state[i] >> 8) & 0xff;
        hash_out[i * 4 + 3] = (state[i]) & 0xff;
    }
}
