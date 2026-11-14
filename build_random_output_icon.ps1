$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$guiRoot = Join-Path $PSScriptRoot 'Gui'
$generatedPath = Join-Path $guiRoot 'RandomOutputGateIcon.png'
$cellPath = Join-Path $guiRoot 'RandomOutputGateIcon96.png'
$atlasPath = Join-Path $guiRoot 'IconMap.png'
$backupPath = Join-Path $guiRoot 'IconMap.before_random_output_gate_icon.png'
$temporaryAtlasPath = Join-Path $guiRoot 'IconMap.random-output.tmp.png'

if (-not (Test-Path -LiteralPath $generatedPath)) {
    throw "Generated icon source is missing: $generatedPath"
}

if (-not (Test-Path -LiteralPath $backupPath)) {
    Copy-Item -LiteralPath $atlasPath -Destination $backupPath
}

$source = [Drawing.Bitmap]::FromFile($generatedPath)
$cell = New-Object Drawing.Bitmap 96, 96, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$cell.SetResolution(96, 96)
$graphics = [Drawing.Graphics]::FromImage($cell)
$graphics.Clear([Drawing.Color]::Transparent)
$graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
$graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
$destinationRectangle = New-Object Drawing.Rectangle 8, 4, 80, 88
$sourceRectangle = New-Object Drawing.Rectangle 140, 80, 980, 1080
$graphics.DrawImage($source, $destinationRectangle, $sourceRectangle, [Drawing.GraphicsUnit]::Pixel)
$graphics.Dispose()
$source.Dispose()

# The generated preview contained a light checkerboard instead of true alpha.
# Remove only bright, nearly-neutral pixels; the green and dark model remain.
for ($y = 0; $y -lt $cell.Height; $y++) {
    for ($x = 0; $x -lt $cell.Width; $x++) {
        $pixel = $cell.GetPixel($x, $y)
        $minimum = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))
        $maximum = [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B))
        if ($minimum -ge 190 -and ($maximum - $minimum) -le 20) {
            $cell.SetPixel($x, $y, [Drawing.Color]::Transparent)
        }
    }
}

$cell.Save($cellPath, [Drawing.Imaging.ImageFormat]::Png)

$originalAtlas = [Drawing.Bitmap]::FromFile($backupPath)
$updatedAtlas = New-Object Drawing.Bitmap $originalAtlas.Width, $originalAtlas.Height, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$updatedAtlas.SetResolution(72, 72)
$atlasGraphics = [Drawing.Graphics]::FromImage($updatedAtlas)
$atlasGraphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
$atlasGraphics.DrawImageUnscaled($originalAtlas, 0, 0)
$atlasGraphics.DrawImageUnscaled($cell, 1920, 1344)
$atlasGraphics.Dispose()
$originalAtlas.Dispose()
$cell.Dispose()

$updatedAtlas.Save($temporaryAtlasPath, [Drawing.Imaging.ImageFormat]::Png)
$updatedAtlas.Dispose()
Copy-Item -LiteralPath $temporaryAtlasPath -Destination $atlasPath -Force
Remove-Item -LiteralPath $temporaryAtlasPath

Write-Output "Random Output Gate icon installed at atlas cell 1920,1344."
