#pragma once

#include <cstdint>

namespace inif {

enum class AimMode {
    GenericAzazel,
    TaintedAzazel,
};

struct AimConfig {
    float enterDeadzone{0.32F};
    float exitDeadzone{0.20F};
    float reverseDot{-0.85F};
    std::uint32_t genericDropoutFrames{2};
    std::uint32_t reverseConfirmFrames{2};
    std::uint32_t taintedConfirmFrames{1};
    std::uint32_t taintedReleaseFrames{2};
    std::uint32_t taintedRearmFrames{2};
};

struct AimOutput {
    float x{};
    float y{};
    bool active{};
    bool triggered{};
    bool pressed{};
    bool suppressRaw{};
};

class AimFilter {
public:
    explicit AimFilter(AimConfig config = {});

    void Reset(AimMode mode);
    AimOutput Update(AimMode mode, std::uint64_t frame, float rawX, float rawY);

private:
    AimOutput UpdateGeneric(std::uint64_t frame, float rawX, float rawY);
    AimOutput UpdateTainted(std::uint64_t frame, float rawX, float rawY);
    void SetDirection(float x, float y);
    bool AcceptDirection(float x, float y, std::uint64_t frame);
    AimOutput Output(bool triggered, bool suppressRaw) const;

    AimConfig config_;
    AimMode mode_{AimMode::GenericAzazel};
    float x_{};
    float y_{};
    bool active_{};
    bool taintedArmed_{true};
    std::uint64_t lastActiveFrame_{};
    std::uint64_t centerStartFrame_{};
    std::uint64_t candidateStartFrame_{};
    std::uint64_t reverseStartFrame_{};
    bool centerPending_{};
    bool candidatePending_{};
    bool reversePending_{};
};

} // namespace inif
