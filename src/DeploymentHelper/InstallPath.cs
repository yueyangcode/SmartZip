internal static class InstallPath {
    internal static void RequireUnused(string target) {
        try { _ = File.GetAttributes(target); }
        catch (FileNotFoundException) { return; }
        catch (DirectoryNotFoundException) { return; }
        // Access errors are not evidence that a path is free. Propagate them.
        throw new InstallDirectoryOccupiedException(target);
    }
    internal static string FromParent(string parent) {
        if (!Path.IsPathFullyQualified(parent) || parent.StartsWith(@"\\") || parent.IndexOf(':', 2) >= 0)
            throw new IOException("请选择本地磁盘上的完整父目录路径。");
        var full = Path.GetFullPath(parent).TrimEnd(Path.DirectorySeparatorChar);
        var target = string.Equals(Path.GetFileName(full), "SmartZip", StringComparison.OrdinalIgnoreCase)
            ? full : Path.Combine(full + (full.EndsWith(':') ? @"\" : ""), "SmartZip");
        return Validate(target);
    }
    internal static string Validate(string target) {
        if (!Path.IsPathFullyQualified(target) || target.StartsWith(@"\\") || target.IndexOf(':', 2) >= 0)
            throw new IOException("不支持网络路径、设备路径或相对路径。");
        target = Path.GetFullPath(target).TrimEnd(Path.DirectorySeparatorChar);
        if (!string.Equals(Path.GetFileName(target), "SmartZip", StringComparison.OrdinalIgnoreCase))
            throw new IOException("安装目录必须是父目录下独立的 SmartZip 文件夹。");
        var drive = new DriveInfo(Path.GetPathRoot(target)!);
        if (drive.DriveType != DriveType.Fixed || !drive.IsReady || drive.DriveFormat != "NTFS")
            throw new IOException("请选择本地固定 NTFS 磁盘，不支持移动磁盘或网络磁盘。");
        for (var d = new DirectoryInfo(target); d != null; d = d.Parent)
            if (d.Exists && (d.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("安装路径不能包含符号链接或目录联接。");
        return target;
    }
}

internal sealed class InstallDirectoryOccupiedException(string path) : IOException(
    "安装目录已存在：\n" + path + "\n\n为保护原有文件，此测试版不会覆盖该目录。请选择其他父目录，例如使用默认安装位置。不要删除原 SmartZip 文件夹。");
