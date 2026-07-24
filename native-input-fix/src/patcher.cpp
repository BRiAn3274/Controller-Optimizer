#include "win_common.hpp"
#include "injection.hpp"

#include <commdlg.h>
#include <shellapi.h>

#include <cstring>
#include <fstream>
#include <string>
#include <vector>

namespace {

constexpr char kOriginalImport[] = "userenv";
constexpr char kPatchedImport[] = "bootstp";
constexpr wchar_t kBridgeName[] = L"bootstp.dll";
constexpr wchar_t kChainName[] = L"cofix_bootstrap_chain.dll";
constexpr wchar_t kPayloadName[] = L"azazel_input_hook.dll";
constexpr wchar_t kOwnerMarker[] = L"cofix_bootstrap_owner.txt";
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

bool CopyFileAtomic(const std::wstring& source, const std::wstring& target) {
    const std::wstring temporary = target + L".cofix.tmp";
    DeleteFileW(temporary.c_str());
    if (!CopyFileW(source.c_str(), temporary.c_str(), TRUE) ||
        !MoveFileExW(temporary.c_str(), target.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temporary.c_str());
        return false;
    }
    return true;
}

enum class PatchState { Invalid, Ready, AlreadyInstalled };

PatchState FindBootstrapMarker(std::vector<BYTE>& bytes, char*& libraryName) {
    libraryName = nullptr;
    if (bytes.size() < sizeof(IMAGE_DOS_HEADER)) return PatchState::Invalid;
    auto* dos = reinterpret_cast<IMAGE_DOS_HEADER*>(bytes.data());
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0 ||
        static_cast<size_t>(dos->e_lfanew) + sizeof(IMAGE_NT_HEADERS32) > bytes.size()) return PatchState::Invalid;
    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS32*>(bytes.data() + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_I386 ||
        nt->OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR32_MAGIC) return PatchState::Invalid;
    size_t originalMatches{};
    size_t patchedMatches{};
    char* original{};
    char* patched{};
    for (size_t offset = 0; offset + sizeof(kOriginalImport) <= bytes.size(); ++offset) {
        char* candidate = reinterpret_cast<char*>(bytes.data() + offset);
        if (std::memcmp(candidate, kOriginalImport, sizeof(kOriginalImport)) == 0) {
            ++originalMatches;
            original = candidate;
        }
        if (std::memcmp(candidate, kPatchedImport, sizeof(kPatchedImport)) == 0) {
            ++patchedMatches;
            patched = candidate;
        }
    }
    if (originalMatches == 1 && patchedMatches == 0) {
        libraryName = original;
        return PatchState::Ready;
    }
    if (patchedMatches == 1 && originalMatches == 0) {
        libraryName = patched;
        return PatchState::AlreadyInstalled;
    }
    return PatchState::Invalid;
}

#ifndef INIF_UNINSTALLER
bool CopySibling(const std::wstring& sourceDirectory, const std::wstring& targetDirectory,
    const wchar_t* filename) {
    const std::wstring source = inif::Join(sourceDirectory, filename);
    const std::wstring target = inif::Join(targetDirectory, filename);
    return inif::FileExists(source) && CopyFileAtomic(source, target);
}
#endif

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
    char* libraryName{};
    const PatchState state = ReadFile(executable, bytes)
        ? FindBootstrapMarker(bytes, libraryName) : PatchState::Invalid;
    if (state == PatchState::Invalid) {
        Notify(L"This executable is not a supported Isaac Win32 build or its unique userenv/bootstp loader name was not found.",
            MB_OK | MB_ICONERROR);
        return 3;
    }
    const std::wstring gameDirectory = inif::DirectoryOf(executable);
    const std::wstring bridge = inif::Join(gameDirectory, kBridgeName);
    const std::wstring chain = inif::Join(gameDirectory, kChainName);
    const std::wstring payload = inif::Join(gameDirectory, kPayloadName);
    const std::wstring owner = inif::Join(gameDirectory, kOwnerMarker);
