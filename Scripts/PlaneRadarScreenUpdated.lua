dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneRadarScreen = class()

PlaneRadarScreen.maxParentCount = -1
PlaneRadarScreen.maxChildCount = -1
PlaneRadarScreen.connectionInput = sm.interactable.connectionType.logic
PlaneRadarScreen.connectionOutput = sm.interactable.connectionType.logic
PlaneRadarScreen.colorNormal = sm.color.new(0x8bd7e6ff)
PlaneRadarScreen.colorHighlight = sm.color.new(0xd7fbffff)

local MARKER_UUID = sm.uuid.new("fe538133-1a7c-4698-8410-377fdd68824a")
local SELECTED_MARKER_UUID = sm.uuid.new("6bd47f9b-4b9f-4fe0-8f6a-8acb1a54c9a2")
local PRESENCE_REGISTRY_NAME = "PlaneConstructPresenceTargets"
local PLANE_CONTROLLER_REGISTRY_NAME = "PlaneConstructPlaneControllers"
local ANTIRADAR_REGISTRY_NAME = "PlaneConstructAntiRadarZones"
local TARGET_FILTER_PLAYERS = "players"
local TARGET_FILTER_PLANE_CONTROLLERS = "planeControllers"
local TARGET_FILTER_PLAYER_PRESENCE = "playerPresence"
local TARGET_FILTER_CONSTRUCTIONS = "constructions"
local TARGET_FILTER_IR = "ir"
local DEFAULT_TARGET_FILTERS = {
    [TARGET_FILTER_PLAYERS] = false,
    [TARGET_FILTER_PLANE_CONTROLLERS] = true,
    [TARGET_FILTER_PLAYER_PRESENCE] = false,
    [TARGET_FILTER_CONSTRUCTIONS] = false,
    [TARGET_FILTER_IR] = false
}
local TARGET_FILTER_KEYS = {
    TARGET_FILTER_PLAYERS,
    TARGET_FILTER_PLANE_CONTROLLERS,
    TARGET_FILTER_PLAYER_PRESENCE,
    TARGET_FILTER_CONSTRUCTIONS,
    TARGET_FILTER_IR
}
local TARGET_FILTER_LABELS = {
    [TARGET_FILTER_PLAYERS] = PC_L.get("filter_players"),
    [TARGET_FILTER_PLANE_CONTROLLERS] = PC_L.get("filter_plane_controller"),
    [TARGET_FILTER_PLAYER_PRESENCE] = PC_L.get("filter_player_presence"),
    [TARGET_FILTER_CONSTRUCTIONS] = PC_L.get("filter_constructions"),
    [TARGET_FILTER_IR] = PC_L.get("filter_ir")
}
local IR_TARGET_ID_OFFSET = 3000000000
local CONSTRUCTION_TARGET_ID_OFFSET = 2000000000

local DEFAULT_FOV_DEGREES = 60
local MIN_FOV_DEGREES = 10
local MAX_FOV_DEGREES = 180
local DEFAULT_MIN_DISTANCE_BLOCKS = 0
local MIN_MIN_DISTANCE_BLOCKS = 0
local MAX_MIN_DISTANCE_BLOCKS = 100
local DEFAULT_MAX_DISTANCE_BLOCKS = 1000
local MIN_MAX_DISTANCE_BLOCKS = 100
local MAX_MAX_DISTANCE_BLOCKS = 5000
local BLOCKS_PER_WORLD_UNIT = 4.0
local SPEED_METERS_PER_SECOND_TO_KMH = 3.6
local DEFAULT_TARGET_DATA_ENABLED = true
local TARGET_LABEL_DEPTH_OFFSET = 0.118
local TARGET_LABEL_PLAYER_DISTANCE_BLOCKS = 15.0
local TARGET_LABEL_HORIZONTAL_OFFSET = 0.0
local TARGET_LABEL_VERTICAL_OFFSET = -0.055
local TARGET_LABEL_MAX_RENDER_DISTANCE = 100
local TARGET_LABEL_WIDTH = 128
local TARGET_LABEL_HEIGHT = 72
local TARGET_LABEL_LAYOUT = PC_L.layout("PlaneRadarTargetData.layout")
local DEFAULT_CROSSHAIR_ENABLED = false
local MIN_CROSSHAIR_OFFSET = -1.0
local MAX_CROSSHAIR_OFFSET = 1.0
local CROSSHAIR_OFFSET_STEPS = 201
local DEFAULT_CROSSHAIR_VERTICAL_OFFSET = 0.0
local DEFAULT_CROSSHAIR_HORIZONTAL_OFFSET = 0.0
local DEFAULT_CROSSHAIR_COLOR = "black"
local DEFAULT_CROSSHAIR_SHAPE = "ordinary"
local MIN_CROSSHAIR_SCALE_PERCENT = 25
local MAX_CROSSHAIR_SCALE_PERCENT = 200
local CROSSHAIR_SCALE_STEPS = MAX_CROSSHAIR_SCALE_PERCENT - MIN_CROSSHAIR_SCALE_PERCENT + 1
local DEFAULT_CROSSHAIR_SIZE_PERCENT = 100
local DEFAULT_CROSSHAIR_DOT_SIZE_PERCENT = 100
local DEFAULT_CROSSHAIR_GAP_SIZE_PERCENT = 100
local DEFAULT_CROSSHAIR_ELEMENT_WIDTH_PERCENT = 100
local DEFAULT_CROSSHAIR_ELEMENT_LENGTH_PERCENT = 100
local CROSSHAIR_RENDER_COLORS = {
    red = sm.color.new(0xff0000ff),
    black = sm.color.new(0x000000ff),
    blue = sm.color.new(0x0000ffff),
    white = sm.color.new(0xffffffff)
}
local CROSSHAIR_COLOR_OPTIONS = { "Red", "Black", "Blue", "White" }
local CROSSHAIR_COLOR_IDS = { red = true, black = true, blue = true, white = true }
local CROSSHAIR_COLOR_NAMES = {
    Red = "red",
    Black = "black",
    Blue = "blue",
    White = "white"
}
local CROSSHAIR_COLOR_LABELS = {
    red = "Red",
    black = "Black",
    blue = "Blue",
    white = "White"
}
local CROSSHAIR_SHAPE_OPTIONS = {
    "Ordinary",
    "Cross with a gap",
    "Cross with a dot",
    "Circle",
    "Circle with dot"
}
local CROSSHAIR_SHAPE_IDS = {
    ordinary = true,
    cross_gap = true,
    cross_dot = true,
    circle = true,
    circle_dot = true
}
local CROSSHAIR_SHAPE_NAMES = {
    ["Ordinary"] = "ordinary",
    ["Cross with a gap"] = "cross_gap",
    ["Cross with a dot"] = "cross_dot",
    ["Circle"] = "circle",
    ["Circle with dot"] = "circle_dot"
}
local CROSSHAIR_SHAPE_LABELS = {
    ordinary = "Ordinary",
    cross_gap = "Cross with a gap",
    cross_dot = "Cross with a dot",
    circle = "Circle",
    circle_dot = "Circle with dot"
}
local CROSSHAIR_SHAPE_UUIDS = {
    ordinary = {
        red = sm.uuid.new("a11b0b89-9ac8-4d07-b4dd-d9b5b5c5fe9d"),
        black = sm.uuid.new("c0bbc7d6-5393-4714-a863-d2ad0a6525ca"),
        blue = sm.uuid.new("106d6acc-9e00-46dc-b57e-604459f3b6e0"),
        white = sm.uuid.new("9e2cbc73-8bf0-4573-858b-beffad24751b")
    },
    cross_gap = {
        red = sm.uuid.new("3f6eb97c-195d-4d76-a5ca-5c624e207e7f"),
        black = sm.uuid.new("62860bd0-f4d3-4f91-8bf1-efda0aaff4fd"),
        blue = sm.uuid.new("9e3937f2-536e-4783-8960-06cfa4cc4ba1"),
        white = sm.uuid.new("177785fe-4e16-4f10-96fa-82d3e8bd46c2")
    },
    dot = {
        red = sm.uuid.new("9952a908-a837-4768-8b0d-9c7c22ff8a5a"),
        black = sm.uuid.new("2440df24-fc6c-4d22-bd37-8b1c25ad7452"),
        blue = sm.uuid.new("7401f60b-9bd4-438f-962b-e3d35f3bea40"),
        white = sm.uuid.new("92253ac4-d732-4b97-aadc-5a368a709523")
    },
    circle = {
        red = sm.uuid.new("d3194a44-74bf-46f3-9103-dba720a1c339"),
        black = sm.uuid.new("4b36db02-2ed3-4c8f-a0dc-f99bc0911b6e"),
        blue = sm.uuid.new("686cebb3-0d39-4f80-90a6-0e8282d0e8af"),
        white = sm.uuid.new("e6afdb8c-cdc3-406a-a43d-6c6dfa08b30a")
    }
}
local CROSSHAIR_ARM_UUIDS = {
    horizontal = {
        red = sm.uuid.new("399212ce-1f40-4699-9698-77e91382598c"),
        black = sm.uuid.new("94573184-7b1d-42fa-bd7f-d87c195fa2e4"),
        blue = sm.uuid.new("8b6b456e-860a-4316-91c9-b9b92ae6333d"),
        white = sm.uuid.new("7ec15779-1cdb-404a-b177-d4a2ee908671")
    },
    vertical = {
        red = sm.uuid.new("d0689523-20f2-4a62-a8da-f0b0e41635ba"),
        black = sm.uuid.new("45e60fc3-d410-48a1-b2af-4d8b3e0dc193"),
        blue = sm.uuid.new("e9a3359a-e812-4c9c-a805-d749d92c2594"),
        white = sm.uuid.new("eeb6e499-b1cf-4c0f-968f-7dad07ef5b06")
    }
}
local CROSSHAIR_RING_WIDTH_STEPS = { 25, 50, 100, 150, 200 }
local CROSSHAIR_RING_UUIDS = {
    red = {
        sm.uuid.new("ead3a9b2-ff8f-4b3c-840c-a16bd3b0673f"),
        sm.uuid.new("8330f202-7805-4924-9008-63b7562dd590"),
        sm.uuid.new("146f7533-c3cc-45a9-b216-d3238ffafc43"),
        sm.uuid.new("5ca11aa2-c39f-4767-95eb-9b0e2b263e4c"),
        sm.uuid.new("84673146-2165-429a-abc9-64142b38c128")
    },
    black = {
        sm.uuid.new("621323b2-be0d-4dfb-a689-217349ef5460"),
        sm.uuid.new("7baf7ded-df7f-492a-8f1d-a8ef3e960db6"),
        sm.uuid.new("06559dc8-ff5f-4191-9ae5-f90b5b527ada"),
        sm.uuid.new("4a789df5-2984-4a34-94cf-702eb4996dfc"),
        sm.uuid.new("e4bd93ae-b7c9-4e56-aa0d-f43bd70751ff")
    },
    blue = {
        sm.uuid.new("4d2d4c1d-e2e9-4670-8ffe-1fb855c6637e"),
        sm.uuid.new("bcbbad0f-2362-419a-96e3-e2812bd1ca80"),
        sm.uuid.new("45932a5a-2063-4c22-acdf-f1f5002f57eb"),
        sm.uuid.new("4cd03712-095e-4fc8-97f3-9d781581916f"),
        sm.uuid.new("1c1dfaee-eff5-4da6-8a66-f7afa12a5e2c")
    },
    white = {
        sm.uuid.new("81f3fe8a-0246-41fe-9ca0-365ad3ed55b8"),
        sm.uuid.new("fa795c39-7d79-42f2-8886-c7d4ad7ca5cd"),
        sm.uuid.new("bbeb950d-2fee-4432-997a-8a7814b6ffab"),
        sm.uuid.new("038f764b-9554-4c59-aa7a-4f3fb4007dd3"),
        sm.uuid.new("eab77b10-ad95-4306-a843-de14d314c2f2")
    }
}

