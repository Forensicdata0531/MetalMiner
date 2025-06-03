#ifndef SHA256_TAIL_HPP
#define SHA256_TAIL_HPP

#include <cstdint>
#include <array>

// Performs second SHA256 compression from a midstate
void sha256_from_midstate(const std::array<uint32_t, 8>& midstate, const uint8_t tail[64], uint8_t hash_out[32]);

#endif // SHA256_TAIL_HPP
