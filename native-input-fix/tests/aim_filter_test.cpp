#include "aim_filter.hpp"

#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>

namespace {

bool Near(float left, float right, float epsilon = 0.001F) {
    return std::fabs(left - right) <= epsilon;
}

void GenericDirectionAndDropout() {
    inif::AimFilter filter;
    auto output = filter.Update(inif::AimMode::GenericAzazel, 1, 1.0F, 0.0F);
    assert(output.active && Near(output.x, 1.0F) && Near(output.y, 0.0F));
    output = filter.Update(inif::AimMode::GenericAzazel, 2, 0.0F, 0.0F);
    assert(output.active);
    output = filter.Update(inif::AimMode::GenericAzazel, 3, 0.0F, 0.0F);
    assert(output.active);
    output = filter.Update(inif::AimMode::GenericAzazel, 4, 0.0F, 0.0F);
    assert(!output.active);
}

void GenericRejectsSingleFrameReverse() {
    inif::AimFilter filter;
    auto output = filter.Update(inif::AimMode::GenericAzazel, 1, 1.0F, 0.0F);
    assert(output.active && output.x > 0.9F);
    output = filter.Update(inif::AimMode::GenericAzazel, 2, -1.0F, 0.0F);
    assert(output.x > 0.9F && output.suppressRaw);
    output = filter.Update(inif::AimMode::GenericAzazel, 3, 1.0F, 0.0F);
    assert(output.x > 0.9F && !output.suppressRaw);
}

void TaintedTriggersOnceAndRearms() {
    inif::AimFilter filter;
    auto output = filter.Update(inif::AimMode::TaintedAzazel, 1, 1.0F, 0.0F);
    assert(!output.active && !output.triggered && output.suppressRaw);
    output = filter.Update(inif::AimMode::TaintedAzazel, 2, 1.0F, 0.0F);
    assert(output.active && output.triggered && output.pressed);
    output = filter.Update(inif::AimMode::TaintedAzazel, 3, 0.0F, -1.0F);
    assert(output.active && !output.triggered && output.pressed);
    filter.Update(inif::AimMode::TaintedAzazel, 4, 0.0F, 0.0F);
    filter.Update(inif::AimMode::TaintedAzazel, 5, 0.0F, 0.0F);
    output = filter.Update(inif::AimMode::TaintedAzazel, 6, 0.0F, 0.0F);
    assert(!output.active && output.suppressRaw);
    filter.Update(inif::AimMode::TaintedAzazel, 7, 0.0F, 0.0F);
    output = filter.Update(inif::AimMode::TaintedAzazel, 8, 0.0F, 0.0F);
    assert(!output.active && !output.suppressRaw);
    filter.Update(inif::AimMode::TaintedAzazel, 9, 0.0F, 1.0F);
    output = filter.Update(inif::AimMode::TaintedAzazel, 10, 0.0F, 1.0F);
    assert(output.triggered);
}

void SanitizesInvalidInput() {
    inif::AimFilter filter;
    const auto output = filter.Update(inif::AimMode::GenericAzazel, 1,
        std::numeric_limits<float>::quiet_NaN(), std::numeric_limits<float>::infinity());
    assert(!output.active && Near(output.x, 0.0F) && Near(output.y, 0.0F));
}

} // namespace

int main() {
    GenericDirectionAndDropout();
    GenericRejectsSingleFrameReverse();
    TaintedTriggersOnceAndRearms();
    SanitizesInvalidInput();
    std::cout << "aim_filter_test: all checks passed\n";
    return 0;
}