-- PlaneRadarGlass.mesh occupies +/-0.5 on its local Y/Z axes and +/-0.1
-- on local X. Keep the dots inside that actual pane instead of the larger
-- one-block hull used for collision.
local PANE_HALF_WIDTH = 0.5
local PANE_HALF_HEIGHT = 0.5
-- Leave room for the complete billboard, not only its center point.
local PANE_MARGIN = 0.12
-- The original radar now scans and renders from the opposite face of the block.
-- Place the crosshair on the block's center plane instead of on the pane edge.
local PANE_DEPTH_OFFSET = 0.0
-- Target dots are centered in the centered glass panel.
local MARKER_DEPTH_OFFSET = 0.0
-- Keep the crosshair's center dot just inside the rear face so it cannot
-- overlap a target dot rendered on that face.
local CROSSHAIR_DOT_DEPTH_OFFSET = 0.09
local SCAN_DIRECTION_SIGN = 1.0
local MARKER_SMOOTHING_RATE = 12.0
-- These are the four yellow shades used by the vanilla paint tool.
local YELLOW_LOGIC_COLORS = {
    f5f071ff = true,
    e2db13ff = true,
    ["817c00ff"] = true,
    ["323000ff"] = true
}

local function clampInteger(value, minimum, maximum)
    local numericValue = tonumber(value)
    if numericValue == nil then
        return minimum
    end
    return math.max(minimum, math.min(maximum, math.floor(numericValue + 0.5)))
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function isCrosshairColor(value)
    return type(value) == "string" and CROSSHAIR_COLOR_IDS[value] == true
end

local function isCrosshairShape(value)
    return type(value) == "string" and CROSSHAIR_SHAPE_IDS[value] == true
end

local function resolveCrosshairColor(value)
    if type(value) == "number" then
        local optionName = CROSSHAIR_COLOR_OPTIONS[value]
            or CROSSHAIR_COLOR_OPTIONS[value + 1]
        return CROSSHAIR_COLOR_NAMES[optionName]
    end
    if type(value) ~= "string" then return nil end

    local normalized = string.lower(value)
    if isCrosshairColor(normalized) then return normalized end
    for optionName, color in pairs(CROSSHAIR_COLOR_NAMES) do
        if string.lower(optionName) == normalized then return color end
    end
    return nil
end

local function resolveCrosshairShape(value)
    if type(value) == "number" then
        local optionName = CROSSHAIR_SHAPE_OPTIONS[value]
            or CROSSHAIR_SHAPE_OPTIONS[value + 1]
        return CROSSHAIR_SHAPE_NAMES[optionName]
    end
    if type(value) ~= "string" then return nil end

    local normalized = string.lower(value)
    if isCrosshairShape(normalized) then return normalized end
    for optionName, shape in pairs(CROSSHAIR_SHAPE_NAMES) do
        if string.lower(optionName) == normalized then return shape end
    end
    return nil
end

-- Convert a normalized world direction into the block's local right/at/up
-- axes before mapping it to the display.
local function toLocal(shape, globalVector)
    if globalVector:length() < 0.000001 then
        return sm.vec3.zero()
    end

    return sm.vec3.new(
        shape:getRight():dot(globalVector),
        shape:getAt():dot(globalVector),
        shape:getUp():dot(globalVector)
    )
end

local function getRegistryKey(self)
    return "PlaneRadarScreen:" .. tostring(self.interactable:getId())
end

local function isTargetInSensorCone(self, targetPosition, fovDegrees, minimumDistanceBlocks, maximumDistanceBlocks)
    local toTarget = targetPosition - self.shape.worldPosition
    local distance = toTarget:length()
    local minimumDistance = minimumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    local maximumDistance = maximumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    if distance <= 0.001 or distance <= minimumDistance or distance > maximumDistance then
        return false
    end

    -- The glass normal is local X (Shape:right), so the FOV is the exact
    -- angle away from that forward axis, not an independent screen clamp.
    local localDirection = toLocal(self.shape, toTarget / distance)
    local scanForward = localDirection.x * SCAN_DIRECTION_SIGN
    local radialAngle = math.atan2(
        math.sqrt(
            localDirection.y * localDirection.y
                + localDirection.z * localDirection.z
        ),
        scanForward
    )
    return radialAngle <= math.rad(fovDegrees) * 0.5
end

local function isTargetInSensorRange(self, targetPosition, minimumDistanceBlocks, maximumDistanceBlocks)
    local offset = targetPosition - self.shape.worldPosition
    local distance = offset:length()
    local minimumDistance = minimumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    local maximumDistance = maximumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    return distance > 0.001 and distance > minimumDistance and distance <= maximumDistance
end

local function isTerrainBlocked(self, targetPosition)
    local origin = self.shape.worldPosition
    local offset = targetPosition - origin
    if offset:length() <= 0.001 then return false end

    -- Radar visibility deliberately checks only terrain and terrain assets.
    -- Built blocks and other creation details are not part of this mask.
    local hit, result = sm.physics.raycast(
        origin,
        targetPosition,
        self.shape:getBody(),
        sm.physics.filter.allTerrain
    )
    return hit == true and result ~= nil
end

local function areTargetIdSetsEqual(left, right)
    for targetId in pairs(left or {}) do
        if right[targetId] ~= true then return false end
    end
    for targetId in pairs(right or {}) do
        if (left or {})[targetId] ~= true then return false end
    end
    return true
end

local function isLogicColorActive(self, colorSet)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            local parentShape = parent:getShape()
            if parentShape ~= nil then
                local parentColor = string.lower(tostring(parentShape:getColor()))
                if colorSet[parentColor] then return true end
            end
        end
    end

    return false
end

