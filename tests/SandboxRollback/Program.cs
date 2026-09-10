using Microsoft.Win32;
using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Xml.Linq;
using Windows.Management.Deployment;

// Deliberately fixed to the mapped Sandbox test materials. No arbitrary installer,
// command, certificate, deployment or cleanup API is exposed by this test runner.
internal static class Program {
    const string Input = @"C:\SmartZipTestInput";
    const string Output = @"C:\SmartZipTestOutput";
    const string CandidateVersion = "0.1.0.14";
    const string Publisher = "CN=SmartZip Modern Evaluation";
    const string Thumbprint = "A1709CED9DB02150E2FB40CE6496BD1938D89195";
    const string Clsid = "{C12835D9-8B49-48D9-AE52-5E66D31209E1}";
    const string StateKey = @"Software\SmartZipModern";
    const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\{DA975784-DC84-48EF-9A47-F60C0C969280}_is1";
    static readonly (string Stage, string Hash)[] Faults = [
        ("after-stage", "EED84F66738EBABEB4A806273B550EEF12B2C26743CA3A4DABA7F27813CA23F4"),
        ("after-package", "5AECBEE9FB361187FC8F665AF1706DA4AFC059BEF3E6C327DB672EE2B166E82C"),
        ("before-commit", "4849A480213D5E25B8F6CC786998C2DBEC6B9358FA1599F1CAE3CA87E435C7C6"),
        ("after-state", "030A4BDFC0187EA6F92593BD68F989D8956DF7BB96F954BBFF2A54FF751A22EE")
    ];
    static string Root => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "SmartZip");
    static string VersionPath => Path.Combine(Root, "Versions", "0.1.0.8");
    static string Installer(string stage) => Path.Combine(Input, $"SmartZipSetup-{CandidateVersion}-test-fault-{stage}.exe");
    static string? runDirectory;
    static void Require(bool condition, string message) { if (!condition) throw new IOException(message); }
    static string Hash(string path) { using var file = File.OpenRead(path); return Convert.ToHexString(SHA256.HashData(file)); }
    static void Note(string message) {
        Console.WriteLine(message);
        if (runDirectory != null) File.AppendAllText(Path.Combine(runDirectory, "runner.log"), $"{DateTimeOffset.Now:O} {message}\n", Encoding.UTF8);
    }
    static void Save(string path, SortedDictionary<string, string> data) =>
        File.WriteAllText(path, JsonSerializer.Serialize(data, SnapshotJson.Default.SortedDictionaryStringString), Encoding.UTF8);
    static SortedDictionary<string,string> ReadSnapshot(ReadOnlySpan<byte> bytes) {
        if(bytes.StartsWith(Encoding.UTF8.Preamble))bytes=bytes[Encoding.UTF8.Preamble.Length..];
        return JsonSerializer.Deserialize(bytes,SnapshotJson.Default.SortedDictionaryStringString)??throw new IOException("Empty snapshot.");
    }
    static SortedDictionary<string, string> Diff(SortedDictionary<string, string> before, SortedDictionary<string, string> after) {
        var differences = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var key in before.Keys.Union(after.Keys, StringComparer.Ordinal)) {
            var had = before.TryGetValue(key, out var oldValue); var has = after.TryGetValue(key, out var newValue);
            if (had != has || oldValue != newValue) differences[key] = $"BEFORE: {(had ? oldValue : "<absent>")}\nAFTER: {(has ? newValue : "<absent>")}";
        }
        return differences;
    }
    static bool ExpectedFailure(string stage, int exitCode, string logs) => exitCode != 0 &&
        logs.Contains("故障注入测试：" + stage + "；", StringComparison.Ordinal) &&
        logs.Contains("UPGRADE_ROLLBACK_COMPLETE;", StringComparison.Ordinal) &&
        !logs.Contains("ROLLBACK_INCOMPLETE", StringComparison.Ordinal);

    // One explicitly reviewed run only, not a general-purpose resume/ignore-failure switch.
    const string ReviewedRun = "rollback-run-20260909-212727";
    const string ReviewedBaselineHash = "8AEBE3AD8A59ECAFB07118414150EC0F2A720BC5A4329CB6D64ED19A1B20BB50";
    static SortedDictionary<string,string> AuditEvidence(string directory) {
        byte[] Pinned(string relative,string expected) {
            var bytes=File.ReadAllBytes(Path.Combine(directory,relative));
            Require(Convert.ToHexString(SHA256.HashData(bytes))==expected,"Reviewed evidence changed: "+relative);
            return bytes;
        }
        var baseline=ReadSnapshot(Pinned("baseline.json",ReviewedBaselineHash));
        Healthy(baseline);
        foreach(var stage in Faults.Take(3))foreach(var snapshot in new[]{"before.json","after.json"})
            _=Pinned(Path.Combine(stage.Stage,snapshot),ReviewedBaselineHash);
        _=Pinned(@"after-stage\result.json","A7489D9962526BC447441942D58C61B32608A62ECE261973FC28A006A181DF50");
        _=Pinned(@"after-package\result.json","3523A481CC8D93A1852401D6E1738626F7071772F49842B107434F16C71100FA");
        _=Pinned(@"before-commit\result.json","11A77642CC44886D5D7B1B72769F84951187C263C984EEA5BE07C94C646FEB22");
        var first=Encoding.UTF8.GetString(Pinned(@"after-stage\SmartZip-0.1.0.14-6412.log","627C7E2B23B41BF39C6F753F5FAA7AD392222F23A64051CAD597C1CCF5E15B08"));
        var second=Encoding.UTF8.GetString(Pinned(@"after-package\SmartZip-0.1.0.14-7828.log","1163E317B64816ADB5BB9118C3947D0E51A39DC5BF35C06F9A2FA07A4EAFCBA4"));
        Require(ExpectedFailure("after-stage",7,first)&&ExpectedFailure("after-package",7,second),"Earlier fault evidence does not pass.");
        var oldLog=Pinned(@"after-package\SmartZip-0.1.0.14-7704.log","0C7335047D7DAE9C0EB8659DEA24C8C7A9A37150D0B20759AF1366B22EE47C1C");
        var fullLog=Pinned(@"supplemental-helper-logs\SmartZip-0.1.0.14-7704.log","AFAA37E180C862899969D93E62A60DDF168C81BC514F7D37EC5E2FDB3C61777A");
        var appended=Encoding.UTF8.GetString(HelperLogCapture.Appended(oldLog,fullLog));
        var commit=Encoding.UTF8.GetString(Pinned(@"before-commit\SmartZip-0.1.0.14-7664.log","4B703C409B83D2F4B1D306B28BB8915CB07DC832B41652ACDB8F5FBEBD3B33F1"));
        Require(ExpectedFailure("before-commit",20,commit+"\n"+appended)&&appended.Contains("PREVIOUS_PACKAGE_RESTORED_HEALTHY=0.1.0.8",StringComparison.Ordinal),
            "Supplemental third-stage evidence does not pass.");
        Require(!Directory.Exists(Path.Combine(directory,"after-state"))&&!File.Exists(Path.Combine(directory,"after-state")),"Fourth stage already exists in the original run; stop and inspect.");
        return baseline;
    }

    static void Guard() {
        // This guard runs before creating an output file or launching an installer.
        using var bios = Registry.LocalMachine.OpenSubKey(@"HARDWARE\DESCRIPTION\System\BIOS");
        Require(Environment.UserName.Equals("WDAGUtilityAccount", StringComparison.OrdinalIgnoreCase) &&
            bios?.GetValue("SystemProductName") as string == "Virtual Machine", "Sandbox account and VM required. Host execution refused.");
        Require(Environment.Is64BitProcess && OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22621), "Windows 11 x64 required.");
        Require(string.Equals(Path.GetDirectoryName(Environment.ProcessPath), Input, StringComparison.OrdinalIgnoreCase) &&
            Directory.Exists(Output), "Run the copied test executable from the dedicated Sandbox mapping only.");
        using var probe = JsonDocument.Parse(File.ReadAllText(Path.Combine(Output, "probe.json")));
        Require(probe.RootElement.GetProperty("Computer").GetString() == Environment.MachineName, "Probe belongs to a different Sandbox session.");
        using var baseline = JsonDocument.Parse(File.ReadAllText(Path.Combine(Output, "baseline-result.json")));
        Require(baseline.RootElement.GetProperty("ProductState").GetProperty("UserSid").GetString() == WindowsIdentity.GetCurrent().User?.Value,
            "Baseline belongs to a different user/session.");
    }

    static SortedDictionary<string, string> Capture() {
        var data = new SortedDictionary<string, string>(StringComparer.Ordinal);
        void Section(string name, Action action) { try { action(); } catch (Exception ex) { data["ERROR/" + name] = ex.ToString(); } }
        Section("files", () => Tree(data, "files", Root));
        Section("shortcuts", () => Tree(data, "shortcuts", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "SmartZip")));
        Section("user-config", () => Tree(data, "user-config", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SmartZip Modern", "UserData")));
        Section("state", () => RegistryTree(data, "HKCU", Registry.CurrentUser, StateKey));
        Section("uninstall", () => RegistryTree(data, "HKCU", Registry.CurrentUser, UninstallKey));
        Section("legacy-menu", () => RegistryTree(data, "HKCU", Registry.CurrentUser, @"Software\Classes\*\shell\UnZip"));
        Section("COM", () => {
            using var packages = Registry.ClassesRoot.OpenSubKey(@"PackagedCom\Package");
            foreach (var name in packages?.GetSubKeyNames().Where(n => n.StartsWith("SmartZip.Modern_", StringComparison.OrdinalIgnoreCase)) ?? [])
                RegistryTree(data, "HKCR", Registry.ClassesRoot, @"PackagedCom\Package\" + name);
            RegistryTree(data, "HKCU", Registry.CurrentUser, @"Software\Classes\CLSID\" + Clsid);
            RegistryTree(data, "HKLM", Registry.LocalMachine, @"Software\Classes\CLSID\" + Clsid);
        });
        Section("certificate", () => {
            foreach (var location in new[] { StoreLocation.LocalMachine, StoreLocation.CurrentUser }) {
                foreach (var name in new[] { StoreName.TrustedPeople, StoreName.Root }) {
                    using var store = new X509Store(name, location); store.Open(OpenFlags.ReadOnly | OpenFlags.OpenExistingOnly);
                    var matches = store.Certificates.Find(X509FindType.FindByThumbprint, Thumbprint, false);
                    data[$"certificate/{location}/{name}/count"] = matches.Count.ToString(CultureInfo.InvariantCulture);
                    foreach (var certificate in matches) {
                        using (certificate) {
                            var hash = Convert.ToHexString(SHA256.HashData(certificate.RawData));
                            data[$"certificate/{location}/{name}/{hash}"] = $"{certificate.Subject};PrivateKey={certificate.HasPrivateKey};NotBefore={certificate.NotBefore.ToUniversalTime():O};NotAfter={certificate.NotAfter.ToUniversalTime():O}";
                            Require(certificate.Subject == Publisher && !certificate.HasPrivateKey, "Unexpected certificate identity or private key.");
                        }
                    }
                    Require(name != StoreName.Root || matches.Count == 0, "Project test certificate must not be trusted in Root.");
                    if (location == StoreLocation.LocalMachine && name == StoreName.TrustedPeople) Require(matches.Count == 1, "Expected machine TrustedPeople test certificate is missing/ambiguous.");
                    // Also record physical registry locations; CU logical stores can inherit LM certificates.
                    RegistryTree(data, location.ToString(), location == StoreLocation.LocalMachine ? Registry.LocalMachine : Registry.CurrentUser,
                        $@"SOFTWARE\Microsoft\SystemCertificates\{name}\Certificates\{Thumbprint}");
                }
            }
            RegistryTree(data, "HKLM", Registry.LocalMachine, @"SOFTWARE\SmartZipModernTestTrust\" + Thumbprint);
        });
        Section("package", () => {
            var packages = new PackageManager().FindPackagesForUser("").Where(p => p.Id.Name == "SmartZip.Modern").ToArray();
            data["package/count"] = packages.Length.ToString(CultureInfo.InvariantCulture);
            foreach (var p in packages) {
                var health = PackageHealth.Read(p.Status); var prefix = "package/" + p.Id.FullName;
                data[prefix + "/health"] = health.ToString();
                data[prefix + "/publisher"] = p.Id.Publisher;
                data[prefix + "/external"] = p.EffectiveExternalLocation.Path;
                var manifest = Path.Combine(p.InstalledLocation.Path, "AppxManifest.xml");
                data[prefix + "/manifest-sha256"] = Hash(manifest);
                using var com = Registry.ClassesRoot.OpenSubKey(@"PackagedCom\Package\" + p.Id.FullName + @"\Class\" + Clsid);
                var menu = XDocument.Load(manifest).Descendants().Any(e => e.Name.LocalName == "Verb" &&
                    Guid.TryParse((string?)e.Attribute("Clsid"), out var id) && id == Guid.Parse(Clsid));
                data[prefix + "/COM-and-menu-declaration"] = (com != null && menu).ToString();
                health.RequireHealthy(p.Id.FullName);
                Require(p.Id.FullName == "SmartZip.Modern_0.1.0.8_x64__fntwt8wa91w8p" && p.Id.Publisher == Publisher &&
                    string.Equals(p.EffectiveExternalLocation.Path.TrimEnd('\\'), VersionPath, StringComparison.OrdinalIgnoreCase) && com != null && menu,
                    "Healthy original 0.1.0.8 package, external path and COM/menu registration required.");
            }
            Require(packages.Length == 1, "Exactly one baseline package required.");
        });
        Section("coherent-baseline", () => {
            using var state = Registry.CurrentUser.OpenSubKey(StateKey);
            using var uninstall = Registry.CurrentUser.OpenSubKey(UninstallKey);
            var receipt = JournalJson.Deserialize(File.ReadAllText(Path.Combine(VersionPath, "installed.json")));
            var sid = WindowsIdentity.GetCurrent().User!.Value;
            Require(state?.GetValue("Version") as string == "0.1.0.8" && state.GetValue("VersionPath") as string == VersionPath &&
                state.GetValue("Publisher") as string == Publisher && state.GetValue("CertificateThumbprint") as string == Thumbprint &&
                state.GetValue("UserSid") as string == sid && Convert.ToInt32(state.GetValue("CertificateCreated")) == (receipt.CertificateCreated ? 1 : 0) &&
                receipt.UserSid == sid && receipt.InstallRoot == Root && File.ReadAllText(Path.Combine(Root, ".install-transaction")) == receipt.Nonce &&
                uninstall?.GetValue("DisplayVersion") as string == "0.1.0.8" && string.Equals((uninstall.GetValue("InstallLocation") as string)?.TrimEnd('\\'), Root, StringComparison.OrdinalIgnoreCase) &&
                uninstall.GetValue("UninstallString") as string == "\"" + Path.Combine(Root, "unins000.exe") + "\"", "Incoherent baseline receipt, state or uninstall entry.");
            Require(Directory.GetDirectories(Path.Combine(Root, "Versions")).SequenceEqual(new[] { VersionPath }) &&
                Directory.GetDirectories(Root, ".upgrade-*").Length == 0 && !File.Exists(Path.Combine(Root, "recovery.json")), "Existing stage/backup/recovery files: stop and inspect.");
        });
        return data;
    }

    static void Tree(SortedDictionary<string, string> data, string prefix, string path) {
        if (!Directory.Exists(path) && !File.Exists(path)) { data[prefix] = "ABSENT"; return; }
        var attributes = File.GetAttributes(path);
        Require((attributes & FileAttributes.ReparsePoint) == 0, "Snapshot refuses reparse points: " + path);
        if ((attributes & FileAttributes.Directory) == 0) { data[prefix] = Hash(path); return; }
        data[prefix] = "DIRECTORY";
        foreach (var child in Directory.EnumerateFileSystemEntries(path)) Tree(data, prefix + "/" + Path.GetFileName(child), child);
    }
    static void RegistryTree(SortedDictionary<string, string> data, string hive, RegistryKey root, string path) {
        using var key = root.OpenSubKey(path);
        var prefix = "registry/" + hive + "/" + path;
        data[prefix] = key == null ? "ABSENT" : "KEY";
        if (key == null) return;
        foreach (var name in key.GetValueNames()) {
            var kind = key.GetValueKind(name); var value = key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            var text = value switch {
                string s => s, int n => n.ToString(CultureInfo.InvariantCulture), long n => n.ToString(CultureInfo.InvariantCulture),
                byte[] b => Convert.ToBase64String(b), string[] s => string.Join(",", s.Select(v => Convert.ToBase64String(Encoding.UTF8.GetBytes(v)))),
                _ => throw new IOException("Unsupported snapshot registry value: " + name)
            };
            data[prefix + "/value:" + name] = kind + ":" + text;
        }
        foreach (var child in key.GetSubKeyNames()) RegistryTree(data, hive, root, path + "\\" + child);
    }
    static void Healthy(SortedDictionary<string, string> snapshot) => Require(!snapshot.Keys.Any(k => k.StartsWith("ERROR/", StringComparison.Ordinal)), "Snapshot contains errors; see JSON. No further installer will run.");

    static async Task<int> Main(string[] args) {
        if (args.SequenceEqual(new[] { "--selftest" })) { SelfTest(); return 0; }
        try {
            // Read-only host audit: no current-machine snapshot, output writes or installer execution.
            if(args.Length==2&&args[0]=="--verify-log-audit") {
                _=AuditEvidence(args[1]);Console.WriteLine("PASS: pinned original/supplemental evidence and 961-byte append verified; no files or system state changed.");return 0;
            }
            bool continuing=args.SequenceEqual(new[]{"--continue-after-log-audit"});
            Require(continuing||args.SequenceEqual(new[] { "--run" }), "Use a Sandbox-only test entry point.");
            Guard();
            using var mutex = new Mutex(false, "Local\\SmartZip.SandboxRollback.Tests");
            Require(mutex.WaitOne(0), "Another rollback test runner is active.");
            // A failed run must be inspected, not silently retried over its evidence.
            var previousRuns=Directory.GetDirectories(Output,"rollback-run-*");
            SortedDictionary<string,string>? reviewed=null;
            if(continuing) {
                Require(previousRuns.Length==1&&Path.GetFileName(previousRuns[0])==ReviewedRun,"Only the explicitly reviewed run may continue.");
                reviewed=AuditEvidence(previousRuns[0]);
            } else Require(previousRuns.Length==0,"A rollback run already exists. Stop and have its evidence reviewed before another run.");
            var destination=Path.Combine(Output,continuing?"rollback-continuation-20260909-212727-after-state":"rollback-run-"+DateTime.Now.ToString("yyyyMMdd-HHmmss"));
            Require(!Directory.Exists(destination)&&!File.Exists(destination),"This test output already exists; no retries or overwrites.");
            Directory.CreateDirectory(destination);runDirectory=destination;
            Note("Sandbox rollback tests: keep this window open. Do not use SmartZip or its menus during deployment.");
            Note("No forced process termination, repair, uninstall, certificate import or normal upgrade by the test runner.");
            foreach (var fault in Faults) Require(Hash(Installer(fault.Stage)) == fault.Hash, "Installer SHA-256 mismatch: " + fault.Stage);
            var baseline = Capture(); Save(Path.Combine(runDirectory, "baseline.json"), baseline); Healthy(baseline);
            if(reviewed!=null) {
                var changes=Diff(reviewed,baseline);Save(Path.Combine(runDirectory,"reviewed-baseline-differences.json"),changes);
                Require(changes.Count==0,"Current Sandbox baseline differs from the reviewed original; no installer will run.");
                Save(Path.Combine(runDirectory,"prior-evidence-audit.json"),new(StringComparer.Ordinal) {
                    ["OriginalRun"]=ReviewedRun,["FirstTwoStages"]="PASS (original automated results)",
                    ["BeforeCommit"]="PASS (pinned supplemental log audit)",["OriginalAutomatedBeforeCommit"]="FAIL (unchanged)",
                    ["ReviewedBaselineSHA256"]=ReviewedBaselineHash,["PendingStage"]="after-state"
                });
                Note("PRIOR EVIDENCE AUDIT PASS; original automated FAIL retained. Running ONLY after-state, with appended-log capture.");
            }
            Require(!baseline.ContainsKey("files/unins000.msg"),
                "This regression requires the fresh original baseline WITHOUT unins000.msg. Preserve existing residue; do not delete it to pass the test.");
            foreach (var fault in (continuing?Faults.Skip(3):Faults)) {
                var folder = Path.Combine(runDirectory, fault.Stage); Directory.CreateDirectory(folder);
                var before = Capture(); Save(Path.Combine(folder, "before.json"), before); Healthy(before);
                Require(Diff(baseline, before).Count == 0, "Baseline changed between tests.");
                var oldLogs = HelperLogCapture.Read(Path.GetTempPath(),$"SmartZip-{CandidateVersion}-*.log");
                HelperLogCapture.Save(Path.Combine(folder,"helper-logs-before"),oldLogs);
                Note("RUNNING " + fault.Stage + " (intentional installation failure expected)");
                var start = new ProcessStartInfo(Installer(fault.Stage)) { UseShellExecute = false, WorkingDirectory = Input };
                foreach (var a in new[] { "/VERYSILENT", "/SUPPRESSMSGBOXES", "/SP-", "/NORESTART", "/NOCLOSEAPPLICATIONS", "/NOFORCECLOSEAPPLICATIONS", "/DIR=" + Root, "/LOG=" + Path.Combine(folder, "inno.log") }) start.ArgumentList.Add(a);
                using var process = Process.Start(start) ?? throw new IOException("Installer did not start.");
                var exited = true;
                using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(3));
                try { await process.WaitForExitAsync(timeout.Token); }
                catch (OperationCanceledException) { exited = false; Note("TIMEOUT: installer left running, not terminated. Stop and inspect."); }
                var logs = new StringBuilder();
                var currentLogs=HelperLogCapture.Read(Path.GetTempPath(),$"SmartZip-{CandidateVersion}-*.log");
                HelperLogCapture.Save(Path.Combine(folder,"helper-logs-after"),currentLogs);
                var appendedLogs=HelperLogCapture.Since(oldLogs,currentLogs);
                HelperLogCapture.Save(folder,appendedLogs);
                foreach(var bytes in appendedLogs.Values)logs.AppendLine(Encoding.UTF8.GetString(bytes));
                var after = Capture(); Save(Path.Combine(folder, "after.json"), after);
                var differences = Diff(before, after); Save(Path.Combine(folder, "differences.json"), differences);
                var pass = exited && ExpectedFailure(fault.Stage, process.ExitCode, logs.ToString()) && differences.Count == 0 && !after.Keys.Any(k => k.StartsWith("ERROR/", StringComparison.Ordinal));
                Save(Path.Combine(folder, "result.json"), new(StringComparer.Ordinal) {
                    ["Stage"] = fault.Stage, ["InstallerSHA256"] = fault.Hash, ["InstallerExit"] = exited ? process.ExitCode.ToString(CultureInfo.InvariantCulture) : "TIMEOUT-STILL-RUNNING",
                    ["Result"] = pass ? "PASS" : "FAIL", ["Differences"] = differences.Count.ToString(CultureInfo.InvariantCulture),
                    ["ExpectedFailureAndRollbackLogged"] = (exited && ExpectedFailure(fault.Stage, process.ExitCode, logs.ToString())).ToString()
                });
                Note($"{fault.Stage}: {(pass ? "PASS" : "FAIL")} (snapshot differences: {differences.Count})");
                Require(pass, "Test failed. Remaining tests NOT RUN. No cleanup or repair attempted.");
            }
            var outcome=continuing?"FOURTH STAGE PASS. First two passed originally; third passed supplemental audit. Original automated FAIL retained.":"ALL FOUR PASS.";
            Note(outcome+" Baseline remains 0.1.0.8. Menu UI / extraction / full font acceptance are separate manual tests.");
            File.WriteAllText(Path.Combine(runDirectory, "overall.txt"),outcome+" No UI behavior claim.\n");
            return 0;
        } catch (Exception ex) {
            Note("STOP: " + ex);
            if (runDirectory != null) File.WriteAllText(Path.Combine(runDirectory, "overall.txt"), "STOP / NOT PASSED\n" + ex);
            return 1;
        }
    }

    static void SelfTest() {
        SortedDictionary<string, string> initial = new(StringComparer.Ordinal) { ["same"] = "1", ["gone"] = "2", ["changed"] = "3" };
        SortedDictionary<string, string> changed = new(StringComparer.Ordinal) { ["same"] = "1", ["added"] = "2", ["changed"] = "4" };
        Require(Diff(initial, initial).Count == 0 && Diff(initial, changed).Count == 3, "Snapshot diff regression.");
        const string log = "故障注入测试：after-stage；\nUPGRADE_ROLLBACK_COMPLETE;";
        Require(ExpectedFailure("after-stage", 7, log) && !ExpectedFailure("after-package", 7, log) && !ExpectedFailure("after-stage", 0, log) &&
            !ExpectedFailure("after-stage", 7, log + "UPGRADE_ROLLBACK_INCOMPLETE") && !ExpectedFailure("after-stage", 7, "UPGRADE_ROLLBACK_COMPLETE;"), "Fault evidence regression.");
        var roundTrip = JsonSerializer.Deserialize(JsonSerializer.Serialize(initial, SnapshotJson.Default.SortedDictionaryStringString), SnapshotJson.Default.SortedDictionaryStringString)!;
        Require(Diff(initial, roundTrip).Count == 0, "Snapshot JSON regression.");
        var jsonBytes=Encoding.UTF8.GetBytes(JsonSerializer.Serialize(initial,SnapshotJson.Default.SortedDictionaryStringString));
        Require(Diff(initial,ReadSnapshot(jsonBytes)).Count==0&&Diff(initial,ReadSnapshot(Encoding.UTF8.GetPreamble().Concat(jsonBytes).ToArray())).Count==0,
            "Snapshot reader must support the original UTF-8 BOM as well as BOM-less JSON.");
        SortedDictionary<string, string> absent = new(StringComparer.Ordinal);
        SortedDictionary<string, string> emptyFile = new(StringComparer.Ordinal) {
            ["files/unins000.msg"] = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"
        };
        Require(Diff(absent, emptyFile).Count == 1 && Diff(emptyFile, absent).Count == 1,
            "An extra/missing zero-byte file must never be accepted as an identical snapshot.");
        static Dictionary<string,byte[]> Logs(string name,string text)=>new(StringComparer.OrdinalIgnoreCase){[name]=Encoding.UTF8.GetBytes(text)};
        static void Reject(Action action) {try{action();}catch(IOException){return;}throw new IOException("Ambiguous helper log evidence was accepted.");}
        var prior=Logs("SmartZip-7704.log","旧阶段：UPGRADE_ROLLBACK_COMPLETE;\n");
        var next=Logs("smartzip-7704.LOG","旧阶段：UPGRADE_ROLLBACK_COMPLETE;\n当前阶段 中文 & ()\n");
        var delta=HelperLogCapture.Since(prior,next);
        Require(delta.Count==1&&Encoding.UTF8.GetString(delta.Single().Value)=="当前阶段 中文 & ()\n","Reused PID append lost or prior-stage evidence leaked.");
        Require(HelperLogCapture.Since(prior,prior).Count==0,"Unchanged logs must not become new evidence.");
        Require(HelperLogCapture.Since(new(StringComparer.OrdinalIgnoreCase),next).Single().Value.SequenceEqual(next.Single().Value),"New helper log omitted.");
        Reject(()=>HelperLogCapture.Since(prior,new(StringComparer.OrdinalIgnoreCase)));
        Reject(()=>HelperLogCapture.Since(prior,Logs("SmartZip-7704.log","short")));
        Reject(()=>HelperLogCapture.Since(prior,Logs("SmartZip-7704.log","X"+Encoding.UTF8.GetString(prior.Single().Value)[1..])));
        var reuse=Logs("SmartZip-7704.log",Encoding.UTF8.GetString(prior.Single().Value)+"故障注入测试：after-state；\nUPGRADE_ROLLBACK_COMPLETE;\n");
        var newEvidence=Encoding.UTF8.GetString(HelperLogCapture.Since(prior,reuse).Single().Value);
        Require(ExpectedFailure("after-state",20,newEvidence),"Current-stage success evidence was lost.");
        Require(!ExpectedFailure("after-state",20,"故障注入测试：after-state；\n"+Encoding.UTF8.GetString(delta.Single().Value)),"Prior rollback marker caused a false pass.");
        Require(!ExpectedFailure("after-state",20,newEvidence+"ROLLBACK_INCOMPLETE"),"Incomplete rollback must fail.");
        Console.WriteLine("PASS helper-log append/new/unchanged/case/Unicode and deletion/truncation/rewrite rejection; no stale rollback markers accepted.");
        Console.WriteLine("PASS: pure snapshot and failure-evidence tests; no installer or system mutation.");
    }
}

[JsonSourceGenerationOptions(WriteIndented = true)]
[JsonSerializable(typeof(SortedDictionary<string, string>))]
internal partial class SnapshotJson : JsonSerializerContext { }
