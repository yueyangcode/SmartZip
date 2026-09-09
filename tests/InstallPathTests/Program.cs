static void Check(bool ok) { if (!ok) throw new Exception("Path safety test failed"); }
var parent = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "测试 空格 & (目录)");
Check(InstallPath.FromParent(parent) == Path.Combine(parent, "SmartZip"));
Check(InstallPath.FromParent(Path.Combine(parent, "SmartZip")) == Path.Combine(parent, "SmartZip"));
Check(InstallPath.FromParent(parent+@"\") == Path.Combine(parent,"SmartZip"));
Check(InstallPath.FromParent(Path.Combine(parent,"smartzip")+@"\") == Path.Combine(parent,"smartzip"));
Check(InstallPath.FromParent(Path.Combine(parent,"SmartZipTools")) == Path.Combine(parent,"SmartZipTools","SmartZip"));
var driveRoot=Path.GetPathRoot(parent)!;
Check(InstallPath.FromParent(driveRoot) == Path.Combine(driveRoot,"SmartZip"));
Check(InstallPath.FromParent(InstallPath.FromParent(parent)) == InstallPath.FromParent(parent));
var existingFile=typeof(InstallPath).Assembly.Location;
foreach(var occupied in new[]{existingFile,Path.GetDirectoryName(existingFile)!}) {
    bool refused=false;try{InstallPath.RequireUnused(occupied);}catch(InstallDirectoryOccupiedException e){refused=e.Message.Contains(occupied);}
    Check(refused);
}
InstallPath.RequireUnused(Path.Combine(Path.GetDirectoryName(existingFile)!,"does-not-exist-"+Guid.NewGuid().ToString("N")));
Console.WriteLine("PASS occupied file/directory rejection and unused path acceptance; no files changed");
foreach (var bad in new[]{@"relative", @"\\server\share\SmartZip", @"\\?\C:\SmartZip", @"C:\", @"C:\Windows", @"C:\SmartZip:stream"}) {
    bool refused=false; try { InstallPath.Validate(bad); } catch (IOException) { refused=true; }
    Check(refused);
}
Console.WriteLine("PASS parent suffix, no duplicate folder, Unicode, relative/UNC/device/root/ADS rejection; no files created");
Check(UpdateRelease.ParseVersion("v1.2.3.0") == UpdateRelease.ParseVersion("1.2.3.0"));
Check(UpdateRelease.ParseVersion("v1.10.0.0") > UpdateRelease.ParseVersion("1.9.9.0"));
foreach (var invalid in new[]{"latest", "v1.0-beta", "https://evil.example", "../../installer"}) {
    bool refused=false; try { UpdateRelease.ParseVersion(invalid); } catch (IOException) { refused=true; }
    Check(refused);
}
Console.WriteLine("PASS update numeric version comparison and invalid tags; no network requests");
for (int mask=0;mask<16;mask++) {
    bool refused=false;
    try { UpgradeBaseline.RequireCoherent((mask&1)!=0,(mask&2)!=0,(mask&4)!=0,(mask&8)!=0); }
    catch (UpgradeBaselineException) { refused=true; }
    Check(refused == (mask!=0 && mask!=15));
}
Console.WriteLine("PASS 16 upgrade baseline combinations; incomplete state fails closed without mutations");
internal static class ProductIdentity { internal const string Version="0.1.0.8"; }
