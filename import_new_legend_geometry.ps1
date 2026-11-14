param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [Parameter(Mandatory = $true)]
    [string]$LegendRoot,
    [switch]$Write
)

$ErrorActionPreference = 'Stop'
$encoding = [System.Text.UTF8Encoding]::new($false)
$wingTextures = @(
    '$CONTENT_DATA/Objects/Textures/aircraft_panel_colorable_contrast_paintable_dif.png',
    '$CONTENT_DATA/Objects/Textures/scoob_asg.png',
    '$CONTENT_DATA/Objects/Textures/scoob_normal.jpg'
)
$excludedWingHalfBlockUuid = '5011aaac-5494-11e6-beb8-9e71128cae77'
$targetShapeSetRelative = 'Objects\Database\ShapeSets\NewLegendGeometry.json'
$targetMeshRootRelative = 'Objects\Mesh\New Legend Geometry'
$targetAtlasWidth = 2048
$targetAtlasHeight = 1536
$iconSize = 96

function Read-CommentJson([string]$path) {
    $json = [System.IO.File]::ReadAllText($path)
    $json = [regex]::Replace($json, '(?s)/\*.*?\*/', '')
    $json = [regex]::Replace($json, '(?m)//.*$', '')
    return $json | ConvertFrom-Json
}

function Get-GeometryCategory([string]$title) {
    if (-not $title -or $title -match '(?i)glass|glow') { return $null }
    if ($title -eq 'Tangential Cube') { return 'Tangential Cubes' }
    if ($title -eq 'Trangular Pyramid') { return 'Trangular Pyramids' }
    if ($title -eq 'Rectangular Pyramid') { return 'Rectangular Pyramids' }
    if ($title -match '^Bevel .*Spacing [0-9]+$') { return 'Bevels With Spacing' }
    if ($title -eq 'Triangle Slice') { return 'Triangle Slices' }
    if ($title -eq 'Corner Slice') { return 'Corner Slices' }
    if ($title -eq 'Square Slice') { return 'Square Slices' }
    if ($title -match 'Half Slice|Half to One Block Slice') { return 'Half Slices' }
    if ($title -match 'Arc Slice') { return 'Arc Slices' }
    if ($title -eq 'Arc' -or $title -eq 'Anti Arc') { return 'Arcs' }
    if ($title -eq '1/8 Ball') { return '1/8 Balls' }
    if ($title -eq '1/4 Cone') { return '1/4 Cones' }
    if ($title -match '(?i)bevel Slice') { return 'Bevel Slices' }
    if ($title -eq 'Trangular Pyramid Slice') { return 'Trangular Slices' }
    if ($title -eq 'Tangential Cube Slice') { return 'Tangential Cube Slices' }
    if ($title -match 'Half Block|Block Half') { return 'Half Blocks' }
    if ($title -eq 'Circular Tube') { return 'Circular Tubes' }
    if ($title -eq 'Cone') { return 'Cones' }
    return $null
}

function Get-DeterministicUuid([string]$sourceUuid) {
    $seed = [System.Text.Encoding]::UTF8.GetBytes('FoamGun-NewLegendGeometry-v1:' + $sourceUuid.ToLowerInvariant())
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($seed)
    } finally {
        $sha256.Dispose()
    }
    $bytes = [byte[]]::new(16)
    [array]::Copy($hash, $bytes, 16)
    $bytes[7] = ($bytes[7] -band 0x0f) -bor 0x50
    $bytes[8] = ($bytes[8] -band 0x3f) -bor 0x80
    return [guid]::new($bytes).ToString()
}

function Get-PartDimensions($part) {
    if ($part.box) { return "$($part.box.x)x$($part.box.y)x$($part.box.z)" }
    if ($part.hull -and $part.hull.x) { return "$($part.hull.x)x$($part.hull.y)x$($part.hull.z)" }
    if ($part.cylinder) { return "diameter $($part.cylinder.diameter), depth $($part.cylinder.depth)" }
    return ''
}

function Get-SourceMeshPath($part) {
    if (-not $part.renderable -or -not $part.renderable.lodList) {
        throw "Unsupported renderable for $($part.uuid)."
    }
    return [string]$part.renderable.lodList[0].mesh
}

