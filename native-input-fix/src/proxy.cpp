#include "win_common.hpp"

#include <mmsystem.h>

namespace {

using TimeBeginPeriodFn = MMRESULT (WINAPI*)(UINT);
using TimeEndPeriodFn = MMRESULT (WINAPI*)(UINT);
using TimeGetDevCapsFn = MMRESULT (WINAPI*)(LPTIMECAPS, UINT);

HMODULE g_module{};
INIT_ONCE g_systemOnce = INIT_ONCE_STATIC_INIT;
INIT_ONCE g_hookOnce = INIT_ONCE_STATIC_INIT;
HMODULE g_systemWinmm{};
TimeBeginPeriodFn g_timeBeginPeriod{};
TimeEndPeriodFn g_timeEndPeriod{};
TimeGetDevCapsFn g_timeGetDevCaps{};

void Log(const wchar_t* message) {
    const std::wstring state = inif::StateDirectory();
    if (state.empty()) return;
    HANDLE file = CreateFileW(inif::Join(state, L"proxy.log").c_str(), FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    DWORD written{};
    WriteFile(file, message, static_cast<DWORD>(wcslen(message) * sizeof(wchar_t)), &written, nullptr);
    static constexpr wchar_t newline[] = L"\r\n";
    WriteFile(file, newline, 4, &written, nullptr);
    CloseHandle(file);
}

BOOL CALLBACK ResolveSystemWinmm(PINIT_ONCE, PVOID, PVOID*) {
    wchar_t directory[MAX_PATH]{};
    const UINT length = GetSystemDirectoryW(directory, MAX_PATH);
    if (!length || length >= MAX_PATH) return TRUE;
    const std::wstring path = inif::Join(directory, L"winmm.dll");
    g_systemWinmm = LoadLibraryExW(path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (!g_systemWinmm || g_systemWinmm == g_module) {
        g_systemWinmm = nullptr;
        return TRUE;
    }
    g_timeBeginPeriod = reinterpret_cast<TimeBeginPeriodFn>(GetProcAddress(g_systemWinmm, "timeBeginPeriod"));
    g_timeEndPeriod = reinterpret_cast<TimeEndPeriodFn>(GetProcAddress(g_systemWinmm, "timeEndPeriod"));
    g_timeGetDevCaps = reinterpret_cast<TimeGetDevCapsFn>(GetProcAddress(g_systemWinmm, "timeGetDevCaps"));
    return TRUE;
}

void EnsureSystemWinmm() {
    InitOnceExecuteOnce(&g_systemOnce, ResolveSystemWinmm, nullptr, nullptr);
}

BOOL CALLBACK LoadHook(PINIT_ONCE, PVOID, PVOID*) {
    EnsureSystemWinmm();
    if (!g_systemWinmm || !g_timeBeginPeriod || !g_timeEndPeriod || !g_timeGetDevCaps) {
        Log(L"system winmm forwarding validation failed; payload not loaded");
        return TRUE;
    }
    const std::wstring proxy = inif::ModulePath(g_module);
    const std::wstring payload = inif::Join(inif::DirectoryOf(proxy), L"azazel_input_hook.dll");
    if (!inif::FileExists(payload)) {
        Log(L"azazel_input_hook.dll missing; system forwarding remains active");
        return TRUE;
    }
    if (!LoadLibraryW(payload.c_str())) {
        Log(L"azazel_input_hook.dll failed to load; system forwarding remains active");
        return TRUE;
    }
    Log(L"system winmm forwarded and diagnostic payload loaded");
    return TRUE;
}

void EnsureHook() {
    InitOnceExecuteOnce(&g_hookOnce, LoadHook, nullptr, nullptr);
}

} // namespace

extern "C" MMRESULT WINAPI timeBeginPeriod(UINT period) {
    EnsureSystemWinmm();
    EnsureHook();
    return g_timeBeginPeriod ? g_timeBeginPeriod(period) : TIMERR_NOCANDO;
}

extern "C" MMRESULT WINAPI timeEndPeriod(UINT period) {
    EnsureSystemWinmm();
    EnsureHook();
    return g_timeEndPeriod ? g_timeEndPeriod(period) : TIMERR_NOCANDO;
}

extern "C" MMRESULT WINAPI timeGetDevCaps(LPTIMECAPS caps, UINT size) {
    EnsureSystemWinmm();
    EnsureHook();
    return g_timeGetDevCaps ? g_timeGetDevCaps(caps, size) : TIMERR_NOCANDO;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_module = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
