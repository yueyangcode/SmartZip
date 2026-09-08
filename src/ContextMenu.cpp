#include "Common.h"
#include <shobjidl.h>
#include <shlwapi.h>
#include <atomic>
#include <new>
#include <mutex>

// Private product CLSID; never reuse another product's registration.
static const CLSID CLSID_SmartZipModern = {0xc12835d9,0x8b49,0x48d9,{0xae,0x52,0x5e,0x66,0xd3,0x12,0x09,0xe1}};
static std::atomic<long> objects{0};
static HMODULE moduleHandle;
static std::wstring installDirectory;
static std::once_flag directoryOnce;
static HRESULT StringResult(const wchar_t* s, LPWSTR* out) {
    if (!out) return E_POINTER; *out = nullptr;
    size_t length=wcslen(s);
    auto p = static_cast<LPWSTR>(CoTaskMemAlloc((length+1)*sizeof(wchar_t)));
    if (!p) return E_OUTOFMEMORY;
    memcpy(p,s,(length+1)*sizeof(wchar_t)); *out=p; return S_OK;
}
static HRESULT Selection(IShellItemArray* items, std::vector<std::wstring>* paths) {
    if (!items) return S_FALSE;
    DWORD count=0; HRESULT hr=items->GetCount(&count);
    if (FAILED(hr)) return hr;
    if (!count || count > 4096) return S_FALSE;
    for (DWORD n=0;n<count;++n) {
        IShellItem* item=nullptr; hr=items->GetItemAt(n,&item); if(FAILED(hr))return hr;
        // Windows exposes browsable archives as FOLDER + STREAM. Reject real
        // directories, not archive files that also implement the folder namespace.
        SFGAOF attr=0; hr=item->GetAttributes(SFGAO_FOLDER|SFGAO_FILESYSTEM|SFGAO_STREAM,&attr);
        if(FAILED(hr) || ((attr&SFGAO_FOLDER) && !(attr&SFGAO_STREAM)) || !(attr&SFGAO_FILESYSTEM)){item->Release();return S_FALSE;}
        LPWSTR path=nullptr;hr=item->GetDisplayName(SIGDN_FILESYSPATH,&path);item->Release();
        if(FAILED(hr))return hr;
        bool ok=szm::ArchiveName(path);
        if(ok && paths){try{paths->emplace_back(path);}catch(...){CoTaskMemFree(path);throw;}}
        CoTaskMemFree(path); if(!ok)return S_FALSE;
    }
    return S_OK;
}
class Command final : public IExplorerCommand {
    std::atomic<ULONG> refs{1};
public:
    Command(){++objects;} ~Command(){--objects;}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,void** out) override {
        if(!out)return E_POINTER;*out=nullptr;
        if(IsEqualIID(iid,IID_IUnknown)||IsEqualIID(iid,IID_IExplorerCommand)){*out=static_cast<IExplorerCommand*>(this);AddRef();return S_OK;}return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override{return ++refs;}
    ULONG STDMETHODCALLTYPE Release() override{ULONG n=--refs;if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE GetTitle(IShellItemArray*,LPWSTR* out) override{return StringResult(L"智能解压",out);}
    HRESULT STDMETHODCALLTYPE GetIcon(IShellItemArray*,LPWSTR* out) override {
        try{return StringResult((installDirectory+L"\\Assets\\SmartZip.ico").c_str(),out);}catch(...){return E_OUTOFMEMORY;}
    }
    HRESULT STDMETHODCALLTYPE GetToolTip(IShellItemArray*,LPWSTR* out) override{return StringResult(L"使用 SmartZip 智能解压所选压缩包",out);}
    HRESULT STDMETHODCALLTYPE GetCanonicalName(GUID* out) override{if(!out)return E_POINTER;*out=CLSID_SmartZipModern;return S_OK;}
    HRESULT STDMETHODCALLTYPE GetState(IShellItemArray* items,BOOL,EXPCMDSTATE* state) override {
        if(!state)return E_POINTER;*state=ECS_HIDDEN;
        try{if(Selection(items,nullptr)==S_OK)*state=ECS_ENABLED;return S_OK;}catch(...){return S_OK;}
    }
    HRESULT STDMETHODCALLTYPE Invoke(IShellItemArray* items,IBindCtx*) override {
        try {
            std::vector<std::wstring> paths;HRESULT hr=Selection(items,&paths);
            if(hr!=S_OK)return FAILED(hr)?hr:E_INVALIDARG;
            paths.insert(paths.begin(),L"x");
            hr=szm::Spawn(installDirectory+L"\\SmartZip.exe",paths,installDirectory,false);
            if(FAILED(hr))MessageBoxW(nullptr,hr==HRESULT_FROM_WIN32(ERROR_FILENAME_EXCED_RANGE)?
                L"所选文件路径总长度过长，请减少一次选择的文件数量。":L"无法启动 SmartZip。请重新安装或检查程序文件。",L"SmartZip Modern",MB_OK|MB_ICONERROR);
            return hr;
        }catch(const std::bad_alloc&){return E_OUTOFMEMORY;}catch(...){return E_FAIL;}
    }
    HRESULT STDMETHODCALLTYPE GetFlags(EXPCMDFLAGS* out) override{if(!out)return E_POINTER;*out=ECF_DEFAULT;return S_OK;}
    HRESULT STDMETHODCALLTYPE EnumSubCommands(IEnumExplorerCommand** out) override{if(out)*out=nullptr;return E_NOTIMPL;}
};
class Factory final : public IClassFactory {
    std::atomic<ULONG> refs{1};
public:
    Factory(){++objects;}~Factory(){--objects;}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,void** out) override{if(!out)return E_POINTER;*out=nullptr;if(IsEqualIID(iid,IID_IUnknown)||IsEqualIID(iid,IID_IClassFactory)){*out=static_cast<IClassFactory*>(this);AddRef();return S_OK;}return E_NOINTERFACE;}
    ULONG STDMETHODCALLTYPE AddRef() override{return ++refs;}
    ULONG STDMETHODCALLTYPE Release() override{ULONG n=--refs;if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer,REFIID iid,void** out) override {
        if(!out)return E_POINTER;*out=nullptr;if(outer)return CLASS_E_NOAGGREGATION;
        auto c=new(std::nothrow) Command;if(!c)return E_OUTOFMEMORY;HRESULT hr=c->QueryInterface(iid,out);c->Release();return hr;
    }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override{if(lock)++objects;else --objects;return S_OK;}
};
extern "C" __declspec(dllexport) HRESULT WINAPI DllGetClassObject(REFCLSID clsid,REFIID iid,void** out) {
    if(!out)return E_POINTER;*out=nullptr;if(!IsEqualCLSID(clsid,CLSID_SmartZipModern))return CLASS_E_CLASSNOTAVAILABLE;
    try{std::call_once(directoryOnce,[]{installDirectory=szm::ModuleDirectory(moduleHandle);});
        auto f=new(std::nothrow) Factory;if(!f)return E_OUTOFMEMORY;HRESULT hr=f->QueryInterface(iid,out);f->Release();return hr;
    }catch(...){return E_FAIL;}
}
extern "C" __declspec(dllexport) HRESULT WINAPI DllCanUnloadNow(){return objects==0?S_OK:S_FALSE;}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,void*){if(reason==DLL_PROCESS_ATTACH){moduleHandle=instance;DisableThreadLibraryCalls(instance);}return TRUE;}
