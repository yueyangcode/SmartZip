// Helper logs append to version/PID filenames; PIDs can be reused between stages.
// Keep both byte snapshots, and use only the verified appended bytes as evidence.
internal static class HelperLogCapture {
    internal static Dictionary<string,byte[]> Read(string directory,string pattern) =>
        Directory.GetFiles(directory,pattern).ToDictionary(path=>Path.GetFileName(path)!,
            path => {
                if((File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)
                    throw new IOException("Refusing a linked helper log: "+path);
                return File.ReadAllBytes(path);
            },StringComparer.OrdinalIgnoreCase);

    internal static byte[] Appended(byte[] before,byte[] after) {
        if(after.Length<before.Length || !after.AsSpan(0,before.Length).SequenceEqual(before))
            throw new IOException("Helper log was truncated or rewritten; evidence is ambiguous.");
        return after.AsSpan(before.Length).ToArray();
    }

    internal static Dictionary<string,byte[]> Since(Dictionary<string,byte[]> before,Dictionary<string,byte[]> after) {
        if(before.Keys.Any(name=>!after.ContainsKey(name)))
            throw new IOException("A helper log disappeared; evidence is incomplete.");
        var result=new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
        foreach(var (name,bytes) in after) {
            var delta=Appended(before.GetValueOrDefault(name)??Array.Empty<byte>(),bytes);
            if(delta.Length!=0)result.Add(name,delta);
        }
        return result;
    }

    internal static void Save(string directory,Dictionary<string,byte[]> logs) {
        Directory.CreateDirectory(directory);
        foreach(var (name,bytes) in logs) {
            using var file=new FileStream(Path.Combine(directory,name),FileMode.CreateNew,FileAccess.Write,FileShare.None);
            file.Write(bytes);
        }
    }
}
