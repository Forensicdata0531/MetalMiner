#include "utils.hpp"
#include "block.hpp"
#include "midstate_utils.hpp"
#include "metal_ui.hpp"
#include <iostream>
#include <chrono>
#include <thread>
#include <climits>
#include <atomic>
#include <mutex>
#include <fstream>
#include <sstream>
#include "nlohmann/json.hpp"

using json = nlohmann::json;

MiningStats stats;

// Utility: Convert hex string (big-endian) to bytes vector
std::vector<uint8_t> hexToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    bytes.reserve(hex.length() / 2);
    for (size_t i = 0; i < hex.length(); i += 2) {
        uint8_t byte = static_cast<uint8_t>(std::stoi(hex.substr(i, 2), nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

// Load file contents into string
std::string loadFile(const std::string& filename) {
    std::ifstream file(filename);
    if (!file) throw std::runtime_error("Failed to open " + filename);
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

// Copy big-endian hex string to little-endian 32-byte array
void copyHashLE(const std::string& hexStr, std::array<uint8_t, 32>& outArray) {
    auto bytes = hexToBytes(hexStr);
    if (bytes.size() != 32) throw std::runtime_error("Invalid hash length");
    std::reverse(bytes.begin(), bytes.end()); // Convert big-endian to little-endian
    std::copy(bytes.begin(), bytes.end(), outArray.begin());
}

// Mining dispatch stub using midstate for CPU (for testing, not GPU)
void dispatchMining(const BlockHeader& header, const std::array<uint32_t, 8>& midstate, const std::vector<uint8_t>& tail, const std::vector<uint8_t>& target, MiningStats& stats) {
    for (uint32_t nonce = 0; nonce < UINT32_MAX && !stats.quit.load(std::memory_order_acquire); ++nonce) {
        // Construct full block header tail with nonce in little endian
        std::vector<uint8_t> blockTail = tail;
        blockTail[12] = (nonce >> 0) & 0xFF;
        blockTail[13] = (nonce >> 8) & 0xFF;
        blockTail[14] = (nonce >> 16) & 0xFF;
        blockTail[15] = (nonce >> 24) & 0xFF;

        // Compute double SHA256 of (midstate + tail)
        // For illustration, here we call sha256 twice on concatenated data
        // A real miner uses optimized midstate reuse (left as exercise)

        // Concatenate midstate bytes (32 bytes) + blockTail (64 bytes)
        // But midstate is already mid-hash state; in this stub, we compute normally.

        // Build full 80-byte block header (32 bytes prefix, 48 bytes tail)
        // Here, assume midstate covers first 64 bytes, tail is last 16 bytes.
        // This is simplified for demonstration.

        // Not a real mining function - just a placeholder
        stats.hashes++;
        if (nonce % 1000000 == 0) {
            std::cout << "Tried nonce " << nonce << "\n";
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: miner <block_template.json>\n";
        return 1;
    }

    try {
        std::string jsonStr = loadFile(argv[1]);
        json tmpl = json::parse(jsonStr);

        std::string hashPrevBlockBE = tmpl["previousblockhash"];
        std::string hashMerkleRootBE = tmpl["merkleroot"];
        std::string hashTargetBE = tmpl["target"];
        uint32_t nTime = tmpl["curtime"];
        uint32_t nBits = tmpl["bits"];
        uint32_t nVersion = tmpl["version"];
        uint32_t nHeight = tmpl["height"];
        uint32_t nNonce = 0;

        // Copy hashes to little-endian arrays
        std::array<uint8_t, 32> prevBlock;
        std::array<uint8_t, 32> merkleRoot;
        std::array<uint8_t, 32> target;

        copyHashLE(hashPrevBlockBE, prevBlock);
        copyHashLE(hashMerkleRootBE, merkleRoot);
        copyHashLE(hashTargetBE, target);

        BlockHeader header;
        header.version = nVersion;
        std::copy(prevBlock.begin(), prevBlock.end(), header.prevBlock.begin());
        std::copy(merkleRoot.begin(), merkleRoot.end(), header.merkleRoot.begin());
        header.timestamp = nTime;
        header.bits = nBits;
        header.nonce = nNonce;

        // Compute midstate and tail for mining
        std::array<uint32_t, 8> midstate = midstateFromHeader(header);
        std::vector<uint8_t> tail = tailFromHeader(header);

        stats.quit.store(false);

        // Start mining dispatch (simple loop here)
        dispatchMining(header, midstate, tail, target, stats);

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
