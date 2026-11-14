param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,
    [switch]$Write
)

$ErrorActionPreference = 'Stop'
$encoding = [System.Text.UTF8Encoding]::new($false)
$shapeSetDirectory = Join-Path $ProjectRoot 'Objects\Database\ShapeSets'

$shapeSetOrder = @(
    '$CONTENT_DATA/Objects/Database/ShapeSets/parts.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/PlanePropellers.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/PlaneDisappearPipes.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/PlaneRadarScreen.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/PlayerPresence.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/AfterbodyThrusters.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/NewWingVariants.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/WingVariants.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/AircraftHalfParts.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/blocks.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/wedges.json',
    '$CONTENT_DATA/Objects/Database/ShapeSets/NewLegendGeometry.json'
)

$functionalPriority = @{
    'obj_interactive_fuel_tank' = 0
    'obj_interactive_random_output_gate' = 1
    'obj_interactive_connected_weapon_selector' = 2
    'obj_interactive_plane_controller' = 3
    'obj_interactive_horn_foam_extinguisher' = 4
    'obj_interactive_fire_pulse' = 5
    'obj_interactive_napalm_bomb' = 6
    'obj_centered_wing_1x1' = 7
    'obj_sided_wing_1x1' = 8
}

$partsPath = Join-Path $shapeSetDirectory 'parts.json'
$parts = Get-Content -Raw -LiteralPath $partsPath | ConvertFrom-Json
if (@($parts.partList).Count -ne 7) { throw 'Expected seven non-wing entries in parts.json.' }
$parts.partList = @($parts.partList | Sort-Object @{e={ if ($functionalPriority.ContainsKey($_.name)) { $functionalPriority[$_.name] } else { 999 } }}, name)

$wingVariantsPath = Join-Path $shapeSetDirectory 'WingVariants.json'
$wingVariants = Get-Content -Raw -LiteralPath $wingVariantsPath | ConvertFrom-Json
if (@($wingVariants.partList).Count -ne 30) { throw 'Expected 30 wing wedge variants.' }
$wingVariants.partList = @($wingVariants.partList | Sort-Object `
    @{e={ if ($_.name -match '1x([0-9]+)$') { [int]$matches[1] } else { 999 } }},
    @{e={ if ($_.name -match 'centered') { 0 } elseif ($_.name -match '_l_') { 1 } else { 2 } }})

$newWingVariantsPath = Join-Path $shapeSetDirectory 'NewWingVariants.json'
$newWingVariants = Get-Content -Raw -LiteralPath $newWingVariantsPath | ConvertFrom-Json
if (@($newWingVariants.partList).Count -ne 12) { throw 'Expected 12 new wing variants.' }
$newWingPriority = @{
    'obj_centered_wing_1x1' = 0
    'obj_sided_wing_1x1' = 1
    'obj_centered_wing_edge_45_1x1' = 2
    'obj_sided_wing_edge_45_1x1' = 3
    'obj_centered_wing_edge_straight_1x1' = 4
    'obj_sided_wing_edge_straight_1x1' = 5
    'obj_centered_wing_2x2' = 6
    'obj_sided_wing_2x2' = 7
    'obj_centered_wing_3x3' = 8
    'obj_sided_wing_3x3' = 9
    'obj_centered_wing_4x4' = 10
    'obj_sided_wing_4x4' = 11
}
$newWingVariants.partList = @($newWingVariants.partList | Sort-Object @{e={$newWingPriority[$_.name]}})

$geometryPath = Join-Path $shapeSetDirectory 'NewLegendGeometry.json'
$geometry = Get-Content -Raw -LiteralPath $geometryPath | ConvertFrom-Json
$inventoryPath = Join-Path $ProjectRoot 'new_legend_geometry_inventory.csv'
$inventory = Import-Csv -LiteralPath $inventoryPath
if (@($geometry.partList).Count -ne 273 -or @($inventory).Count -ne 273) { throw 'Expected 273 geometry entries.' }
$categoryOrder = @(
    'Tangential Cubes',
    'Trangular Pyramids',
    'Rectangular Pyramids',
    'Bevels With Spacing',
    'Triangle Slices',
    'Corner Slices',
    'Square Slices',
    'Half Slices',
    'Arc Slices',
    'Arcs',
    '1/8 Balls',
    '1/4 Cones',
    'Bevel Slices',
    'Trangular Slices',
    'Tangential Cube Slices',
    'Half Blocks',
    'Circular Tubes',
    'Cones'
)
$categoryPriority = @{}
for ($index = 0; $index -lt $categoryOrder.Count; $index++) { $categoryPriority[$categoryOrder[$index]] = $index }
$inventoryByUuid = @{}
foreach ($row in $inventory) { $inventoryByUuid[$row.Uuid] = $row }
$geometry.partList = @($geometry.partList | Sort-Object `
    @{e={$categoryPriority[$inventoryByUuid[[string]$_.uuid].Category]}},
    @{e={$inventoryByUuid[[string]$_.uuid].DisplayTitle}},
    @{e={$inventoryByUuid[[string]$_.uuid].SourceMeshRelative}})

$shapeDatabasePath = Join-Path $ProjectRoot 'Objects\Database\shapesets.shapedb'
$shapeDatabase = Get-Content -Raw -LiteralPath $shapeDatabasePath | ConvertFrom-Json
$shapeDatabase.shapeSetList = $shapeSetOrder

if ($Write) {
    [System.IO.File]::WriteAllText($partsPath, ($parts | ConvertTo-Json -Depth 40), $encoding)
    [System.IO.File]::WriteAllText($newWingVariantsPath, ($newWingVariants | ConvertTo-Json -Depth 40), $encoding)
    [System.IO.File]::WriteAllText($wingVariantsPath, ($wingVariants | ConvertTo-Json -Depth 40), $encoding)
    [System.IO.File]::WriteAllText($geometryPath, ($geometry | ConvertTo-Json -Depth 40), $encoding)
    [System.IO.File]::WriteAllText($shapeDatabasePath, ($shapeDatabase | ConvertTo-Json -Depth 10), $encoding)
}

[pscustomobject]@{
    FirstPart = $parts.partList[0].name
    FunctionalParts = @($parts.partList).Count
    NewWingVariants = @($newWingVariants.partList).Count
    WingWedgeVariants = @($wingVariants.partList).Count
    GeometryVariants = @($geometry.partList).Count
    ShapeSets = @($shapeDatabase.shapeSetList).Count
}
