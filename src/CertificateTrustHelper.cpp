// Test-only native elevation broker. No file paths, shell commands, or certificate
// material are accepted over IPC. The one permitted DER certificate is embedded.
#include "Common.h"
#include <wincrypt.h>
#include <sddl.h>
#include <cstdio>
#include "CertificateIdentity.g.h"

static constexpr wchar_t KeyBase[]=L"SOFTWARE\\SmartZipModernTestTrust\\";
static void Check(bool ok){if(!ok)throw std::runtime_error("certificate broker operation failed");}
static std::string Hex(const BYTE* b,DWORD n){static const char* h="0123456789ABCDEF";std::string s;for(DWORD i=0;i<n;++i){s+=h[b[i]>>4];s+=h[b[i]&15];}return s;}
static std::wstring CallerSid(DWORD pid){
 HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,pid);Check(process!=nullptr);
 HANDLE token=nullptr;BOOL ok=OpenProcessToken(process,TOKEN_QUERY,&token);CloseHandle(process);Check(ok);
 DWORD n=0;GetTokenInformation(token,TokenUser,nullptr,0,&n);std::vector<BYTE> bytes(n);
 ok=GetTokenInformation(token,TokenUser,bytes.data(),n,&n);CloseHandle(token);Check(ok);
 LPWSTR text=nullptr;Check(ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(bytes.data())->User.Sid,&text));
 std::wstring sid(text);LocalFree(text);return sid;
}
static bool IsAdmin(){SID_IDENTIFIER_AUTHORITY nt=SECURITY_NT_AUTHORITY;PSID sid=nullptr;BOOL yes=FALSE;
 if(AllocateAndInitializeSid(&nt,2,SECURITY_BUILTIN_DOMAIN_RID,DOMAIN_ALIAS_RID_ADMINS,0,0,0,0,0,0,&sid)){CheckTokenMembership(nullptr,sid,&yes);FreeSid(sid);}return yes;}
