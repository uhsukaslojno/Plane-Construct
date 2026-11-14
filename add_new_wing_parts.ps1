param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $true)]
    [string]$ScoobRoot,
    [switch]$Write
)

$ErrorActionPreference = 'Stop'
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$encoding = [System.Text.UTF8Encoding]::new($false)
$meshRoot = Join-Path $ProjectRoot 'Objects\Mesh\Wing Additions'
$sourceOther = Join-Path $ScoobRoot 'Objects\Mesh\Other Wings'
$sourceEdges = Join-Path $ScoobRoot 'Objects\Mesh\WingEdge'

$parts = @(
    [pscustomobject]@{ Uuid = '10c8439e-c8bc-41e4-896b-b0fb1802bd55'; Name = 'obj_centered_wing_edge_45_1x1'; Title = 'Centered Wing Edge 45'; Description = 'A centered sharp 45-degree lifting wing edge.'; Source = (Join-Path $sourceEdges 'Wing Edge 45 1x1.obj'); Mesh = 'Centered\Centered Wing Edge 45 1x1.obj'; Size = 1; Class = 'Wing1x1'; OffsetY = 0.0; MirrorZ = $false; ScaleXZ = 1.0; Icon = '96 0' },
    [pscustomobject]@{ Uuid = 'a5a27827-71d4-420d-b24c-c19fa75bccad'; Name = 'obj_sided_wing_edge_45_1x1'; Title = 'Sided Wing Edge 45'; Description = 'A sharp 45-degree lifting wing edge aligned to one side of the building grid.'; Source = (Join-Path $sourceEdges 'Wing Edge 45 1x1.obj'); Mesh = 'Sided\Sided Wing Edge 45 1x1.obj'; Size = 1; Class = 'Wing1x1'; OffsetY = 0.25; MirrorZ = $false; ScaleXZ = 1.0; Icon = '96 0' },
    [pscustomobject]@{ Uuid = 'f8463888-870e-4110-b625-d9f0191a0c10'; Name = 'obj_centered_wing_edge_straight_1x1'; Title = 'Centered Wing Edge Straight 1x1'; Description = 'A centered straight tapered lifting wing edge.'; Source = (Join-Path $sourceEdges 'Wing Edge Straight 1x1.obj'); Mesh = 'Centered\Centered Wing Edge Straight 1x1.obj'; Size = 1; Class = 'Wing1x1'; OffsetY = 0.0; MirrorZ = $false; ScaleXZ = 1.0; Icon = '192 0' },
    [pscustomobject]@{ Uuid = 'e5313e97-bd5e-489f-8b93-404d8355d3b2'; Name = 'obj_sided_wing_edge_straight_1x1'; Title = 'Sided Wing Edge Straight 1x1'; Description = 'A straight tapered lifting wing edge aligned to one side of the building grid.'; Source = (Join-Path $sourceEdges 'Wing Edge Straight 1x1.obj'); Mesh = 'Sided\Sided Wing Edge Straight 1x1.obj'; Size = 1; Class = 'Wing1x1'; OffsetY = 0.25; MirrorZ = $false; ScaleXZ = 1.0; Icon = '192 0' },
    [pscustomobject]@{ Uuid = 'd24f70d6-7cd6-4b9b-8eb2-03f99fb356b6'; Name = 'obj_centered_wing_2x2'; Title = 'Centered Wing 2x2'; Description = 'A centered 2x2 lifting wing panel.'; Source = (Join-Path $sourceOther 'Wing 2x2.obj'); Mesh = 'Centered\Centered Wing 2x2.obj'; Size = 2; Class = 'Wing2x2'; OffsetY = 0.0; MirrorZ = $false; ScaleXZ = 1.0; Icon = '288 0' },
    [pscustomobject]@{ Uuid = '9e8e7e48-234c-490f-af8f-d8e703734258'; Name = 'obj_sided_wing_2x2'; Title = 'Sided Wing 2x2'; Description = 'A 2x2 lifting wing panel aligned to one side of the building grid.'; Source = (Join-Path $sourceOther 'Wing 2x2.obj'); Mesh = 'Sided\Sided Wing 2x2.obj'; Size = 2; Class = 'Wing2x2'; OffsetY = 0.25; MirrorZ = $false; ScaleXZ = 1.0; Icon = '288 0' },
    [pscustomobject]@{ Uuid = 'c6159641-0bc1-4957-b6a7-be10ec74cf47'; Name = 'obj_centered_wing_3x3'; Title = 'Centered Wing 3x3'; Description = 'A centered 3x3 lifting wing panel.'; Source = (Join-Path $sourceOther 'Wing 3x3.obj'); Mesh = 'Centered\Centered Wing 3x3.obj'; Size = 3; Class = 'Wing3x3'; OffsetY = 0.0; MirrorZ = $false; ScaleXZ = 1.0; Icon = '384 0' },
    [pscustomobject]@{ Uuid = 'cdf62bba-0208-470b-b849-629384682b08'; Name = 'obj_sided_wing_3x3'; Title = 'Sided Wing 3x3'; Description = 'A 3x3 lifting wing panel aligned to one side of the building grid.'; Source = (Join-Path $sourceOther 'Wing 3x3.obj'); Mesh = 'Sided\Sided Wing 3x3.obj'; Size = 3; Class = 'Wing3x3'; OffsetY = 0.25; MirrorZ = $false; ScaleXZ = 1.0; Icon = '384 0' },
    [pscustomobject]@{ Uuid = '8ce3fb7e-ab19-4c2d-81e8-46e7e894688b'; Name = 'obj_centered_wing_4x4'; Title = 'Centered Wing 4x4'; Description = 'A centered 4x4 lifting wing panel.'; Source = (Join-Path $sourceOther 'Wing 3x3.obj'); Mesh = 'Centered\Centered Wing 4x4.obj'; Size = 4; Class = 'Wing4x4'; OffsetY = 0.0; MirrorZ = $false; ScaleXZ = (4.0 / 3.0); Icon = '480 0' },
    [pscustomobject]@{ Uuid = '83aa4d09-c38e-4925-8fdf-ebb5db436078'; Name = 'obj_sided_wing_4x4'; Title = 'Sided Wing 4x4'; Description = 'A 4x4 lifting wing panel aligned to one side of the building grid.'; Source = (Join-Path $sourceOther 'Wing 3x3.obj'); Mesh = 'Sided\Sided Wing 4x4.obj'; Size = 4; Class = 'Wing4x4'; OffsetY = 0.25; MirrorZ = $false; ScaleXZ = (4.0 / 3.0); Icon = '480 0' }
)

