param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$Write
)

$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$ErrorActionPreference = 'Stop'
$uvScale = 0.09375
$uvCenter = 0.5
$meshDirectories = @(
    'Objects\Mesh\Centered Wings',
    'Objects\Mesh\Centered Wing Wedges',
    'Objects\Mesh\Sided Wings',
    'Objects\Mesh\Sided Wing Wedges',
    'Objects\Mesh\Sided Wing Wedges Mirrored',
    'Objects\Mesh\Wing Additions\Centered',
    'Objects\Mesh\Wing Additions\Sided',
    'Objects\Mesh\Wing Additions\Sided Mirrored'
)

function Get-DotProduct([double[]]$left, [double[]]$right) {
    return $left[0] * $right[0] + $left[1] * $right[1] + $left[2] * $right[2]
}

function Get-VectorLength([double[]]$vector) {
    return [Math]::Sqrt((Get-DotProduct -left $vector -right $vector))
}

function Get-NormalizedVector([double[]]$vector) {
    $length = Get-VectorLength -vector $vector
    if ($length -le 0.0000001) {
        throw 'Cannot normalize a zero-length vector.'
    }
    return @(
        ($vector[0] / $length),
        ($vector[1] / $length),
        ($vector[2] / $length)
    )
}

function Get-CrossProduct([double[]]$left, [double[]]$right) {
    return @(
        ($left[1] * $right[2] - $left[2] * $right[1]),
        ($left[2] * $right[0] - $left[0] * $right[2]),
        ($left[0] * $right[1] - $left[1] * $right[0])
    )
}

function Get-FaceNormal([object[]]$positions) {
    $edgeA = @(
        ($positions[1][0] - $positions[0][0]),
        ($positions[1][1] - $positions[0][1]),
        ($positions[1][2] - $positions[0][2])
    )
    $edgeB = @(
        ($positions[2][0] - $positions[0][0]),
        ($positions[2][1] - $positions[0][1]),
        ($positions[2][2] - $positions[0][2])
    )
    $crossProduct = Get-CrossProduct -left $edgeA -right $edgeB
    return Get-NormalizedVector -vector $crossProduct
}

function Test-FacePlanar([object[]]$positions, [double[]]$normal) {
    $origin = $positions[0]
    for ($positionIndex = 3; $positionIndex -lt $positions.Count; $positionIndex++) {
        $offset = @(
            ($positions[$positionIndex][0] - $origin[0]),
            ($positions[$positionIndex][1] - $origin[1]),
            ($positions[$positionIndex][2] - $origin[2])
        )
        if ([Math]::Abs((Get-DotProduct -left $offset -right $normal)) -gt 0.000001) {
            return $false
        }
    }
    return $true
}

function Get-PlanarAxes([double[]]$normal) {
    $preferredAxis = if ([Math]::Abs($normal[0]) -lt 0.9) { @(1.0, 0.0, 0.0) } else { @(0.0, 1.0, 0.0) }
    $normalProjection = Get-DotProduct -left $preferredAxis -right $normal
    $uAxis = Get-NormalizedVector -vector @(
        ($preferredAxis[0] - $normal[0] * $normalProjection),
        ($preferredAxis[1] - $normal[1] * $normalProjection),
        ($preferredAxis[2] - $normal[2] * $normalProjection)
    )
    $crossProduct = Get-CrossProduct -left $normal -right $uAxis
    $vAxis = Get-NormalizedVector -vector $crossProduct
    return [pscustomobject]@{ U = $uAxis; V = $vAxis }
}

$meshFiles = foreach ($relativeDirectory in $meshDirectories) {
    $directory = Join-Path $ProjectRoot $relativeDirectory
    Get-ChildItem -LiteralPath $directory -Filter '*.obj' -File
}
$meshFiles = @($meshFiles | Sort-Object FullName)
if ($meshFiles.Count -ne 42) {
    throw "Expected 42 wing meshes, found $($meshFiles.Count)."
}

