#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include "block.hpp"
#include <iostream>
#include <vector>
#include <cstring>
#include <limits>

void sha256(const uint8_t* data, size_t len, uint8_t* outHash);

bool isHashLower(const uint32_t* a, const uint32_t* b) {
    for (int i = 0; i < 8; ++i) {
        uint32_t aBE = __builtin_bswap32(a[i]);
        uint32_t bBE = __builtin_bswap32(b[i]);
        if (aBE < bBE) return true;
        if (aBE > bBE) return false;
    }
    return false;
}

std::vector<uint8_t> serializeHeader80(const BlockHeader& header) {
    std::vector<uint8_t> out;
    auto appendLE32 = [&](uint32_t val) {
        for (size_t i = 0; i < 4; ++i)
            out.push_back((val >> (8 * i)) & 0xff);
    };
    auto appendReversed = [&](const std::array<uint8_t, 32>& v) {
        for (int i = 31; i >= 0; --i)
            out.push_back(v[i]);
    };
    appendLE32(header.version);
    appendReversed(header.prevBlockHash);
    appendReversed(header.merkleRoot);
    appendLE32(header.timestamp);
    appendLE32(header.bits);
    appendLE32(header.nonce);
    return out;
}

bool metalMineBlock(const BlockHeader& header,
                    const std::vector<uint8_t>& target,
                    uint32_t initialNonceBase,
                    uint32_t& validNonce,
                    std::vector<uint8_t>& validHash,
                    uint64_t& totalHashesTried)
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        std::cerr << "No Metal device found\n";
        return false;
    }

    NSError* error = nil;
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> kernelFunction = [library newFunctionWithName:@"mineKernel"];
    id<MTLComputePipelineState> pipelineState = [device newComputePipelineStateWithFunction:kernelFunction error:&error];
    if (!pipelineState) {
        std::cerr << "Failed to create pipeline state: " << [[error localizedDescription] UTF8String] << std::endl;
        return false;
    }

    id<MTLCommandQueue> commandQueue = [device newCommandQueue];

    std::vector<uint8_t> headerData = serializeHeader80(header);
    if (headerData.size() != 80) {
        std::cerr << "Header serialization incorrect size\n";
        return false;
    }

    uint8_t midstateBytes[32];
    sha256(headerData.data(), 64, midstateBytes);
    uint32_t midstate[8];
    for (int i = 0; i < 8; ++i) {
        midstate[i] = ((uint32_t)midstateBytes[i * 4]) |
                      ((uint32_t)midstateBytes[i * 4 + 1] << 8) |
                      ((uint32_t)midstateBytes[i * 4 + 2] << 16) |
                      ((uint32_t)midstateBytes[i * 4 + 3] << 24);
    }

    uint32_t tail32[4];
    for (int i = 0; i < 4; ++i) {
        tail32[i] = ((uint32_t)headerData[64 + i * 4 + 0]) |
                    ((uint32_t)headerData[64 + i * 4 + 1] << 8) |
                    ((uint32_t)headerData[64 + i * 4 + 2] << 16) |
                    ((uint32_t)headerData[64 + i * 4 + 3] << 24);
    }

    uint32_t target32[8];
    for (int i = 0; i < 8; ++i) {
        target32[i] = ((uint32_t)target[i * 4 + 0] << 24) |
                      ((uint32_t)target[i * 4 + 1] << 16) |
                      ((uint32_t)target[i * 4 + 2] << 8)  |
                      ((uint32_t)target[i * 4 + 3]);
    }

    const uint32_t threadsPerDispatch = 131072;
    const uint32_t dispatchCount = 8;
    const uint32_t totalThreads = threadsPerDispatch * dispatchCount;
    totalHashesTried = totalThreads;

    id<MTLBuffer> midstateBuffer = [device newBufferWithBytes:midstate length:sizeof(midstate) options:MTLResourceStorageModeShared];
    id<MTLBuffer> tailBuffer     = [device newBufferWithBytes:tail32  length:sizeof(tail32)  options:MTLResourceStorageModeShared];
    id<MTLBuffer> targetBuffer   = [device newBufferWithBytes:target32 length:sizeof(target32) options:MTLResourceStorageModeShared];
    id<MTLBuffer> resultNonceBuf = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
    id<MTLBuffer> resultHashes   = [device newBufferWithLength:totalThreads * sizeof(uint32_t) * 8 options:MTLResourceStorageModeShared];
    id<MTLBuffer> nonceBaseBuf   = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];

    uint32_t zero = 0;
    memcpy(resultNonceBuf.contents, &zero, sizeof(uint32_t));

    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

    [encoder setComputePipelineState:pipelineState];
    [encoder setBuffer:midstateBuffer offset:0 atIndex:0];
    [encoder setBuffer:tailBuffer     offset:0 atIndex:1];
    [encoder setBuffer:targetBuffer   offset:0 atIndex:2];
    [encoder setBuffer:resultNonceBuf offset:0 atIndex:3];
    [encoder setBuffer:resultHashes   offset:0 atIndex:4];
    [encoder setBuffer:nonceBaseBuf   offset:0 atIndex:5];
    [encoder setThreadgroupMemoryLength:sizeof(uint32_t) * (64 + 4 + 8) atIndex:0];

    NSUInteger threadGroupSize = pipelineState.maxTotalThreadsPerThreadgroup;
    if (threadGroupSize > threadsPerDispatch) threadGroupSize = threadsPerDispatch;
    MTLSize threadgroupSize = MTLSizeMake(threadGroupSize, 1, 1);

    for (uint32_t i = 0; i < dispatchCount; ++i) {
        uint32_t nonceBase = initialNonceBase + i * threadsPerDispatch;
        MTLSize gridSize = MTLSizeMake(threadsPerDispatch, 1, 1);
        memcpy(nonceBaseBuf.contents, &nonceBase, sizeof(uint32_t));
        [encoder setBuffer:nonceBaseBuf offset:0 atIndex:5];
        [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
    }

    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    const uint32_t* hashStart = (const uint32_t*)resultHashes.contents;
    const uint32_t* bestHash = hashStart;
    uint32_t bestIndex = 0;

    for (uint32_t i = 1; i < totalThreads; ++i) {
        const uint32_t* current = hashStart + i * 8;
        if (isHashLower(current, bestHash)) {
            bestHash = current;
            bestIndex = i;
        }
    }

    printf("[DEBUG] Best Sample Hash [%u]: ", bestIndex);
    for (int i = 0; i < 8; ++i) {
        uint32_t be = __builtin_bswap32(bestHash[i]);
        printf("%02x%02x%02x%02x", (be >> 24), (be >> 16) & 0xff, (be >> 8) & 0xff, be & 0xff);
    }
    printf("\n");

    uint32_t foundNonce = *((uint32_t*)resultNonceBuf.contents);
    if (foundNonce != 0 && foundNonce < totalThreads) {
        validNonce = foundNonce + initialNonceBase;
        const uint32_t* validHashPtr = hashStart + foundNonce * 8;
        validHash.resize(32);
        for (int i = 0; i < 8; ++i) {
            uint32_t word = __builtin_bswap32(validHashPtr[i]);
            validHash[i * 4 + 0] = (word >> 24) & 0xFF;
            validHash[i * 4 + 1] = (word >> 16) & 0xFF;
            validHash[i * 4 + 2] = (word >> 8) & 0xFF;
            validHash[i * 4 + 3] = word & 0xFF;
        }
        return true;
    } else {
        validNonce = 0;
        validHash.resize(32);
        for (int i = 0; i < 8; ++i) {
            uint32_t word = __builtin_bswap32(bestHash[i]);
            validHash[i * 4 + 0] = (word >> 24) & 0xFF;
            validHash[i * 4 + 1] = (word >> 16) & 0xFF;
            validHash[i * 4 + 2] = (word >> 8) & 0xFF;
            validHash[i * 4 + 3] = word & 0xFF;
        }
        return false;
    }
}