function Convert-Mesh([pscustomobject]$part) {
    $output = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadAllLines($part.Source)) {
        $tokens = $line.Trim() -split '\s+'
        $isSharpEdgeFace = $line.StartsWith('f ') -and [System.IO.Path]::GetFileName($part.Source) -eq 'Wing Edge 45 1x1.obj'
        if ($isSharpEdgeFace) {
            $cleanTokens = [System.Collections.Generic.List[string]]::new()
            $usedVertexIndices = @{}
            foreach ($faceToken in @($line.Substring(2).Trim() -split '\s+')) {
                $indices = $faceToken -split '/'
                $vertexIndex = if ($indices[0] -eq '4') { '2' } elseif ($indices[0] -eq '6') { '1' } else { $indices[0] }
                if (-not $usedVertexIndices.ContainsKey($vertexIndex)) {
                    $indices[0] = $vertexIndex
                    $cleanTokens.Add($indices -join '/')
                    $usedVertexIndices[$vertexIndex] = $true
                }
            }
            if ($cleanTokens.Count -lt 3) {
                continue
            }
            $cleanFaceTokens = $cleanTokens.ToArray()
            if ($part.MirrorZ) {
                [array]::Reverse($cleanFaceTokens)
            }
            $output.Add('f ' + ($cleanFaceTokens -join ' '))
            continue
        } elseif ($tokens[0] -eq 'v') {
            $x = [double]::Parse($tokens[1], $invariant) * $part.ScaleXZ
            $y = [double]::Parse($tokens[2], $invariant) + $part.OffsetY
            $z = [double]::Parse($tokens[3], $invariant) * $part.ScaleXZ
            if ($part.MirrorZ) { $z = -$z }
            $output.Add('v ' + $x.ToString('F8', $invariant) + ' ' + $y.ToString('F8', $invariant) + ' ' + $z.ToString('F8', $invariant))
        } elseif ($tokens[0] -eq 'vn' -and $part.MirrorZ) {
            $normalZ = -[double]::Parse($tokens[3], $invariant)
            $output.Add('vn ' + $tokens[1] + ' ' + $tokens[2] + ' ' + $normalZ.ToString('F8', $invariant))
        } elseif ($line.StartsWith('f ') -and $part.MirrorZ) {
            $faceTokens = @($line.Substring(2).Trim() -split '\s+')
            [array]::Reverse($faceTokens)
            $output.Add('f ' + ($faceTokens -join ' '))
        } else {
            $output.Add($line)
        }
    }
    return $output.ToArray()
}

