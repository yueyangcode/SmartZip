# One-time, asset-specific cutout of the user-approved Win11 concept.
# No regenerated artwork: the texture preserves the original interior pixels.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$source = [Drawing.Bitmap]::new((Join-Path $PSScriptRoot 'smartzip-win11-concept-v1.png'))
if ($source.Width -ne 1254 -or $source.Height -ne 1254) { throw 'This outline is only for the approved 1254px concept.' }
$result = [Drawing.Bitmap]::new(1254, 1254, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$outline = [Drawing.Drawing2D.GraphicsPath]::new()
$graphics = [Drawing.Graphics]::FromImage($result)
$texture = [Drawing.TextureBrush]::new($source)
try {
    # Trace only the outside silhouette; the white paper and zipper stay opaque.
    $outline.StartFigure()
    $outline.AddLine(420, 173, 731, 173)
    $outline.AddBezier(731, 173, 741, 173, 750, 178, 758, 186)
    $outline.AddLine(758, 186, 844, 266)
    $outline.AddLine(844, 266, 955, 266)
    $outline.AddBezier(955, 266, 1007, 266, 1042, 296, 1042, 348)
    $outline.AddLine(1042, 348, 1042, 429)
    $outline.AddBezier(1042, 429, 1069, 447, 1084, 472, 1084, 504)
    $outline.AddLine(1084, 504, 1084, 918)
    $outline.AddBezier(1084, 918, 1084, 986, 1032, 1037, 962, 1037)
    $outline.AddLine(962, 1037, 289, 1037)
    $outline.AddBezier(289, 1037, 222, 1037, 171, 986, 171, 918)
    $outline.AddLine(171, 918, 171, 477)
    $outline.AddBezier(171, 477, 171, 435, 183, 401, 209, 377)
    $outline.AddLine(209, 377, 209, 345)
    $outline.AddBezier(209, 345, 209, 293, 245, 257, 293, 257)
    $outline.AddLine(293, 257, 373, 257)
    $outline.AddLine(373, 257, 373, 222)
    $outline.AddBezier(373, 222, 373, 193, 391, 173, 420, 173)
    $outline.CloseFigure()
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.FillPath($texture, $outline)
    $destination = Join-Path $PSScriptRoot '../../packaging/Assets'
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    $result.Save((Join-Path $destination 'SmartZip.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally {
    $texture.Dispose(); $graphics.Dispose(); $outline.Dispose(); $result.Dispose(); $source.Dispose()
}
