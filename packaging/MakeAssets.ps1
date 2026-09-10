param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$source = [Drawing.Bitmap]::new((Join-Path $PSScriptRoot 'Assets/SmartZip.png'))
$writer = $null
try {
    if ($source.Width -ne 1254 -or $source.Height -ne 1254 -or $source.GetPixel(0,0).A -ne 0) {
        throw 'Expected the approved 1254px transparent SmartZip master.'
    }
    # Remove excess concept-sheet margins, keeping ~4% breathing room on the icon.
    $crop = [Drawing.Rectangle]::new(127, 105, 1000, 1000)
    $sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
    $frames = @{}
    $packageAssets = @{44='Square44x44Logo.png'; 50='StoreLogo.png'; 150='Logo.png'}
    foreach ($size in @($sizes + @($packageAssets.Keys))) {
        $bitmap = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $stream = [IO.MemoryStream]::new()
        try {
            $graphics.Clear([Drawing.Color]::Transparent)
            $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($source, [Drawing.Rectangle]::new(0, 0, $size, $size), $crop, [Drawing.GraphicsUnit]::Pixel)
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            $frames[$size] = $stream.ToArray()
            if ($packageAssets.ContainsKey($size)) {
                [IO.File]::WriteAllBytes((Join-Path $Destination $packageAssets[$size]), $frames[$size])
            }
            if ($size -eq 150) {
                # Inno's light wizard header uses a BMP; render at 3x for high DPI.
                $header = [Drawing.Bitmap]::new(165, 174)
                $headerGraphics = [Drawing.Graphics]::FromImage($header)
                try {
                    $headerGraphics.Clear([Drawing.Color]::White)
                    $headerGraphics.DrawImageUnscaled($bitmap, 7, 12)
                    $header.Save((Join-Path $Destination 'WizardSmall.bmp'), [Drawing.Imaging.ImageFormat]::Bmp)
                } finally { $headerGraphics.Dispose(); $header.Dispose() }
            }
        } finally { $stream.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
    }
    # PNG-backed ICO frames are supported by the Windows 11 minimum target.
    $writer = [IO.BinaryWriter]::new([IO.File]::Create((Join-Path $Destination 'SmartZip.ico')))
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    foreach ($size in $sizes) {
        $dimension = if ($size -eq 256) { 0 } else { $size }
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$frames[$size].Length); $writer.Write([uint32]$offset)
        $offset += $frames[$size].Length
    }
    foreach ($size in $sizes) { $writer.Write([byte[]]$frames[$size]) }
} finally { if ($writer) { $writer.Dispose() }; $source.Dispose() }
