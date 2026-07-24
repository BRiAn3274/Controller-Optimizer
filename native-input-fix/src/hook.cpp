#include "win_common.hpp"
#include "aim_filter.hpp"

#include <atomic>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <intrin.h>

#pragma intrinsic(_ReturnAddress)

namespace {

struct ImageAnalysis {
    bool pe32{};
    bool textFound{};
    DWORD imageSize{};
    DWORD textRva{};
    DWORD textSize{};
    DWORD timestamp{};
    bool bootstrapLoaderDetected{};
    size_t pressedWrapperMatches{};
    size_t triggeredWrapperMatches{};
    size_t valueWrapperMatches{};
    DWORD pressedWrapperRva{};
    DWORD triggeredWrapperRva{};
    DWORD valueWrapperRva{};
};

struct InputCapture {
    bool attempted{};
    bool detourInstalled{};
    bool restored{};
    bool captured{};
    DWORD objectAddress{};
    DWORD vtableAddress{};
    DWORD pressedMethod{};
    DWORD triggeredMethod{};
    DWORD valueMethod{};
};

using ValueBridgeFn = bool (__cdecl*)(void*, void*, int*, float*);
ValueBridgeFn g_originalValueBridge{};
std::atomic<InputCapture*> g_capture{};
std::atomic<bool> g_captureClaimed{};
std::atomic<bool> g_captureReady{};

using ValueMethodFn = float (__thiscall*)(void*, int);
using BoolMethodFn = bool (__thiscall*)(void*, int);

enum class RuntimeProfile {
    Generic,
    Tainted,
};

ValueMethodFn g_originalValueMethod{};
BoolMethodFn g_originalPressedMethod{};
BoolMethodFn g_originalTriggeredMethod{};
void* g_activeInputObject{};
RuntimeProfile g_runtimeProfile{RuntimeProfile::Generic};
inif::AimFilter g_aimFilter{};
inif::AimOutput g_cachedAim{};
ULONGLONG g_lastSampleBucket{~0ULL};
std::atomic<unsigned long> g_filteredCalls{};
std::atomic<unsigned long> g_filteredSamples{};
std::atomic<DWORD> g_returnSites[8]{};
std::atomic<unsigned long> g_returnSiteCalls[8]{};

void RecordReturnSite() {
    const DWORD address = static_cast<DWORD>(reinterpret_cast<uintptr_t>(_ReturnAddress()));
    for (size_t index = 0; index < std::size(g_returnSites); ++index) {
        DWORD recorded = g_returnSites[index].load();
        if (recorded == address) {
            ++g_returnSiteCalls[index];
            return;
        }
        if (recorded == 0 && g_returnSites[index].compare_exchange_strong(recorded, address)) {
            ++g_returnSiteCalls[index];
            return;
        }
    }
}

bool __cdecl CaptureValueBridge(void* inputObject, void* callbackState, int* action, float* output) {
    InputCapture* capture = g_capture.load(std::memory_order_acquire);
    if (capture && inputObject) {
        auto** vtable = *reinterpret_cast<void***>(inputObject);
        bool expected{};
        if (vtable && g_captureClaimed.compare_exchange_strong(expected, true,
                std::memory_order_acq_rel)) {
            capture->captured = true;
            capture->objectAddress = static_cast<DWORD>(reinterpret_cast<uintptr_t>(inputObject));
            capture->vtableAddress = static_cast<DWORD>(reinterpret_cast<uintptr_t>(vtable));
            capture->pressedMethod = static_cast<DWORD>(reinterpret_cast<uintptr_t>(vtable[0x30 / 4]));
            capture->triggeredMethod = static_cast<DWORD>(reinterpret_cast<uintptr_t>(vtable[0x34 / 4]));
            capture->valueMethod = static_cast<DWORD>(reinterpret_cast<uintptr_t>(vtable[0x38 / 4]));
            g_captureReady.store(true, std::memory_order_release);
        }
    }
    return g_originalValueBridge
        ? g_originalValueBridge(inputObject, callbackState, action, output)
        : false;
}

bool WriteRelativeJump(BYTE* source, const void* destination) {
    const intptr_t displacement = reinterpret_cast<const BYTE*>(destination) - (source + 5);
    if (displacement < INT32_MIN || displacement > INT32_MAX) return false;
    source[0] = 0xE9;
    *reinterpret_cast<int32_t*>(source + 1) = static_cast<int32_t>(displacement);
    return true;
}

float OutputForAction(const inif::AimOutput& output, int action) {
    if (action == 4) return output.x < 0.0F ? -output.x : 0.0F;
    if (action == 5) return output.x > 0.0F ? output.x : 0.0F;
    if (action == 6) return output.y < 0.0F ? -output.y : 0.0F;
    if (action == 7) return output.y > 0.0F ? output.y : 0.0F;
    return 0.0F;
}

bool IsShootAction(int action) {
    return action >= 4 && action <= 7;
}

void RefreshFilteredAim(void* inputObject) {
    const ULONGLONG bucket = GetTickCount64() / 16;
    if (bucket == g_lastSampleBucket) return;
    g_lastSampleBucket = bucket;
    const float left = g_originalValueMethod(inputObject, 4);
    const float right = g_originalValueMethod(inputObject, 5);
    const float up = g_originalValueMethod(inputObject, 6);
    const float down = g_originalValueMethod(inputObject, 7);
    const inif::AimMode mode = g_runtimeProfile == RuntimeProfile::Tainted
        ? inif::AimMode::TaintedAzazel : inif::AimMode::GenericAzazel;
    g_cachedAim = g_aimFilter.Update(mode, bucket, right - left, down - up);
    ++g_filteredSamples;
}

float __fastcall FilteredActionValue(void* inputObject, void*, int action) {
    if (!g_originalValueMethod) return 0.0F;
    if (inputObject != g_activeInputObject || !IsShootAction(action)) {
        return g_originalValueMethod(inputObject, action);
    }
    RecordReturnSite();
    RefreshFilteredAim(inputObject);
    ++g_filteredCalls;
    if (g_runtimeProfile == RuntimeProfile::Tainted && !g_cachedAim.active) {
        return g_cachedAim.suppressRaw ? 0.0F : g_originalValueMethod(inputObject, action);
    }
    return OutputForAction(g_cachedAim, action);
}

bool __fastcall FilteredActionPressed(void* inputObject, void*, int action) {
    if (!g_originalPressedMethod || inputObject != g_activeInputObject ||
        !IsShootAction(action) || g_runtimeProfile != RuntimeProfile::Tainted) {
        return g_originalPressedMethod ? g_originalPressedMethod(inputObject, action) : false;
    }
    RefreshFilteredAim(inputObject);
    if (g_cachedAim.active) return OutputForAction(g_cachedAim, action) > 0.001F;
    return g_cachedAim.suppressRaw ? false : g_originalPressedMethod(inputObject, action);
}

bool __fastcall FilteredActionTriggered(void* inputObject, void*, int action) {
    if (!g_originalTriggeredMethod || inputObject != g_activeInputObject ||
        !IsShootAction(action) || g_runtimeProfile != RuntimeProfile::Tainted) {
        return g_originalTriggeredMethod ? g_originalTriggeredMethod(inputObject, action) : false;
    }
    RefreshFilteredAim(inputObject);
    if (g_cachedAim.active) {
        return g_cachedAim.triggered && OutputForAction(g_cachedAim, action) > 0.001F;
    }
    return g_cachedAim.suppressRaw ? false : g_originalTriggeredMethod(inputObject, action);
}

struct MethodDetour {
    BYTE* method{};
    BYTE original[6]{};
    size_t length{};
    BYTE* trampoline{};
    bool installed{};
};

bool InstallMethodDetour(BYTE* image, const ImageAnalysis& analysis, DWORD methodAddress,
    const BYTE* expected, size_t length, const void* replacement, MethodDetour& result) {
    if (!methodAddress || length < 5 || length > std::size(result.original)) return false;
    BYTE* method = reinterpret_cast<BYTE*>(static_cast<uintptr_t>(methodAddress));
    if (method < image + analysis.textRva || method + length > image + analysis.textRva + analysis.textSize ||
        std::memcmp(method, expected, length) != 0) return false;

    BYTE* trampoline = static_cast<BYTE*>(VirtualAlloc(nullptr, 16,
        MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!trampoline) return false;
    std::memcpy(trampoline, method, length);
    if (!WriteRelativeJump(trampoline + length, method + length)) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }

    DWORD oldProtection{};
    if (!VirtualProtect(method, length, PAGE_EXECUTE_READWRITE, &oldProtection)) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    std::memcpy(result.original, method, length);
    const bool patched = WriteRelativeJump(method, replacement);
    for (size_t index = 5; patched && index < length; ++index) method[index] = 0x90;
    FlushInstructionCache(GetCurrentProcess(), method, length);
    DWORD ignored{};
    VirtualProtect(method, length, oldProtection, &ignored);
    if (!patched) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return false;
    }
    result.method = method;
    result.length = length;
    result.trampoline = trampoline;
    result.installed = true;
    return true;
}

