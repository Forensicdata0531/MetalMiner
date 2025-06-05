#ifndef MIDSTATE_UTILS_HPP
#define MIDSTATE_UTILS_HPP

#include <array>
#include <cstdint>
#include <vector>

struct Midstate {
    std::array<uint32_t, 8> h;
};

// Calculates SHA256 midstate from first 64 bytes of header
Midstate calculateMidstateFromHeader(const std::vector<uint8_t>& header);

// Convenience wrappers used in main.cpp:
std::array<uint32_t, 8> midstateFromHeader(const struct BlockHeader& header);
std::vector<uint8_t> tailFromHeader(const struct BlockHeader& header);

#endif // MIDSTATE_UTILS_HPP
