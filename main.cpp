#include "utils.hpp"
#include "block.hpp"
#include "midstate_utils.hpp"
#include "metal_ui.hpp"
#include "metal_miner.hpp"  // Include the Metal miner header
#include <iostream>
#include <chrono>
#include <thread>
#include <climits>
#include <fstream>
#include <sstream>
#include "nlohmann/json.hpp"

using json = nlohmann::json;

MiningStats stats;

// Converts bytes to hex string (for sample hash display)
std::string toHex(const std::vector<uint8_t>& data) {
    static const char* digits = "0123456789abcdef";
    std::string output;
    output.reserve(data.size() * 2);
    for (uint8_t byte : data) {
        output.push_back(digits[byte >> 4]);
        output.push_back(digits[byte & 0xF]);
    }
    return output;
}

std::string toHex(const std::array<uint8_t, 32>& data) {
    static const char* digits = "0123456789abcdef";
    std::string output;
    output.reserve(data.size() * 2);
    for (uint8_t byte : data) {
        output.push_back(digits[byte >> 4]);
        output.push_back(digits[byte & 0xF]);
    }
    return output;
}

std::vector<uint8_t> hexToBytes(const std::string& hex) {
    std::vector<uint8_t> bytes;
    bytes.reserve(hex.length() / 2);
    for (size_t i = 0; i < hex.length(); i += 2) {
        uint8_t byte = static_cast<uint8_t>(std::stoi(hex.substr(i, 2), nullptr, 16));
        bytes.push_back(byte);
    }
    return bytes;
}

std::string loadFile(const std::string& filename) {
    std::ifstream file(filename);
    if (!file) throw std::runtime_error("Failed to open " + filename);
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

void copyHashLE(const std::string& hexStr, std::array<uint8_t, 32>& outArray) {
    auto bytes = hexToBytes(hexStr);
    if (bytes.size() != 32) throw std::runtime_error("Invalid hash length");
    std::reverse(bytes.begin(), bytes.end());
    std::copy(bytes.begin(), bytes.end(), outArray.begin());
}

// Updated dispatchMining calls your Metal miner and updates stats
void dispatchMining(const BlockHeader& header,
                    const std::array<uint32_t, 8>& midstate,
                    const std::vector<uint8_t>& tail,
                    const std::vector<uint8_t>& target,
                    MiningStats& stats) {
    (void)midstate; // unused param warning suppression
    (void)tail;

    uint32_t nonceBase = 0;
    uint32_t validNonce = 0;
    std::vector<uint8_t> validHash(32, 0);
    uint64_t totalHashesTried = 0;

    const int maxBatches = 1000;

    for (int batch = 0; batch < maxBatches && !stats.quit.load(std::memory_order_acquire); batch++) {
        bool found = metalMineBlock(header, target, nonceBase, validNonce, validHash, totalHashesTried);

        stats.hashes += totalHashesTried;

        std::copy(validHash.begin(), validHash.end(), stats.sampleHash.begin());
        stats.sampleHashStr = toHex(stats.sampleHash);

        std::cout << "Batch " << batch << " tried " << totalHashesTried << " hashes, total " << stats.hashes.load() << "\n";
        std::cout << "Sample Hash: " << stats.sampleHashStr << "\n";

        if (found) {
            stats.validNonce = validNonce;
            stats.validHashStr = toHex(validHash);
            std::cout << ">>> Valid nonce found: " << validNonce << "\n";
            std::cout << ">>> Valid hash: " << stats.validHashStr << "\n";
            break;
        }

        nonceBase += (uint32_t)totalHashesTried;
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
        uint32_t nVersion = tmpl["version"];
        std::string bitsHex = tmpl["bits"];
        uint32_t nNonce = 0;

        std::array<uint8_t, 32> prevBlock;
        std::array<uint8_t, 32> merkleRoot;
        std::array<uint8_t, 32> target;

        copyHashLE(hashPrevBlockBE, prevBlock);
        copyHashLE(hashMerkleRootBE, merkleRoot);
        copyHashLE(hashTargetBE, target);

        uint32_t nBits = 0;
        for (int i = 0; i < 4; ++i) {
            std::string byteStr = bitsHex.substr(i * 2, 2);
            nBits |= static_cast<uint32_t>(std::stoi(byteStr, nullptr, 16)) << (8 * (3 - i));
        }

        BlockHeader header;
        header.version = nVersion;
        std::copy(prevBlock.begin(), prevBlock.end(), header.prevBlockHash.begin());
        std::copy(merkleRoot.begin(), merkleRoot.end(), header.merkleRoot.begin());
        header.timestamp = nTime;
        header.bits = nBits;
        header.nonce = nNonce;

        std::array<uint32_t, 8> midstate = midstateFromHeader(header);
        std::vector<uint8_t> tail = tailFromHeader(header);
        std::vector<uint8_t> targetVec(target.begin(), target.end());

        stats.quit.store(false);
        dispatchMining(header, midstate, tail, targetVec, stats);

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