void RemoveMethodDetour(MethodDetour& detour) {
    if (detour.installed) {
        DWORD oldProtection{};
        if (VirtualProtect(detour.method, detour.length, PAGE_EXECUTE_READWRITE, &oldProtection)) {
            std::memcpy(detour.method, detour.original, detour.length);
            FlushInstructionCache(GetCurrentProcess(), detour.method, detour.length);
            DWORD ignored{};
            VirtualProtect(detour.method, detour.length, oldProtection, &ignored);
        }
    }
    if (detour.trampoline) VirtualFree(detour.trampoline, 0, MEM_RELEASE);
    detour = {};
}

bool InstallInputHooks(BYTE* image, const ImageAnalysis& analysis, const InputCapture& capture,
    RuntimeProfile profile, bool& pressedInstalled, bool& triggeredInstalled) {
    pressedInstalled = false;
    triggeredInstalled = false;
    if (!capture.captured || !capture.restored || !capture.valueMethod) return false;

    static constexpr BYTE valuePrologue[6] = {0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x08};
    static constexpr BYTE boolPrologue[5] = {0x55, 0x8B, 0xEC, 0x53, 0x56};
    MethodDetour valueDetour{};
    MethodDetour pressedDetour{};
    MethodDetour triggeredDetour{};
    if (!InstallMethodDetour(image, analysis, capture.valueMethod, valuePrologue,
            sizeof(valuePrologue), reinterpret_cast<const void*>(&FilteredActionValue), valueDetour)) {
        return false;
    }
    if (profile == RuntimeProfile::Tainted &&
        !InstallMethodDetour(image, analysis, capture.pressedMethod, boolPrologue,
            sizeof(boolPrologue), reinterpret_cast<const void*>(&FilteredActionPressed), pressedDetour)) {
        RemoveMethodDetour(valueDetour);
        return false;
    }
    if (profile == RuntimeProfile::Tainted &&
        !InstallMethodDetour(image, analysis, capture.triggeredMethod, boolPrologue,
            sizeof(boolPrologue), reinterpret_cast<const void*>(&FilteredActionTriggered), triggeredDetour)) {
        RemoveMethodDetour(pressedDetour);
        RemoveMethodDetour(valueDetour);
        return false;
    }

    g_originalValueMethod = reinterpret_cast<ValueMethodFn>(valueDetour.trampoline);
    g_originalPressedMethod = profile == RuntimeProfile::Tainted
        ? reinterpret_cast<BoolMethodFn>(pressedDetour.trampoline) : nullptr;
    g_originalTriggeredMethod = profile == RuntimeProfile::Tainted
        ? reinterpret_cast<BoolMethodFn>(triggeredDetour.trampoline) : nullptr;
    g_activeInputObject = reinterpret_cast<void*>(static_cast<uintptr_t>(capture.objectAddress));
    g_runtimeProfile = profile;
    g_aimFilter.Reset(profile == RuntimeProfile::Tainted
        ? inif::AimMode::TaintedAzazel : inif::AimMode::GenericAzazel);
    g_lastSampleBucket = ~0ULL;
    g_filteredCalls = 0;
    g_filteredSamples = 0;
    for (size_t index = 0; index < std::size(g_returnSites); ++index) {
        g_returnSites[index] = 0;
        g_returnSiteCalls[index] = 0;
    }
    pressedInstalled = pressedDetour.installed;
    triggeredInstalled = triggeredDetour.installed;
    return true;
}