$pendingMeshes = foreach ($part in $parts) {
    if (-not (Test-Path -LiteralPath $part.Source)) {
        throw "Missing source mesh: $($part.Source)"
    }
    [pscustomobject]@{ Path = (Join-Path $meshRoot $part.Mesh); Lines = (Convert-Mesh -part $part) }
}

$partList = foreach ($part in $parts) {
    [ordered]@{
        uuid = $part.Uuid
        name = $part.Name
        renderable = [ordered]@{
            lodList = @([ordered]@{
                mesh = '$CONTENT_DATA/Objects/Mesh/Wing Additions/' + $part.Mesh.Replace('\', '/')
                subMeshList = @([ordered]@{
                    material = 'DifAsgNor'
                    textureList = @(
                        '$CONTENT_DATA/Objects/Textures/aircraft_panel_colorable_contrast_paintable_dif.png',
                        '$CONTENT_DATA/Objects/Textures/scoob_asg.png',
                        '$CONTENT_DATA/Objects/Textures/scoob_normal.jpg'
                    )
                })
            })
        }
        box = [ordered]@{ x = $part.Size; y = 1; z = $part.Size }
        scripted = [ordered]@{ filename = '$CONTENT_DATA/Scripts/ScoobAirfoil.lua'; classname = $part.Class }
        qualityLevel = 0
        color = 'aeb5bb'
        density = 250
        flammable = $true
        physicsMaterial = 'Plastic'
        rotationSet = 'PropFull'
        sticky = '+X-X+Y-Y+Z-Z'
    }
}

if ($Write) {
    $retiredMeshPaths = @(
        (Join-Path $meshRoot 'Sided\Sided Wing Edge 45 R 1x1.obj'),
        (Join-Path $meshRoot 'Sided\Sided Wing Edge Straight R 1x1.obj'),
        (Join-Path $meshRoot 'Sided Mirrored\Sided Wing Edge 45 L 1x1.obj'),
        (Join-Path $meshRoot 'Sided Mirrored\Sided Wing Edge Straight L 1x1.obj')
    )
    foreach ($retiredMeshPath in $retiredMeshPaths) {
        if (Test-Path -LiteralPath $retiredMeshPath) {
            Remove-Item -LiteralPath $retiredMeshPath -Force
        }
    }
    foreach ($pendingMesh in $pendingMeshes) {
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $pendingMesh.Path)) | Out-Null
        [System.IO.File]::WriteAllLines($pendingMesh.Path, $pendingMesh.Lines, $encoding)
    }

    $shapeSetPath = Join-Path $ProjectRoot 'Objects\Database\ShapeSets\NewWingVariants.json'
    [System.IO.File]::WriteAllText($shapeSetPath, (@{ partList = @($partList) } | ConvertTo-Json -Depth 12), $encoding)

    $languagePath = Join-Path $ProjectRoot 'Gui\Language\English\inventoryDescriptions.json'
    $language = Get-Content -Raw -LiteralPath $languagePath | ConvertFrom-Json
    foreach ($retiredUuid in @('ab6a3e87-da18-49e7-9180-b828ceaef5a8', '316001e3-0da8-48bb-be77-69d1ff8f958b')) {
        if ($language.PSObject.Properties.Name -contains $retiredUuid) {
            $language.PSObject.Properties.Remove($retiredUuid)
        }
    }
    foreach ($part in $parts) {
        if ($language.PSObject.Properties.Name -contains $part.Uuid) {
            $language.PSObject.Properties.Remove($part.Uuid)
        }
        $language | Add-Member -NotePropertyName $part.Uuid -NotePropertyValue ([ordered]@{ title = $part.Title; description = $part.Description })
    }
    [System.IO.File]::WriteAllText($languagePath, ($language | ConvertTo-Json -Depth 10), $encoding)

    Add-Type -AssemblyName System.Drawing
    $sourceAtlasPath = Join-Path $ScoobRoot 'Gui\IconMap.png'
    $targetAtlasPath = Join-Path $ProjectRoot 'Gui\IconMap.png'
    $temporaryAtlasPath = Join-Path $ProjectRoot 'Gui\IconMap.new-wings.tmp.png'
    $sourceAtlas = [System.Drawing.Bitmap]::new($sourceAtlasPath)
    $targetAtlas = [System.Drawing.Bitmap]::new($targetAtlasPath)
    $iconCopies = @(
        [pscustomobject]@{ SourceX = 1920; SourceY = 0; TargetX = 96; TargetY = 0 },
        [pscustomobject]@{ SourceX = 288; SourceY = 192; TargetX = 192; TargetY = 0 },
        [pscustomobject]@{ SourceX = 1440; SourceY = 0; TargetX = 288; TargetY = 0 },
        [pscustomobject]@{ SourceX = 1536; SourceY = 0; TargetX = 384; TargetY = 0 },
        [pscustomobject]@{ SourceX = 1536; SourceY = 0; TargetX = 480; TargetY = 0 }
    )
    foreach ($iconCopy in $iconCopies) {
        $sourceRectangle = [System.Drawing.Rectangle]::new($iconCopy.SourceX, $iconCopy.SourceY, 96, 96)
        $targetRectangle = [System.Drawing.Rectangle]::new($iconCopy.TargetX, $iconCopy.TargetY, 96, 96)
        $sourceData = $sourceAtlas.LockBits($sourceRectangle, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $targetData = $targetAtlas.LockBits($targetRectangle, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $row = [byte[]]::new(96 * 4)
            for ($pixelRow = 0; $pixelRow -lt 96; $pixelRow++) {
                $sourcePointer = [IntPtr]::Add($sourceData.Scan0, $pixelRow * $sourceData.Stride)
                $targetPointer = [IntPtr]::Add($targetData.Scan0, $pixelRow * $targetData.Stride)
                [System.Runtime.InteropServices.Marshal]::Copy($sourcePointer, $row, 0, $row.Length)
                [System.Runtime.InteropServices.Marshal]::Copy($row, 0, $targetPointer, $row.Length)
            }
        } finally {
            $sourceAtlas.UnlockBits($sourceData)
            $targetAtlas.UnlockBits($targetData)
        }
    }
    $sourceAtlas.Dispose()
    $targetAtlas.SetResolution(72.0, 72.0)
    $targetAtlas.Save($temporaryAtlasPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $targetAtlas.Dispose()
    Move-Item -LiteralPath $temporaryAtlasPath -Destination $targetAtlasPath -Force
}

$parts | Select-Object Uuid, Title, Mesh, Class, Size
