#pragma once

#include <atomic>
#include <string>
#include <array>
#include <mutex>
#include <chrono>

// Tracks stats during mining sessions
struct MiningStats {
    std::atomic<bool> quit{false};                      // Signal to stop mining
    std::atomic<uint64_t> totalHashes{0};               // Total hashes computed
    std::atomic<uint64_t> hashes{0};                    // Hashes in current session (used in main.cpp)
    std::atomic<uint32_t> nonceBase{0};                 // Starting nonce for GPU batch
    std::atomic<bool> found{false};                     // Valid hash found

    std::atomic<float> hashrate{0.0f};                  // Measured hash rate

    std::array<uint8_t, 32> sampleHash{};               // Latest sample hash (raw bytes)
    std::string sampleHashStr;                          // Latest sample hash (hex string)
    std::string validHashStr;                           // Final hash (if found)
    uint32_t validNonce{0};                             // Nonce that produced final hash

    std::atomic<std::chrono::steady_clock::time_point> startTime;  // Benchmark start
    std::mutex mutex;                                   // For protecting shared display data
};

// Optional: Function to update terminal UI (e.g. ncurses)
void updateCursesUI(MiningStats& stats);
