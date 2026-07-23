#pragma once

#include <windows.h>

#include <cstdint>
#include <string>

namespace inif {

DWORD FindProcess(const wchar_t* executable);
uintptr_t RemoteModuleBase(DWORD processId, const wchar_t* moduleName);
int InjectPayload(DWORD processId, const std::wstring& payload);
std::wstring SiblingPayloadPath();

} // namespace inif
