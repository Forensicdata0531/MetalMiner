#import <Metal/Metal.h>
#import <Foundation/Foundation.h>
#include "block.hpp"
#include <iostream>
#include <vector>
#include <cstring>
#include <simd/simd.h>

void sha256(const uint8_t* data, size_t len, uint8_t* outHash);

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
    if (!device) return false;

    NSError* error = nil;
    id<MTLLibrary> library = [device newDefaultLibrary];
    id<MTLFunction> kernelFunction = [library newFunctionWithName:@"mineKernel"];
    id<MTLComputePipelineState> pipelineState = [device newComputePipelineStateWithFunction:kernelFunction error:&error];
    id<MTLCommandQueue> commandQueue = [device newCommandQueue];

    std::vector<uint8_t> headerData = serializeHeader80(header);
    if (headerData.size() != 80) return false;

    uint8_t midstateBytes[32];
    sha256(headerData.data(), 64, midstateBytes);

    uint32_t midstate[8];
    for (int i = 0; i < 8; ++i) {
        midstate[i] = ((uint32_t)midstateBytes[i * 4] << 24) |
                      ((uint32_t)midstateBytes[i * 4 + 1] << 16) |
                      ((uint32_t)midstateBytes[i * 4 + 2] << 8) |
                      ((uint32_t)midstateBytes[i * 4 + 3]);
    }

    uint8_t tail[16];
    memcpy(tail, headerData.data() + 64, 16);

    const uint32_t threads = 131072;
    totalHashesTried = threads;

    uint32_t nonceBase = initialNonceBase;
    id<MTLBuffer> nonceBaseBuf = [device newBufferWithBytes:&nonceBase
                                                     length:sizeof(uint32_t)
                                                    options:MTLResourceStorageModeShared];

    id<MTLBuffer> midstateBuffer = [device newBufferWithBytes:midstate length:sizeof(midstate) options:MTLResourceStorageModeShared];
    id<MTLBuffer> tailBuffer = [device newBufferWithBytes:tail length:sizeof(tail) options:MTLResourceStorageModeShared];
    id<MTLBuffer> targetBuffer = [device newBufferWithBytes:target.data() length:target.size() options:MTLResourceStorageModeShared];
    id<MTLBuffer> resultNonceBuf = [device newBufferWithLength:sizeof(uint32_t) options:MTLResourceStorageModeShared];
    id<MTLBuffer> resultHashes = [device newBufferWithLength:threads * 32 options:MTLResourceStorageModeShared];

    uint32_t zero = 0;
    memcpy(resultNonceBuf.contents, &zero, sizeof(uint32_t));

    id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];

    [encoder setComputePipelineState:pipelineState];
    [encoder setBuffer:midstateBuffer offset:0 atIndex:0];
    [encoder setBuffer:tailBuffer offset:0 atIndex:1];
    [encoder setBuffer:targetBuffer offset:0 atIndex:2];
    [encoder setBuffer:resultNonceBuf offset:0 atIndex:3];
    [encoder setBuffer:resultHashes offset:0 atIndex:4];
    [encoder setBuffer:nonceBaseBuf offset:0 atIndex:5];

    MTLSize gridSize = MTLSizeMake(threads, 1, 1);
    NSUInteger threadGroupSize = pipelineState.maxTotalThreadsPerThreadgroup;
    if (threadGroupSize > threads) threadGroupSize = threads;
    MTLSize threadgroupSize = MTLSizeMake(threadGroupSize, 1, 1);

    [encoder dispatchThreads:gridSize threadsPerThreadgroup:threadgroupSize];
    [encoder endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];

    uint32_t foundNonce = *((uint32_t*)resultNonceBuf.contents);
    const uint8_t* hashStart = (uint8_t*)resultHashes.contents;

    if (foundNonce != 0 && foundNonce < threads) {
        validNonce = foundNonce + nonceBase;
        validHash.assign(
            hashStart + (foundNonce * 32),
            hashStart + (foundNonce * 32 + 32)
        );
        return true;
    } else {
        validNonce = 0;
        validHash.assign(hashStart, hashStart + 32);
        return false;
    }
}
