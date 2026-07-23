#include "injection.hpp"

#include <tlhelp32.h>

#include <vector>

namespace inif {

DWORD FindProcess(const wchar_t* executable) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    PROCESSENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    DWORD result{};
    if (Process32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szExeFile, executable) == 0) {
                result = entry.th32ProcessID;
                break;
            }
        } while (Process32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return result;
}

uintptr_t RemoteModuleBase(DWORD processId, const wchar_t* moduleName) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, processId);
    if (snapshot == INVALID_HANDLE_VALUE) return 0;
    MODULEENTRY32W entry{};
    entry.dwSize = sizeof(entry);
    uintptr_t result{};
    if (Module32FirstW(snapshot, &entry)) {
        do {
            if (_wcsicmp(entry.szModule, moduleName) == 0) {
                result = reinterpret_cast<uintptr_t>(entry.modBaseAddr);
                break;
            }
        } while (Module32NextW(snapshot, &entry));
    }
    CloseHandle(snapshot);
    return result;
}

std::wstring SiblingPayloadPath() {
    std::vector<wchar_t> buffer(32768);
    const DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (!length || length >= buffer.size()) return L"";
    std::wstring path(buffer.data(), length);
    const size_t separator = path.find_last_of(L"\\/");
    if (separator == std::wstring::npos) return L"";
    return path.substr(0, separator + 1) + L"azazel_input_hook.dll";
}

int InjectPayload(DWORD processId, const std::wstring& payload) {
    const DWORD attributes = GetFileAttributesW(payload.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY)) return 10;

    HMODULE localKernel = GetModuleHandleW(L"kernel32.dll");
    FARPROC localLoadLibrary = localKernel ? GetProcAddress(localKernel, "LoadLibraryW") : nullptr;
    const uintptr_t remoteKernel = RemoteModuleBase(processId, L"kernel32.dll");
    if (!localKernel || !localLoadLibrary || !remoteKernel) return 11;
    const uintptr_t loadLibraryOffset = reinterpret_cast<uintptr_t>(localLoadLibrary) -
        reinterpret_cast<uintptr_t>(localKernel);
    auto remoteLoadLibrary = reinterpret_cast<LPTHREAD_START_ROUTINE>(remoteKernel + loadLibraryOffset);

    HANDLE process = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
        PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ, FALSE, processId);
    if (!process) return 12;
    const SIZE_T bytes = (payload.size() + 1) * sizeof(wchar_t);
    void* remotePath = VirtualAllocEx(process, nullptr, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remotePath) { CloseHandle(process); return 13; }
    SIZE_T written{};
    if (!WriteProcessMemory(process, remotePath, payload.c_str(), bytes, &written) || written != bytes) {
        VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
        CloseHandle(process);
        return 14;
    }
    HANDLE thread = CreateRemoteThread(process, nullptr, 0, remoteLoadLibrary, remotePath, 0, nullptr);
    if (!thread) {
        VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
        CloseHandle(process);
        return 15;
    }
    const DWORD wait = WaitForSingleObject(thread, 10000);
    DWORD moduleHandle{};
    const bool loaded = wait == WAIT_OBJECT_0 && GetExitCodeThread(thread, &moduleHandle) && moduleHandle != 0;
    CloseHandle(thread);
    VirtualFreeEx(process, remotePath, 0, MEM_RELEASE);
    CloseHandle(process);
    return loaded ? 0 : 16;
}

} // namespace inif
