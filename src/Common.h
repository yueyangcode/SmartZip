#pragma once
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <shellapi.h>
#include <string>
#include <vector>
#include <algorithm>
#include <cwctype>
#include <stdexcept>

namespace szm {
inline std::wstring ModuleDirectory(HMODULE module) {
    std::wstring path(32768, L'\0');
    DWORD n = GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
    if (!n || n >= path.size()) throw std::runtime_error("module path");
    path.resize(n);
    return path.substr(0, path.find_last_of(L"\\/"));
}
// Windows CommandLineToArgvW/MS CRT quoting; never invoke cmd.exe.
inline std::wstring Quote(const std::wstring& arg) {
    std::wstring out = L"\"";
    size_t slashes = 0;
    for (wchar_t c : arg) {
        if (c == L'\\') { ++slashes; continue; }
        if (c == L'\"') out.append(slashes * 2 + 1, L'\\');
        else out.append(slashes, L'\\');
        slashes = 0; out += c;
    }
    out.append(slashes * 2, L'\\'); out += L'\"'; return out;
}
inline bool ArchiveName(const std::wstring& path) {
    auto dot = path.find_last_of(L'.');
    auto sep = path.find_last_of(L"\\/");
    if (dot == std::wstring::npos || (sep != std::wstring::npos && dot < sep)) return false;
    std::wstring ext = path.substr(dot + 1);
    for (auto& c : ext) if (c >= L'A' && c <= L'Z') c += L'a' - L'A';
    static const wchar_t* fixed[] = {L"zip",L"rar",L"7z",L"cab",L"bz2",L"gz",L"gzip",L"tar"};
    for (auto e : fixed) if (ext == e) return true;
    // Upstream IsPart explicitly recognizes numeric volumes and .partN.rar.
    bool numeric = !ext.empty() && ext.size() <= 6;
    for (auto c : ext) numeric = numeric && c >= L'0' && c <= L'9';
    return numeric;
}
inline HRESULT Spawn(const std::wstring& exe, const std::vector<std::wstring>& args,
                     const std::wstring& cwd, bool wait, DWORD* childExit = nullptr) {
    std::wstring cmd = Quote(exe);
    for (const auto& arg : args) { cmd += L' '; cmd += Quote(arg); }
    if (cmd.size() >= 30000) return HRESULT_FROM_WIN32(ERROR_FILENAME_EXCED_RANGE);
    STARTUPINFOW si{sizeof(si)}; PROCESS_INFORMATION pi{};
    if (!CreateProcessW(exe.c_str(), cmd.data(), nullptr, nullptr, FALSE, 0,
                        nullptr, cwd.c_str(), &si, &pi)) return HRESULT_FROM_WIN32(GetLastError());
    CloseHandle(pi.hThread);
    if (wait) { WaitForSingleObject(pi.hProcess, INFINITE); if(childExit) GetExitCodeProcess(pi.hProcess, childExit); }
    CloseHandle(pi.hProcess); return S_OK;
}
}
