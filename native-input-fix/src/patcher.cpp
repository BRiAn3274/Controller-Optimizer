#include "win_common.hpp"
#include "injection.hpp"

#include <commdlg.h>
#include <shellapi.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

namespace {

constexpr char kOriginalImport[] = "WINMM.dll";
constexpr char kPatchedImport[] = "cofix.dll";
bool g_silent{};

void Notify(const wchar_t* message, UINT flags) {
    if (!g_silent) MessageBoxW(nullptr, message, L"Isaac Native Input Fix", flags);
}

bool ReadFile(const std::wstring& path, std::vector<BYTE>& bytes) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) return false;
    const std::streamsize size = file.tellg();
    if (size <= 0 || size > 64 * 1024 * 1024) return false;
    bytes.resize(static_cast<size_t>(size));
    file.seekg(0);
    return static_cast<bool>(file.read(reinterpret_cast<char*>(bytes.data()), size));
}

bool WriteFile(const std::wstring& path, const std::vector<BYTE>& bytes) {
    const std::wstring temporary = path + L".cofix.tmp";
    std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
    if (!file) return false;
    file.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    file.close();
    if (!file || !MoveFileExW(temporary.c_str(), path.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temporary.c_str());
        return false;
    }
    return true;
}

DWORD RvaToOffset(const IMAGE_NT_HEADERS32* headers, DWORD rva) {
    const IMAGE_SECTION_HEADER* section = IMAGE_FIRST_SECTION(headers);
    for (WORD index = 0; index < headers->FileHeader.NumberOfSections; ++index) {
        const DWORD start = section[index].VirtualAddress;
        const DWORD size = std::max(section[index].Misc.VirtualSize, section[index].SizeOfRawData);
        if (rva >= start && rva < start + size) return section[index].PointerToRawData + rva - start;
    }
    return 0;
}

bool EqualsIgnoreCase(const char* left, const char* right) {
    while (*left && *right) {
        if (std::tolower(static_cast<unsigned char>(*left)) != std::tolower(static_cast<unsigned char>(*right))) {
            return false;
        }
        ++left;
        ++right;
    }
    return *left == *right;
}

enum class PatchState { Invalid, Ready, AlreadyInstalled };

PatchState FindWinmmImport(std::vector<BYTE>& bytes, char*& importName) {
    importName = nullptr;
    if (bytes.size() < sizeof(IMAGE_DOS_HEADER)) return PatchState::Invalid;
    auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(bytes.data());
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0 ||
        static_cast<size_t>(dos->e_lfanew) + sizeof(IMAGE_NT_HEADERS32) > bytes.size()) return PatchState::Invalid;
    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS32*>(bytes.data() + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_I386 ||
        nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC) return PatchState::Invalid;
    const IMAGE_DATA_DIRECTORY& imports = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    const DWORD importOffset = RvaToOffset(nt, imports.VirtualAddress);
    if (!importOffset || importOffset >= bytes.size()) return PatchState::Invalid;
    auto* descriptor = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(bytes.data() + importOffset);
    for (size_t index = 0; index < 256; ++index, ++descriptor) {
        if (reinterpret_cast<BYTE*>(descriptor + 1) > bytes.data() + bytes.size()) return PatchState::Invalid;
        if (!descriptor->Name) break;
        const DWORD nameOffset = RvaToOffset(nt, descriptor->Name);
        if (!nameOffset || nameOffset + sizeof(kOriginalImport) > bytes.size()) return PatchState::Invalid;
        char* name = reinterpret_cast<char*>(bytes.data() + nameOffset);
        if (EqualsIgnoreCase(name, kOriginalImport)) {
            importName = name;
            return PatchState::Ready;
        }
        if (EqualsIgnoreCase(name, kPatchedImport)) {
            importName = name;
            return PatchState::AlreadyInstalled;
        }
    }
    return PatchState::Invalid;
}

