#include <windows.h>

#include <algorithm>
#include <array>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

namespace {

std::wstring Join(const std::wstring& left, const wchar_t* right) {
    return left + L"\\" + right;
}

bool Run(const std::wstring& executable, const std::wstring& target) {
    std::wstring command = L"\"" + executable + L"\" /silent \"" + target + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(nullptr, &command[0], nullptr, nullptr, FALSE, 0,
            nullptr, nullptr, &startup, &process)) return false;
    WaitForSingleObject(process.hProcess, 30000);
    DWORD exitCode{};
    const bool okay = GetExitCodeProcess(process.hProcess, &exitCode) && exitCode == 0;
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return okay;
}

bool Read(const std::wstring& path, std::vector<char>& bytes) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) return false;
    const std::streamsize size = file.tellg();
    if (size <= 0) return false;
    bytes.resize(static_cast<size_t>(size));
    file.seekg(0);
    return static_cast<bool>(file.read(bytes.data(), size));
}

bool Write(const std::wstring& path, const std::vector<char>& bytes) {
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    return static_cast<bool>(file.write(bytes.data(), static_cast<std::streamsize>(bytes.size())));
}

size_t Count(const std::vector<char>& bytes, const std::array<char, 8>& value) {
    size_t count{};
    for (size_t offset = 0; offset + value.size() <= bytes.size(); ++offset) {
        if (std::equal(value.begin(), value.end(), bytes.begin() + offset)) ++count;
    }
    return count;
}

bool ReplaceImport(const std::wstring& path, const std::array<char, 8>& from,
    const std::array<char, 8>& to) {
    std::vector<char> bytes;
    if (!Read(path, bytes) || Count(bytes, from) != 1) return false;
    for (size_t offset = 0; offset + from.size() <= bytes.size(); ++offset) {
        if (std::equal(from.begin(), from.end(), bytes.begin() + offset)) {
            std::copy(to.begin(), to.end(), bytes.begin() + offset);
            return Write(path, bytes);
        }
    }
    return false;
}

bool NormalizeFixtureImport(const std::wstring& path) {
    static constexpr char linkedName[] = "userenv.dll";
    static constexpr std::array<char, 8> isaacName = {'u','s','e','r','e','n','v',0};
    std::vector<char> bytes;
    if (!Read(path, bytes)) return false;
    size_t matches{};
    size_t matchOffset{};
    for (size_t offset = 0; offset + sizeof(linkedName) <= bytes.size(); ++offset) {
        bool same = true;
        for (size_t index = 0; index < sizeof(linkedName); ++index) {
            const unsigned char value = static_cast<unsigned char>(bytes[offset + index]);
            const char lowered = value >= 'A' && value <= 'Z'
                ? static_cast<char>(value - 'A' + 'a') : static_cast<char>(value);
            if (lowered != linkedName[index]) { same = false; break; }
        }
        if (same) { ++matches; matchOffset = offset; }
    }
    if (matches != 1) return false;
    std::copy(isaacName.begin(), isaacName.end(), bytes.begin() + matchOffset);
    return Write(path, bytes);
}

bool Exists(const std::wstring& path) {
    return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

bool SameFile(const std::wstring& left, const std::wstring& right) {
    std::vector<char> leftBytes;
    std::vector<char> rightBytes;
    return Read(left, leftBytes) && Read(right, rightBytes) && leftBytes == rightBytes;
}

void Cleanup(const std::wstring& directory) {
    static constexpr const wchar_t* files[] = {
        L"isaac-ng.exe", L"isaac-ng.exe.cofix-original", L"bootstp.dll",
        L"azazel_input_hook.dll", L"cofix_bootstrap_chain.dll",
        L"cofix_bootstrap_owner.txt", L"foreign.bin"
    };
    for (const wchar_t* file : files) DeleteFileW(Join(directory, file).c_str());
    RemoveDirectoryW(directory.c_str());
}

} // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc != 4) return 2;
    static constexpr std::array<char, 8> userenv = {'u','s','e','r','e','n','v',0};
    static constexpr std::array<char, 8> bootstp = {'b','o','o','t','s','t','p',0};
    wchar_t temporaryRoot[MAX_PATH]{};
    if (!GetTempPathW(MAX_PATH, temporaryRoot)) return 3;
    const std::wstring directory = std::wstring(temporaryRoot) + L"cofix-patcher-" +
        std::to_wstring(GetCurrentProcessId());
    Cleanup(directory);
    if (!CreateDirectoryW(directory.c_str(), nullptr)) return 4;
    const std::wstring target = Join(directory, L"isaac-ng.exe");

    // Vanilla userenv path must round-trip both the executable and owned files.
    if (!CopyFileW(argv[3], target.c_str(), FALSE) || !NormalizeFixtureImport(target)) return 10;
    std::vector<char> pristine;
    if (!Read(target, pristine) || Count(pristine, userenv) != 1) return 11;
    if (!Run(argv[1], target)) return 12;
    std::vector<char> installed;
    if (!Read(target, installed) || Count(installed, bootstp) != 1 ||
        !Exists(Join(directory, L"bootstp.dll")) ||
        !Exists(Join(directory, L"azazel_input_hook.dll")) ||
        !Exists(Join(directory, L"cofix_bootstrap_owner.txt")) ||
        Exists(Join(directory, L"cofix_bootstrap_chain.dll"))) return 13;
    if (!Run(argv[2], target)) return 14;
    std::vector<char> restored;
    if (!Read(target, restored) || restored != pristine || Exists(Join(directory, L"bootstp.dll")) ||
        Exists(Join(directory, L"azazel_input_hook.dll")) ||
        Exists(Join(directory, L"cofix_bootstrap_owner.txt"))) return 15;

    // A pre-existing bootstrap must be chained and restored byte-for-byte.
    if (!ReplaceImport(target, userenv, bootstp)) return 20;
    const std::wstring foreign = Join(directory, L"foreign.bin");
    const std::vector<char> foreignBytes = {'f','o','r','e','i','g','n','-','b','o','o','t'};
    if (!Write(foreign, foreignBytes) || !CopyFileW(foreign.c_str(),
            Join(directory, L"bootstp.dll").c_str(), FALSE)) return 21;
    std::vector<char> chainedExe;
    if (!Read(target, chainedExe) || !Run(argv[1], target)) return 22;
    if (!SameFile(foreign, Join(directory, L"cofix_bootstrap_chain.dll")) ||
        SameFile(foreign, Join(directory, L"bootstp.dll"))) return 23;
    std::vector<char> afterChainInstall;
    if (!Read(target, afterChainInstall) || afterChainInstall != chainedExe) return 24;
    if (!Run(argv[2], target)) return 25;
    std::vector<char> afterChainRemove;
    if (!Read(target, afterChainRemove) || afterChainRemove != chainedExe ||
        !SameFile(foreign, Join(directory, L"bootstp.dll")) ||
        Exists(Join(directory, L"cofix_bootstrap_chain.dll")) ||
        Exists(Join(directory, L"azazel_input_hook.dll")) ||
        Exists(Join(directory, L"cofix_bootstrap_owner.txt"))) return 26;

    Cleanup(directory);
    return 0;
}
