#pragma once
#include "Common.h"
#include <shlobj.h>

namespace szm {
// A read-shared lease permits parallel extraction. The updater takes an
// exclusive file handle, so a new extraction cannot race installation.
inline bool ActivityPathSafe(const std::wstring& file) {
    for(auto path=file;!path.empty();) {
        DWORD attrs=GetFileAttributesW(path.c_str());
        if(attrs!=INVALID_FILE_ATTRIBUTES&&(attrs&FILE_ATTRIBUTE_REPARSE_POINT)){SetLastError(ERROR_REPARSE_TAG_INVALID);return false;}
        auto slash=path.find_last_of(L"\\/");if(slash==std::wstring::npos||slash<3)break;path.resize(slash);
    }
    return true;
}
inline HANDLE OpenActivity(const std::wstring& file) {
    if(!ActivityPathSafe(file))return INVALID_HANDLE_VALUE;
    return CreateFileW(file.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
}
inline std::wstring ActivityPath() {
    PWSTR local=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&local)))throw std::runtime_error("local app data");
    std::wstring path=local;CoTaskMemFree(local);
    if(!ActivityPathSafe(path))throw std::runtime_error("activity directory reparse point");
    for(auto leaf:{L"\\SmartZip",L"\\UpdateCheck"}){
        path+=leaf;
        if(!CreateDirectoryW(path.c_str(),nullptr)&&GetLastError()!=ERROR_ALREADY_EXISTS)throw std::runtime_error("activity directory");
        DWORD attrs=GetFileAttributesW(path.c_str());
        if(attrs==INVALID_FILE_ATTRIBUTES||!(attrs&FILE_ATTRIBUTE_DIRECTORY)||(attrs&FILE_ATTRIBUTE_REPARSE_POINT))throw std::runtime_error("activity directory type");
    }
    return path+L"\\activity.lock";
}
struct ActivityLease {
    HANDLE handle=INVALID_HANDLE_VALUE;
    ~ActivityLease(){if(handle!=INVALID_HANDLE_VALUE)CloseHandle(handle);}
};
}