#ifdef INIF_UNINSTALLER
    if (!inif::FileExists(owner)) {
        Notify(L"The automatic loader is not installed in this executable.", MB_OK | MB_ICONINFORMATION);
        return 0;
    }
    if (inif::FileExists(chain)) {
        if (!CopyFileAtomic(chain, bridge)) {
            Notify(L"Could not restore the pre-existing bootstp.dll. Nothing was removed.",
                MB_OK | MB_ICONERROR);
            return 4;
        }
        DeleteFileW(chain.c_str());
    } else {
        if (state != PatchState::AlreadyInstalled) {
            Notify(L"Loader ownership metadata and executable state disagree. Nothing was removed.",
                MB_OK | MB_ICONERROR);
            return 4;
        }
        std::memcpy(libraryName, kOriginalImport, sizeof(kOriginalImport));
        if (!WriteFile(executable, bytes)) {
            Notify(L"Could not restore isaac-ng.exe. Check permissions and confirm the game is closed.",
                MB_OK | MB_ICONERROR);
            return 4;
        }
        DeleteFileW(bridge.c_str());
    }
    DeleteFileW(payload.c_str());
    DeleteFileW(owner.c_str());
    Notify(L"Automatic loader removed. Steam will start Isaac without this input fix.", MB_OK | MB_ICONINFORMATION);
    return 0;
#else
    const std::wstring packageDirectory = inif::DirectoryOf(inif::ModulePath(nullptr));
    const std::wstring packageBridge = inif::Join(packageDirectory, kBridgeName);
    if (!inif::FileExists(packageBridge) ||
        !inif::FileExists(inif::Join(packageDirectory, kPayloadName))) {
        Notify(L"The installer package is incomplete. Keep the EXE and both DLL files together.",
            MB_OK | MB_ICONERROR);
        return 4;
    }
    const bool refreshingOwnedBridge = inif::FileExists(owner);
    bool chainCreated{};
    if (state == PatchState::Ready && refreshingOwnedBridge) {
        Notify(L"Loader metadata exists but isaac-ng.exe is no longer patched. Nothing was changed.",
            MB_OK | MB_ICONERROR);
        return 5;
    }
    if (state == PatchState::Ready && inif::FileExists(bridge)) {
        Notify(L"A bootstp.dll exists although Isaac still names userenv. Nothing was overwritten.",
            MB_OK | MB_ICONERROR);
        return 5;
    }
    if (state == PatchState::AlreadyInstalled && !refreshingOwnedBridge) {
        if (!inif::FileExists(bridge) || inif::FileExists(chain) ||
            !CopyFileW(bridge.c_str(), chain.c_str(), TRUE)) {
            Notify(L"Could not preserve the existing bootstp.dll. Nothing was overwritten.",
                MB_OK | MB_ICONERROR);
            return 5;
        }
        chainCreated = true;
    }
    if (!CopySibling(packageDirectory, gameDirectory, kPayloadName) ||
        !CopyFileAtomic(packageBridge, bridge)) {
        if (chainCreated) {
            CopyFileAtomic(chain, bridge);
            DeleteFileW(chain.c_str());
        }
        Notify(L"Could not install bootstp.dll or azazel_input_hook.dll beside the game executable.",
            MB_OK | MB_ICONERROR);
        return 6;
    }
    if (state == PatchState::Ready) {
        const std::wstring backup = executable + L".cofix-original";
        if (!inif::FileExists(backup) && !CopyFileW(executable.c_str(), backup.c_str(), TRUE)) {
            DeleteFileW(bridge.c_str());
            DeleteFileW(payload.c_str());
            Notify(L"Could not create the original executable backup. No changes were made.", MB_OK | MB_ICONERROR);
            return 7;
        }
        std::memcpy(libraryName, kPatchedImport, sizeof(kPatchedImport));
        if (!WriteFile(executable, bytes)) {
            DeleteFileW(bridge.c_str());
            DeleteFileW(payload.c_str());
            Notify(L"Could not update isaac-ng.exe. Check permissions and confirm the game is closed.", MB_OK | MB_ICONERROR);
            return 8;
        }
    }
    if (!inif::WriteTextAtomic(owner, "Controller Optimizer bootstrap bridge\r\n")) {
        if (chainCreated) {
            CopyFileAtomic(chain, bridge);
            DeleteFileW(chain.c_str());
        } else if (state == PatchState::Ready) {
            std::memcpy(libraryName, kOriginalImport, sizeof(kOriginalImport));
            WriteFile(executable, bytes);
            DeleteFileW(bridge.c_str());
        }
        DeleteFileW(payload.c_str());
        Notify(L"Could not write loader ownership metadata; installation was rolled back.",
            MB_OK | MB_ICONERROR);
        return 9;
    }
    Notify(state == PatchState::Ready
        ? L"Automatic loader installed using Isaac's userenv bootstrap point. Start Isaac normally from Steam."
        : refreshingOwnedBridge
            ? L"Automatic loader files refreshed; the existing bootstrap chain was preserved."
            : L"Automatic loader installed and the existing bootstp.dll was preserved in the compatibility chain.",
        MB_OK | MB_ICONINFORMATION);
    return 0;
#endif
}
