#include "ActivityLock.h"
#include <commctrl.h>
#include <wintrust.h>
#include <iostream>
int wmain(int count,wchar_t** args) {
    if(count==1){std::cout<<sizeof(TASKDIALOGCONFIG)<<" "<<sizeof(TASKDIALOG_BUTTON)<<" "<<sizeof(WINTRUST_DATA)<<" "<<sizeof(WINTRUST_FILE_INFO)<<std::endl;return 0;}
    if(count>=3&&std::wstring(args[1])==L"--echo"){
        auto out=CreateFileW(args[2],GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);if(out==INVALID_HANDLE_VALUE)return 4;
        std::wstring text;for(int i=3;i<count;i++){text+=args[i];text+=L"\n";}DWORD written=0;
        bool ok=WriteFile(out,text.data(),static_cast<DWORD>(text.size()*sizeof(wchar_t)),&written,nullptr);CloseHandle(out);return ok?0:5;
    }
    if(count!=2)return 2;
    auto handle=szm::OpenActivity(args[1]);
    if(handle==INVALID_HANDLE_VALUE)return 3;
    std::cout<<"HELD"<<std::endl;
    std::string line;std::getline(std::cin,line);CloseHandle(handle);return 0;
}
