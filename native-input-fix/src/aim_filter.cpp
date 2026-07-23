#include "aim_filter.hpp"

#include <algorithm>
#include <cmath>

namespace inif {
namespace {

float Clean(float value) {
    return std::isfinite(value) ? std::clamp(value, -1.0F, 1.0F) : 0.0F;
}

} // namespace

AimFilter::AimFilter(AimConfig config) : config_(config) {
    config_.enterDeadzone = std::clamp(config_.enterDeadzone, 0.05F, 0.95F);
    config_.exitDeadzone = std::clamp(config_.exitDeadzone, 0.01F, config_.enterDeadzone);
    config_.reverseDot = std::clamp(config_.reverseDot, -1.0F, -0.1F);
    config_.genericDropoutFrames = std::min(config_.genericDropoutFrames, 8U);
    config_.reverseConfirmFrames = std::clamp(config_.reverseConfirmFrames, 1U, 8U);
    config_.taintedConfirmFrames = std::clamp(config_.taintedConfirmFrames, 1U, 8U);
    config_.taintedReleaseFrames = std::clamp(config_.taintedReleaseFrames, 1U, 8U);
    config_.taintedRearmFrames = std::clamp(config_.taintedRearmFrames, 1U, 8U);
}

void AimFilter::Reset(AimMode mode) {
    mode_ = mode;
    x_ = 0.0F;
    y_ = 0.0F;
    active_ = false;
    taintedArmed_ = true;
    lastActiveFrame_ = 0;
    centerStartFrame_ = 0;
    candidateStartFrame_ = 0;
    reverseStartFrame_ = 0;
    centerPending_ = false;
    candidatePending_ = false;
    reversePending_ = false;
}

AimOutput AimFilter::Update(AimMode mode, std::uint64_t frame, float rawX, float rawY) {
    if (mode != mode_) Reset(mode);
    rawX = Clean(rawX);
    rawY = Clean(rawY);
    return mode == AimMode::TaintedAzazel
        ? UpdateTainted(frame, rawX, rawY)
        : UpdateGeneric(frame, rawX, rawY);
}

void AimFilter::SetDirection(float x, float y) {
    const float magnitude = std::sqrt(x * x + y * y);
    if (magnitude <= 0.0001F) return;
    x_ = x / magnitude;
    y_ = y / magnitude;
}

bool AimFilter::AcceptDirection(float x, float y, std::uint64_t frame) {
    if (!active_) {
        SetDirection(x, y);
        reversePending_ = false;
        return true;
    }
    const float magnitude = std::sqrt(x * x + y * y);
    if (magnitude <= 0.0001F) return false;
    const float nx = x / magnitude;
    const float ny = y / magnitude;
    const float dot = nx * x_ + ny * y_;
    if (dot > config_.reverseDot) {
        SetDirection(nx, ny);
        reversePending_ = false;
        return true;
    }
    if (!reversePending_) {
        reversePending_ = true;
        reverseStartFrame_ = frame;
        return false;
    }
    if (frame - reverseStartFrame_ < config_.reverseConfirmFrames) return false;
    SetDirection(nx, ny);
    reversePending_ = false;
    return true;
}

AimOutput AimFilter::Output(bool triggered, bool suppressRaw) const {
    return {active_ ? x_ : 0.0F, active_ ? y_ : 0.0F,
        active_, triggered, active_, suppressRaw};
}

AimOutput AimFilter::UpdateGeneric(std::uint64_t frame, float rawX, float rawY) {
    const float magnitude = std::sqrt(rawX * rawX + rawY * rawY);
    if (magnitude >= config_.enterDeadzone) {
        if (AcceptDirection(rawX, rawY, frame)) {
            active_ = true;
            lastActiveFrame_ = frame;
            centerPending_ = false;
        }
        return Output(false, reversePending_);
    }

    if (active_ && magnitude < config_.exitDeadzone) {
        if (!centerPending_) {
            centerPending_ = true;
            centerStartFrame_ = frame;
        }
        if (frame - centerStartFrame_ >= config_.genericDropoutFrames) {
            active_ = false;
            x_ = 0.0F;
            y_ = 0.0F;
            centerPending_ = false;
            reversePending_ = false;
        }
    }
    return Output(false, false);
}

AimOutput AimFilter::UpdateTainted(std::uint64_t frame, float rawX, float rawY) {
    const float magnitude = std::sqrt(rawX * rawX + rawY * rawY);

    if (active_) {
        if (magnitude >= config_.enterDeadzone) {
            if (AcceptDirection(rawX, rawY, frame)) {
                lastActiveFrame_ = frame;
                centerPending_ = false;
            }
            return Output(false, true);
        }
        if (magnitude < config_.exitDeadzone) {
            if (!centerPending_) {
                centerPending_ = true;
                centerStartFrame_ = frame;
            }
            if (frame - centerStartFrame_ >= config_.taintedReleaseFrames) {
                active_ = false;
                x_ = 0.0F;
                y_ = 0.0F;
                taintedArmed_ = false;
                candidatePending_ = false;
                reversePending_ = false;
                centerStartFrame_ = frame;
                return Output(false, true);
            }
        }
        return Output(false, true);
    }

    if (!taintedArmed_) {
        if (magnitude < config_.exitDeadzone) {
            if (!centerPending_) {
                centerPending_ = true;
                centerStartFrame_ = frame;
            }
            if (frame - centerStartFrame_ >= config_.taintedRearmFrames) {
                taintedArmed_ = true;
                centerPending_ = false;
                return Output(false, false);
            }
        } else {
            centerPending_ = false;
        }
        return Output(false, true);
    }

    if (magnitude < config_.enterDeadzone) {
        candidatePending_ = false;
        return Output(false, magnitude > 0.01F);
    }
    if (!candidatePending_) {
        candidatePending_ = true;
        candidateStartFrame_ = frame;
        return Output(false, true);
    }
    if (frame - candidateStartFrame_ < config_.taintedConfirmFrames) {
        return Output(false, true);
    }

    SetDirection(rawX, rawY);
    active_ = true;
    taintedArmed_ = false;
    candidatePending_ = false;
    centerPending_ = false;
    lastActiveFrame_ = frame;
    return Output(true, true);
}

} // namespace inif
