using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

internal static class UpdateSignature {
    internal static (int Data,int File) Layout()=>(Marshal.SizeOf<TrustData>(),Marshal.SizeOf<TrustFile>());
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
    struct TrustFile {internal uint Size;[MarshalAs(UnmanagedType.LPWStr)]internal string Path;internal IntPtr Handle,KnownSubject;}
    [StructLayout(LayoutKind.Sequential)]
    struct TrustData {
        internal uint Size;internal IntPtr Policy,Sip;internal uint Ui,Revocation,Choice;internal IntPtr File;
        internal uint Action;internal IntPtr State,Url;internal uint Flags,Context;internal IntPtr SignatureSettings;
    }
    [StructLayout(LayoutKind.Sequential)]struct ProviderCertificate {internal uint Size;internal IntPtr Certificate;}
    [DllImport("wintrust.dll",ExactSpelling=true)]static extern int WinVerifyTrust(IntPtr window,ref Guid action,ref TrustData data);
    [DllImport("wintrust.dll",ExactSpelling=true)]static extern IntPtr WTHelperProvDataFromStateData(IntPtr state);
    [DllImport("wintrust.dll",ExactSpelling=true)]static extern IntPtr WTHelperGetProvSignerFromChain(IntPtr data,uint index,[MarshalAs(UnmanagedType.Bool)]bool counter,uint counterIndex);
    [DllImport("wintrust.dll",ExactSpelling=true)]static extern IntPtr WTHelperGetProvCertFromChain(IntPtr signer,uint index);
    internal static void Verify(string file,string version,string expectedSubject,string expectedCertificateHash,bool testSigned) {
        var info=new TrustFile{Size=(uint)Marshal.SizeOf<TrustFile>(),Path=file};
        IntPtr memory=Marshal.AllocHGlobal(Marshal.SizeOf<TrustFile>());Marshal.StructureToPtr(info,memory,false);
        var data=new TrustData{Size=(uint)Marshal.SizeOf<TrustData>(),Ui=2,Revocation=1,Choice=1,File=memory,Action=1,Flags=0x80|0x2000};
        var action=new Guid("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");
        try {
            int result=WinVerifyTrust(new IntPtr(-1),ref action,ref data);
            if(result!=0)throw new IOException("更新包的 Windows 数字签名验证失败：0x"+result.ToString("X8"));
            var provider=WTHelperProvDataFromStateData(data.State);
            var signer=provider==IntPtr.Zero?IntPtr.Zero:WTHelperGetProvSignerFromChain(provider,0,false,0);
            var certificate=signer==IntPtr.Zero?IntPtr.Zero:WTHelperGetProvCertFromChain(signer,0);
            if(certificate==IntPtr.Zero)throw new IOException("无法取得已验证的更新签名者。");
            using var cert=new X509Certificate2(Marshal.PtrToStructure<ProviderCertificate>(certificate).Certificate);
            if(cert.Subject!=expectedSubject||Convert.ToHexString(SHA256.HashData(cert.RawData))!=expectedCertificateHash||
               (!testSigned&&cert.Subject==cert.Issuer))throw new IOException("更新包签名者与当前安装不一致，不会自动导入证书或切换发布者。");
            var v=FileVersionInfo.GetVersionInfo(file);
            if(v.ProductVersion?.Trim()!=version||v.ProductName?.Trim()!="SmartZip")throw new IOException("更新包产品名称或版本不匹配。");
        }finally {
            data.Action=2;WinVerifyTrust(new IntPtr(-1),ref action,ref data);
            Marshal.DestroyStructure<TrustFile>(memory);Marshal.FreeHGlobal(memory);
        }
    }
}
