param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$bmp=[Drawing.Bitmap]::new(150,150)
$g=[Drawing.Graphics]::FromImage($bmp)
$g.Clear([Drawing.Color]::Transparent)
$blue=[Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(35,95,190))
$white=[Drawing.SolidBrush]::new([Drawing.Color]::White)
$g.FillRectangle($blue,12,12,126,126)
for($y=24;$y -lt 100;$y+=16){$g.FillRectangle($white,65,$y,12,8);$g.FillRectangle($white,77,($y+8),12,8)}
$g.FillRectangle($white,65,106,24,18)
$g.FillRectangle($blue,71,110,12,8)
$bmp.Save((Join-Path $Destination 'Logo.png'),[Drawing.Imaging.ImageFormat]::Png)
# ICO containing a PNG image; no third-party icon artwork.
$png=[IO.File]::ReadAllBytes((Join-Path $Destination 'Logo.png'))
$stream=[IO.File]::Create((Join-Path $Destination 'SmartZip.ico'));$writer=[IO.BinaryWriter]::new($stream)
$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]1)
$writer.Write([byte]150);$writer.Write([byte]150);$writer.Write([byte]0);$writer.Write([byte]0)
$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$png.Length);$writer.Write([uint32]22);$writer.Write($png)
$writer.Dispose();$g.Dispose();$bmp.Dispose();$blue.Dispose();$white.Dispose()
