using System.Runtime.InteropServices;

internal sealed class UpdateOperation:IDisposable {
    readonly object sync=new();readonly CancellationTokenSource cancel=new();
    string text="正在准备下载……";int percent;bool canCancel=true;
    internal CancellationToken Token=>cancel.Token;
    internal (string Text,int Percent,bool CanCancel) Snapshot {get{lock(sync)return(text,percent,canCancel);}}
    internal void Report(string message,int progress=0){lock(sync){text=message;percent=progress;}}
    internal void Cancel(){lock(sync){if(canCancel){cancel.Cancel();text="正在取消并清理未完成的下载……";}}}
    internal void BeginInstall(){lock(sync){Token.ThrowIfCancellationRequested();canCancel=false;text="正在后台安装，请稍候。不会自动重启电脑。";percent=100;}}
    public void Dispose()=>cancel.Dispose();
}

internal static class UpdateDialog {
    internal const int Install=100,Later=101,Skip=102;
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    delegate int Callback(IntPtr window,uint notification,IntPtr wParam,IntPtr lParam,IntPtr data);
    // commctrl.h explicitly uses pshpack1 for TASKDIALOGCONFIG/TASKDIALOG_BUTTON.
    [StructLayout(LayoutKind.Sequential,Pack=1,CharSet=CharSet.Unicode)]
    struct Button {internal int Id;[MarshalAs(UnmanagedType.LPWStr)]internal string Text;}
    [StructLayout(LayoutKind.Sequential,Pack=1,CharSet=CharSet.Unicode)]
    struct Config {
        internal uint Size;internal IntPtr Parent,Instance;internal uint Flags,Common;
        internal string? Title;internal IntPtr Icon;internal string? Instruction,Content;
        internal uint ButtonCount;internal IntPtr Buttons;internal int DefaultButton;
        internal uint RadioCount;internal IntPtr Radios;internal int DefaultRadio;
        internal string? Verification,Expanded,ExpandText,CollapseText;internal IntPtr FooterIcon;
        internal string? Footer;internal Callback? Callback;internal IntPtr CallbackData;internal uint Width;
    }
    [DllImport("comctl32.dll",ExactSpelling=true,CharSet=CharSet.Unicode)]
    static extern int TaskDialogIndirect(ref Config config,out int button,IntPtr radio,IntPtr verification);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern IntPtr SendMessageW(IntPtr window,uint message,IntPtr wParam,IntPtr lParam);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="SendMessageW")]static extern IntPtr SetText(IntPtr window,uint message,IntPtr element,string text);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int MessageBoxW(IntPtr owner,string text,string caption,uint flags);
    internal static void Info(string text,bool error=false)=>MessageBoxW(IntPtr.Zero,text,"SmartZip 更新",error?0x10u:0x40u);
    static int Show(ref Config config,Button[] buttons) {
        int size=Marshal.SizeOf<Button>();IntPtr memory=buttons.Length==0?IntPtr.Zero:Marshal.AllocHGlobal(size*buttons.Length);int written=0;
        try {
            foreach(var b in buttons){Marshal.StructureToPtr(b,memory+size*written,false);written++;}
            config.Size=(uint)Marshal.SizeOf<Config>();config.ButtonCount=(uint)buttons.Length;config.Buttons=memory;
            int hr=TaskDialogIndirect(ref config,out int button,IntPtr.Zero,IntPtr.Zero);
            GC.KeepAlive(config.Callback);if(hr<0)Marshal.ThrowExceptionForHR(hr);return button;
        }finally {for(int i=0;i<written;i++)Marshal.DestroyStructure<Button>(memory+i*size);if(memory!=IntPtr.Zero)Marshal.FreeHGlobal(memory);}
    }
    internal static int Ask(UpdateRelease release,string current) {
        var config=new Config{Title="SmartZip 更新",Flags=0x8|0x10,Instruction=$"发现新版本 {release.Version}",
            Content=$"当前版本：{current}\n下载大小：{release.Size/1048576.0:F2} MiB\n\n点击立即更新后下载并验证签名，再后台安装。安装位置和用户配置保持不变。",
            Expanded=string.IsNullOrWhiteSpace(release.Notes)?"此版本未提供更新说明。":release.Notes,
            ExpandText="查看更新说明",CollapseText="收起更新说明",DefaultButton=Later,Width=330};
        return Show(ref config,new[]{new Button{Id=Install,Text="立即更新"},new Button{Id=Later,Text="稍后提醒"},new Button{Id=Skip,Text="跳过此版本"}});
    }
    internal static void Run(Func<UpdateOperation,Task> work,string heading="正在更新 SmartZip") {
        using var operation=new UpdateOperation();Task? running=null;Exception? callbackFailure=null;
        Callback callback=(window,message,wParam,lParam,data)=>{
            try {
                if(message==0)running=Task.Run(()=>work(operation));
                if(message==2){if(running?.IsCompleted==true)return 0;operation.Cancel();return 1;}
                if(message==4) {
                    if(running?.IsCompleted==true){SendMessageW(window,1024+102,new IntPtr(2),IntPtr.Zero);return 0;}
                    var status=operation.Snapshot;
                    SetText(window,1024+108,IntPtr.Zero,status.Text);
                    SendMessageW(window,1024+106,new IntPtr(status.Percent),IntPtr.Zero);
                    SendMessageW(window,1024+111,new IntPtr(2),status.CanCancel?new IntPtr(1):IntPtr.Zero);
                }
            }catch(Exception ex){callbackFailure=ex;operation.Cancel();}
            return 0;
        };
        var config=new Config{Title="SmartZip 更新",Instruction=heading,Content="正在准备……",
            Flags=0x200|0x800|0x8,Common=8,Callback=callback,Width=330};
        try{Show(ref config,Array.Empty<Button>());}
        catch{operation.Cancel();if(running!=null)try{running.GetAwaiter().GetResult();}catch{}throw;}
        if(running==null)throw new IOException("更新进度窗口未正常启动，未执行更新。");
        running.GetAwaiter().GetResult();
        if(callbackFailure!=null)throw new IOException("更新进度窗口异常。",callbackFailure);
    }
    internal static (int Config,int Button) Layout()=>(Marshal.SizeOf<Config>(),Marshal.SizeOf<Button>());
}
