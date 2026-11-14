$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$guiRoot = Join-Path $PSScriptRoot 'Gui'
$vanillaAtlasPath = 'C:\Program Files (x86)\Steam\steamapps\common\Scrap Mechanic\Data\Gui\IconMap.png'
$atlasPath = Join-Path $guiRoot 'IconMap.png'
$temporaryAtlasPath = Join-Path $guiRoot 'IconMap.hud.tmp.png'
$previewPath = Join-Path $guiRoot 'HudBlockIcon96.png'

$sourceX = 672
$sourceY = 96
$targetX = 1344
$targetY = 1440
$iconSize = 96

if (-not (Test-Path -LiteralPath $atlasPath -PathType Leaf)) {
    throw "Icon atlas is missing: $atlasPath"
}
if (-not (Test-Path -LiteralPath $vanillaAtlasPath -PathType Leaf)) {
    throw "Vanilla icon atlas is missing: $vanillaAtlasPath"
}

$sourceAtlas = [System.Drawing.Bitmap]::new($vanillaAtlasPath)
$targetAtlas = [System.Drawing.Bitmap]::new($atlasPath)
$updatedAtlas = [System.Drawing.Bitmap]::new($targetAtlas.Width, $targetAtlas.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$updatedAtlas.SetResolution(72.0, 72.0)
$atlasGraphics = [System.Drawing.Graphics]::FromImage($updatedAtlas)
$atlasGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$atlasGraphics.DrawImageUnscaled($targetAtlas, 0, 0)
$atlasGraphics.Dispose()

$cell = [System.Drawing.Bitmap]::new($iconSize, $iconSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$cell.SetResolution(96.0, 96.0)
for ($y = 0; $y -lt $iconSize; $y++) {
    for ($x = 0; $x -lt $iconSize; $x++) {
        $pixel = $sourceAtlas.GetPixel($sourceX + $x, $sourceY + $y)
        if ($pixel.A -eq 0) {
            $output = [System.Drawing.Color]::Transparent
        } elseif ($pixel.R -gt ($pixel.B + 40) -and $pixel.G -gt ($pixel.B + 20)) {
            $luminance = (0.299 * $pixel.R) + (0.587 * $pixel.G) + (0.114 * $pixel.B)
            $shade = [int][Math]::Max(18, [Math]::Min(78, 16 + ($luminance * 0.30)))
            $output = [System.Drawing.Color]::FromArgb($pixel.A, $shade, $shade, $shade)
        } else {
            $output = $pixel
        }
        $cell.SetPixel($x, $y, $output)
        $updatedAtlas.SetPixel($targetX + $x, $targetY + $y, $output)
    }
}

$sourceAtlas.Dispose()
$targetAtlas.Dispose()
$cell.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
$cell.Dispose()
$updatedAtlas.Save($temporaryAtlasPath, [System.Drawing.Imaging.ImageFormat]::Png)
$updatedAtlas.Dispose()
Move-Item -LiteralPath $temporaryAtlasPath -Destination $atlasPath -Force

Write-Output "HUD icon installed at atlas cell $targetX,$targetY."
