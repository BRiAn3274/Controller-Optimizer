#include "win_common.hpp"

namespace {

using GetUserProfileDirectoryAFn = BOOL (WINAPI*)(HANDLE, LPSTR, LPDWORD);

HMODULE g_module{};
INIT_ONCE g_delegateOnce = INIT_ONCE_STATIC_INIT;
INIT_ONCE g_payloadOnce = INIT_ONCE_STATIC_INIT;
HMODULE g_delegateModule{};
GetUserProfileDirectoryAFn g_delegate{};

void Log(const wchar_t* message) {
    const std::wstring state = inif::StateDirectory();
    if (state.empty()) return;
    HANDLE file = CreateFileW(inif::Join(state, L"bootstrap.log").c_str(), FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    DWORD written{};
    WriteFile(file, message, static_cast<DWORD>(wcslen(message) * sizeof(wchar_t)), &written, nullptr);
    static constexpr wchar_t newline[] = L"\r\n";
    WriteFile(file, newline, 4, &written, nullptr);
    CloseHandle(file);
}

BOOL CALLBACK ResolveDelegate(PINIT_ONCE, PVOID, PVOID*) {
    const std::wstring modulePath = inif::ModulePath(g_module);
    const std::wstring moduleDirectory = inif::DirectoryOf(modulePath);
    const std::wstring chained = inif::Join(moduleDirectory, L"cofix_bootstrap_chain.dll");
    if (inif::FileExists(chained)) {
        g_delegateModule = LoadLibraryW(chained.c_str());
        if (g_delegateModule) {
            g_delegate = reinterpret_cast<GetUserProfileDirectoryAFn>(
                GetProcAddress(g_delegateModule, "GetUserProfileDirectoryA"));
        }
        if (g_delegate) {
            Log(L"chained bootstrap loaded");
            return TRUE;
        }
        Log(L"chained bootstrap invalid; refusing system fallback");
        return TRUE;
    }

    wchar_t systemDirectory[MAX_PATH]{};
    const UINT length = GetSystemDirectoryW(systemDirectory, MAX_PATH);
    if (!length || length >= MAX_PATH) return TRUE;
    const std::wstring userenv = inif::Join(systemDirectory, L"userenv.dll");
    g_delegateModule = LoadLibraryExW(userenv.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (g_delegateModule) {
        g_delegate = reinterpret_cast<GetUserProfileDirectoryAFn>(
            GetProcAddress(g_delegateModule, "GetUserProfileDirectoryA"));
    }
    Log(g_delegate ? L"system userenv loaded" : L"system userenv forwarding failed");
    return TRUE;
}

BOOL CALLBACK LoadPayload(PINIT_ONCE, PVOID, PVOID*) {
    const std::wstring moduleDirectory = inif::DirectoryOf(inif::ModulePath(g_module));
    const std::wstring payload = inif::Join(moduleDirectory, L"azazel_input_hook.dll");
    if (!inif::FileExists(payload)) {
        Log(L"azazel_input_hook.dll missing");
        return TRUE;
    }
    Log(LoadLibraryW(payload.c_str()) ? L"input payload loaded" : L"input payload failed to load");
    return TRUE;
}

} // namespace

extern "C" BOOL WINAPI GetUserProfileDirectoryA(HANDLE token, LPSTR profileDirectory,
    LPDWORD profileDirectorySize) {
    InitOnceExecuteOnce(&g_delegateOnce, ResolveDelegate, nullptr, nullptr);
    const BOOL result = g_delegate
        ? g_delegate(token, profileDirectory, profileDirectorySize) : FALSE;
    // This export is invoked outside the loader lock at Isaac's established
    // profile-path initialization point. Preserve the upstream result first,
    // then attach the independent input payload once per process.
    InitOnceExecuteOnce(&g_payloadOnce, LoadPayload, nullptr, nullptr);
    return result;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_module = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
