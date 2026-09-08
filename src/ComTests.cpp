#include "Common.h"
#include <shobjidl.h>
#include <shlobj.h>
#include <iostream>
#include <chrono>
static const CLSID id={0xc12835d9,0x8b49,0x48d9,{0xae,0x52,0x5e,0x66,0xd3,0x12,0x09,0xe1}};
int wmain(int argc,wchar_t** argv){
 if(argc!=3)return 1;
 if(FAILED(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED)))return 2;
 auto dll=LoadLibraryW(argv[1]);if(!dll)return 3;
 auto get=reinterpret_cast<HRESULT(WINAPI*)(REFCLSID,REFIID,void**)>(GetProcAddress(dll,"DllGetClassObject"));
 auto unload=reinterpret_cast<HRESULT(WINAPI*)()>(GetProcAddress(dll,"DllCanUnloadNow"));
 IClassFactory* factory=nullptr;if(!get||FAILED(get(id,IID_PPV_ARGS(&factory))))return 4;
 IExplorerCommand* command=nullptr;auto hr=factory->CreateInstance(nullptr,IID_PPV_ARGS(&command));factory->Release();if(FAILED(hr))return 5;
 LPWSTR title=nullptr;if(FAILED(command->GetTitle(nullptr,&title))||std::wstring(title)!=L"智能解压")return 6;CoTaskMemFree(title);
 auto test=[&](std::vector<std::wstring> names,EXPCMDSTATE expected){
  std::vector<PIDLIST_ABSOLUTE> pidls;
  for(auto& name:names){PIDLIST_ABSOLUTE pidl=nullptr;auto path=std::wstring(argv[2])+L"\\"+name;
   if(FAILED(SHParseDisplayName(path.c_str(),nullptr,&pidl,0,nullptr)))return false;pidls.push_back(pidl);}
  IShellItemArray* items=nullptr;HRESULT h=SHCreateShellItemArrayFromIDLists(static_cast<UINT>(pidls.size()),const_cast<PCIDLIST_ABSOLUTE*>(pidls.data()),&items);
  for(auto p:pidls)CoTaskMemFree(p);if(FAILED(h))return false;
  EXPCMDSTATE state=ECS_HIDDEN;h=command->GetState(items,FALSE,&state);
  auto start=std::chrono::steady_clock::now();for(int i=0;i<100;++i)command->GetState(items,FALSE,&state);
  auto ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count()/100;
  items->Release();std::wcout<<names.front()<<L": state="<<state<<L" expected="<<expected<<L" mean-ms="<<ms<<L"\n";return SUCCEEDED(h)&&state==expected;
 };
 bool good=true;
 for(auto n:{L"a.zip",L"a.rar",L"a.7z",L"a.001",L"a.cab",L"a.bz2",L"a.gz",L"a.gzip",L"a.tar"})good=test({n},ECS_ENABLED)&&good;
 good=test({L"a.txt"},ECS_HIDDEN)&&good;good=test({L"folder"},ECS_HIDDEN)&&good;good=test({L"folder.zip"},ECS_HIDDEN)&&good;
 good=test({L"a.zip",L"a.rar",L"a.7z"},ECS_ENABLED)&&good;
 good=test({L"a.zip",L"a.txt"},ECS_HIDDEN)&&good;
 command->Release();if(unload()!=S_OK)good=false;FreeLibrary(dll);CoUninitialize();
 return good?0:7;
}
