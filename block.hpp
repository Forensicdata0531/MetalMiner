#pragma once

#include <cstdint>
#include <vector>
#include <array>
#include <string>
#include <algorithm>
#include "nlohmann/json.hpp"

using json = nlohmann::json;

// Convert compact bits field (Bitcoin format) into a 32-byte target hash (big-endian)
inline std::vector<uint8_t> bitsToTarget(uint32_t bits) {
    uint32_t exponent = bits >> 24;
    uint32_t mantissa = bits & 0x007fffff;
    std::vector<uint8_t> target(32, 0);

    if (exponent <= 3) {
        mantissa >>= 8 * (3 - exponent);
        target[31] = mantissa & 0xff;
        if (exponent >= 2) target[30] = (mantissa >> 8) & 0xff;
        if (exponent >= 1) target[29] = (mantissa >> 16) & 0xff;
    } else {
        size_t index = 32 - exponent;
        target[index]     = (mantissa >> 16) & 0xff;
        target[index + 1] = (mantissa >> 8) & 0xff;
        target[index + 2] = mantissa & 0xff;
    }

    return target;
}

// Block header structure — 80 bytes when serialized
struct BlockHeader {
    uint32_t version;
    std::array<uint8_t, 32> prevBlockHash;
    std::array<uint8_t, 32> merkleRoot;
    uint32_t timestamp;
    uint32_t bits;
    uint32_t nonce;

    // Returns the 80-byte serialized block header in little-endian format with hashes reversed
    std::vector<uint8_t> toBytes() const {
        std::vector<uint8_t> bytes;

        auto appendLE32 = [&](uint32_t val) {
            bytes.push_back(static_cast<uint8_t>(val & 0xff));
            bytes.push_back(static_cast<uint8_t>((val >> 8) & 0xff));
            bytes.push_back(static_cast<uint8_t>((val >> 16) & 0xff));
            bytes.push_back(static_cast<uint8_t>((val >> 24) & 0xff));
        };

        auto appendReversed = [&](const std::array<uint8_t, 32>& arr) {
            // Bitcoin serializes hashes as little-endian, so reverse bytes before appending
            for (int i = 31; i >= 0; --i) {
                bytes.push_back(arr[i]);
            }
        };

        appendLE32(version);
        appendReversed(prevBlockHash);
        appendReversed(merkleRoot);
        appendLE32(timestamp);
        appendLE32(bits);
        appendLE32(nonce);

        return bytes;
    }

    // Static method to parse BlockHeader from JSON (blocktemplate)
    static BlockHeader fromJson(const json& j) {
        BlockHeader header{};

        // Parse version
        if (!j.contains("version")) throw std::runtime_error("Block template missing 'version'");
        header.version = j["version"].get<uint32_t>();

        // Parse previous block hash (hex string, big-endian)
        if (!j.contains("previousblockhash")) throw std::runtime_error("Block template missing 'previousblockhash'");
        std::string prevHashHex = j["previousblockhash"].get<std::string>();
        if (prevHashHex.size() != 64) throw std::runtime_error("Invalid previousblockhash length");
        // Convert big-endian hex string to little-endian array
        for (size_t i = 0; i < 32; ++i) {
            std::string byteStr = prevHashHex.substr(i * 2, 2);
            header.prevBlockHash[31 - i] = static_cast<uint8_t>(std::stoi(byteStr, nullptr, 16));
        }

        // Parse merkle root (hex string, big-endian)
        if (!j.contains("merkleroot")) throw std::runtime_error("Block template missing 'merkleroot'");
        std::string merkleHex = j["merkleroot"].get<std::string>();
        if (merkleHex.size() != 64) throw std::runtime_error("Invalid merkleroot length");
        for (size_t i = 0; i < 32; ++i) {
            std::string byteStr = merkleHex.substr(i * 2, 2);
            header.merkleRoot[31 - i] = static_cast<uint8_t>(std::stoi(byteStr, nullptr, 16));
        }

        // Parse timestamp
        if (!j.contains("curtime")) throw std::runtime_error("Block template missing 'curtime'");
        header.timestamp = j["curtime"].get<uint32_t>();

        // Parse bits
        if (!j.contains("bits")) throw std::runtime_error("Block template missing 'bits'");
        std::string bitsHex = j["bits"].get<std::string>();
        if (bitsHex.size() != 8) throw std::runtime_error("Invalid bits length");
        // bits is a uint32_t in big-endian hex string; convert to little-endian uint32_t
        header.bits = 0;
        for (int i = 0; i < 4; ++i) {
            std::string byteStr = bitsHex.substr(i * 2, 2);
            header.bits |= static_cast<uint32_t>(std::stoi(byteStr, nullptr, 16)) << (8 * (3 - i));
        }

        header.nonce = 0; // Start nonce at 0

        return header;
    }
};