local function isBasicLogicInputActive(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            local parentShape = parent:getShape()
            local parentColor = parentShape ~= nil and string.lower(tostring(parentShape:getColor())) or ""
            if not YELLOW_LOGIC_COLORS[parentColor] then
                return true
            end
        end
    end

    return false
end

local function getPresenceRegistry()
    return _G[PRESENCE_REGISTRY_NAME] or {}
end

local function getPlaneControllerRegistry()
    return _G[PLANE_CONTROLLER_REGISTRY_NAME] or {}
end

local function getAntiRadarRegistry()
    return _G[ANTIRADAR_REGISTRY_NAME] or {}
end

local CHAFF_DISTRACTION_CHANCE = 0.5

local IR_SOURCE_SHAPE_UUIDS = {
    -- Vanilla engines and thrusters, including Creative and Survival variants.
    ["d5e36413-b3c1-4636-8447-3410c352ec7b"] = true,
    ["6546c293-a5aa-4442-80d5-a2819f077746"] = true,
    ["5e96037a-a338-490a-a76f-6b4d820f8e46"] = true,
    ["1bfccc0a-828f-475c-882c-87d5a96054c9"] = true,
    ["33d01ddd-f32b-4a9a-87d6-efb6710b389c"] = true,
    ["470b9a92-ed94-4ef2-b1ea-b45f47ef0982"] = true,
    ["bfcaac1a-5a7f-4fba-9980-1159617a7212"] = true,
    ["3091926a-9340-46d9-83d6-4fd7c68ad950"] = true,
    ["5e5d231e-405e-4f45-9bd0-b3557dbb42eb"] = true,
    ["0c9cc5bb-af2f-4023-b8d8-cd7d52a60efe"] = true,
    ["56cea967-a685-494d-85ef-3aa121a0c193"] = true,
    ["5e57e0f7-e87c-4269-b274-146fe40e1b44"] = true,
    ["22f3e797-82f5-4819-a085-c3cc28ec9025"] = true,
    ["df8528ed-15ad-4a39-a33a-698880684001"] = true,
    ["9fc793b2-250b-40ab-bcb3-97cf97c7b481"] = true,
    ["4c1cc8de-7af1-4f8e-a5c4-c583460af9e5"] = true,
    ["e6db321c-6f98-47f6-9f7f-4e6794a62cb8"] = true,
    ["a736ffdf-22c1-40f2-8e40-988cab7c0559"] = true,
    ["c96ab903-f238-4bae-a614-28a758716d00"] = true,
    ["48563128-f84a-4342-8d9f-190c633a6ea9"] = true,
    ["f56d7788-122e-421a-b63b-2938466125e9"] = true,
    ["4001aaad-5494-11e6-beb8-9e71128cae77"] = true,
    ["3048aaab-5494-11e6-beb8-9e71128cae77"] = true,

    -- Plane Construct Doppler engine.
    ["b7c8d9e0-1234-4abc-8def-0123456789ab"] = true,

    -- Plane Construct afterbody thrusters.
    ["c81f2a4e-12d9-4ec6-8b33-1e61f230a401"] = true,
    ["c81f2a4e-12d9-4ec6-8b33-1e61f230a402"] = true,

    -- Vanilla and Survival light sources. They are filtered by isActive below.
    ["ed27f5e2-cac5-4a32-a5d9-49f116acc6af"] = true,
    ["695d66c8-b937-472d-8bc2-f3d72dd92879"] = true,
    ["da6e54df-a223-4a0e-b42f-ddeddd33f5b3"] = true,
    ["6620ceb4-3c35-4a61-9d98-f923d2277395"] = true,
    ["13ce3374-841a-4ad2-a6c3-ad0dabc1963d"] = true,
    ["e91b0bf2-dafa-439e-a503-286e91461bb0"] = true,
    ["1e2485d7-f600-406e-b348-9f0b7c1f5077"] = true,
    ["7b2c96af-a4a1-420e-9370-ea5b58f23a7e"] = true,
    ["5e3dff9b-2450-44ae-ad46-d2f6b5148cbf"] = true,
    ["16ba2d22-7b96-4c5e-9eb7-f6422ed80ad4"] = true,
    ["85339a1d-e67f-4c63-94fd-4a1cf8c25810"] = true,
    ["2c90e412-9476-40d9-a440-228c888186bd"] = true,
    ["47062936-5d28-43ec-81b5-8fdb619e97e4"] = true,
    ["e84680b8-83ab-4cc3-af10-df857a300e9e"] = true,
    ["c4a0a65b-3b24-4beb-bd7a-d687f4210169"] = true
}

local function copyTargetFilters(filters)
    local selectedKey = nil
    for _, key in ipairs(TARGET_FILTER_KEYS) do
        local enabled = nil
        if type(filters) == "table" and filters[key] ~= nil then
            enabled = filters[key] == true
        else
            enabled = DEFAULT_TARGET_FILTERS[key] == true
        end
        if enabled and selectedKey == nil then
            selectedKey = key
        end
    end

    if selectedKey == nil then
        selectedKey = TARGET_FILTER_PLANE_CONTROLLERS
    end

    local result = {}
    for _, key in ipairs(TARGET_FILTER_KEYS) do
        result[key] = key == selectedKey
    end
    return result
end

local function getActiveTargetFilter(filters)
    if type(filters) == "table" then
        for _, key in ipairs(TARGET_FILTER_KEYS) do
            if filters[key] == true then
                return key
            end
        end
    end
    return TARGET_FILTER_PLANE_CONTROLLERS
end

local function isTargetFilterEnabled(self, key)
    if self.sv == nil then return false end
    if self.sv.targetFilter ~= nil then
        return self.sv.targetFilter == key
    end
    return self.sv.targetFilters ~= nil and self.sv.targetFilters[key] == true
end

local function isPlayerPresenceTarget(target)
    return type(target) == "table"
        and target.active == true
        and target.position ~= nil
        and target.countermeasure ~= true
        and target.kind == nil
end

local function isInfraredTargetShape(shape)
    if shape == nil or not sm.exists(shape) then return false end

    local shapeUuid = string.lower(tostring(sm.shape.getShapeUuid(shape)))
    local title = ""
    local titleResolved, resolvedTitle = pcall(
        sm.shape.getShapeTitle,
        sm.shape.getShapeUuid(shape)
    )
    if titleResolved then
        title = string.lower(tostring(resolvedTitle or ""))
    end

    local isNamedSource = string.find(title, "thruster", 1, true) ~= nil
        or string.find(title, "engine", 1, true) ~= nil
        or string.find(title, "booster", 1, true) ~= nil
        or string.find(title, "light", 1, true) ~= nil
        or string.find(title, "lamp", 1, true) ~= nil
        or string.find(title, "headlight", 1, true) ~= nil
    if not IR_SOURCE_SHAPE_UUIDS[shapeUuid] and not isNamedSource then
        return false
    end

    local interactable = shape.interactable
    if interactable == nil then
        local interactableResolved, resolvedInteractable = pcall(function()
            return shape:getInteractable()
        end)
        if interactableResolved then
            interactable = resolvedInteractable
        end
    end
    if interactable == nil then return false end

    -- Vanilla engines publish their real running state here. Their
    -- interactable:isActive() flag describes the input signal instead and
    -- can remain false while the engine is actually consuming fuel.
    local publicDataResolved, publicData = pcall(function()
        return interactable:getPublicData()
    end)
    if publicDataResolved and type(publicData) == "table"
        and publicData.isActive ~= nil then
        return publicData.isActive == true
    end

    local activeResolved, active = pcall(function()
        return interactable:isActive()
    end)
    return activeResolved and active == true
end

local function getShapeNumericId(shape)
    local ok, id = pcall(function() return shape.id end)
    return ok and tonumber(id) or nil
end

local function getConstructionIdentity(body)
    if body == nil then return nil, nil end

    -- A creation is the complete connected construction. Unlike Body.id, its
    -- id also groups bodies separated by bearings, suspensions and wheels.
    local creationResolved, creationId = pcall(function()
        return body:getCreationId()
    end)
    creationId = creationResolved and tonumber(creationId) or nil
    if creationId ~= nil then
        return "creation:" .. tostring(creationId), math.abs(math.floor(creationId))
    end

    local bodyResolved, bodyId = pcall(function()
        return body:getId()
    end)
    bodyId = bodyResolved and tonumber(bodyId) or nil
    if bodyId ~= nil then
        return "body:" .. tostring(bodyId), math.abs(math.floor(bodyId))
    end

    return tostring(body), nil
end

local function getConstructionBodies(body)
    if body == nil then return nil end
    local resolved, bodies = pcall(function()
        return body:getCreationBodies()
    end)
    if resolved and type(bodies) == "table" and #bodies > 0 then
        return bodies
    end
    return { body }
end

local function getConstructionPositionAndVelocity(body, fallbackShape)
    local fallbackPosition = fallbackShape ~= nil and fallbackShape.worldPosition or nil
    local fallbackVelocity = sm.vec3.zero()
    if fallbackShape ~= nil then
        local velocityResolved, velocity = pcall(function()
            return fallbackShape:getVelocity()
        end)
        if velocityResolved and velocity ~= nil then
            fallbackVelocity = velocity
        end
    end

    local bodies = getConstructionBodies(body)
    if bodies == nil then
        return fallbackPosition, fallbackVelocity
    end

    local positionSum = sm.vec3.zero()
    local velocitySum = sm.vec3.zero()
    local bodyCount = 0
    for _, constructionBody in ipairs(bodies) do
        local positionResolved, position = pcall(function() return constructionBody.worldPosition end)
        local velocityResolved, velocity = pcall(function() return constructionBody.velocity end)
        if positionResolved and position ~= nil then
            positionSum = positionSum + position
            if velocityResolved and velocity ~= nil then
                velocitySum = velocitySum + velocity
            end
            bodyCount = bodyCount + 1
        end
    end

    if bodyCount > 0 then
        return positionSum / bodyCount, velocitySum / bodyCount
    end
    return fallbackPosition, fallbackVelocity
end

local function getPlayerTargetById(targetId)
    local numericTargetId = tonumber(targetId)
    if numericTargetId == nil or sm.player == nil or sm.player.getAllPlayers == nil then
        return nil
    end

    for _, player in ipairs(sm.player.getAllPlayers()) do
        if player:getId() == numericTargetId then
            local character = player:getCharacter()
            if character ~= nil and sm.exists(character) then
                return {
                    id = numericTargetId,
                    kind = "player",
                    name = "Player",
                    active = true,
                    position = character.worldPosition,
                    velocity = character.velocity or sm.vec3.zero(),
                    sourceShape = character
                }
            end
        end
    end
    return nil
end

local function isRadarTarget(target)
    return type(target) == "table"
        and target.active == true
        and target.position ~= nil
        and (target.kind == nil
            or target.kind == "player"
            or target.kind == "plane_controller"
            or target.kind == "construction"
            or target.kind == "ir"
            or target.kind == "chaff")
end

local function isTargetJammed(self, target)
    if type(target) ~= "table" or target.position == nil then return false end

    for _, jammer in pairs(getAntiRadarRegistry()) do
        if type(jammer) == "table"
            and jammer.enabled == true
            and jammer.position ~= nil
            and tonumber(jammer.radius) ~= nil then
            if (target.position - jammer.position):length() <= tonumber(jammer.radius) then
                return true
            end
        end
    end

    return false
end

local function isTargetAllowedForRadar(self, target)
    if not isRadarTarget(target) then return false end
    if target.kind == "chaff" then return true end
    if isTargetJammed(self, target) then return false end
    if target.kind == "plane_controller" then
        return isTargetFilterEnabled(self, TARGET_FILTER_PLANE_CONTROLLERS)
    elseif target.kind == "player" then
        return isTargetFilterEnabled(self, TARGET_FILTER_PLAYERS)
    elseif target.kind == "construction" then
        return isTargetFilterEnabled(self, TARGET_FILTER_CONSTRUCTIONS)
    elseif target.kind == "ir" then
        return isTargetFilterEnabled(self, TARGET_FILTER_IR)
    elseif target.kind == nil then
        return isTargetFilterEnabled(self, TARGET_FILTER_PLAYER_PRESENCE)
    end
    return false
end

local function isPlaneControllerTarget(target)
    return isRadarTarget(target) and target.kind == "plane_controller"
end

local function getPlaneControllerById(targetId)
    local registry = getPlaneControllerRegistry()
    return registry[targetId] or registry[tostring(targetId)]
end

local function getPresenceTargetById(targetId)
    local registry = getPresenceRegistry()
    return registry[targetId] or registry[tostring(targetId)]
end

local function isSameConstruction(self, target)
    if type(target) ~= "table" then return false end

    local targetBody = target.sourceBody
    if targetBody == nil and target.sourceShape ~= nil then
        local ok, resolvedBody = pcall(function() return target.sourceShape:getBody() end)
        if ok then targetBody = resolvedBody end
    end
    if targetBody == nil then return false end

    local ownBody = self.shape:getBody()
    local targetKey = getConstructionIdentity(targetBody)
    local ownKey = getConstructionIdentity(ownBody)
    return targetKey ~= nil and targetKey == ownKey
end

local function getTargetData(targetId, targetPosition, sourceShape, targetOverride)
    local target = targetOverride
        or getPlaneControllerById(targetId)
        or getPresenceTargetById(targetId)
        or getPlayerTargetById(targetId)
    local velocity = type(target) == "table" and target.velocity or sm.vec3.zero()
    return {
        kind = type(target) == "table" and target.kind or nil,
        speedKmh = velocity:length() * SPEED_METERS_PER_SECOND_TO_KMH,
        altitude = type(target) == "table" and target.position.z
            or (targetPosition ~= nil and targetPosition.z or 0),
        position = targetPosition
    }
end

local function formatTargetData(targetId, targetPosition, sourceShape, targetData)
    local data = targetData or getTargetData(targetId, targetPosition, sourceShape)
    return string.format(
        "%.0f km/h\n%.0f m",
        data.speedKmh,
        data.altitude
    )
end

local function localToWorldPosition(shape, localPosition)
    return shape.worldPosition
        + shape:getRight() * localPosition.x
        + shape:getAt() * localPosition.y
        + shape:getUp() * localPosition.z
end

local function isPlayerWithinTargetLabelRange(self)
    local player = sm.localPlayer.getPlayer()
    local character = player ~= nil and player:getCharacter() or nil
    if character == nil or not sm.exists(character) then return true end

    local distanceBlocks = (character.worldPosition - self.shape.worldPosition):length()
        * BLOCKS_PER_WORLD_UNIT
    return distanceBlocks <= TARGET_LABEL_PLAYER_DISTANCE_BLOCKS
end

local function isActiveChaffTarget(target)
    return type(target) == "table"
        and target.active == true
        and target.countermeasure == true
        and target.kind == "chaff"
        and target.spawnSequence ~= nil
end

function PlaneRadarScreen.server_onCreate(self)
    self:sv_initialize()
end

function PlaneRadarScreen.server_onRefresh(self)
    self:sv_initialize()
end

function PlaneRadarScreen.server_onDestroy(self)
    if self.interactable ~= nil then
        self.interactable:setActive(false)
    end
    _G[getRegistryKey(self)] = nil
end

function PlaneRadarScreen.sv_save(self)
    self.storage:save({
        fovDegrees = self.sv.fovDegrees,
        minimumDistanceBlocks = self.sv.minimumDistanceBlocks,
        maximumDistanceBlocks = self.sv.maximumDistanceBlocks,
        selectedPlayerId = self.sv.selectedPlayerId,
        targetDataEnabled = self.sv.targetDataEnabled,
        targetFilters = self.sv.targetFilters,
        targetFilter = self.sv.targetFilter or getActiveTargetFilter(self.sv.targetFilters),
        crosshairEnabled = self.sv.crosshairEnabled,
        crosshairVerticalOffset = self.sv.crosshairVerticalOffset,
        crosshairHorizontalOffset = self.sv.crosshairHorizontalOffset,
        crosshairColor = self.sv.crosshairColor,
        crosshairShape = self.sv.crosshairShape,
        crosshairSize = self.sv.crosshairSize,
        crosshairDotSize = self.sv.crosshairDotSize,
        crosshairGapSize = self.sv.crosshairGapSize,
        crosshairElementWidth = self.sv.crosshairElementWidth,
        crosshairElementLength = self.sv.crosshairElementLength
    })
end

function PlaneRadarScreen.sv_initialize(self)
    local stored = self.storage:load()
    local fovDegrees = DEFAULT_FOV_DEGREES
    local minimumDistanceBlocks = DEFAULT_MIN_DISTANCE_BLOCKS
    local maximumDistanceBlocks = DEFAULT_MAX_DISTANCE_BLOCKS
    local selectedPlayerId = nil
    local targetDataEnabled = DEFAULT_TARGET_DATA_ENABLED
    local targetFilters = copyTargetFilters(nil)
    local targetFilter = TARGET_FILTER_PLANE_CONTROLLERS
    local crosshairEnabled = DEFAULT_CROSSHAIR_ENABLED
    local crosshairVerticalOffset = DEFAULT_CROSSHAIR_VERTICAL_OFFSET
    local crosshairHorizontalOffset = DEFAULT_CROSSHAIR_HORIZONTAL_OFFSET
    local crosshairColor = DEFAULT_CROSSHAIR_COLOR
    local crosshairShape = DEFAULT_CROSSHAIR_SHAPE
    local crosshairSize = DEFAULT_CROSSHAIR_SIZE_PERCENT
    local crosshairDotSize = DEFAULT_CROSSHAIR_DOT_SIZE_PERCENT
    local crosshairGapSize = DEFAULT_CROSSHAIR_GAP_SIZE_PERCENT
    local crosshairElementWidth = DEFAULT_CROSSHAIR_ELEMENT_WIDTH_PERCENT
    local crosshairElementLength = DEFAULT_CROSSHAIR_ELEMENT_LENGTH_PERCENT

    if type(stored) == "table" then
        fovDegrees = clampInteger(stored.fovDegrees, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
        minimumDistanceBlocks = clampInteger(
            stored.minimumDistanceBlocks,
            MIN_MIN_DISTANCE_BLOCKS,
            MAX_MIN_DISTANCE_BLOCKS
        )
        maximumDistanceBlocks = clampInteger(
            stored.maximumDistanceBlocks or stored.distanceBlocks,
            MIN_MAX_DISTANCE_BLOCKS,
            MAX_MAX_DISTANCE_BLOCKS
        )
        selectedPlayerId = tonumber(stored.selectedPlayerId)
        targetDataEnabled = stored.targetDataEnabled ~= false
        if type(stored.targetFilter) == "string"
            and DEFAULT_TARGET_FILTERS[stored.targetFilter] ~= nil then
            targetFilter = stored.targetFilter
            targetFilters = copyTargetFilters({ [targetFilter] = true })
        else
            targetFilters = copyTargetFilters(stored.targetFilters)
            targetFilter = getActiveTargetFilter(targetFilters)
        end
        crosshairEnabled = stored.crosshairEnabled == true
        crosshairVerticalOffset = clamp(
            tonumber(stored.crosshairVerticalOffset) or DEFAULT_CROSSHAIR_VERTICAL_OFFSET,
            MIN_CROSSHAIR_OFFSET,
            MAX_CROSSHAIR_OFFSET
        )
        crosshairHorizontalOffset = clamp(
            tonumber(stored.crosshairHorizontalOffset) or DEFAULT_CROSSHAIR_HORIZONTAL_OFFSET,
            MIN_CROSSHAIR_OFFSET,
            MAX_CROSSHAIR_OFFSET
        )
        if stored.crosshairColor == "yellow" then
            crosshairColor = "white"
        elseif isCrosshairColor(stored.crosshairColor) then
            crosshairColor = stored.crosshairColor
        end
        if isCrosshairShape(stored.crosshairShape) then
            crosshairShape = stored.crosshairShape
        end
        crosshairSize = clampInteger(
            stored.crosshairSize or DEFAULT_CROSSHAIR_SIZE_PERCENT,
            MIN_CROSSHAIR_SCALE_PERCENT,
            MAX_CROSSHAIR_SCALE_PERCENT
        )
        crosshairDotSize = clampInteger(
            stored.crosshairDotSize or DEFAULT_CROSSHAIR_DOT_SIZE_PERCENT,
            MIN_CROSSHAIR_SCALE_PERCENT,
            MAX_CROSSHAIR_SCALE_PERCENT
        )
        crosshairGapSize = clampInteger(
            stored.crosshairGapSize or DEFAULT_CROSSHAIR_GAP_SIZE_PERCENT,
            MIN_CROSSHAIR_SCALE_PERCENT,
            MAX_CROSSHAIR_SCALE_PERCENT
        )
        crosshairElementWidth = clampInteger(
            stored.crosshairElementWidth or DEFAULT_CROSSHAIR_ELEMENT_WIDTH_PERCENT,
            MIN_CROSSHAIR_SCALE_PERCENT,
            MAX_CROSSHAIR_SCALE_PERCENT
        )
        crosshairElementLength = clampInteger(
            stored.crosshairElementLength or DEFAULT_CROSSHAIR_ELEMENT_LENGTH_PERCENT,
            MIN_CROSSHAIR_SCALE_PERCENT,
            MAX_CROSSHAIR_SCALE_PERCENT
        )
    end

    self.sv = {
        fovDegrees = fovDegrees,
        minimumDistanceBlocks = minimumDistanceBlocks,
        maximumDistanceBlocks = maximumDistanceBlocks,
        selectedPlayerId = selectedPlayerId,
        targetDataEnabled = targetDataEnabled,
        targetFilters = targetFilters,
        targetFilter = targetFilter,
        crosshairEnabled = crosshairEnabled,
        crosshairVerticalOffset = crosshairVerticalOffset,
        crosshairHorizontalOffset = crosshairHorizontalOffset,
        crosshairColor = crosshairColor,
        crosshairShape = crosshairShape,
        crosshairSize = crosshairSize,
        crosshairDotSize = crosshairDotSize,
        crosshairGapSize = crosshairGapSize,
        crosshairElementWidth = crosshairElementWidth,
        crosshairElementLength = crosshairElementLength,
        previousYellowActive = false,
        yellowCycleTimer = 0.0,
        outputActive = false,
        inRangeTargets = {},
        visibleTargetIds = {},
        chaffSeenSequences = {},
        extraTargets = {}
    }

    self.interactable:setActive(false)
    self:sv_save()
    self:sv_syncClientData()
    self:sv_publishRegistry()
end

function PlaneRadarScreen.sv_syncClientData(self)
    self.network:setClientData({
        fovDegrees = self.sv.fovDegrees,
        minimumDistanceBlocks = self.sv.minimumDistanceBlocks,
        maximumDistanceBlocks = self.sv.maximumDistanceBlocks,
        selectedPlayerId = self.sv.selectedPlayerId,
        targetDataEnabled = self.sv.targetDataEnabled,
        targetFilters = self.sv.targetFilters,
        targetFilter = self.sv.targetFilter,
        crosshairEnabled = self.sv.crosshairEnabled,
        crosshairVerticalOffset = self.sv.crosshairVerticalOffset,
        crosshairHorizontalOffset = self.sv.crosshairHorizontalOffset,
        crosshairColor = self.sv.crosshairColor,
        crosshairShape = self.sv.crosshairShape,
        crosshairSize = self.sv.crosshairSize,
        crosshairDotSize = self.sv.crosshairDotSize,
        crosshairGapSize = self.sv.crosshairGapSize,
        crosshairElementWidth = self.sv.crosshairElementWidth,
        crosshairElementLength = self.sv.crosshairElementLength,
        visibleTargetIds = self.sv.visibleTargetIds or {},
        visibleTargetData = self.sv.visibleTargetData or {}
    })
end

function PlaneRadarScreen.sv_setFovDegrees(self, requestedFov)
    local fovDegrees = clampInteger(requestedFov, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
    if fovDegrees == self.sv.fovDegrees then return end

    self.sv.fovDegrees = fovDegrees
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setMinimumDistanceBlocks(self, requestedDistance)
    local minimumDistanceBlocks = clampInteger(
        requestedDistance,
        MIN_MIN_DISTANCE_BLOCKS,
        MAX_MIN_DISTANCE_BLOCKS
    )
    if minimumDistanceBlocks == self.sv.minimumDistanceBlocks then return end

    self.sv.minimumDistanceBlocks = minimumDistanceBlocks
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setMaximumDistanceBlocks(self, requestedDistance)
    local maximumDistanceBlocks = clampInteger(
        requestedDistance,
        MIN_MAX_DISTANCE_BLOCKS,
        MAX_MAX_DISTANCE_BLOCKS
    )
    if maximumDistanceBlocks == self.sv.maximumDistanceBlocks then return end

    self.sv.maximumDistanceBlocks = maximumDistanceBlocks
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setTargetDataEnabled(self, requestedState)
    local targetDataEnabled = requestedState == true
    if targetDataEnabled == self.sv.targetDataEnabled then return end

    self.sv.targetDataEnabled = targetDataEnabled
    self:sv_save()
    self:sv_syncClientData()
    self:sv_publishRegistry()
end

function PlaneRadarScreen.sv_applyTargetFilter(self, filterKey)
    if type(filterKey) ~= "string" or DEFAULT_TARGET_FILTERS[filterKey] == nil then return end

    local changed = self.sv.targetFilter ~= filterKey
    self.sv.targetFilter = filterKey
    self.sv.targetFilters = {}
    for _, key in ipairs(TARGET_FILTER_KEYS) do
        self.sv.targetFilters[key] = key == filterKey
    end
    if not changed then return end

    self.sv.selectedPlayerId = nil
    self:sv_save()
    self:sv_syncClientData()
    self:sv_publishRegistry()
end

function PlaneRadarScreen.sv_setTargetFilter(self, filterKey)
    self:sv_applyTargetFilter(filterKey)
end

function PlaneRadarScreen.sv_selectPlayers(self)
    self:sv_applyTargetFilter(TARGET_FILTER_PLAYERS)
end

function PlaneRadarScreen.sv_selectPlaneControllers(self)
    self:sv_applyTargetFilter(TARGET_FILTER_PLANE_CONTROLLERS)
end

function PlaneRadarScreen.sv_selectPlayerPresence(self)
    self:sv_applyTargetFilter(TARGET_FILTER_PLAYER_PRESENCE)
end

function PlaneRadarScreen.sv_selectConstructions(self)
    self:sv_applyTargetFilter(TARGET_FILTER_CONSTRUCTIONS)
end

function PlaneRadarScreen.sv_selectIr(self)
    self:sv_applyTargetFilter(TARGET_FILTER_IR)
end

function PlaneRadarScreen.sv_setCrosshairEnabled(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.crosshairEnabled then return end

    self.sv.crosshairEnabled = requestedState
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setCrosshairOffset(self, field, requestedOffset)
    local offset = tonumber(requestedOffset)
    if offset == nil then return end
    offset = clamp(offset, MIN_CROSSHAIR_OFFSET, MAX_CROSSHAIR_OFFSET)
    if offset == self.sv[field] then return end

    self.sv[field] = offset
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setCrosshairVerticalOffset(self, requestedOffset)
    self:sv_setCrosshairOffset("crosshairVerticalOffset", requestedOffset)
end

function PlaneRadarScreen.sv_setCrosshairHorizontalOffset(self, requestedOffset)
    self:sv_setCrosshairOffset("crosshairHorizontalOffset", requestedOffset)
end

function PlaneRadarScreen.sv_setCrosshairColor(self, requestedColor)
    if not isCrosshairColor(requestedColor) then return end
    if requestedColor == self.sv.crosshairColor then return end

    self.sv.crosshairColor = requestedColor
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setCrosshairShape(self, requestedShape)
    if not isCrosshairShape(requestedShape) then return end
    if requestedShape == self.sv.crosshairShape then return end

    self.sv.crosshairShape = requestedShape
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setCrosshairScale(self, field, requestedScale)
    local scale = clampInteger(
        requestedScale,
        MIN_CROSSHAIR_SCALE_PERCENT,
        MAX_CROSSHAIR_SCALE_PERCENT
    )
    if scale == self.sv[field] then return end

    self.sv[field] = scale
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setCrosshairSize(self, requestedScale)
    self:sv_setCrosshairScale("crosshairSize", requestedScale)
end

function PlaneRadarScreen.sv_setCrosshairDotSize(self, requestedScale)
    self:sv_setCrosshairScale("crosshairDotSize", requestedScale)
end

function PlaneRadarScreen.sv_setCrosshairGapSize(self, requestedScale)
    self:sv_setCrosshairScale("crosshairGapSize", requestedScale)
end

function PlaneRadarScreen.sv_setCrosshairElementWidth(self, requestedScale)
    self:sv_setCrosshairScale("crosshairElementWidth", requestedScale)
end

function PlaneRadarScreen.sv_setCrosshairElementLength(self, requestedScale)
    self:sv_setCrosshairScale("crosshairElementLength", requestedScale)
end

local getSelectedTargetKind

function PlaneRadarScreen.sv_publishRegistry(self)
    _G[getRegistryKey(self)] = {
        lockSource = "radar",
        sourceShape = self.shape,
        selectedPlayerId = self.sv.selectedPlayerId,
        selectedTargetKind = getSelectedTargetKind(self),
        targetFilter = self.sv.targetFilter,
        targetDataEnabled = self.sv.targetDataEnabled,
        targetFilters = self.sv.targetFilters,
        outputActive = self.sv.outputActive == true,
        fovDegrees = self.sv.fovDegrees,
        maximumDistanceBlocks = self.sv.maximumDistanceBlocks,
        sensorPosition = self.shape.worldPosition,
        sensorRight = self.shape:getRight() * SCAN_DIRECTION_SIGN,
        sensorAt = self.shape:getAt(),
        sensorUp = self.shape:getUp(),
        visibleTargets = self.sv.visibleTargets or {},
        targetData = self.sv.visibleTargetData or {},
        inRangeTargets = self.sv.inRangeTargets or {}
    }
end

function PlaneRadarScreen.sv_refreshExtraTargets(self)
    self.sv.extraTargets = {}
    if not isTargetFilterEnabled(self, TARGET_FILTER_CONSTRUCTIONS)
        and not isTargetFilterEnabled(self, TARGET_FILTER_IR) then
        return
    end

    local radius = self.sv.maximumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    local nearbyShapes = sm.shape.shapesInSphere(self.shape.worldPosition, radius)
    local ownBody = self.shape:getBody()
    local seenConstructions = {}

    for _, shape in ipairs(nearbyShapes) do
        if shape ~= nil and sm.exists(shape) and shape ~= self.shape then
            local shapeBody = shape:getBody()
            if shapeBody ~= ownBody then
                local shapeId = getShapeNumericId(shape)
                if shapeId ~= nil then
                    if isTargetFilterEnabled(self, TARGET_FILTER_CONSTRUCTIONS) then
                        local constructionKey, constructionNumericId = getConstructionIdentity(shapeBody)
                        if constructionKey ~= nil and not seenConstructions[constructionKey] then
                            seenConstructions[constructionKey] = true
                            local constructionId = constructionNumericId or shapeId
                            local constructionPosition, constructionVelocity =
                                getConstructionPositionAndVelocity(shapeBody, shape)
                            local targetId = CONSTRUCTION_TARGET_ID_OFFSET + constructionId
                            self.sv.extraTargets[targetId] = {
                                id = targetId,
                                kind = "construction",
                                name = "Construction",
                                active = true,
                                position = constructionPosition,
                                velocity = constructionVelocity,
                                sourceShape = shape,
                                sourceBody = shapeBody
                            }
                        end
                    end

                    if isTargetFilterEnabled(self, TARGET_FILTER_IR)
                        and isInfraredTargetShape(shape) then
                        self.sv.extraTargets[IR_TARGET_ID_OFFSET + shapeId] = {
                            id = IR_TARGET_ID_OFFSET + shapeId,
                            kind = "ir",
                            name = "IR source",
                            active = true,
                            position = shape.worldPosition,
                            velocity = shape:getVelocity(),
                            sourceShape = shape
                        }
                    end
                end
            end
        end
    end
end

local function getExtraTargetById(self, targetId)
    local extraTargets = self.sv ~= nil and self.sv.extraTargets or {}
    return extraTargets[targetId] or extraTargets[tostring(targetId)]
end

local function getServerRadarTargetById(self, targetId)
    -- Player ids and interactable ids are separate namespaces and can be
    -- numerically identical. Resolve the id using the active radar mode first;
    -- otherwise a player is incorrectly displayed as a Plane Controller.
    local presenceTarget = getPresenceTargetById(targetId)
    if isActiveChaffTarget(presenceTarget) then
        return presenceTarget
    end

    if isTargetFilterEnabled(self, TARGET_FILTER_PLAYERS) then
        return getPlayerTargetById(targetId) or getExtraTargetById(self, targetId)
    elseif isTargetFilterEnabled(self, TARGET_FILTER_PLANE_CONTROLLERS) then
        return getPlaneControllerById(targetId) or getExtraTargetById(self, targetId)
    elseif isTargetFilterEnabled(self, TARGET_FILTER_PLAYER_PRESENCE) then
        return presenceTarget
    elseif isTargetFilterEnabled(self, TARGET_FILTER_CONSTRUCTIONS)
        or isTargetFilterEnabled(self, TARGET_FILTER_IR) then
        return getExtraTargetById(self, targetId)
    end

    return presenceTarget
end

getSelectedTargetKind = function(self)
    local targetId = self.sv.selectedPlayerId
    if targetId == nil then return nil end

    local target = getServerRadarTargetById(self, targetId)
    if type(target) == "table" then
        if target.kind == nil then
            return "presence"
        end
        return target.kind
    end
    return nil
end

function PlaneRadarScreen.sv_getTargetPositionById(self, targetId)
    local target = getServerRadarTargetById(self, targetId)
    if isRadarTarget(target)
        and (target.kind ~= "plane_controller" or not isSameConstruction(self, target)) then
        return target.position
    end
    return nil
end

function PlaneRadarScreen.sv_getInRangeTargets(self)
    local inRangeTargets = {}
    local function addTarget(targetId, targetPosition)
        if targetId ~= nil and targetPosition ~= nil
            and isTargetInSensorRange(
                self,
                targetPosition,
                self.sv.minimumDistanceBlocks,
                self.sv.maximumDistanceBlocks
            ) then
            inRangeTargets[targetId] = true
        end
    end

    for targetId, target in pairs(getPlaneControllerRegistry()) do
        local numericTargetId = tonumber(targetId)
            or (type(target) == "table" and tonumber(target.id) or nil)
        if numericTargetId ~= nil and type(target) == "table"
            and isTargetAllowedForRadar(self, target)
            and not isSameConstruction(self, target) then
            addTarget(numericTargetId, target.position)
        end
    end

    for targetId, target in pairs(getPresenceRegistry()) do
        local numericTargetId = tonumber(targetId)
            or (type(target) == "table" and tonumber(target.id) or nil)
        if numericTargetId ~= nil and isTargetAllowedForRadar(self, target) then
            addTarget(numericTargetId, target.position)
        end
    end

    for targetId, target in pairs(self.sv.extraTargets or {}) do
        if isTargetAllowedForRadar(self, target) then
            addTarget(targetId, target.position)
        end
    end

    if isTargetFilterEnabled(self, TARGET_FILTER_PLAYERS) then
        for _, player in ipairs(sm.player.getAllPlayers()) do
            local target = getPlayerTargetById(player:getId())
            if target ~= nil then
                addTarget(target.id, target.position)
            end
        end
    end

    return inRangeTargets
end

function PlaneRadarScreen.sv_getEligiblePlayers(self)
    local eligiblePlayers = {}
    for targetId, target in pairs(getPlaneControllerRegistry()) do
        local numericTargetId = tonumber(targetId) or tonumber(target.id)
        if numericTargetId ~= nil and isTargetAllowedForRadar(self, target)
            and target.active == true and target.position ~= nil
            and not isSameConstruction(self, target)
            and isTargetInSensorCone(
                self,
                target.position,
                self.sv.fovDegrees,
                self.sv.minimumDistanceBlocks,
                self.sv.maximumDistanceBlocks
            )
            and not isTerrainBlocked(self, target.position) then
            local offset = target.position - self.shape.worldPosition
            table.insert(eligiblePlayers, {
                id = numericTargetId,
                distanceSquared = offset:dot(offset)
            })
        end
    end

    for targetId, target in pairs(getPresenceRegistry()) do
        local numericTargetId = tonumber(targetId) or tonumber(target.id)
        if numericTargetId ~= nil and isTargetAllowedForRadar(self, target)
            and isTargetInSensorCone(
                self,
                target.position,
                self.sv.fovDegrees,
                self.sv.minimumDistanceBlocks,
                self.sv.maximumDistanceBlocks
            )
            and not isTerrainBlocked(self, target.position) then
            local offset = target.position - self.shape.worldPosition
            table.insert(eligiblePlayers, {
                id = numericTargetId,
                distanceSquared = offset:dot(offset)
            })
        end
    end

    for targetId, target in pairs(self.sv.extraTargets or {}) do
        if isTargetAllowedForRadar(self, target)
            and isTargetInSensorCone(
                self,
                target.position,
                self.sv.fovDegrees,
                self.sv.minimumDistanceBlocks,
                self.sv.maximumDistanceBlocks
            )
            and not isTerrainBlocked(self, target.position) then
            local offset = target.position - self.shape.worldPosition
            table.insert(eligiblePlayers, {
                id = targetId,
                distanceSquared = offset:dot(offset)
            })
        end
    end

    if isTargetFilterEnabled(self, TARGET_FILTER_PLAYERS) then
        for _, player in ipairs(sm.player.getAllPlayers()) do
            local target = getPlayerTargetById(player:getId())
            if target ~= nil
                and isTargetInSensorCone(
                    self,
                    target.position,
                    self.sv.fovDegrees,
                    self.sv.minimumDistanceBlocks,
                    self.sv.maximumDistanceBlocks
                )
                and not isTerrainBlocked(self, target.position) then
                local offset = target.position - self.shape.worldPosition
                table.insert(eligiblePlayers, {
                    id = target.id,
                    distanceSquared = offset:dot(offset)
                })
            end
        end
    end

    -- Closest first gives a useful default and a stable, intuitive cycle order.
    table.sort(eligiblePlayers, function(left, right)
        if left.distanceSquared == right.distanceSquared then
            return left.id < right.id
        end
        return left.distanceSquared < right.distanceSquared
    end)
    return eligiblePlayers
end

function PlaneRadarScreen.sv_setSelectedPlayer(self, playerId)
    if self.sv.selectedPlayerId == playerId then return end

    self.sv.selectedPlayerId = playerId
    self:sv_save()
    self:sv_syncClientData()
    self:sv_publishRegistry()
end

function PlaneRadarScreen.sv_ensureSelectedPlayer(self, eligiblePlayers)
    if #eligiblePlayers == 0 then
        self:sv_setSelectedPlayer(nil)
        return
    end

    for _, eligiblePlayer in ipairs(eligiblePlayers) do
        if eligiblePlayer.id == self.sv.selectedPlayerId then
            return
        end
    end

    -- The closest eligible player gets the yellow marker by default.
    self:sv_setSelectedPlayer(eligiblePlayers[1].id)
end

function PlaneRadarScreen.sv_cycleSelectedPlayer(self, eligiblePlayers)
    if #eligiblePlayers <= 1 then return end

    local currentIndex = 0
    for index, eligiblePlayer in ipairs(eligiblePlayers) do
        if eligiblePlayer.id == self.sv.selectedPlayerId then
            currentIndex = index
            break
        end
    end

    local nextIndex = currentIndex + 1
    if nextIndex > #eligiblePlayers then
        nextIndex = 1
    end
    self:sv_setSelectedPlayer(eligiblePlayers[nextIndex].id)
end

function PlaneRadarScreen.sv_updateChaffDistraction(self, eligiblePlayers)
    local seenSequences = self.sv.chaffSeenSequences or {}
    local visibleChaffIds = {}

    for _, eligiblePlayer in ipairs(eligiblePlayers) do
        local targetId = eligiblePlayer.id
        local target = getPresenceTargetById(targetId)
        if isActiveChaffTarget(target) then
            visibleChaffIds[targetId] = true
            local spawnSequence = tonumber(target.spawnSequence) or 0
            if spawnSequence > 0 and seenSequences[targetId] ~= spawnSequence then
                seenSequences[targetId] = spawnSequence
                if math.random() < CHAFF_DISTRACTION_CHANCE then
                    self:sv_setSelectedPlayer(targetId)
                end
            end
        end
    end

    for targetId in pairs(seenSequences) do
        local target = getPresenceTargetById(targetId)
        if not visibleChaffIds[targetId] and not isActiveChaffTarget(target) then
            seenSequences[targetId] = nil
        end
    end

    self.sv.chaffSeenSequences = seenSequences
end

function PlaneRadarScreen.server_onFixedUpdate(self, timeStep)
    self:sv_refreshExtraTargets()
    self.sv.inRangeTargets = self:sv_getInRangeTargets()
    local eligiblePlayers = self:sv_getEligiblePlayers()
    self.sv.visibleTargets = {}
    self.sv.visibleTargetData = {}
    for _, eligiblePlayer in ipairs(eligiblePlayers) do
        local position = self:sv_getTargetPositionById(eligiblePlayer.id)
        if position ~= nil then
            self.sv.visibleTargets[eligiblePlayer.id] = position
            self.sv.visibleTargetData[eligiblePlayer.id] = getTargetData(
                eligiblePlayer.id,
                position,
                self.shape,
                getServerRadarTargetById(self, eligiblePlayer.id)
            )
        end
    end

    local visibleTargetIds = {}
    for targetId in pairs(self.sv.visibleTargets) do
        visibleTargetIds[targetId] = true
    end
    self.sv.visibleTargetIds = visibleTargetIds
    -- Player, construction and IR targets do not have a client-side registry,
    -- so their positions/data must be refreshed as they move.
    self:sv_syncClientData()
    self:sv_ensureSelectedPlayer(eligiblePlayers)

    local yellowActive = isLogicColorActive(self, YELLOW_LOGIC_COLORS)
    if yellowActive then
        if not self.sv.previousYellowActive then
            -- Rising edge: one immediate cycle.
            self:sv_cycleSelectedPlayer(eligiblePlayers)
            self.sv.yellowCycleTimer = 0.0
        else
            self.sv.yellowCycleTimer = self.sv.yellowCycleTimer + (tonumber(timeStep) or 0.025)
            while self.sv.yellowCycleTimer >= 1.0 do
                self.sv.yellowCycleTimer = self.sv.yellowCycleTimer - 1.0
                self:sv_cycleSelectedPlayer(eligiblePlayers)
            end
        end
    else
        self.sv.yellowCycleTimer = 0.0
    end
    self.sv.previousYellowActive = yellowActive

    -- Each newly visible chaff deployment has one 50% chance to become the
    -- selected radar target, matching the Plane Controller's distraction rule.
    self:sv_updateChaffDistraction(eligiblePlayers)

    -- Basic logic is the radar's tracking-enable output. Yellow only changes
    -- the selected target and never starts the Plane Controller by itself.
    local basicActive = isBasicLogicInputActive(self)
    if basicActive ~= self.sv.outputActive then
        self.sv.outputActive = basicActive
        self.interactable:setActive(basicActive)
    end
    self:sv_publishRegistry()
end

function PlaneRadarScreen.client_onCreate(self)
    self.cl = {
        fovDegrees = DEFAULT_FOV_DEGREES,
        minimumDistanceBlocks = DEFAULT_MIN_DISTANCE_BLOCKS,
        maximumDistanceBlocks = DEFAULT_MAX_DISTANCE_BLOCKS,
        selectedPlayerId = nil,
        visibleTargetIds = {},
        visibleTargetData = {},
        targetFilters = copyTargetFilters(nil),
        targetFilter = TARGET_FILTER_PLANE_CONTROLLERS,
        targetDataEnabled = DEFAULT_TARGET_DATA_ENABLED,
        crosshairEnabled = DEFAULT_CROSSHAIR_ENABLED,
        crosshairVerticalOffset = DEFAULT_CROSSHAIR_VERTICAL_OFFSET,
        crosshairHorizontalOffset = DEFAULT_CROSSHAIR_HORIZONTAL_OFFSET,
        crosshairColor = DEFAULT_CROSSHAIR_COLOR,
        crosshairShape = DEFAULT_CROSSHAIR_SHAPE,
        crosshairSize = DEFAULT_CROSSHAIR_SIZE_PERCENT,
        crosshairDotSize = DEFAULT_CROSSHAIR_DOT_SIZE_PERCENT,
        crosshairGapSize = DEFAULT_CROSSHAIR_GAP_SIZE_PERCENT,
        crosshairElementWidth = DEFAULT_CROSSHAIR_ELEMENT_WIDTH_PERCENT,
        crosshairElementLength = DEFAULT_CROSSHAIR_ELEMENT_LENGTH_PERCENT,
        gui = nil,
        markers = {},
        markerUuids = {},
        markerPositions = {},
        targetLabels = {},
        targetLabelVisibility = {},
        crosshair = nil,
        crosshairDot = nil,
        crosshairParts = {}
    }
end

function PlaneRadarScreen.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self:client_onCreate()
    end

    self.cl.fovDegrees = clampInteger(data.fovDegrees, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
    self.cl.minimumDistanceBlocks = clampInteger(
        data.minimumDistanceBlocks,
        MIN_MIN_DISTANCE_BLOCKS,
        MAX_MIN_DISTANCE_BLOCKS
    )
    self.cl.maximumDistanceBlocks = clampInteger(
        data.maximumDistanceBlocks or data.distanceBlocks,
        MIN_MAX_DISTANCE_BLOCKS,
        MAX_MAX_DISTANCE_BLOCKS
    )
    self.cl.selectedPlayerId = tonumber(data.selectedPlayerId)
    self.cl.targetDataEnabled = data.targetDataEnabled ~= false
    if type(data.targetFilter) == "string"
        and DEFAULT_TARGET_FILTERS[data.targetFilter] ~= nil then
        self.cl.targetFilter = data.targetFilter
        self.cl.targetFilters = copyTargetFilters({ [data.targetFilter] = true })
    else
        self.cl.targetFilters = copyTargetFilters(data.targetFilters)
        self.cl.targetFilter = getActiveTargetFilter(self.cl.targetFilters)
    end
    self.cl.crosshairEnabled = data.crosshairEnabled == true
    self.cl.crosshairVerticalOffset = clamp(
        tonumber(data.crosshairVerticalOffset) or DEFAULT_CROSSHAIR_VERTICAL_OFFSET,
        MIN_CROSSHAIR_OFFSET,
        MAX_CROSSHAIR_OFFSET
    )
    self.cl.crosshairHorizontalOffset = clamp(
        tonumber(data.crosshairHorizontalOffset) or DEFAULT_CROSSHAIR_HORIZONTAL_OFFSET,
        MIN_CROSSHAIR_OFFSET,
        MAX_CROSSHAIR_OFFSET
    )
    self.cl.crosshairColor = isCrosshairColor(data.crosshairColor)
        and data.crosshairColor
        or DEFAULT_CROSSHAIR_COLOR
    self.cl.crosshairShape = isCrosshairShape(data.crosshairShape)
        and data.crosshairShape
        or DEFAULT_CROSSHAIR_SHAPE
    self.cl.crosshairSize = clampInteger(
        data.crosshairSize or DEFAULT_CROSSHAIR_SIZE_PERCENT,
        MIN_CROSSHAIR_SCALE_PERCENT,
        MAX_CROSSHAIR_SCALE_PERCENT
    )
    self.cl.crosshairDotSize = clampInteger(
        data.crosshairDotSize or DEFAULT_CROSSHAIR_DOT_SIZE_PERCENT,
        MIN_CROSSHAIR_SCALE_PERCENT,
        MAX_CROSSHAIR_SCALE_PERCENT
    )
    self.cl.crosshairGapSize = clampInteger(
        data.crosshairGapSize or DEFAULT_CROSSHAIR_GAP_SIZE_PERCENT,
        MIN_CROSSHAIR_SCALE_PERCENT,
        MAX_CROSSHAIR_SCALE_PERCENT
    )
    self.cl.crosshairElementWidth = clampInteger(
        data.crosshairElementWidth or DEFAULT_CROSSHAIR_ELEMENT_WIDTH_PERCENT,
        MIN_CROSSHAIR_SCALE_PERCENT,
        MAX_CROSSHAIR_SCALE_PERCENT
    )
    self.cl.crosshairElementLength = clampInteger(
        data.crosshairElementLength or DEFAULT_CROSSHAIR_ELEMENT_LENGTH_PERCENT,
        MIN_CROSSHAIR_SCALE_PERCENT,
        MAX_CROSSHAIR_SCALE_PERCENT
    )
    self.cl.visibleTargetIds = {}
    for targetId, isVisible in pairs(data.visibleTargetIds or {}) do
        local numericTargetId = tonumber(targetId)
        if numericTargetId ~= nil and isVisible == true then
            self.cl.visibleTargetIds[numericTargetId] = true
        end
    end
    self.cl.visibleTargetData = data.visibleTargetData or {}
    self:cl_refreshCrosshair()
    self:cl_refreshGui()
end

function PlaneRadarScreen.client_onDestroy(self)
    if self.cl == nil then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
    for _, marker in pairs(self.cl.markers) do
        if marker:isPlaying() then marker:stop() end
        marker:destroy()
    end
    self.cl.markers = {}
    self.cl.markerUuids = {}
    self.cl.markerPositions = {}
    for _, label in pairs(self.cl.targetLabels) do
        label:close()
        label:destroy()
    end
    self.cl.targetLabels = {}
    self:cl_destroyCrosshair()
end

function PlaneRadarScreen.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_radar_screen"))
    return true
end

function PlaneRadarScreen.cl_openGui(self)
    if self.cl.gui then
        local oldGui = self.cl.gui
        self.cl.gui = nil
        oldGui:close()
        oldGui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneRadarScreenUpdated.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "FovSlider",
        MAX_FOV_DEGREES - MIN_FOV_DEGREES + 1,
        self.cl.fovDegrees - MIN_FOV_DEGREES,
        "cl_onFovSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "MinimumDistanceSlider",
        MAX_MIN_DISTANCE_BLOCKS - MIN_MIN_DISTANCE_BLOCKS + 1,
        self.cl.minimumDistanceBlocks - MIN_MIN_DISTANCE_BLOCKS,
        "cl_onMinimumDistanceSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "DistanceSlider",
        MAX_MAX_DISTANCE_BLOCKS - MIN_MAX_DISTANCE_BLOCKS + 1,
        self.cl.maximumDistanceBlocks - MIN_MAX_DISTANCE_BLOCKS,
        "cl_onMaximumDistanceSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "FovSliderCentered",
        MAX_FOV_DEGREES - MIN_FOV_DEGREES + 1,
        self.cl.fovDegrees - MIN_FOV_DEGREES,
        "cl_onFovSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "MinimumDistanceSliderCentered",
        MAX_MIN_DISTANCE_BLOCKS - MIN_MIN_DISTANCE_BLOCKS + 1,
        self.cl.minimumDistanceBlocks - MIN_MIN_DISTANCE_BLOCKS,
        "cl_onMinimumDistanceSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "DistanceSliderCentered",
        MAX_MAX_DISTANCE_BLOCKS - MIN_MAX_DISTANCE_BLOCKS + 1,
        self.cl.maximumDistanceBlocks - MIN_MAX_DISTANCE_BLOCKS,
        "cl_onMaximumDistanceSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairVerticalSlider",
        CROSSHAIR_OFFSET_STEPS,
        math.floor((self.cl.crosshairVerticalOffset - MIN_CROSSHAIR_OFFSET) * 100 + 0.5),
        "cl_onCrosshairVerticalSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairHorizontalSlider",
        CROSSHAIR_OFFSET_STEPS,
        math.floor((self.cl.crosshairHorizontalOffset - MIN_CROSSHAIR_OFFSET) * 100 + 0.5),
        "cl_onCrosshairHorizontalSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairSizeSlider",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairSize - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairSizeSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairDotSizeSlider",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairDotSize - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairDotSizeSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairGapSizeSlider",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairGapSize - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairGapSizeSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairElementWidthSlider",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairElementWidth - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairElementWidthSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairElementLengthSlider",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairElementLength - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairElementLengthSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairElementWidthSliderLeft",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairElementWidth - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairElementWidthSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairElementLengthSliderLeft",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairElementLength - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairElementLengthSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairDotSizeSliderRight",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairDotSize - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairDotSizeSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairGapSizeSliderRight",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairGapSize - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairGapSizeSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairGapSizeSliderLeft",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairGapSize - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairGapSizeSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairElementWidthSliderRightRow2",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairElementWidth - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairElementWidthSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CrosshairElementLengthSliderLeftRow3",
        CROSSHAIR_SCALE_STEPS,
        self.cl.crosshairElementLength - MIN_CROSSHAIR_SCALE_PERCENT,
        "cl_onCrosshairElementLengthSliderChanged"
    )
    self.cl.gui:setButtonCallback("CrosshairButton", "cl_onCrosshairPressed")
    self.cl.gui:setButtonCallback("CrosshairButtonCentered", "cl_onCrosshairPressed")
    self.cl.gui:setButtonCallback("TargetDataButton", "cl_onTargetDataPressed")
    self.cl.gui:setButtonCallback("TargetDataButtonCentered", "cl_onTargetDataPressed")
    self.cl.gui:setButtonCallback("TargetFilterDropDown", "cl_onTargetFilterCyclePressed")
    self.cl.gui:setButtonCallback("TargetFilterDropDownCentered", "cl_onTargetFilterCyclePressed")
    self.cl.gui:setButtonCallback("CrosshairColorButton", "cl_onCrosshairColorPressed")
    self.cl.gui:setButtonCallback("CrosshairShapeButton", "cl_onCrosshairShapePressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self.cl.guiLayoutCrosshairEnabled = self.cl.crosshairEnabled
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneRadarScreen.client_onInteract(self, _, state)
    if not state then return end
    self:cl_openGui()
end

function PlaneRadarScreen.cl_onFovSliderChanged(self, sliderPosition)
    self.cl.fovDegrees = clampInteger(sliderPosition + MIN_FOV_DEGREES, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setFovDegrees", self.cl.fovDegrees)
end

function PlaneRadarScreen.cl_onMinimumDistanceSliderChanged(self, sliderPosition)
    self.cl.minimumDistanceBlocks = clampInteger(
        sliderPosition + MIN_MIN_DISTANCE_BLOCKS,
        MIN_MIN_DISTANCE_BLOCKS,
        MAX_MIN_DISTANCE_BLOCKS
    )
    self:cl_refreshGui()
    self.network:sendToServer("sv_setMinimumDistanceBlocks", self.cl.minimumDistanceBlocks)
end

function PlaneRadarScreen.cl_onMaximumDistanceSliderChanged(self, sliderPosition)
    self.cl.maximumDistanceBlocks = clampInteger(
        sliderPosition + MIN_MAX_DISTANCE_BLOCKS,
        MIN_MAX_DISTANCE_BLOCKS,
        MAX_MAX_DISTANCE_BLOCKS
    )
    self:cl_refreshGui()
    self.network:sendToServer("sv_setMaximumDistanceBlocks", self.cl.maximumDistanceBlocks)
end

function PlaneRadarScreen.cl_onCrosshairPressed(self)
    self.cl.crosshairEnabled = not self.cl.crosshairEnabled
    self:cl_refreshCrosshair()
    self:cl_refreshGui()
    self.network:sendToServer("sv_setCrosshairEnabled", self.cl.crosshairEnabled)
end

function PlaneRadarScreen.cl_onTargetDataPressed(self)
    self.cl.targetDataEnabled = not self.cl.targetDataEnabled
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTargetDataEnabled", self.cl.targetDataEnabled)
end

function PlaneRadarScreen.cl_onCrosshairVerticalSliderChanged(self, sliderPosition)
    self.cl.crosshairVerticalOffset = clamp(
        MIN_CROSSHAIR_OFFSET + sliderPosition / 100,
        MIN_CROSSHAIR_OFFSET,
        MAX_CROSSHAIR_OFFSET
    )
    self:cl_refreshCrosshair()
    self:cl_refreshGui()
    self.network:sendToServer("sv_setCrosshairVerticalOffset", self.cl.crosshairVerticalOffset)
end

function PlaneRadarScreen.cl_onCrosshairHorizontalSliderChanged(self, sliderPosition)
    self.cl.crosshairHorizontalOffset = clamp(
        MIN_CROSSHAIR_OFFSET + sliderPosition / 100,
        MIN_CROSSHAIR_OFFSET,
        MAX_CROSSHAIR_OFFSET
    )
    self:cl_refreshCrosshair()
    self:cl_refreshGui()
    self.network:sendToServer("sv_setCrosshairHorizontalOffset", self.cl.crosshairHorizontalOffset)
end

function PlaneRadarScreen.cl_setCrosshairScale(self, field, sliderPosition, serverMethod)
    self.cl[field] = clampInteger(
        sliderPosition + MIN_CROSSHAIR_SCALE_PERCENT,
        MIN_CROSSHAIR_SCALE_PERCENT,
        MAX_CROSSHAIR_SCALE_PERCENT
    )
    self:cl_refreshCrosshair()
    self:cl_refreshGui()
    self.network:sendToServer(serverMethod, self.cl[field])
end

function PlaneRadarScreen.cl_onCrosshairSizeSliderChanged(self, sliderPosition)
    self:cl_setCrosshairScale("crosshairSize", sliderPosition, "sv_setCrosshairSize")
end

function PlaneRadarScreen.cl_onCrosshairDotSizeSliderChanged(self, sliderPosition)
    self:cl_setCrosshairScale("crosshairDotSize", sliderPosition, "sv_setCrosshairDotSize")
end

function PlaneRadarScreen.cl_onCrosshairGapSizeSliderChanged(self, sliderPosition)
    self:cl_setCrosshairScale("crosshairGapSize", sliderPosition, "sv_setCrosshairGapSize")
end

function PlaneRadarScreen.cl_onCrosshairElementWidthSliderChanged(self, sliderPosition)
    self:cl_setCrosshairScale("crosshairElementWidth", sliderPosition, "sv_setCrosshairElementWidth")
end

function PlaneRadarScreen.cl_onCrosshairElementLengthSliderChanged(self, sliderPosition)
    self:cl_setCrosshairScale("crosshairElementLength", sliderPosition, "sv_setCrosshairElementLength")
end

function PlaneRadarScreen.cl_onCrosshairColorPressed(self)
    local currentIndex = 1
    for index, optionName in ipairs(CROSSHAIR_COLOR_OPTIONS) do
        if CROSSHAIR_COLOR_NAMES[optionName] == self.cl.crosshairColor then
            currentIndex = index
            break
        end
    end
    local nextIndex = (currentIndex % #CROSSHAIR_COLOR_OPTIONS) + 1
    self.cl.crosshairColor = CROSSHAIR_COLOR_NAMES[CROSSHAIR_COLOR_OPTIONS[nextIndex]]
    self:cl_refreshCrosshair()
    self:cl_refreshGui()
    self.network:sendToServer("sv_setCrosshairColor", self.cl.crosshairColor)
end

function PlaneRadarScreen.cl_onCrosshairShapePressed(self)
    local currentIndex = 1
    for index, optionName in ipairs(CROSSHAIR_SHAPE_OPTIONS) do
        if CROSSHAIR_SHAPE_NAMES[optionName] == self.cl.crosshairShape then
            currentIndex = index
            break
        end
    end
    local nextIndex = (currentIndex % #CROSSHAIR_SHAPE_OPTIONS) + 1
    self.cl.crosshairShape = CROSSHAIR_SHAPE_NAMES[CROSSHAIR_SHAPE_OPTIONS[nextIndex]]
    self:cl_refreshCrosshair()
    self:cl_refreshGui()
    self.network:sendToServer("sv_setCrosshairShape", self.cl.crosshairShape)
end

function PlaneRadarScreen.cl_targetFilterSummary(self)
    return TARGET_FILTER_LABELS[self.cl.targetFilter or getActiveTargetFilter(self.cl.targetFilters)]
end

function PlaneRadarScreen.cl_targetFilterOptions(self)
    local options = {}
    for _, key in ipairs(TARGET_FILTER_KEYS) do
        table.insert(options, TARGET_FILTER_LABELS[key])
    end
    return options
end

function PlaneRadarScreen.cl_onTargetFilterCyclePressed(self)
    local currentKey = self.cl.targetFilter or getActiveTargetFilter(self.cl.targetFilters)
    local currentIndex = 1
    for index, key in ipairs(TARGET_FILTER_KEYS) do
        if key == currentKey then
            currentIndex = index
            break
        end
    end

    local nextIndex = (currentIndex % #TARGET_FILTER_KEYS) + 1
    local selectedKey = TARGET_FILTER_KEYS[nextIndex]
    for _, key in ipairs(TARGET_FILTER_KEYS) do
        self.cl.targetFilters[key] = key == selectedKey
    end
    self.cl.targetFilter = selectedKey
    local serverMethods = {
        [TARGET_FILTER_PLAYERS] = "sv_selectPlayers",
        [TARGET_FILTER_PLANE_CONTROLLERS] = "sv_selectPlaneControllers",
        [TARGET_FILTER_PLAYER_PRESENCE] = "sv_selectPlayerPresence",
        [TARGET_FILTER_CONSTRUCTIONS] = "sv_selectConstructions",
        [TARGET_FILTER_IR] = "sv_selectIr"
    }
    self.network:sendToServer(serverMethods[selectedKey])
    self:cl_refreshTargetFilterDropDown()
end

function PlaneRadarScreen.cl_refreshTargetFilterDropDown(self)
    if self.cl == nil or self.cl.gui == nil then return end
    local summary = PC_L.get("target_filter_summary", self:cl_targetFilterSummary())
    self.cl.gui:setText("TargetFilterLabel", summary)
    self.cl.gui:setText("TargetFilterLabelCentered", summary)
end

function PlaneRadarScreen.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end

    self.cl.gui:setText("FovValue", PC_L.get("field_of_view", self.cl.fovDegrees))
    self.cl.gui:setText(
        "MinimumDistanceValue",
        PC_L.get("minimum_distance", self.cl.minimumDistanceBlocks)
    )
    self.cl.gui:setText(
        "DistanceValue",
        PC_L.get("maximum_distance", self.cl.maximumDistanceBlocks)
    )
    self.cl.gui:setText("FovValueCentered", PC_L.get("field_of_view", self.cl.fovDegrees))
    self.cl.gui:setText(
        "MinimumDistanceValueCentered",
        PC_L.get("minimum_distance", self.cl.minimumDistanceBlocks)
    )
    self.cl.gui:setText(
        "DistanceValueCentered",
        PC_L.get("maximum_distance", self.cl.maximumDistanceBlocks)
    )
    self.cl.gui:setButtonState("CrosshairButton", self.cl.crosshairEnabled)
    self.cl.gui:setButtonState("CrosshairButtonCentered", self.cl.crosshairEnabled)
    self.cl.gui:setButtonState("TargetDataButton", self.cl.targetDataEnabled)
    self.cl.gui:setButtonState("TargetDataButtonCentered", self.cl.targetDataEnabled)
    self:cl_refreshTargetFilterDropDown()
    self.cl.gui:setVisible("MainMenu", self.cl.crosshairEnabled)
    self.cl.gui:setVisible("MainMenuCentered", not self.cl.crosshairEnabled)
    self.cl.gui:setVisible("CrosshairMenu", self.cl.crosshairEnabled)
    local isOrdinary = self.cl.crosshairShape == "ordinary"
    local isCrossGap = self.cl.crosshairShape == "cross_gap"
    local isCrossDot = self.cl.crosshairShape == "cross_dot"
    local isCircle = self.cl.crosshairShape == "circle"
    local isCircleDot = self.cl.crosshairShape == "circle_dot"

    -- Lay the active controls out in alternating left/right slots:
    -- 1st left, 2nd right, 3rd left, 4th right, 5th left.
    self.cl.gui:setVisible("CrosshairDotSizeValue", false)
    self.cl.gui:setVisible("CrosshairDotSizeSlider", false)
    self.cl.gui:setVisible("CrosshairDotSizeValueRight", isCrossDot or isCircleDot)
    self.cl.gui:setVisible("CrosshairDotSizeSliderRight", isCrossDot or isCircleDot)

    self.cl.gui:setVisible("CrosshairGapSizeValue", false)
    self.cl.gui:setVisible("CrosshairGapSizeSlider", false)
    self.cl.gui:setVisible("CrosshairGapSizeValueRight", isCrossGap)
    self.cl.gui:setVisible("CrosshairGapSizeSliderRight", isCrossGap)
    self.cl.gui:setVisible("CrosshairGapSizeValueLeft", isCrossDot)
    self.cl.gui:setVisible("CrosshairGapSizeSliderLeft", isCrossDot)

    self.cl.gui:setVisible("CrosshairElementWidthValue", isOrdinary or isCircle)
    self.cl.gui:setVisible("CrosshairElementWidthSlider", isOrdinary or isCircle)
    self.cl.gui:setVisible("CrosshairElementWidthValueLeft", isCrossGap or isCircleDot)
    self.cl.gui:setVisible("CrosshairElementWidthSliderLeft", isCrossGap or isCircleDot)
    self.cl.gui:setVisible("CrosshairElementWidthValueRightRow2", isCrossDot)
    self.cl.gui:setVisible("CrosshairElementWidthSliderRightRow2", isCrossDot)

    self.cl.gui:setVisible("CrosshairElementLengthValue", isCrossGap)
    self.cl.gui:setVisible("CrosshairElementLengthSlider", isCrossGap)
    self.cl.gui:setVisible("CrosshairElementLengthValueLeft", isOrdinary)
    self.cl.gui:setVisible("CrosshairElementLengthSliderLeft", isOrdinary)
    self.cl.gui:setVisible("CrosshairElementLengthValueLeftRow3", isCrossDot)
    self.cl.gui:setVisible("CrosshairElementLengthSliderLeftRow3", isCrossDot)
    self.cl.gui:setText(
        "CrosshairVerticalValueText",
        PC_L.get("horizontal_offset", self.cl.crosshairVerticalOffset)
    )
    self.cl.gui:setText(
        "CrosshairHorizontalValueText",
        PC_L.get("vertical_offset", self.cl.crosshairHorizontalOffset)
    )
    self.cl.gui:setText(
        "CrosshairColorButtonText",
        PC_L.get("crosshair_color", CROSSHAIR_COLOR_LABELS[self.cl.crosshairColor])
    )
    self.cl.gui:setText(
        "CrosshairShapeButtonText",
        PC_L.get("crosshair_shape", CROSSHAIR_SHAPE_LABELS[self.cl.crosshairShape])
    )
    self.cl.gui:setText(
        "CrosshairSizeValueText",
        PC_L.get("crosshair_size", self.cl.crosshairSize)
    )
    self.cl.gui:setText(
        "CrosshairDotSizeValueText",
        PC_L.get("dot_size", self.cl.crosshairDotSize)
    )
    self.cl.gui:setText(
        "CrosshairDotSizeValueTextRight",
        PC_L.get("dot_size", self.cl.crosshairDotSize)
    )
    self.cl.gui:setText(
        "CrosshairGapSizeValueText",
        PC_L.get("gap_size", self.cl.crosshairGapSize)
    )
    self.cl.gui:setText(
        "CrosshairGapSizeValueTextRight",
        PC_L.get("gap_size", self.cl.crosshairGapSize)
    )
    self.cl.gui:setText(
        "CrosshairGapSizeValueTextLeft",
        PC_L.get("gap_size", self.cl.crosshairGapSize)
    )
    self.cl.gui:setText(
        "CrosshairElementWidthValueText",
        PC_L.get("element_width", self.cl.crosshairElementWidth)
    )
    self.cl.gui:setText(
        "CrosshairElementWidthValueTextLeft",
        PC_L.get("element_width", self.cl.crosshairElementWidth)
    )
    self.cl.gui:setText(
        "CrosshairElementWidthValueTextRightRow2",
        PC_L.get("element_width", self.cl.crosshairElementWidth)
    )
    self.cl.gui:setText(
        "CrosshairElementLengthValueText",
        PC_L.get("element_length", self.cl.crosshairElementLength)
    )
    self.cl.gui:setText(
        "CrosshairElementLengthValueTextLeft",
        PC_L.get("element_length", self.cl.crosshairElementLength)
    )
    self.cl.gui:setText(
        "CrosshairElementLengthValueTextLeftRow3",
        PC_L.get("element_length", self.cl.crosshairElementLength)
    )
end

function PlaneRadarScreen.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneRadarScreen.cl_destroyCrosshair(self)
    for _, effect in ipairs(self.cl.crosshairParts or {}) do
        if effect ~= nil then
            if effect:isPlaying() then effect:stop() end
            effect:destroy()
        end
    end
    self.cl.crosshairParts = {}
    self.cl.crosshair = nil
    self.cl.crosshairDot = nil
end

function PlaneRadarScreen.cl_getCrosshairElementScale(self, orientation, lengthMultiplier)
    local overall = self.cl.crosshairSize / 100.0
    local width = self.cl.crosshairElementWidth / 100.0
    local length = self.cl.crosshairElementLength / 100.0
    local armLength = length * (lengthMultiplier or 1.0)
    if orientation == "vertical" then
        return sm.vec3.new(0.65 * overall * width, 1, 0.65 * overall * armLength)
    end
    return sm.vec3.new(0.65 * overall * armLength, 1, 0.65 * overall * width)
end

function PlaneRadarScreen.cl_getCrosshairDotScale(self)
    local overall = self.cl.crosshairSize / 100.0
    local dot = self.cl.crosshairDotSize / 100.0
    return sm.vec3.new(0.65 * overall * dot, 1, 0.65 * overall * dot)
end

function PlaneRadarScreen.cl_getCrosshairRingUuid(self, color)
    local width = self.cl.crosshairElementWidth
    local selectedIndex = 1
    local selectedDistance = math.abs(width - CROSSHAIR_RING_WIDTH_STEPS[1])
    for index = 2, #CROSSHAIR_RING_WIDTH_STEPS do
        local distance = math.abs(width - CROSSHAIR_RING_WIDTH_STEPS[index])
        if distance < selectedDistance then
            selectedIndex = index
            selectedDistance = distance
        end
    end
    return CROSSHAIR_RING_UUIDS[color][selectedIndex]
end

function PlaneRadarScreen.cl_createCrosshairPart(self, uuid, position, scale)
    local effect = sm.effect.createEffect("ShapeRenderable", self.shape)
    effect:setParameter("uuid", uuid)
    effect:setParameter("color", CROSSHAIR_RENDER_COLORS[self.cl.crosshairColor])
    effect:setOffsetPosition(position)
    effect:setOffsetRotation(
        sm.vec3.getRotation(sm.vec3.new(0, 1, 0), sm.vec3.new(1, 0, 0))
    )
    effect:setScale(scale or sm.vec3.new(0.65, 1, 0.65))
    effect:start()
    table.insert(self.cl.crosshairParts, effect)
    return effect
end

function PlaneRadarScreen.cl_refreshCrosshair(self)
    if self.cl == nil then return end
    self:cl_destroyCrosshair()
    if not self.cl.crosshairEnabled then return end

    local paneHalfWidth = math.max(PANE_HALF_WIDTH - PANE_MARGIN, 0.01)
    local paneHalfHeight = math.max(PANE_HALF_HEIGHT - PANE_MARGIN, 0.01)
    local position = sm.vec3.new(
        PANE_DEPTH_OFFSET,
        self.cl.crosshairHorizontalOffset * paneHalfWidth,
        self.cl.crosshairVerticalOffset * paneHalfHeight
    )
    local color = self.cl.crosshairColor
    local shape = self.cl.crosshairShape
    local overall = self.cl.crosshairSize / 100.0
    local gapHalf = 0.025 * overall * self.cl.crosshairGapSize / 100.0
    local armHalf = 0.0475 * overall * self.cl.crosshairElementLength / 100.0
    local gapArmOffset = gapHalf + armHalf

    if shape == "ordinary" then
        self.cl.crosshair = self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.horizontal[color],
            position,
            self:cl_getCrosshairElementScale("horizontal")
        )
        self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.vertical[color],
            position,
            self:cl_getCrosshairElementScale("vertical")
        )
    elseif shape == "cross_gap" then
        self.cl.crosshair = self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.horizontal[color],
            position + sm.vec3.new(0, -gapArmOffset, 0),
            self:cl_getCrosshairElementScale("horizontal", 0.475)
        )
        self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.horizontal[color],
            position + sm.vec3.new(0, gapArmOffset, 0),
            self:cl_getCrosshairElementScale("horizontal", 0.475)
        )
        self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.vertical[color],
            position + sm.vec3.new(0, 0, -gapArmOffset),
            self:cl_getCrosshairElementScale("vertical", 0.475)
        )
        self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.vertical[color],
            position + sm.vec3.new(0, 0, gapArmOffset),
            self:cl_getCrosshairElementScale("vertical", 0.475)
        )
    elseif shape == "cross_dot" then
        self.cl.crosshair = self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.horizontal[color],
            position + sm.vec3.new(0, -gapArmOffset, 0),
            self:cl_getCrosshairElementScale("horizontal", 0.475)
        )
        self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.horizontal[color],
            position + sm.vec3.new(0, gapArmOffset, 0),
            self:cl_getCrosshairElementScale("horizontal", 0.475)
        )
        self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.vertical[color],
            position + sm.vec3.new(0, 0, -gapArmOffset),
            self:cl_getCrosshairElementScale("vertical", 0.475)
        )
        self:cl_createCrosshairPart(
            CROSSHAIR_ARM_UUIDS.vertical[color],
            position + sm.vec3.new(0, 0, gapArmOffset),
            self:cl_getCrosshairElementScale("vertical", 0.475)
        )
        self.cl.crosshairDot = self:cl_createCrosshairPart(
            CROSSHAIR_SHAPE_UUIDS.dot[color],
            sm.vec3.new(CROSSHAIR_DOT_DEPTH_OFFSET, position.y, position.z),
            self:cl_getCrosshairDotScale()
        )
    elseif shape == "circle" then
        self.cl.crosshair = self:cl_createCrosshairPart(
            self:cl_getCrosshairRingUuid(color),
            position,
            sm.vec3.new(0.65 * overall, 1, 0.65 * overall)
        )
    elseif shape == "circle_dot" then
        self.cl.crosshair = self:cl_createCrosshairPart(
            self:cl_getCrosshairRingUuid(color),
            position,
            sm.vec3.new(0.65 * overall, 1, 0.65 * overall)
        )
        self.cl.crosshairDot = self:cl_createCrosshairPart(
            CROSSHAIR_SHAPE_UUIDS.dot[color],
            sm.vec3.new(CROSSHAIR_DOT_DEPTH_OFFSET, position.y, position.z),
            self:cl_getCrosshairDotScale()
        )
    end
