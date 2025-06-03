#include "utils.hpp"
#include <fstream>
#include <sstream>
#include <iomanip>
#include <stdexcept>
#include <openssl/evp.h>   // use EVP API instead of deprecated SHA256_*
#include <algorithm>
#include <vector>

// Calculate midstate by hashing the first 64 bytes of the header
std::array<uint32_t, 8> calculateMidstateArray(const std::vector<uint8_t>& headerPrefix) {
    if (headerPrefix.size() != 64) {
        throw std::runtime_error("Header prefix must be exactly 64 bytes");
    }

    uint8_t hash[32];

    // Use EVP API for SHA256 hashing
    EVP_MD_CTX* mdctx = EVP_MD_CTX_new();
    if (!mdctx) throw std::runtime_error("EVP_MD_CTX_new failed");

    if (EVP_DigestInit_ex(mdctx, EVP_sha256(), nullptr) != 1)
        throw std::runtime_error("EVP_DigestInit_ex failed");

    if (EVP_DigestUpdate(mdctx, headerPrefix.data(), headerPrefix.size()) != 1)
        throw std::runtime_error("EVP_DigestUpdate failed");

    unsigned int out_len = 0;
    if (EVP_DigestFinal_ex(mdctx, hash, &out_len) != 1)
        throw std::runtime_error("EVP_DigestFinal_ex failed");

    EVP_MD_CTX_free(mdctx);

    std::array<uint32_t, 8> result;
    for (size_t i = 0; i < 8; ++i) {
        result[i] = (hash[i * 4] << 24) | (hash[i * 4 + 1] << 16) |
                    (hash[i * 4 + 2] << 8) | hash[i * 4 + 3];
    }

    return result;
}

std::string loadBlockTemplate(const std::string& filepath) {
    std::ifstream file(filepath);
    if (!file) throw std::runtime_error("Failed to open block template file: " + filepath);
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

std::vector<uint8_t> sha256d(const std::vector<uint8_t>& data) {
    uint8_t hash1[EVP_MAX_MD_SIZE];
    unsigned int hash1_len = 0;

    EVP_MD_CTX* mdctx = EVP_MD_CTX_new();
    if (!mdctx) throw std::runtime_error("EVP_MD_CTX_new failed");

    // First SHA256
    if (EVP_DigestInit_ex(mdctx, EVP_sha256(), nullptr) != 1)
        throw std::runtime_error("EVP_DigestInit_ex failed");

    if (EVP_DigestUpdate(mdctx, data.data(), data.size()) != 1)
        throw std::runtime_error("EVP_DigestUpdate failed");

    if (EVP_DigestFinal_ex(mdctx, hash1, &hash1_len) != 1)
        throw std::runtime_error("EVP_DigestFinal_ex failed");

    // Second SHA256
    uint8_t hash2[EVP_MAX_MD_SIZE];
    unsigned int hash2_len = 0;

    if (EVP_DigestInit_ex(mdctx, EVP_sha256(), nullptr) != 1)
        throw std::runtime_error("EVP_DigestInit_ex failed (2nd pass)");

    if (EVP_DigestUpdate(mdctx, hash1, hash1_len) != 1)
        throw std::runtime_error("EVP_DigestUpdate failed (2nd pass)");

    if (EVP_DigestFinal_ex(mdctx, hash2, &hash2_len) != 1)
        throw std::runtime_error("EVP_DigestFinal_ex failed (2nd pass)");

    EVP_MD_CTX_free(mdctx);

    return std::vector<uint8_t>(hash2, hash2 + hash2_len);
}

std::string bytesToHex(const std::vector<uint8_t>& bytes) {
    std::ostringstream oss;
    for (auto b : bytes) {
        oss << std::hex << std::setw(2) << std::setfill('0') << (int)b;
    }
    return oss.str();
}
