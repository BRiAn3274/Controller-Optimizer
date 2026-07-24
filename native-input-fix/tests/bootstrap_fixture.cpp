#include <windows.h>
#include <userenv.h>

int main() {
    HANDLE token{};
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return 1;
    char path[MAX_PATH]{};
    DWORD size = static_cast<DWORD>(sizeof(path));
    const BOOL okay = GetUserProfileDirectoryA(token, path, &size);
    CloseHandle(token);
    return okay ? 0 : 2;
}