end

function PlaneRadarScreen.cl_updateMarker(self, targetId, targetPosition, activeMarkers, timeStep)
    local localPosition = self:cl_getScreenLocalPosition(targetPosition)
    if localPosition == nil then return end

    local displayPosition = localPosition
    local previousPosition = self.cl.markerPositions[targetId]
    if previousPosition ~= nil then
        local deltaTime = math.max(tonumber(timeStep) or 0.016, 0)
        local smoothing = 1 - math.exp(-MARKER_SMOOTHING_RATE * deltaTime)
        displayPosition = previousPosition
            + (localPosition - previousPosition) * smoothing
    end
    self.cl.markerPositions[targetId] = displayPosition

    local isSelected = targetId == self.cl.selectedPlayerId
    local markerUuid = isSelected and SELECTED_MARKER_UUID or MARKER_UUID
    local marker = self.cl.markers[targetId]
    if marker == nil or self.cl.markerUuids[targetId] ~= markerUuid then
        if marker ~= nil then
            marker:stop()
            marker:destroy()
        end
        marker = sm.effect.createEffect("ShapeRenderable", self.shape)
        marker:setParameter("uuid", markerUuid)
        self.cl.markers[targetId] = marker
        self.cl.markerUuids[targetId] = markerUuid
    end

    marker:setOffsetPosition(displayPosition)
    marker:setOffsetRotation(
        sm.vec3.getRotation(sm.vec3.new(0, 1, 0), sm.vec3.new(1, 0, 0))
    )
    -- Selected targets use a dedicated yellow mesh as well as a larger dot.
    local markerScale = isSelected and 0.19 or 0.15
    marker:setScale(sm.vec3.new(markerScale, 1, markerScale))
    if not marker:isPlaying() then marker:start() end

    local label = self.cl.targetLabels[targetId]
    if self.cl.targetDataEnabled then
        if label == nil then
            label = sm.gui.createWorldIconGui(
                TARGET_LABEL_WIDTH,
                TARGET_LABEL_HEIGHT,
                TARGET_LABEL_LAYOUT,
                false
            )
            label:setMaxRenderDistance(TARGET_LABEL_MAX_RENDER_DISTANCE)
            label:setRequireLineOfSight(false)
            self.cl.targetLabels[targetId] = label
        end
        local paneHalfWidth = math.max(PANE_HALF_WIDTH - PANE_MARGIN, 0.01)
        local paneHalfHeight = math.max(PANE_HALF_HEIGHT - PANE_MARGIN, 0.01)
        local labelPosition = sm.vec3.new(
            TARGET_LABEL_DEPTH_OFFSET,
            clamp(
                displayPosition.y + TARGET_LABEL_HORIZONTAL_OFFSET,
                -paneHalfWidth,
                paneHalfWidth
            ),
            clamp(
                displayPosition.z + TARGET_LABEL_VERTICAL_OFFSET,
                -paneHalfHeight,
                paneHalfHeight
            )
        )
        local targetData = self.cl.visibleTargetData[targetId]
            or self.cl.visibleTargetData[tostring(targetId)]
        label:setText("TargetText", formatTargetData(targetId, targetPosition, self.shape, targetData))
        local labelWorldPosition = localToWorldPosition(self.shape, labelPosition)
        label:setWorldPosition(labelWorldPosition)
        local labelVisible = isPlayerWithinTargetLabelRange(self)
        if self.cl.targetLabelVisibility[targetId] ~= labelVisible then
            if labelVisible then
                label:open()
            else
                label:close()
            end
            self.cl.targetLabelVisibility[targetId] = labelVisible
        end
    elseif label ~= nil then
        label:close()
        self.cl.targetLabelVisibility[targetId] = false
    end
    activeMarkers[targetId] = true