function Convert-SourcePathToRelative([string]$sourcePath) {
    $relative = $sourcePath.Replace('$MOD_DATA/', '').Replace('$CONTENT_DATA/', '').Replace('/', '\')
    if (-not $relative.StartsWith('Objects\Mesh\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unexpected source mesh path: $sourcePath"
    }
    return $relative
}

function Copy-BitmapRectangle($sourceBitmap, $targetBitmap, [System.Drawing.Rectangle]$sourceRectangle, [System.Drawing.Rectangle]$targetRectangle) {
    $pixelFormat = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    $sourceData = $sourceBitmap.LockBits($sourceRectangle, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $pixelFormat)
    $targetData = $targetBitmap.LockBits($targetRectangle, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $pixelFormat)
    try {
        $rowLength = $sourceRectangle.Width * 4
        $row = [byte[]]::new($rowLength)
        for ($pixelRow = 0; $pixelRow -lt $sourceRectangle.Height; $pixelRow++) {
            $sourcePointer = [IntPtr]::Add($sourceData.Scan0, $pixelRow * $sourceData.Stride)
            $targetPointer = [IntPtr]::Add($targetData.Scan0, $pixelRow * $targetData.Stride)
            [System.Runtime.InteropServices.Marshal]::Copy($sourcePointer, $row, 0, $rowLength)
            [System.Runtime.InteropServices.Marshal]::Copy($row, 0, $targetPointer, $rowLength)
        }
    } finally {
        $sourceBitmap.UnlockBits($sourceData)
        $targetBitmap.UnlockBits($targetData)
    }
}

$languagePath = Join-Path $LegendRoot 'Gui\Language\English\inventoryDescriptions.json'
$sourceLanguage = Read-CommentJson $languagePath
$sourceTitles = @{}
$sourceDescriptions = @{}
foreach ($property in $sourceLanguage.PSObject.Properties) {
    $sourceTitles[$property.Name] = [string]$property.Value.title
    $sourceDescriptions[$property.Name] = [string]$property.Value.description
}

$sourceIconXmlPath = Join-Path $LegendRoot 'Gui\IconMap.xml'
[xml]$sourceIconXml = Get-Content -Raw -LiteralPath $sourceIconXmlPath
$sourceIconPoints = @{}
foreach ($index in $sourceIconXml.MyGUI.Resource.Group.Index) {
    $sourceIconPoints[[string]$index.name] = [string]$index.Frame.point
}

$selected = [System.Collections.Generic.List[object]]::new()
$shapeSetDirectory = Join-Path $LegendRoot 'Objects\Database\ShapeSets'
foreach ($shapeSetFile in Get-ChildItem -LiteralPath $shapeSetDirectory -Filter '*.json' -File | Sort-Object Name) {
    try {
        $shapeSet = Read-CommentJson $shapeSetFile.FullName
    } catch {
        continue
    }
    foreach ($part in @($shapeSet.partList)) {
        if (-not $part.uuid -or [string]$part.uuid -eq $excludedWingHalfBlockUuid) { continue }
        $sourceUuid = [string]$part.uuid
        $title = $sourceTitles[$sourceUuid]
        $category = Get-GeometryCategory $title
        if (-not $category) { continue }
        $sourceMeshReference = Get-SourceMeshPath $part
        $sourceMeshRelative = Convert-SourcePathToRelative $sourceMeshReference
        $sourceMeshPath = Join-Path $LegendRoot $sourceMeshRelative
        if (-not (Test-Path -LiteralPath $sourceMeshPath)) {
            throw "Missing source mesh: $sourceMeshPath"
        }
        if (-not $sourceIconPoints.ContainsKey($sourceUuid)) {
            throw "Missing source icon: $sourceUuid"
        }
        $selected.Add([pscustomobject]@{
            Category = $category
            SourceUuid = $sourceUuid
            Uuid = Get-DeterministicUuid $sourceUuid
            Title = $title
            Description = $sourceDescriptions[$sourceUuid]
            Dimensions = Get-PartDimensions $part
            ShapeSet = $shapeSetFile.Name
            SourceMeshReference = $sourceMeshReference
            SourceMeshRelative = $sourceMeshRelative
            SourceMeshPath = $sourceMeshPath
            Part = $part
            SourceIconPoint = $sourceIconPoints[$sourceUuid]
        })
    }
}
$selected = @($selected | Sort-Object Category, Title, Dimensions, SourceMeshRelative, SourceUuid)

if ($selected.Count -ne 273) {
    throw "Expected 273 selected geometry variants, found $($selected.Count)."
}
if (@($selected.Uuid | Sort-Object -Unique).Count -ne $selected.Count) {
    throw 'Generated UUID collision detected.'
}
if (@($selected.SourceMeshRelative | Sort-Object -Unique).Count -ne $selected.Count) {
    throw 'Expected every selected definition to use a unique source mesh.'
}

$existingUuids = @{}
$projectShapeDatabasePath = Join-Path $ProjectRoot 'Objects\Database\shapesets.shapedb'
$projectShapeDatabase = Get-Content -Raw -LiteralPath $projectShapeDatabasePath | ConvertFrom-Json
foreach ($shapeSetReference in $projectShapeDatabase.shapeSetList) {
    $shapeSetRelative = $shapeSetReference.Replace('$CONTENT_DATA/', '').Replace('/', '\')
    if ($shapeSetRelative -eq $targetShapeSetRelative) { continue }
    $shapeSetPath = Join-Path $ProjectRoot $shapeSetRelative
    if (-not (Test-Path -LiteralPath $shapeSetPath)) { continue }
    $shapeSet = Get-Content -Raw -LiteralPath $shapeSetPath | ConvertFrom-Json
    foreach ($shape in @($shapeSet.partList) + @($shapeSet.blockList)) {
        if ($shape.uuid) { $existingUuids[[string]$shape.uuid] = $true }
    }
}
foreach ($item in $selected) {
    if ($existingUuids.ContainsKey($item.Uuid)) {
        throw "Generated UUID collides with an existing shape: $($item.Uuid)"
    }
}

$titleGroups = $selected | Group-Object { $_.Title + '|' + $_.Dimensions }
$displayTitles = @{}
foreach ($group in $titleGroups) {
    $variantIndex = 0
    foreach ($item in @($group.Group | Sort-Object SourceMeshRelative, SourceUuid)) {
        $variantIndex++
        $displayTitle = $item.Title
        if ($item.Dimensions) { $displayTitle += " [$($item.Dimensions)]" }
        if ($group.Count -gt 1) { $displayTitle += " (Variant $variantIndex)" }
        $displayTitles[$item.SourceUuid] = $displayTitle
    }
}

$newParts = [System.Collections.Generic.List[object]]::new()
$meshCopies = [System.Collections.Generic.List[object]]::new()
foreach ($item in $selected) {
    $part = ($item.Part | ConvertTo-Json -Depth 40) | ConvertFrom-Json
    $part.uuid = $item.Uuid
    $part | Add-Member -NotePropertyName name -NotePropertyValue ('obj_new_legend_geometry_' + $item.SourceUuid.Replace('-', '_')) -Force
    if ($part.PSObject.Properties.Name -contains 'scripted') {
        $part.PSObject.Properties.Remove('scripted')
    }
    $part.flammable = $true
    $part.color = 'aeb5bb'
    foreach ($lod in @($part.renderable.lodList)) {
        foreach ($subMesh in @($lod.subMeshList)) {
            $subMesh.material = 'DifAsgNor'
            $subMesh.textureList = $wingTextures
        }
        $sourceSuffix = $item.SourceMeshRelative.Substring('Objects\Mesh\'.Length)
        $targetMeshRelative = Join-Path $targetMeshRootRelative $sourceSuffix
        $lod.mesh = '$CONTENT_DATA/' + $targetMeshRelative.Replace('\', '/')
    }
    $newParts.Add($part)
    $targetMeshPath = Join-Path $ProjectRoot (Join-Path $targetMeshRootRelative $item.SourceMeshRelative.Substring('Objects\Mesh\'.Length))
    $meshCopies.Add([pscustomobject]@{ Source = $item.SourceMeshPath; Target = $targetMeshPath })
}

if ($Write) {
    foreach ($meshCopy in $meshCopies) {
        [System.IO.Directory]::CreateDirectory((Split-Path -Parent $meshCopy.Target)) | Out-Null
        [System.IO.File]::Copy($meshCopy.Source, $meshCopy.Target, $true)
    }

    $shapeSetPath = Join-Path $ProjectRoot $targetShapeSetRelative
    [System.IO.File]::WriteAllText($shapeSetPath, (@{ partList = $newParts.ToArray() } | ConvertTo-Json -Depth 40), $encoding)

    $rotationSource = Join-Path $LegendRoot 'Objects\Database\rotationsets.json'
    $rotationTarget = Join-Path $ProjectRoot 'Objects\Database\rotationsets.json'
    [System.IO.File]::Copy($rotationSource, $rotationTarget, $true)

    $targetLanguagePath = Join-Path $ProjectRoot 'Gui\Language\English\inventoryDescriptions.json'
    $targetLanguage = Get-Content -Raw -LiteralPath $targetLanguagePath | ConvertFrom-Json
    foreach ($item in $selected) {
        if ($targetLanguage.PSObject.Properties.Name -contains $item.Uuid) {
            $targetLanguage.PSObject.Properties.Remove($item.Uuid)
        }
        $description = $item.Description
        if ($description) { $description += "`n" }
        $description += 'Static, flammable geometry with an aircraft-panel finish.'
        $targetLanguage | Add-Member -NotePropertyName $item.Uuid -NotePropertyValue ([ordered]@{
            title = $displayTitles[$item.SourceUuid]
            description = $description
        })
    }
    [System.IO.File]::WriteAllText($targetLanguagePath, ($targetLanguage | ConvertTo-Json -Depth 10), $encoding)

    [xml]$targetIconXml = Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot 'Gui\IconMap.xml')
    $targetIconGroup = $targetIconXml.MyGUI.Resource.Group
    $generatedUuids = @{}
    foreach ($item in $selected) { $generatedUuids[$item.Uuid] = $true }
    foreach ($index in @($targetIconGroup.Index)) {
        if ($generatedUuids.ContainsKey([string]$index.name)) {
            $null = $targetIconGroup.RemoveChild($index)
        }
    }
    $usedPoints = @{}
    foreach ($index in @($targetIconGroup.Index)) {
        $usedPoints[[string]$index.Frame.point] = $true
    }
    $availablePoints = [System.Collections.Generic.List[string]]::new()
    for ($y = 0; $y -le $targetAtlasHeight - $iconSize; $y += $iconSize) {
        for ($x = 0; $x -le $targetAtlasWidth - $iconSize; $x += $iconSize) {
            $point = "$x $y"
            if (-not $usedPoints.ContainsKey($point)) { $availablePoints.Add($point) }
        }
    }
    if ($availablePoints.Count -lt $selected.Count) {
        throw "Icon atlas has only $($availablePoints.Count) free cells for $($selected.Count) parts."
    }
    $targetIconAssignments = @{}
    for ($index = 0; $index -lt $selected.Count; $index++) {
        $item = $selected[$index]
        $point = $availablePoints[$index]
        $targetIconAssignments[$item.SourceUuid] = $point
        $indexNode = $targetIconXml.CreateElement('Index')
        $indexNode.SetAttribute('name', $item.Uuid)
        $frameNode = $targetIconXml.CreateElement('Frame')
        $frameNode.SetAttribute('point', $point)
        $null = $indexNode.AppendChild($frameNode)
        $null = $targetIconGroup.AppendChild($indexNode)
    }
    $targetIconXmlPath = Join-Path $ProjectRoot 'Gui\IconMap.xml'
    $xmlSettings = [System.Xml.XmlWriterSettings]::new()
    $xmlSettings.Indent = $true
    $xmlSettings.IndentChars = '  '
    $xmlSettings.Encoding = $encoding
    $xmlWriter = [System.Xml.XmlWriter]::Create($targetIconXmlPath, $xmlSettings)
    try {
        $targetIconXml.Save($xmlWriter)
    } finally {
        $xmlWriter.Dispose()
    }

    Add-Type -AssemblyName System.Drawing
    $sourceAtlas = [System.Drawing.Bitmap]::new((Join-Path $LegendRoot 'Gui\IconMap.png'))
    $existingAtlasPath = Join-Path $ProjectRoot 'Gui\IconMap.png'
    $existingAtlas = [System.Drawing.Bitmap]::new($existingAtlasPath)
    $newAtlas = [System.Drawing.Bitmap]::new($targetAtlasWidth, $targetAtlasHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $newAtlas.SetResolution(72.0, 72.0)
    $existingRectangle = [System.Drawing.Rectangle]::new(0, 0, $existingAtlas.Width, $existingAtlas.Height)
    Copy-BitmapRectangle $existingAtlas $newAtlas $existingRectangle $existingRectangle
    foreach ($item in $selected) {
        $sourceCoordinates = @($item.SourceIconPoint -split '\s+' | ForEach-Object { [int]$_ })
        $targetCoordinates = @($targetIconAssignments[$item.SourceUuid] -split '\s+' | ForEach-Object { [int]$_ })
        $sourceRectangle = [System.Drawing.Rectangle]::new($sourceCoordinates[0], $sourceCoordinates[1], $iconSize, $iconSize)
        $targetRectangle = [System.Drawing.Rectangle]::new($targetCoordinates[0], $targetCoordinates[1], $iconSize, $iconSize)
        Copy-BitmapRectangle $sourceAtlas $newAtlas $sourceRectangle $targetRectangle
    }
    $sourceAtlas.Dispose()
    $existingAtlas.Dispose()
    $temporaryAtlasPath = Join-Path $ProjectRoot 'Gui\IconMap.new-legend.tmp.png'
    $newAtlas.Save($temporaryAtlasPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $newAtlas.Dispose()
    Move-Item -LiteralPath $temporaryAtlasPath -Destination $existingAtlasPath -Force

    $inventoryPath = Join-Path $ProjectRoot 'new_legend_geometry_inventory.csv'
    $selected | Select-Object Category, SourceUuid, Uuid, @{n='DisplayTitle';e={$displayTitles[$_.SourceUuid]}}, Dimensions, ShapeSet, SourceMeshRelative | Export-Csv -LiteralPath $inventoryPath -NoTypeInformation -Encoding UTF8
}

$selected | Group-Object Category | Sort-Object Name | Select-Object Name, Count
