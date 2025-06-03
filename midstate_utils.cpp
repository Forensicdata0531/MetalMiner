#include "midstate_utils.hpp"
#include <openssl/sha.h>
#include <stdexcept>

Midstate calculateMidstateFromHeader(const std::vector<uint8_t>& header) {
    if (header.size() != 64) {
        throw std::runtime_error("Header must be exactly 64 bytes to calculate midstate");
    }

    uint8_t hash[32];
    SHA256(header.data(), header.size(), hash);

    Midstate mid;
    for (size_t i = 0; i < 8; ++i) {
        mid.h[i] = (uint32_t(hash[i * 4]) << 24) |
                   (uint32_t(hash[i * 4 + 1]) << 16) |
                   (uint32_t(hash[i * 4 + 2]) << 8) |
                   uint32_t(hash[i * 4 + 3]);
    }

    return mid;
}
