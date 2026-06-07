// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <cstring>
#include <vector>

namespace mrt2_au {

/// Lock-free stereo ring buffer for sidechain reference capture (audio thread writes).
class SidechainReferenceRingBuffer {
public:
    static constexpr size_t kMaxSeconds = 10;
    static constexpr size_t kSampleRate = 48000;
    static constexpr size_t kCapacity = kSampleRate * kMaxSeconds;

    SidechainReferenceRingBuffer()
        : left_(kCapacity, 0.0f), right_(kCapacity, 0.0f) {}

    void clear() {
        write_pos_.store(0, std::memory_order_relaxed);
        filled_.store(0, std::memory_order_relaxed);
    }

    void write(const float* l, const float* r, size_t count) {
        if (!l || !r || count == 0) return;
        size_t wp = write_pos_.load(std::memory_order_relaxed);
        for (size_t i = 0; i < count; ++i) {
            left_[wp] = l[i];
            right_[wp] = r[i];
            wp = (wp + 1) % kCapacity;
        }
        write_pos_.store(wp, std::memory_order_release);
        size_t prev = filled_.load(std::memory_order_relaxed);
        size_t next = std::min(kCapacity, prev + count);
        filled_.store(next, std::memory_order_release);
    }

    /// Copies the most recent `max_samples` stereo frames into outL/outR.
    /// Returns the number of frames copied (may be less than max_samples).
    size_t read_recent(float* outL, float* outR, size_t max_samples) const {
        if (!outL || !outR || max_samples == 0) return 0;
        const size_t avail = std::min(filled_.load(std::memory_order_acquire), kCapacity);
        const size_t to_read = std::min(avail, max_samples);
        if (to_read == 0) return 0;

        const size_t wp = write_pos_.load(std::memory_order_acquire);
        const size_t start = (wp + kCapacity - to_read) % kCapacity;

        if (start + to_read <= kCapacity) {
            std::memcpy(outL, left_.data() + start, to_read * sizeof(float));
            std::memcpy(outR, right_.data() + start, to_read * sizeof(float));
        } else {
            const size_t first = kCapacity - start;
            const size_t second = to_read - first;
            std::memcpy(outL, left_.data() + start, first * sizeof(float));
            std::memcpy(outL + first, left_.data(), second * sizeof(float));
            std::memcpy(outR, right_.data() + start, first * sizeof(float));
            std::memcpy(outR + first, right_.data(), second * sizeof(float));
        }
        return to_read;
    }

    size_t filled_samples() const {
        return std::min(filled_.load(std::memory_order_acquire), kCapacity);
    }

private:
    std::vector<float> left_;
    std::vector<float> right_;
    std::atomic<size_t> write_pos_{0};
    std::atomic<size_t> filled_{0};
};

/// Downmix stereo 48 kHz to mono 16 kHz (3:1 decimation, averaged channels).
inline size_t downmix_resample_to_16k_mono(const float* inL, const float* inR, size_t inFrames,
                                           float* outMono, size_t outCapacity) {
    if (!inL || !inR || !outMono || inFrames == 0 || outCapacity == 0) return 0;
    size_t outFrames = 0;
    for (size_t i = 0; i + 2 < inFrames && outFrames < outCapacity; i += 3) {
        outMono[outFrames++] = 0.5f * (inL[i] + inR[i]);
    }
    return outFrames;
}

/// Pad or truncate mono samples to exactly `target_frames` (MusicCoCa expects 10 s @ 16 kHz).
inline void pad_mono_to_length(const float* src, size_t srcFrames, float* dest, size_t targetFrames) {
    if (srcFrames == 0 || targetFrames == 0) {
        if (targetFrames > 0) std::memset(dest, 0, targetFrames * sizeof(float));
        return;
    }
    for (size_t i = 0; i < targetFrames; ++i) {
        dest[i] = src[i % srcFrames];
    }
}

}  // namespace mrt2_au
