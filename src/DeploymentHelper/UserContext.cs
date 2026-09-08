using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;

internal static class UserContext {
    [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out SafeAccessTokenHandle token);
    [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(SafeAccessTokenHandle token,int kind,out int value,int length,out int returned);

    // Default (1) is an unsplit token, NOT proof of a non-admin account.
    internal static bool Allowed(bool sameUser,bool sameSession,bool admin,int? enableLua,int elevationType) =>
        sameUser && sameSession && elevationType is >=1 and <=3 &&
        ((!admin && elevationType!=2) || (admin && enableLua==0 && elevationType==1));

    internal static string Require(Action<string> log){
        using var current=WindowsIdentity.GetCurrent();
        string sid=current.User?.Value??throw new InvalidOperationException("No current user SID.");
        var window=GetShellWindow();
        if(window==IntPtr.Zero||GetWindowThreadProcessId(window,out uint shellPid)==0)
            throw new InvalidOperationException("An interactive Windows desktop is required. No shell identity could be verified.");
        using var shell=Process.GetProcessById(checked((int)shellPid));
        using var process=Process.GetCurrentProcess();
        if(!OpenProcessToken(shell.Handle,8,out var token))throw new Win32Exception(Marshal.GetLastWin32Error());
        using(token){
            using var desktop=new WindowsIdentity(token.DangerousGetHandle());
            if(!GetTokenInformation(current.AccessToken,18,out int type,sizeof(int),out _))throw new Win32Exception(Marshal.GetLastWin32Error());
            using var policy=Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System");
            int? lua=policy?.GetValue("EnableLUA") is int value?value:null;
            bool admin=new WindowsPrincipal(current).IsInRole(WindowsBuiltInRole.Administrator);
            bool same=sid==desktop.User?.Value,session=process.SessionId!=0&&process.SessionId==shell.SessionId;
            log($"USER_CONTEXT SID={sid}; ShellSID={desktop.User?.Value}; SameSession={session}; Admin={admin}; EnableLUA={lua}; TokenElevationType={type}");
            if(!Allowed(same,session,admin,lua,type))
                throw new InvalidOperationException("Installation must use the interactive desktop user's identity. With UAC enabled, launch without elevation. With UAC disabled, only a same-user unsplit token is accepted. No security settings were changed.");
        }
        return sid;
    }
}