$pendingWrites = @()
foreach ($meshFile in $meshFiles) {
    $lines = [System.IO.File]::ReadAllLines($meshFile.FullName)
    $vertices = [System.Collections.Generic.List[object]]::new()
    $normals = [System.Collections.Generic.List[object]]::new()

    foreach ($line in $lines) {
        $parts = $line.Trim() -split '\s+'
        if ($parts[0] -eq 'v') {
            $vertices.Add(@(
                [double]::Parse($parts[1], $invariant),
                [double]::Parse($parts[2], $invariant),
                [double]::Parse($parts[3], $invariant)
            ))
        } elseif ($parts[0] -eq 'vn') {
            $normals.Add((Get-NormalizedVector -vector @(
                [double]::Parse($parts[1], $invariant),
                [double]::Parse($parts[2], $invariant),
                [double]::Parse($parts[3], $invariant)
            )))
        }
    }

    $textureLines = [System.Collections.Generic.List[string]]::new()
    $replacementFaces = @{}
    $outputFaceCount = 0
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        if (-not $line.StartsWith('f ')) {
            continue
        }

        $tokens = @($line.Substring(2).Trim() -split '\s+')
        $facePositions = @()
        $faceData = @()
        foreach ($token in $tokens) {
            $indices = $token -split '/'
            $vertexIndex = [int]$indices[0]
            $normalIndex = if ($indices.Count -ge 3 -and $indices[2]) { [int]$indices[2] } else { 0 }
            if ($vertexIndex -le 0) {
                throw "Only positive OBJ vertex indices are supported: $($meshFile.FullName)"
            }
            $facePositions += ,$vertices[$vertexIndex - 1]
            $faceData += ,@($vertexIndex, $normalIndex)
        }

        $originalNormal = Get-FaceNormal -positions $facePositions
        $faceCornerSets = [System.Collections.Generic.List[object]]::new()
        if (Test-FacePlanar -positions $facePositions -normal $originalNormal) {
            $faceCornerSets.Add(@(0..($facePositions.Count - 1)))
        } else {
            for ($triangleIndex = 1; $triangleIndex -lt $facePositions.Count - 1; $triangleIndex++) {
                $faceCornerSets.Add(@(0, $triangleIndex, ($triangleIndex + 1)))
            }
        }

        $replacementFaceLines = [System.Collections.Generic.List[string]]::new()
        foreach ($faceCornerSet in $faceCornerSets) {
            $mappedPositions = @()
            $mappedData = @()
            foreach ($sourceCornerIndex in $faceCornerSet) {
                $mappedPositions += ,$facePositions[$sourceCornerIndex]
                $mappedData += ,$faceData[$sourceCornerIndex]
            }

            try {
                $normal = Get-FaceNormal -positions $mappedPositions
            } catch {
                throw "Invalid generated face in $($meshFile.FullName), line $($lineIndex + 1), corners $($faceCornerSet -join ','): $($_.Exception.Message)"
            }
            $axes = Get-PlanarAxes -normal $normal
            $uAxis = $axes.U
            $vAxis = $axes.V
            $newTokens = @()
            $faceUvs = @()

            for ($cornerIndex = 0; $cornerIndex -lt $mappedPositions.Count; $cornerIndex++) {
                $position = $mappedPositions[$cornerIndex]
                $u = $uvCenter + (Get-DotProduct -left $position -right $uAxis) * $uvScale
                $v = $uvCenter + (Get-DotProduct -left $position -right $vAxis) * $uvScale
                if ($u -lt -0.000001 -or $u -gt 1.000001 -or $v -lt -0.000001 -or $v -gt 1.000001) {
                    throw "Generated UV outside the texture for $($meshFile.FullName): $u, $v"
                }

                $textureLines.Add('vt ' + $u.ToString('F6', $invariant) + ' ' + $v.ToString('F6', $invariant))
                $textureIndex = $textureLines.Count
                $vertexIndex = $mappedData[$cornerIndex][0]
                $cornerNormalIndex = $mappedData[$cornerIndex][1]
                $newTokens += if ($cornerNormalIndex -gt 0) {
                    "$vertexIndex/$textureIndex/$cornerNormalIndex"
                } else {
                    "$vertexIndex/$textureIndex"
                }
                $faceUvs += ,@($u, $v)
            }

            for ($cornerIndex = 0; $cornerIndex -lt $mappedPositions.Count; $cornerIndex++) {
                $nextIndex = ($cornerIndex + 1) % $mappedPositions.Count
                $positionA = $mappedPositions[$cornerIndex]
                $positionB = $mappedPositions[$nextIndex]
                $worldDistance = Get-VectorLength -vector @(
                    ($positionB[0] - $positionA[0]),
                    ($positionB[1] - $positionA[1]),
                    ($positionB[2] - $positionA[2])
                )
                $uvDistance = [Math]::Sqrt(
                    [Math]::Pow($faceUvs[$nextIndex][0] - $faceUvs[$cornerIndex][0], 2) +
                    [Math]::Pow($faceUvs[$nextIndex][1] - $faceUvs[$cornerIndex][1], 2)
                )
                $scaleError = if ($worldDistance -gt 0.000001) {
                    [Math]::Abs($uvDistance / $worldDistance - $uvScale)
                } else {
                    0
                }
                if ($scaleError -gt 0.00001) {
                    throw "UV scale validation failed for $($meshFile.FullName), line $($lineIndex + 1), edge $cornerIndex`: $scaleError"
                }
            }

            $replacementFaceLines.Add('f ' + ($newTokens -join ' '))
            $outputFaceCount++
        }

        $replacementFaces[$lineIndex] = $replacementFaceLines.ToArray()
    }

    $firstNormalIndex = -1
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        if ($lines[$lineIndex].StartsWith('vn ')) {
            $firstNormalIndex = $lineIndex
            break
        }
    }
    if ($firstNormalIndex -lt 0) {
        throw "No normals found in $($meshFile.FullName)."
    }

    $newLines = [System.Collections.Generic.List[string]]::new()
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        if ($lineIndex -eq $firstNormalIndex) {
            foreach ($textureLine in $textureLines) {
                $newLines.Add($textureLine)
            }
        }
        if ($lines[$lineIndex].StartsWith('vt ')) {
            continue
        }
        if ($replacementFaces.ContainsKey($lineIndex)) {
            foreach ($replacementFaceLine in $replacementFaces[$lineIndex]) {
                $newLines.Add($replacementFaceLine)
            }
        } else {
            $newLines.Add($lines[$lineIndex])
        }
    }

    $pendingWrites += [pscustomobject]@{
        Path = $meshFile.FullName
        Lines = $newLines.ToArray()
        VertexCount = $vertices.Count
        FaceCount = $outputFaceCount
        TextureCoordinateCount = $textureLines.Count
    }
}

