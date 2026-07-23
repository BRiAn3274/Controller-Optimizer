#include "injection.hpp"

#include <iostream>

int wmain(int argc, wchar_t** argv) {
    const std::wstring payload = argc >= 2 ? argv[1] : inif::SiblingPayloadPath();
    if (payload.empty()) return 2;
    const DWORD processId = inif::FindProcess(L"isaac-ng.exe");
    if (!processId) {
        std::wcerr << L"isaac-ng.exe is not running\n";
        return 3;
    }
    const int result = inif::InjectPayload(processId, payload);
    if (result != 0) {
        std::wcerr << L"injection failed, code=" << result << L", win32=" << GetLastError() << L"\n";
        return result;
    }
    std::wcout << L"payload injected into process " << processId << L"\n";
    return 0;
}
