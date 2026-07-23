#include "injection.hpp"

#include <iterator>
#include <string>

namespace {

constexpr int kGenericRadio = 1001;
constexpr int kTaintedRadio = 1002;
constexpr int kRefreshButton = 1003;
constexpr int kInjectButton = 1004;

HWND g_window{};
HWND g_status{};
HWND g_injectButton{};

void SetStatus(const wchar_t* text) {
    SetWindowTextW(g_status, text);
}

bool WriteProfile(bool tainted) {
    wchar_t localAppData[MAX_PATH]{};
    const DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", localAppData,
        static_cast<DWORD>(std::size(localAppData)));
    if (!length || length >= std::size(localAppData)) return false;
    const std::wstring directory = std::wstring(localAppData) + L"\\IsaacNativeInputFix";
    if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS) return false;
    const std::wstring path = directory + L"\\config.ini";
    const std::string contents = tainted
        ? "[hook]\r\nmode=tainted-test\r\n"
        : "[hook]\r\nmode=generic-test\r\n";
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written{};
    const DWORD byteCount = static_cast<DWORD>(contents.size());
    const bool success = WriteFile(file, contents.data(), byteCount, &written, nullptr) && written == byteCount;
    CloseHandle(file);
    return success;
}

void RefreshGameState() {
    const bool running = inif::FindProcess(L"isaac-ng.exe") != 0;
    SetStatus(running ? L"已找到正在运行的 Isaac。选择角色模式后确认注入。"
                      : L"未找到 Isaac。请先通过 Steam 启动游戏，然后点击“重新检测”。");
    EnableWindow(g_injectButton, running);
}

void Inject() {
    const DWORD processId = inif::FindProcess(L"isaac-ng.exe");
    if (!processId) {
        RefreshGameState();
        return;
    }
    const bool generic = IsDlgButtonChecked(g_window, kGenericRadio) == BST_CHECKED;
    const bool tainted = IsDlgButtonChecked(g_window, kTaintedRadio) == BST_CHECKED;
    if (!generic && !tainted) {
        MessageBoxW(g_window, L"请选择当前角色模式。", L"Isaac Native Input Fix", MB_OK | MB_ICONWARNING);
        return;
    }
    if (inif::RemoteModuleBase(processId, L"azazel_input_hook.dll")) {
        MessageBoxW(g_window, L"本局已经注入。\n\n如需切换角色模式，请关闭并重启游戏后再注入。",
            L"Isaac Native Input Fix", MB_OK | MB_ICONINFORMATION);
        return;
    }
    const wchar_t* profile = tainted ? L"里阿撒泻勒" : L"普通阿撒泻勒";
    std::wstring prompt = L"确认向正在运行的 Isaac 注入“";
    prompt += profile;
    prompt += L"”本地输入修复吗？";
    if (MessageBoxW(g_window, prompt.c_str(), L"Isaac Native Input Fix", MB_YESNO | MB_ICONQUESTION) != IDYES) {
        return;
    }
    if (!WriteProfile(tainted)) {
        MessageBoxW(g_window, L"无法写入本地配置，注入未执行。", L"Isaac Native Input Fix",
            MB_OK | MB_ICONERROR);
        return;
    }
    EnableWindow(g_injectButton, FALSE);
    SetStatus(L"正在注入...");
    UpdateWindow(g_window);
    const int result = inif::InjectPayload(processId, inif::SiblingPayloadPath());
    if (result != 0) {
        SetStatus(L"注入失败。请查看提示和 diagnostics.json。");
        EnableWindow(g_injectButton, TRUE);
        MessageBoxW(g_window, L"注入失败。\n\n请确认游戏版本受支持、游戏和工具使用相同权限，并检查 diagnostics.json。",
            L"Isaac Native Input Fix", MB_OK | MB_ICONERROR);
        return;
    }
    SetStatus(L"注入成功。关闭游戏后会自动恢复原始输入。");
    MessageBoxW(g_window, L"注入成功。\n\n现在只测试已选择的角色；关闭游戏后会自动恢复原始输入。",
        L"Isaac Native Input Fix", MB_OK | MB_ICONINFORMATION);
}

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam) {
    if (message == WM_COMMAND && HIWORD(wParam) == BN_CLICKED) {
        if (LOWORD(wParam) == kRefreshButton) RefreshGameState();
        if (LOWORD(wParam) == kInjectButton) Inject();
        return 0;
    }
    if (message == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window, message, wParam, lParam);
}

} // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand) {
    const wchar_t className[] = L"IsaacNativeInputLauncher";
    WNDCLASSW windowClass{};
    windowClass.hInstance = instance;
    windowClass.lpszClassName = className;
    windowClass.lpfnWndProc = WindowProcedure;
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_BTNFACE + 1);
    RegisterClassW(&windowClass);

    g_window = CreateWindowExW(0, className, L"Isaac Native Input Fix", WS_OVERLAPPED | WS_CAPTION |
        WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, 500, 235, nullptr, nullptr, instance, nullptr);
    CreateWindowW(L"STATIC", L"本地手柄输入修复（实验版）", WS_CHILD | WS_VISIBLE,
        22, 18, 430, 22, g_window, nullptr, instance, nullptr);
    CreateWindowW(L"BUTTON", L"普通阿撒泻勒", WS_CHILD | WS_VISIBLE | BS_AUTORADIOBUTTON,
        28, 54, 180, 24, g_window, reinterpret_cast<HMENU>(kGenericRadio), instance, nullptr);
    CreateWindowW(L"BUTTON", L"里阿撒泻勒", WS_CHILD | WS_VISIBLE | BS_AUTORADIOBUTTON,
        225, 54, 180, 24, g_window, reinterpret_cast<HMENU>(kTaintedRadio), instance, nullptr);
    CreateWindowW(L"BUTTON", L"重新检测", WS_CHILD | WS_VISIBLE,
        22, 98, 110, 32, g_window, reinterpret_cast<HMENU>(kRefreshButton), instance, nullptr);
    g_injectButton = CreateWindowW(L"BUTTON", L"确认注入", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
        145, 98, 130, 32, g_window, reinterpret_cast<HMENU>(kInjectButton), instance, nullptr);
    g_status = CreateWindowW(L"STATIC", L"正在检测 Isaac...", WS_CHILD | WS_VISIBLE,
        22, 153, 440, 36, g_window, nullptr, instance, nullptr);
    RefreshGameState();
    ShowWindow(g_window, showCommand);
    UpdateWindow(g_window);

    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0)) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return static_cast<int>(message.wParam);
}