bool CopySibling(const std::wstring& sourceDirectory, const std::wstring& targetDirectory,
    const wchar_t* filename) {
    const std::wstring source = inif::Join(sourceDirectory, filename);
    const std::wstring target = inif::Join(targetDirectory, filename);
    return inif::FileExists(source) && CopyFileW(source.c_str(), target.c_str(), FALSE);
}

std::wstring ChooseGameExecutable() {
    wchar_t path[32768]{};
    OPENFILENAMEW dialog{};
    dialog.lStructSize = sizeof(dialog);
    dialog.lpstrFile = path;
    dialog.nMaxFile = static_cast<DWORD>(std::size(path));
    dialog.lpstrFilter = L"Isaac executable (isaac-ng.exe)\0isaac-ng.exe\0Executable files (*.exe)\0*.exe\0\0";
    dialog.nFilterIndex = 1;
    dialog.lpstrTitle = L"Select Isaac's isaac-ng.exe while the game is closed";
    dialog.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY;
    return GetOpenFileNameW(&dialog) ? std::wstring(path) : L"";
}

} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    if (inif::FindProcess(L"isaac-ng.exe")) {
        Notify(L"Close Isaac before installing the automatic loader.", MB_OK | MB_ICONWARNING);
        return 1;
    }
    int argumentCount{};
    LPWSTR* arguments = CommandLineToArgvW(GetCommandLineW(), &argumentCount);
    g_silent = arguments && argumentCount >= 3 && _wcsicmp(arguments[1], L"/silent") == 0;
    const std::wstring executable = arguments && argumentCount >= (g_silent ? 3 : 2)
        ? std::wstring(arguments[g_silent ? 2 : 1]) : ChooseGameExecutable();
    if (arguments) LocalFree(arguments);
    if (executable.empty()) return 0;
    if (_wcsicmp(executable.substr(executable.find_last_of(L"\\/") + 1).c_str(), L"isaac-ng.exe") != 0) {
        Notify(L"Select Isaac's isaac-ng.exe.", MB_OK | MB_ICONERROR);
        return 2;
    }

    std::vector<BYTE> bytes;
    char* importName{};
    const PatchState state = ReadFile(executable, bytes) ? FindWinmmImport(bytes, importName) : PatchState::Invalid;
    if (state == PatchState::Invalid) {
        Notify(L"This executable is not a supported Isaac Win32 build or its WINMM import was not found.", MB_OK | MB_ICONERROR);
        return 3;
    }
    const std::wstring gameDirectory = inif::DirectoryOf(executable);
    const std::wstring packageDirectory = inif::DirectoryOf(inif::ModulePath(nullptr));
    if (!CopySibling(packageDirectory, gameDirectory, L"cofix.dll") ||
        !CopySibling(packageDirectory, gameDirectory, L"azazel_input_hook.dll")) {
        Notify(L"Could not copy cofix.dll or azazel_input_hook.dll beside the game executable.", MB_OK | MB_ICONERROR);
        return 4;
    }
    if (state == PatchState::Ready) {
        const std::wstring backup = executable + L".cofix-original";
        if (!inif::FileExists(backup) && !CopyFileW(executable.c_str(), backup.c_str(), TRUE)) {
            Notify(L"Could not create the original executable backup. No changes were made.", MB_OK | MB_ICONERROR);
            return 5;
        }
        std::memcpy(importName, kPatchedImport, sizeof(kPatchedImport));
        if (!WriteFile(executable, bytes)) {
            Notify(L"Could not update isaac-ng.exe. Check permissions and confirm the game is closed.", MB_OK | MB_ICONERROR);
            return 6;
        }
    }
    Notify(state == PatchState::Ready
        ? L"Automatic loader installed. Start Isaac normally from Steam; the input fix will load with the game."
        : L"Automatic loader was already installed. The loader files were refreshed.",
        MB_OK | MB_ICONINFORMATION);
    return 0;
}
