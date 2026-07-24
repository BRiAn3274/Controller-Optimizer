#include <windows.h>
#include <userenv.h>

#include <iostream>
#include <iterator>
#include <string>

namespace {

std::wstring DiagnosticPath() {
    wchar_t localAppData[32768]{};
    const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData,
        static_cast<DWORD>(std::size(localAppData)));
    if (!length || length >= std::size(localAppData)) return L"";
    return std::wstring(localAppData) + L"\\IsaacNativeInputFix\\diagnostics.json";
}

bool WaitForDiagnostic(const std::wstring& path) {
    for (int attempt = 0; attempt < 40; ++attempt) {
        if (GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) return true;
        Sleep(50);
    }
    return false;
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc != 2) return 2;
    const std::wstring diagnostic = DiagnosticPath();
    if (!diagnostic.empty()) DeleteFileW(diagnostic.c_str());
    HMODULE proxy = LoadLibraryW(argv[1]);
    if (!proxy) return 3;
    using GetUserProfileDirectoryAFn = BOOL (WINAPI*)(HANDLE, LPSTR, LPDWORD);
    auto getProfile = reinterpret_cast<GetUserProfileDirectoryAFn>(
        GetProcAddress(proxy, "GetUserProfileDirectoryA"));
    if (!getProfile) return 4;
    HANDLE token{};
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return 5;
    char profile[MAX_PATH]{};
    DWORD profileSize = static_cast<DWORD>(std::size(profile));
    const BOOL result = getProfile(token, profile, &profileSize);
    CloseHandle(token);
    const bool diagnosticWritten = !diagnostic.empty() && WaitForDiagnostic(diagnostic);
    FreeLibrary(proxy);
    if (!result || profile[0] == '\0') return 6;
    if (!diagnosticWritten) return 7;
    std::cout << "bootstrap_smoke_test: forwarding succeeded\n";
    return 0;
}
