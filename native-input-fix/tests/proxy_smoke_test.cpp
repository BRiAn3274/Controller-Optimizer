#include <windows.h>
#include <mmsystem.h>

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
    SetEnvironmentVariableW(L"INIF_PROXY_SMOKE_TEST", L"1");
    const std::wstring diagnostic = DiagnosticPath();
    if (!diagnostic.empty()) DeleteFileW(diagnostic.c_str());
    HMODULE proxy = LoadLibraryW(argv[1]);
    if (!proxy) return 3;
    using TimeGetDevCapsFn = MMRESULT (WINAPI*)(LPTIMECAPS, UINT);
    auto getCaps = reinterpret_cast<TimeGetDevCapsFn>(GetProcAddress(proxy, "timeGetDevCaps"));
    if (!getCaps) return 4;
    TIMECAPS caps{};
    const MMRESULT result = getCaps(&caps, sizeof(caps));
    const bool diagnosticWritten = !diagnostic.empty() && WaitForDiagnostic(diagnostic);
    FreeLibrary(proxy);
    if (result != TIMERR_NOERROR || caps.wPeriodMin == 0) return 5;
    if (!diagnosticWritten) return 6;
    std::cout << "proxy_smoke_test: forwarding succeeded\n";
    return 0;
}
