#include "Common.h"
int WINAPI wWinMain(HINSTANCE,HINSTANCE,LPWSTR,int) {
    try {
        const auto dir=szm::ModuleDirectory(nullptr);
        int count=0;LPWSTR* argv=CommandLineToArgvW(GetCommandLineW(),&count);
        if(!argv)return 2;
        const bool checkUpdates=count==2 && std::wstring(argv[1])==L"--check-updates";
        // Installed builds only: no GitHub polling from workspace smoke tests.
        if(checkUpdates || GetFileAttributesW((dir+L"\\installed.json").c_str())!=INVALID_FILE_ATTRIBUTES) {
            std::vector<std::wstring> updateArgs{L"check-updates"};
            if(!checkUpdates)updateArgs.emplace_back(L"--no-ui");
            szm::Spawn(dir+L"\\DeploymentHelper.exe",updateArgs,dir,false);
        }
        if(checkUpdates){LocalFree(argv);return 0;}
        std::vector<std::wstring> args{L"/ErrorStdOut=UTF-8",dir+L"\\Engine\\SmartZip.ahk"};
        for(int i=1;i<count;++i)args.emplace_back(argv[i]);LocalFree(argv);
        DWORD exitCode=0;HRESULT hr=szm::Spawn(dir+L"\\Engine\\AutoHotkey64.exe",args,dir,true,&exitCode);
        if(FAILED(hr)){MessageBoxW(nullptr,L"SmartZip 无法启动。程序文件可能缺失，或所选路径总长度过长。",L"SmartZip",MB_OK|MB_ICONERROR);return 2;}
        return static_cast<int>(exitCode);
    }catch(...){return 2;}
}
