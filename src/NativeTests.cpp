#include "Common.h"
#include <iostream>
int wmain() {
    std::vector<std::wstring> values{L"",L"x",L"中文 路径\\压缩包.zip",L"C:\\尾部\\",L"a\"b",L"a&b%1^!.7z",L"emoji-\U0001f4e6.rar"};
    std::wstring cmd=L"test.exe";for(auto& v:values)cmd+=L" "+szm::Quote(v);
    int n=0;auto parsed=CommandLineToArgvW(cmd.c_str(),&n);if(!parsed||n!=values.size()+1)return 1;
    for(int i=1;i<n;++i)if(values[i-1]!=parsed[i])return 2;LocalFree(parsed);
    for(auto v:{L"a.zip",L"a.RAR",L"a.7z",L"a.tar.gz",L"a.001",L"a.part001.rar",L"a.cab",L"a.bz2",L"a.gzip"})if(!szm::ArchiveName(v))return 3;
    for(auto v:{L"a.txt",L"a.exe",L"directory",L"folder.zip\\a.txt",L"a.zip.txt"})if(szm::ArchiveName(v))return 4;
    std::cout<<"PASS: Unicode argument round-trip, extension and split-volume filtering\n";
}