static PCCERT_CONTEXT Certificate(bool requireCurrentValidity=true){
 BYTE hash[32];DWORD size=sizeof(hash);Check(CryptHashCertificate2(L"SHA256",0,nullptr,EmbeddedCertificate,sizeof(EmbeddedCertificate),hash,&size));
 Check(Hex(hash,size)==CertificateSha256);
 auto c=CertCreateCertificateContext(X509_ASN_ENCODING,EmbeddedCertificate,sizeof(EmbeddedCertificate));Check(c!=nullptr);
 try {
  wchar_t subject[512];Check(CertNameToStrW(X509_ASN_ENCODING,&c->pCertInfo->Subject,CERT_X500_NAME_STR,subject,512)>1);
  Check(std::wstring(subject)==CertificateSubject);BYTE thumb[20];size=sizeof(thumb);
  Check(CertGetCertificateContextProperty(c,CERT_SHA1_HASH_PROP_ID,thumb,&size));Check(Hex(thumb,size)==CertificateThumbprint);
  if(requireCurrentValidity)Check(CertVerifyTimeValidity(nullptr,c->pCertInfo)==0);
  Check(CompareFileTime(&c->pCertInfo->NotBefore,&CertificateNotBefore)==0 && CompareFileTime(&c->pCertInfo->NotAfter,&CertificateNotAfter)==0);
  BYTE usage=0;Check(CertGetIntendedKeyUsage(X509_ASN_ENCODING,c->pCertInfo,&usage,1));Check(usage==CERT_DIGITAL_SIGNATURE_KEY_USAGE);
  size=0;Check(CertGetEnhancedKeyUsage(c,0,nullptr,&size));std::vector<BYTE> ekub(size);
  auto eku=reinterpret_cast<PCERT_ENHKEY_USAGE>(ekub.data());Check(CertGetEnhancedKeyUsage(c,0,eku,&size));
  Check(eku->cUsageIdentifier==1 && std::string(eku->rgpszUsageIdentifier[0])==szOID_PKIX_KP_CODE_SIGNING);
  Check(CryptVerifyCertificateSignatureEx(0,X509_ASN_ENCODING,CRYPT_VERIFY_CERT_SIGN_SUBJECT_CERT,(void*)c,CRYPT_VERIFY_CERT_SIGN_ISSUER_CERT,(void*)c,0,nullptr));
  return c;
 }catch(...){CertFreeCertificateContext(c);throw;}
}
struct TrustSession {
 PCCERT_CONTEXT cert=Certificate(false); HCERTSTORE store=nullptr; HKEY key=nullptr;
 std::wstring sid,keyPath; bool created=false,newRecord=false,newLease=false,done=false;
 explicit TrustSession(DWORD pid):sid(CallerSid(pid)),keyPath(KeyBase+std::wstring(CertificateThumbprintW)){
  store=CertOpenStore(CERT_STORE_PROV_SYSTEM_W,0,0,CERT_SYSTEM_STORE_LOCAL_MACHINE|CERT_STORE_OPEN_EXISTING_FLAG,L"TrustedPeople");Check(store!=nullptr);
 }
 ~TrustSession(){if(!done){try{Rollback();}catch(...){}}if(key)RegCloseKey(key);if(store)CertCloseStore(store,0);if(cert)CertFreeCertificateContext(cert);}
 PCCERT_CONTEXT Find(){BYTE hash[20];DWORD n=sizeof(hash);Check(CertGetCertificateContextProperty(cert,CERT_SHA1_HASH_PROP_ID,hash,&n));CRYPT_HASH_BLOB blob{n,hash};auto found=CertFindCertificateInStore(store,X509_ASN_ENCODING,0,CERT_FIND_SHA1_HASH,&blob,nullptr);if(found)Check(found->cbCertEncoded==sizeof(EmbeddedCertificate)&&memcmp(found->pbCertEncoded,EmbeddedCertificate,sizeof(EmbeddedCertificate))==0);return found;}
 void OpenKey(bool create){if(key)return;DWORD disposition=0;LSTATUS e=create?RegCreateKeyExW(HKEY_LOCAL_MACHINE,keyPath.c_str(),0,nullptr,0,KEY_READ|KEY_WRITE|KEY_WOW64_64KEY,nullptr,&key,&disposition):RegOpenKeyExW(HKEY_LOCAL_MACHINE,keyPath.c_str(),0,KEY_READ|KEY_WRITE|KEY_WOW64_64KEY,&key);if(!create&&e==ERROR_FILE_NOT_FOUND)return;Check(e==ERROR_SUCCESS);if(create){Check(disposition==REG_CREATED_NEW_KEY);newRecord=true;}}
 std::wstring Read(const wchar_t* name){if(!key)return L"";wchar_t b[256]{};DWORD n=sizeof(b),type=0;auto e=RegQueryValueExW(key,name,nullptr,&type,(BYTE*)b,&n);if(e==ERROR_FILE_NOT_FOUND)return L"";Check(e==ERROR_SUCCESS&&type==REG_SZ&&n>=2&&n<=sizeof(b)&&b[n/2-1]==0);return b;}
 void Write(const wchar_t* name,const std::wstring& value){Check(RegSetValueExW(key,name,0,REG_SZ,(const BYTE*)value.c_str(),static_cast<DWORD>((value.size()+1)*2))==ERROR_SUCCESS);}
 bool HasLease(){if(!key)return false;DWORD t=0,n=0;return RegQueryValueExW(key,sid.c_str(),nullptr,&t,nullptr,&n)==ERROR_SUCCESS;}
 int LeaseCount(){if(!key)return 0;int count=0;for(DWORD i=0;;++i){wchar_t name[256];DWORD n=256;auto e=RegEnumValueW(key,i,name,&n,nullptr,nullptr,nullptr,nullptr);if(e==ERROR_NO_MORE_ITEMS)break;Check(e==ERROR_SUCCESS);if(std::wstring(name).rfind(L"S-1-",0)==0)++count;}return count;}
 void CheckRecord(){if(key)Check(Read(L"Subject")==CertificateSubject && Read(L"SHA256")==CertificateSha256W);}
 std::string Begin(){
  Check(CertVerifyTimeValidity(nullptr,cert->pCertInfo)==0);
  auto old=Find();bool present=old!=nullptr;if(old){Check(old->cbCertEncoded==sizeof(EmbeddedCertificate)&&memcmp(old->pbCertEncoded,EmbeddedCertificate,sizeof(EmbeddedCertificate))==0);CertFreeCertificateContext(old);}
  OpenKey(false);CheckRecord();
  if(!present){
   // A stale record is not silently adopted; a prior interrupted run needs review.
   Check(key==nullptr);OpenKey(true);Write(L"Subject",CertificateSubject);Write(L"SHA256",CertificateSha256W);Write(L"Creator",sid);
   // ADD_NEW must succeed before ownership is claimed. Never delete a certificate
   // concurrently imported by someone else when this call fails with EXISTS.
   created=CertAddCertificateContextToStore(store,cert,CERT_STORE_ADD_NEW,nullptr)!=FALSE;Check(created);
  }
  if(key&&!HasLease()){newLease=true;Write(sid.c_str(),L"1");}
  return created?"CREATED":"PREEXISTING";
 }
 void Rollback(){
  if(key&&newLease){auto e=RegDeleteValueW(key,sid.c_str());Check(e==ERROR_SUCCESS||e==ERROR_FILE_NOT_FOUND);}
  if(created){auto existing=Find();if(existing)Check(CertDeleteCertificateFromStore(existing));}
  if(newRecord){
   if(key){RegCloseKey(key);key=nullptr;}auto e=RegDeleteKeyExW(HKEY_LOCAL_MACHINE,keyPath.c_str(),KEY_WOW64_64KEY,0);Check(e==ERROR_SUCCESS||e==ERROR_FILE_NOT_FOUND);
   RegDeleteKeyExW(HKEY_LOCAL_MACHINE,L"SOFTWARE\\SmartZipModernTestTrust",KEY_WOW64_64KEY,0); // succeeds only if empty
  }done=true;
 }
 std::string Release(bool permitDelete){
  OpenKey(false);CheckRecord();if(!key){done=true;return "RETAINED";}
  // Only this product's protected marker can authorize removal; pre-existing
  // unmanaged certificates and other users' leases are never removed.
  bool ours=Read(L"Creator")==sid;if(HasLease())Check(RegDeleteValueW(key,sid.c_str())==ERROR_SUCCESS);
  if(permitDelete&&ours&&LeaseCount()==0){auto old=Find();if(old)Check(CertDeleteCertificateFromStore(old));
   RegCloseKey(key);key=nullptr;Check(RegDeleteKeyExW(HKEY_LOCAL_MACHINE,keyPath.c_str(),KEY_WOW64_64KEY,0)==ERROR_SUCCESS);
   RegDeleteKeyExW(HKEY_LOCAL_MACHINE,L"SOFTWARE\\SmartZipModernTestTrust",KEY_WOW64_64KEY,0);done=true;return "REMOVED";
  }done=true;return "RETAINED";
 }
};
static bool Send(HANDLE pipe,const std::string& s){DWORD n=0;auto line=s+"\n";return WriteFile(pipe,line.data(),static_cast<DWORD>(line.size()),&n,nullptr)&&n==line.size();}
static std::string Receive(HANDLE pipe){std::string line;for(;;){char c;DWORD n=0;if(!ReadFile(pipe,&c,1,&n,nullptr)||!n)throw std::runtime_error("pipe closed");if(c=='\n')return line;Check(line.size()<32);line+=c;}}
#ifdef CERTIFICATE_SELF_TEST
int wmain(){try{auto c=Certificate();CertFreeCertificateContext(c);std::puts("PASS embedded DER, SHA256, thumbprint, subject, validity, code-signing EKU, self-signature; no store writes");return 0;}catch(...){return 1;}}
#else
int WINAPI wWinMain(HINSTANCE,HINSTANCE,LPWSTR,int){
 HANDLE pipe=INVALID_HANDLE_VALUE,mutex=nullptr;bool locked=false;int exitCode=1;
 try{
  SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32);Check(IsAdmin());
  int count=0;auto args=CommandLineToArgvW(GetCommandLineW(),&count);Check(args!=nullptr);
  if(count!=4||std::wstring(args[1])!=L"--session"){LocalFree(args);return 2;}
  std::wstring nonce=args[2],pidText=args[3];LocalFree(args);
  Check(nonce.size()==32&&std::all_of(nonce.begin(),nonce.end(),[](wchar_t c){return(c>=L'0'&&c<=L'9')||(c>=L'a'&&c<=L'f');}));
  Check(!pidText.empty()&&pidText.size()<=10&&std::all_of(pidText.begin(),pidText.end(),[](wchar_t c){return c>=L'0'&&c<=L'9';}));
  DWORD pid=std::stoul(pidText);Check(pid!=0);
  // Serialize access to the fixed machine-level certificate and ownership marker.
  mutex=CreateMutexW(nullptr,FALSE,L"Global\\SmartZipModernTestTrust-7DA69699");Check(mutex!=nullptr);
  auto wait=WaitForSingleObject(mutex,120000);Check(wait==WAIT_OBJECT_0||wait==WAIT_ABANDONED);locked=true;
  std::wstring name=L"\\\\.\\pipe\\SmartZipModernTrust-"+nonce;
  pipe=CreateFileW(name.c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,SECURITY_SQOS_PRESENT|SECURITY_IDENTIFICATION,nullptr);Check(pipe!=INVALID_HANDLE_VALUE);
  ULONG server=0;Check(GetNamedPipeServerProcessId(pipe,&server)&&server==pid);
  TrustSession tx(pid);Check(Send(pipe,"READY"));
  auto first=Receive(pipe);Check(first=="BEGIN"||first=="OPEN");
  Check(Send(pipe,first=="BEGIN"?tx.Begin():"OPENED"));
  auto decision=Receive(pipe);
  if(decision=="COMMIT"){tx.done=true;Check(Send(pipe,"COMMITTED"));}
  else if(decision=="ROLLBACK"){tx.Rollback();Check(Send(pipe,"ROLLEDBACK"));}
  else if(first=="OPEN"&&(decision=="RELEASE_OWNED"||decision=="RELEASE_SHARED")){Check(Send(pipe,tx.Release(decision=="RELEASE_OWNED")));}
  else throw std::runtime_error("invalid command");exitCode=0;
 }catch(...){if(pipe!=INVALID_HANDLE_VALUE)Send(pipe,"ERROR");}
 if(pipe!=INVALID_HANDLE_VALUE)CloseHandle(pipe);if(locked)ReleaseMutex(mutex);if(mutex)CloseHandle(mutex);return exitCode;
}
#endif