void WriteTelemetry(const std::wstring& state) {
    char json[4096]{};
    _snprintf_s(json, _countof(json), _TRUNCATE,
        "{\r\n"
        "  \"filtered_calls\": %lu,\r\n"
        "  \"filtered_samples\": %lu,\r\n"
        "  \"return_sites\": [\r\n"
        "    {\"address\": \"%08lX\", \"calls\": %lu},\r\n"
        "    {\"address\": \"%08lX\", \"calls\": %lu},\r\n"
        "    {\"address\": \"%08lX\", \"calls\": %lu},\r\n"
        "    {\"address\": \"%08lX\", \"calls\": %lu}\r\n"
        "  ]\r\n"
        "}\r\n",
        g_filteredCalls.load(), g_filteredSamples.load(),
        g_returnSites[0].load(), g_returnSiteCalls[0].load(),
        g_returnSites[1].load(), g_returnSiteCalls[1].load(),
        g_returnSites[2].load(), g_returnSiteCalls[2].load(),
        g_returnSites[3].load(), g_returnSiteCalls[3].load());
    inif::WriteTextAtomic(inif::Join(state, L"telemetry.json"), json);
}

InputCapture CaptureNativeInputObject(BYTE* image, const ImageAnalysis& analysis, bool approved) {
    InputCapture capture{};
    if (!approved || analysis.valueWrapperMatches != 1 || analysis.valueWrapperRva < 0x2B) return capture;
    capture.attempted = true;

    // Exact for the approved J460 image. Install a temporary passive detour
    // and wait for the game to supply a real, initialized input object. Do not
    // invoke an internal game function during startup.
    BYTE* bridge = image + analysis.valueWrapperRva - 0x2B;
    BYTE original[5]{};
    static constexpr BYTE expected[5] = {0x55, 0x8B, 0xEC, 0x6A, 0xFF};
    if (std::memcmp(bridge, expected, sizeof(expected)) != 0) return capture;
    std::memcpy(original, bridge, sizeof(original));

    BYTE* trampoline = static_cast<BYTE*>(VirtualAlloc(nullptr, 16,
        MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    if (!trampoline) return capture;
    std::memcpy(trampoline, original, sizeof(original));
    if (!WriteRelativeJump(trampoline + 5, bridge + 5)) {
        VirtualFree(trampoline, 0, MEM_RELEASE);
        return capture;
    }
    g_originalValueBridge = reinterpret_cast<ValueBridgeFn>(trampoline);
    g_captureClaimed.store(false, std::memory_order_relaxed);
    g_captureReady.store(false, std::memory_order_relaxed);
    g_capture.store(&capture, std::memory_order_release);

    DWORD oldProtection{};
    if (VirtualProtect(bridge, sizeof(original), PAGE_EXECUTE_READWRITE, &oldProtection)) {
        if (WriteRelativeJump(bridge, reinterpret_cast<const void*>(&CaptureValueBridge))) {
            FlushInstructionCache(GetCurrentProcess(), bridge, sizeof(original));
            capture.detourInstalled = true;
            for (int attempt = 0; attempt < 6000 &&
                    !g_captureReady.load(std::memory_order_acquire); ++attempt) Sleep(10);
        }
        std::memcpy(bridge, original, sizeof(original));
        FlushInstructionCache(GetCurrentProcess(), bridge, sizeof(original));
        DWORD ignored{};
        VirtualProtect(bridge, sizeof(original), oldProtection, &ignored);
        capture.restored = std::memcmp(bridge, original, sizeof(original)) == 0;
    }
    g_capture.store(nullptr, std::memory_order_release);
    // Keep this tiny trampoline for the process lifetime. A bridge invocation
    // already in flight may still be returning through it while the original
    // bytes are restored.
    return capture;
}

template <size_t Size>
void FindPattern(const BYTE* text, DWORD textSize, const BYTE (&pattern)[Size],
    size_t& matches, DWORD& resultRva, const BYTE* image) {
    for (DWORD offset = 0; offset + Size <= textSize; ++offset) {
        if (std::memcmp(text + offset, pattern, Size) == 0) {
            ++matches;
            resultRva = static_cast<DWORD>((text + offset) - image);
        }
    }
}

ImageAnalysis AnalyzeImage() {
    ImageAnalysis result{};
    BYTE* image = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
    if (!image) return result;
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return result;
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS32*>(image + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE ||
        nt->FileHeader.Machine != IMAGE_FILE_MACHINE_I386 ||
        nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC) return result;
    result.pe32 = true;
    result.imageSize = nt->OptionalHeader.SizeOfImage;
    result.timestamp = nt->FileHeader.TimeDateStamp;
    static constexpr BYTE bootstrapName[] = {'b', 'o', 'o', 't', 's', 't', 'p', 0};
    size_t bootstrapMatches{};
    for (DWORD offset = 0; offset + sizeof(bootstrapName) <= result.imageSize; ++offset) {
        if (std::memcmp(image + offset, bootstrapName, sizeof(bootstrapName)) == 0) ++bootstrapMatches;
    }
    result.bootstrapLoaderDetected = bootstrapMatches == 1;
    const IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(nt);
    for (WORD i = 0; i < nt->FileHeader.NumberOfSections; ++i) {
        if (std::memcmp(section[i].Name, ".text", 5) == 0 &&
            (section[i].Characteristics & IMAGE_SCN_MEM_EXECUTE)) {
            if (result.textFound) {
                result.textFound = false;
                return result;
            }
            result.textFound = true;
            result.textRva = section[i].VirtualAddress;
            result.textSize = section[i].Misc.VirtualSize;
        }
    }
    if (result.textFound) {
        const BYTE* text = image + result.textRva;
        // J460 Lua input bridges. These short instruction sequences identify
        // calls through the native input object's pressed (+0x30), triggered
        // (+0x34), and value (+0x38) virtual methods. They are discovery
        // anchors only; diagnostics never patch these wrappers.
        static constexpr BYTE pressed[] = {
            0x8B, 0x4D, 0x08, 0x8B, 0x01, 0x8B, 0x50, 0x30,
            0x8B, 0x45, 0x10, 0xFF, 0x30, 0xFF, 0xD2
        };
        static constexpr BYTE triggered[] = {
            0x8B, 0x4D, 0x08, 0x8B, 0x01, 0x8B, 0x50, 0x34,
            0x8B, 0x45, 0x10, 0xFF, 0x30, 0xFF, 0xD2
        };
        static constexpr BYTE value[] = {
            0x8B, 0x4D, 0x08, 0x8B, 0x01, 0x8B, 0x40, 0x38,
            0x89, 0x45, 0xF0, 0x8B, 0x45, 0x10, 0xFF, 0x30,
            0xFF, 0x55, 0xF0
        };
        FindPattern(text, result.textSize, pressed,
            result.pressedWrapperMatches, result.pressedWrapperRva, image);
        FindPattern(text, result.textSize, triggered,
            result.triggeredWrapperMatches, result.triggeredWrapperRva, image);
        FindPattern(text, result.textSize, value,
            result.valueWrapperMatches, result.valueWrapperRva, image);
    }
    return result;
}

std::string WineVersion() {
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (!ntdll) return "native-windows";
    using WineVersionFn = const char* (__cdecl*)();
    auto fn = reinterpret_cast<WineVersionFn>(GetProcAddress(ntdll, "wine_get_version"));
    if (!fn) return "native-windows";
    const char* version = fn();
    return version ? version : "wine-unknown";
}

DWORD WINAPI Initialize(void*) {
    const std::wstring state = inif::StateDirectory();
    if (state.empty()) return 1;
    const std::wstring executable = inif::ModulePath(nullptr);
    std::wstring hash;
    const bool hashed = !executable.empty() && inif::Sha256File(executable, hash);
    const ImageAnalysis analysis = AnalyzeImage();
    const std::string runtime = WineVersion();
    const bool exactDeckHash = hashed &&
        _wcsicmp(hash.c_str(), L"7122AC28779925B24E23E2416F231322B1470388BD25E2C08665AD8D53B3EA4F") == 0;
    const bool observedDeckBuild = exactDeckHash || analysis.bootstrapLoaderDetected;
    const std::wstring configPath = inif::Join(state, L"config.ini");
    wchar_t modeBuffer[32]{};
    GetPrivateProfileStringW(L"hook", L"mode", L"diagnostic", modeBuffer,
        static_cast<DWORD>(std::size(modeBuffer)), configPath.c_str());
    const bool genericRequested = _wcsicmp(modeBuffer, L"generic-test") == 0;
    const bool taintedRequested = _wcsicmp(modeBuffer, L"tainted-test") == 0;
    InputCapture capture{};
    if (observedDeckBuild && analysis.pe32 && analysis.textFound) {
        Sleep(1500);
        capture = CaptureNativeInputObject(reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr)),
            analysis, true);
    }
    bool taintedPressedInstalled{};
    bool taintedTriggeredInstalled{};
    const bool hooksRequested = genericRequested || taintedRequested;
    const RuntimeProfile requestedProfile = taintedRequested
        ? RuntimeProfile::Tainted : RuntimeProfile::Generic;
    const bool hooksInstalled = hooksRequested && observedDeckBuild &&
        InstallInputHooks(reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr)), analysis, capture,
            requestedProfile, taintedPressedInstalled, taintedTriggeredInstalled);
    if (hooksInstalled) Sleep(1000);
    const char* requestedMode = taintedRequested ? "tainted-test"
        : genericRequested ? "generic-test" : "diagnostic";
    const char* hookStatus = hooksInstalled
        ? taintedRequested ? "tainted-test-active" : "generic-test-active"
        : "diagnostic-capture-only";

    char json[4096]{};
    _snprintf_s(json, _countof(json), _TRUNCATE,
        "{\r\n"
        "  \"schema\": 1,\r\n"
        "  \"runtime\": \"%s\",\r\n"
        "  \"exe_sha256\": \"%s\",\r\n"
        "  \"pe32\": %s,\r\n"
        "  \"image_size\": %lu,\r\n"
        "  \"timestamp\": \"%08lX\",\r\n"
        "  \"text_found\": %s,\r\n"
        "  \"text_rva\": \"%08lX\",\r\n"
        "  \"text_size\": %lu,\r\n"
        "  \"input_discovery\": {\r\n"
        "    \"pressed_wrapper_matches\": %zu,\r\n"
        "    \"pressed_wrapper_rva\": \"%08lX\",\r\n"
        "    \"triggered_wrapper_matches\": %zu,\r\n"
        "    \"triggered_wrapper_rva\": \"%08lX\",\r\n"
        "    \"value_wrapper_matches\": %zu,\r\n"
        "    \"value_wrapper_rva\": \"%08lX\"\r\n"
        "  },\r\n"
        "  \"observed_deck_build\": %s,\r\n"
        "  \"bootstrap_loader_detected\": %s,\r\n"
        "  \"requested_mode\": \"%s\",\r\n"
        "  \"runtime_capture\": {\r\n"
        "    \"attempted\": %s,\r\n"
        "    \"detour_installed\": %s,\r\n"
        "    \"restored\": %s,\r\n"
        "    \"captured\": %s,\r\n"
        "    \"object\": \"%08lX\",\r\n"
        "    \"vtable\": \"%08lX\",\r\n"
        "    \"pressed_method\": \"%08lX\",\r\n"
        "    \"triggered_method\": \"%08lX\",\r\n"
        "    \"value_method\": \"%08lX\"\r\n"
        "  },\r\n"
        "  \"generic_value_hook_installed\": %s,\r\n"
        "  \"tainted_pressed_hook_installed\": %s,\r\n"
        "  \"tainted_triggered_hook_installed\": %s,\r\n"
        "  \"filtered_calls_at_write\": %lu,\r\n"
        "  \"hook_status\": \"%s\",\r\n"
        "  \"code_modified\": %s\r\n"
        "}\r\n",
        runtime.c_str(), hashed ? inif::Narrow(hash).c_str() : "",
        analysis.pe32 ? "true" : "false", analysis.imageSize, analysis.timestamp,
        analysis.textFound ? "true" : "false", analysis.textRva, analysis.textSize,
        analysis.pressedWrapperMatches, analysis.pressedWrapperRva,
        analysis.triggeredWrapperMatches, analysis.triggeredWrapperRva,
        analysis.valueWrapperMatches, analysis.valueWrapperRva,
        observedDeckBuild ? "true" : "false",
        analysis.bootstrapLoaderDetected ? "true" : "false",
        requestedMode,
        capture.attempted ? "true" : "false",
        capture.detourInstalled ? "true" : "false",
        capture.restored ? "true" : "false",
        capture.captured ? "true" : "false",
        capture.objectAddress, capture.vtableAddress, capture.pressedMethod,
        capture.triggeredMethod, capture.valueMethod,
        hooksInstalled ? "true" : "false",
        taintedPressedInstalled ? "true" : "false",
        taintedTriggeredInstalled ? "true" : "false",
        g_filteredCalls.load(), hookStatus, hooksInstalled ? "true" : "false");
    inif::WriteTextAtomic(inif::Join(state, L"diagnostics.json"), json);
    if (hooksInstalled) {
        for (int second = 0; second < 180; ++second) {
            Sleep(1000);
            WriteTelemetry(state);
        }
    }
    return 0;
}

} // namespace

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        HANDLE worker = CreateThread(nullptr, 0, Initialize, nullptr, 0, nullptr);
        if (worker) CloseHandle(worker);
    }
    return TRUE;
}
