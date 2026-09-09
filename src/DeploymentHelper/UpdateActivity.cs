internal static class UpdateActivity {
    internal static bool IsSharingViolation(IOException error)=>(error.HResult&0xffff) is 32 or 33;
    internal static void NoLinks(string path) {
        for(var p=Path.GetFullPath(path);!string.IsNullOrEmpty(p);p=Path.GetDirectoryName(p)!) {
            try{if((File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0)throw new IOException("更新工作目录包含重解析点，已停止操作。");}
            catch(FileNotFoundException){}catch(DirectoryNotFoundException){}
        }
    }
    internal static async Task<FileStream> WaitForIdle(string file,CancellationToken cancel,Action waiting) {
        while(true) {
            cancel.ThrowIfCancellationRequested();NoLinks(file);
            try{return new FileStream(file,FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}
            catch(IOException ex)when(IsSharingViolation(ex)){waiting();await Task.Delay(500,cancel);}
        }
    }
}