end

function PlaneRadarScreen.cl_updateMarkers(self, timeStep)
    if self.cl == nil then return end

    local activeMarkers = {}
    for targetId, targetData in pairs(self.cl.visibleTargetData or {}) do
        local numericTargetId = tonumber(targetId)
        local targetPosition = type(targetData) == "table" and targetData.position or nil
        if numericTargetId ~= nil and targetPosition ~= nil
            and self.cl.visibleTargetIds[numericTargetId] == true then
            self:cl_updateMarker(numericTargetId, targetPosition, activeMarkers, timeStep)
        end
    end

    for playerId, marker in pairs(self.cl.markers) do
        if not activeMarkers[playerId] and marker:isPlaying() then
            marker:stop()
        end
        if not activeMarkers[playerId] then
            self.cl.markerPositions[playerId] = nil
            local label = self.cl.targetLabels[playerId]
            if label ~= nil then
                label:close()
            end
            self.cl.targetLabelVisibility[playerId] = nil
        end
    end
end

-- Keep the fixed-tick update, while also refreshing during render frames so a
-- moving physics target does not visibly outrun the marker.
function PlaneRadarScreen.client_onFixedUpdate(self, timeStep)
    self:cl_updateMarkers(timeStep)
end

function PlaneRadarScreen.client_onUpdate(self, timeStep)
    self:cl_updateMarkers(timeStep)
