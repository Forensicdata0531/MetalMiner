#include "midstate_utils.hpp"
#include "block.hpp"
#include <openssl/sha.h>
#include <stdexcept>
#include <vector>
#include <cstring>  // for memcpy

// Calculate midstate (SHA256 first 64 bytes of block header)
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

// Converts BlockHeader struct to a vector<uint8_t> 80 bytes in little-endian format
static std::vector<uint8_t> serializeBlockHeader(const BlockHeader& header) {
    std::vector<uint8_t> data(80);

    // version - 4 bytes LE
    data[0] = (header.version >> 0) & 0xFF;
    data[1] = (header.version >> 8) & 0xFF;
    data[2] = (header.version >> 16) & 0xFF;
    data[3] = (header.version >> 24) & 0xFF;

    // prevBlockHash - 32 bytes LE
    std::copy(header.prevBlockHash.begin(), header.prevBlockHash.end(), data.begin() + 4);

    // merkleRoot - 32 bytes LE
    std::copy(header.merkleRoot.begin(), header.merkleRoot.end(), data.begin() + 36);

    // timestamp - 4 bytes LE
    data[68] = (header.timestamp >> 0) & 0xFF;
    data[69] = (header.timestamp >> 8) & 0xFF;
    data[70] = (header.timestamp >> 16) & 0xFF;
    data[71] = (header.timestamp >> 24) & 0xFF;

    // bits - 4 bytes LE
    data[72] = (header.bits >> 0) & 0xFF;
    data[73] = (header.bits >> 8) & 0xFF;
    data[74] = (header.bits >> 16) & 0xFF;
    data[75] = (header.bits >> 24) & 0xFF;

    // nonce - 4 bytes LE
    data[76] = (header.nonce >> 0) & 0xFF;
    data[77] = (header.nonce >> 8) & 0xFF;
    data[78] = (header.nonce >> 16) & 0xFF;
    data[79] = (header.nonce >> 24) & 0xFF;

    return data;
}

// Compute midstate from BlockHeader
std::array<uint32_t, 8> midstateFromHeader(const BlockHeader& header) {
    std::vector<uint8_t> serialized = serializeBlockHeader(header);
    std::vector<uint8_t> first64(serialized.begin(), serialized.begin() + 64);
    Midstate mid = calculateMidstateFromHeader(first64);
    return mid.h;
}

// Extract tail from BlockHeader: bytes from offset 64 to 80
std::vector<uint8_t> tailFromHeader(const BlockHeader& header) {
    std::vector<uint8_t> serialized = serializeBlockHeader(header);
    return std::vector<uint8_t>(serialized.begin() + 64, serialized.end());
}
