param([Parameter(Mandatory)][string]$Assets, [string[]]$Executables = @())
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot
function Require([bool]$condition, [string]$message) { if (!$condition) { throw $message } }

# The approved interior must be unmodified, including the white document/zipper.
$master = [Drawing.Bitmap]::new((Join-Path $root 'packaging/Assets/SmartZip.png'))
$concept = [Drawing.Bitmap]::new((Join-Path $root 'design/logo/smartzip-win11-concept-v1.png'))
try {
    Require ($master.Width -eq 1254 -and $master.Height -eq 1254) 'Wrong master dimensions.'
    foreach ($point in @(@(20,20), @(627,100), @(100,600), @(1150,600), @(627,1150))) {
        Require ($master.GetPixel($point[0],$point[1]).A -eq 0) 'Exterior background is not transparent.'
    }
    foreach ($point in @(@(500,210), @(450,300), @(627,476), @(627,910), @(400,600), @(900,900))) {
        Require ($master.GetPixel($point[0],$point[1]).ToArgb() -eq $concept.GetPixel($point[0],$point[1]).ToArgb()) 'Approved interior pixels changed.'
    }
} finally { $master.Dispose(); $concept.Dispose() }

$sizes = @(16,20,24,32,40,48,64,96,128,256)
$frameHashes = [Collections.Generic.List[string]]::new()
$reader = [IO.BinaryReader]::new([IO.File]::OpenRead((Join-Path $Assets 'SmartZip.ico')))
try {
    Require ($reader.ReadUInt16() -eq 0 -and $reader.ReadUInt16() -eq 1 -and $reader.ReadUInt16() -eq $sizes.Count) 'Invalid ICO header.'
    $offset = 6 + 16 * $sizes.Count
    foreach ($size in $sizes) {
        $dimension = if ($size -eq 256) { 0 } else { $size }
        Require ($reader.ReadByte() -eq $dimension -and $reader.ReadByte() -eq $dimension) "ICO size missing: $size"
        Require ($reader.ReadByte() -eq 0 -and $reader.ReadByte() -eq 0) 'Unexpected ICO palette/reserved value.'
        Require ($reader.ReadUInt16() -eq 1 -and $reader.ReadUInt16() -eq 32) 'ICO must be 32-bit.'
        $length = $reader.ReadUInt32()
        Require ($reader.ReadUInt32() -eq $offset) 'ICO frame offset mismatch.'
        $nextEntry = $reader.BaseStream.Position
        $reader.BaseStream.Position = $offset
        $bytes = $reader.ReadBytes($length)
        $frameHashes.Add([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))
        Require ([Convert]::ToHexString($bytes[0..7]) -eq '89504E470D0A1A0A') 'ICO frame is not PNG.'
        $stream = [IO.MemoryStream]::new($bytes, $false)
        $bitmap = [Drawing.Bitmap]::new($stream)
        try {
            Require ($bitmap.Width -eq $size -and $bitmap.Height -eq $size) 'ICO PNG dimensions mismatch.'
            Require ($bitmap.GetPixel(0,0).A -eq 0 -and $bitmap.GetPixel(($size-1),($size-1)).A -eq 0) 'ICO lost transparent corners.'
            Require ($bitmap.GetPixel([int]($size/2),[int]($size/2)).A -eq 255) 'ICO center is not opaque.'
        } finally { $bitmap.Dispose(); $stream.Dispose() }
        $offset += $length
        $reader.BaseStream.Position = $nextEntry
    }
    Require ($offset -eq $reader.BaseStream.Length) 'ICO has trailing or missing image data.'
} finally { $reader.Dispose() }

[xml]$manifest = Get-Content -LiteralPath (Join-Path $root 'packaging/AppxManifest.xml.in') -Raw
$visual = $manifest.Package.Applications.Application.VisualElements
$packageImages = @(@($manifest.Package.Properties.Logo, 50), @($visual.Square44x44Logo, 44), @($visual.Square150x150Logo, 150))
foreach ($entry in $packageImages) {
    $bitmap = [Drawing.Bitmap]::new((Join-Path $Assets ([IO.Path]::GetFileName($entry[0]))))
    try {
        Require ($bitmap.Width -eq $entry[1] -and $bitmap.Height -eq $entry[1]) 'Package logo dimensions mismatch.'
        Require ($bitmap.GetPixel(0,0).A -eq 0) 'Package logo is not transparent.'
    } finally { $bitmap.Dispose() }
}
$header = [Drawing.Bitmap]::new((Join-Path $Assets 'WizardSmall.bmp'))
try {
    Require ($header.Width -eq 165 -and $header.Height -eq 174) 'Wrong high-DPI wizard bitmap.'
    Require ($header.GetPixel(0,0).ToArgb() -eq [Drawing.Color]::White.ToArgb()) 'Wizard header matte mismatch.'
} finally { $header.Dispose() }
$iss = Get-Content -LiteralPath (Join-Path $root 'installer/SmartZipModern.iss') -Raw
Require ([regex]::Matches($iss, '(?m)^Name: .*; IconFilename: .*Assets\\SmartZip.ico"\r?$').Count -eq 3) 'All three Start menu shortcuts must use the shared icon.'
Require ($iss.Contains('SetupIconFile={#Root}build\payload\Assets\SmartZip.ico') -and $iss.Contains('WizardSmallImageFile={#Root}build\payload\Assets\WizardSmall.bmp')) 'Installer icon references missing.'
if ($Executables.Count) {
    # Load PE files as data/resources only: no entry point, installation or UI.
    if (!('SmartZipIconResources' -as [type])) {
        Add-Type @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class SmartZipIconResources {
    private delegate bool ResourceNameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr arg);
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool EnumResourceNamesW(IntPtr module, IntPtr type, ResourceNameCallback callback, IntPtr arg);
    [DllImport("kernel32", CharSet=CharSet.Unicode)] private static extern IntPtr FindResourceW(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32")] private static extern uint SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32")] private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32")] private static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32")] private static extern bool FreeLibrary(IntPtr module);
    public static byte[][] Read(string path) {
        IntPtr module=LoadLibraryExW(path,IntPtr.Zero,0x22);
        if(module==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try {
            var images=new List<byte[]>();
            bool ok=EnumResourceNamesW(module,(IntPtr)3,(m,t,n,a)=>{
                IntPtr resource=FindResourceW(m,n,t);
                uint size=SizeofResource(m,resource);
                IntPtr data=LockResource(LoadResource(m,resource));
                if(data==IntPtr.Zero || size==0 || size>16*1024*1024) return false;
                var bytes=new byte[size];
                Marshal.Copy(data,bytes,0,bytes.Length);
                images.Add(bytes); return true;
            },IntPtr.Zero);
            if(!ok || images.Count==0) throw new InvalidOperationException("Cannot read embedded icon resources: "+path);
            return images.ToArray();
        } finally { FreeLibrary(module); }
    }
}
'@
    }
    foreach ($executable in $Executables) {
        $embedded = @([SmartZipIconResources]::Read([IO.Path]::GetFullPath($executable)) | ForEach-Object {
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($_))
        })
        foreach ($hash in $frameHashes) { Require ($hash -cin $embedded) "Missing or changed embedded ICO frame in $executable" }
        Write-Host "PASS all 10 icon frames embedded byte-for-byte: $([IO.Path]::GetFileName($executable))"
    }
}
Write-Host 'PASS approved artwork, transparent alpha, 10 ICO sizes, package images and installer/shortcut assets'