end

function PlaneRadarScreen.cl_getScreenLocalPosition(self, targetPosition)
    if not isTargetInSensorCone(
        self,
        targetPosition,
        self.cl.fovDegrees,
        self.cl.minimumDistanceBlocks,
        self.cl.maximumDistanceBlocks
    ) then
        return nil
    end

    local toTarget = targetPosition - self.shape.worldPosition
    local distance = toTarget:length()
    if distance <= 0.001 then return nil end

    -- Normalize first, then map the local direction directly to the display.
    -- This keeps marker movement proportional to
    -- target direction and tied to the same fixed tick as target updates.
    local targetLocal = toLocal(self.shape, toTarget / distance)
    local paneHalfWidth = math.max(PANE_HALF_WIDTH - PANE_MARGIN, 0.01)
    local paneHalfHeight = math.max(PANE_HALF_HEIGHT - PANE_MARGIN, 0.01)
    -- Each component of targetLocal is already in [-1, 1], so this is the
    -- normalized screen mapping and inherently keeps the dot inside the
    -- physical glass bounds.
    local paneX = clamp(targetLocal.y * paneHalfWidth, -paneHalfWidth, paneHalfWidth)
    local paneZ = clamp(targetLocal.z * paneHalfHeight, -paneHalfHeight, paneHalfHeight)
    return sm.vec3.new(MARKER_DEPTH_OFFSET, paneX, paneZ)
end