if ($Write) {
    $encoding = [System.Text.UTF8Encoding]::new($false)
    foreach ($pendingWrite in $pendingWrites) {
        [System.IO.File]::WriteAllLines($pendingWrite.Path, $pendingWrite.Lines, $encoding)
    }

    $oldAsgTexture = '$GAME_DATA/Objects/Textures/Blocks/blk_wedge_border_metal_asg.tga'
    $oldNormalTexture = '$GAME_DATA/Objects/Textures/Blocks/blk_wedge_border_nor.tga'
    $newAsgTexture = '$CONTENT_DATA/Objects/Textures/scoob_asg.png'
    $newNormalTexture = '$CONTENT_DATA/Objects/Textures/scoob_normal.jpg'
    $shapeSetFiles = @(
        [pscustomobject]@{ Path = (Join-Path $ProjectRoot 'Objects\Database\ShapeSets\parts.json'); Expected = 2 },
        [pscustomobject]@{ Path = (Join-Path $ProjectRoot 'Objects\Database\ShapeSets\WingVariants.json'); Expected = 30 },
        [pscustomobject]@{ Path = (Join-Path $ProjectRoot 'Objects\Database\ShapeSets\NewWingVariants.json'); Expected = 10 }
    )
    foreach ($shapeSetFile in $shapeSetFiles) {
        $json = [System.IO.File]::ReadAllText($shapeSetFile.Path)
        $oldAsgCount = ([regex]::Matches($json, [regex]::Escape($oldAsgTexture))).Count
        $oldNormalCount = ([regex]::Matches($json, [regex]::Escape($oldNormalTexture))).Count
        $newAsgCount = ([regex]::Matches($json, [regex]::Escape($newAsgTexture))).Count
        $newNormalCount = ([regex]::Matches($json, [regex]::Escape($newNormalTexture))).Count
        $hasOldMaps = $oldAsgCount -eq $shapeSetFile.Expected -and $oldNormalCount -eq $shapeSetFile.Expected
        $hasNewMaps = $newAsgCount -eq $shapeSetFile.Expected -and $newNormalCount -eq $shapeSetFile.Expected
        if (-not $hasOldMaps -and -not $hasNewMaps) {
            throw "Unexpected wing lighting texture counts in $($shapeSetFile.Path)."
        }
        if ($hasOldMaps) {
            $json = $json.Replace($oldAsgTexture, $newAsgTexture).Replace($oldNormalTexture, $newNormalTexture)
            [System.IO.File]::WriteAllText($shapeSetFile.Path, $json, $encoding)
        }
    }
}

$pendingWrites | Select-Object Path, VertexCount, FaceCount, TextureCoordinateCount
