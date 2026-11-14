dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
RadarDataScreen = class()

RadarDataScreen.maxParentCount = -1
RadarDataScreen.maxChildCount = -1
RadarDataScreen.connectionInput = sm.interactable.connectionType.logic
RadarDataScreen.connectionOutput = sm.interactable.connectionType.logic + sm.interactable.connectionType.bearing
RadarDataScreen.colorNormal = sm.color.new(0x8bd7e6ff)
RadarDataScreen.colorHighlight = sm.color.new(0xd7fbffff)

local RADAR_GLASS_UUID = "0307d97e-1016-4131-9ca2-7c1d653d3f69"
local MARKER_UUID = sm.uuid.new("fe538133-1a7c-4698-8410-377fdd68824a")
local SELECTED_MARKER_UUID = sm.uuid.new("6bd47f9b-4b9f-4fe0-8f6a-8acb1a54c9a2")
local POLAR_RING_UUIDS = {
    sm.uuid.new("4f9f5a19-2b80-4ce7-a2a2-1c2f6d9a1001"),
    sm.uuid.new("4f9f5a19-2b80-4ce7-a2a2-1c2f6d9a1002"),
    sm.uuid.new("4f9f5a19-2b80-4ce7-a2a2-1c2f6d9a1003"),
    sm.uuid.new("4f9f5a19-2b80-4ce7-a2a2-1c2f6d9a1004"),
    sm.uuid.new("4f9f5a19-2b80-4ce7-a2a2-1c2f6d9a1005"),
 }
local POLAR_RING_COUNT = 5
local POLAR_RING_STEP_BLOCKS = 1000
local POLAR_RING_MAX_DISTANCE_BLOCKS = POLAR_RING_COUNT * POLAR_RING_STEP_BLOCKS
local POLAR_RING_MAX_RADIUS = 0.38
local POLAR_RING_DEPTH_OFFSET = -0.001
local POLAR_RING_COLOR = sm.color.new(0x00ff00ff)
local REGISTRY_PREFIX = "PlaneRadarScreen:"
local BLOCKS_PER_WORLD_UNIT = 4.0
local DEFAULT_TARGET_DATA_ENABLED = true
local MARKER_DEPTH_OFFSET = 0.0
local TARGET_LABEL_PLAYER_DISTANCE_BLOCKS = 15.0
local TARGET_LABEL_DEPTH_OFFSET = 0.118
local TARGET_LABEL_HORIZONTAL_OFFSET = 0.0
local TARGET_LABEL_VERTICAL_OFFSET = -0.055
local TARGET_LABEL_MAX_RENDER_DISTANCE = 100
local TARGET_LABEL_WIDTH = 128
local TARGET_LABEL_HEIGHT = 72
local TARGET_LABEL_LAYOUT = PC_L.layout("PlaneRadarTargetData.layout")
local YELLOW_LOGIC_COLORS = { f5f071ff = true, e2db13ff = true, ["817c00ff"] = true, ["323000ff"] = true }
local BLACK_LOGIC_COLORS = { ["222222ff"] = true, ["111111ff"] = true, ["000000ff"] = true }
local WHITE_LOGIC_COLORS = { ["eeeeeeff"] = true, ["ffffffff"] = true, ["ddddddff"] = true }
local TRACKING_DEAD_ZONE = math.rad(1.5)
local TRACKING_GAIN = 2.5
local TRACKING_MIN_SPEED = 60
local MAX_IMPULSE = 5000
local TRACKING_ERROR_SMOOTHING = 0.2
-- The normal bearing follows the radar's signed PoV error directly. Keep this
-- in code so the user does not have to reverse the bearing manually.
local TRACKING_ROTATION_SIGN = 1.0
local CLOSE_TRACKING_RANGE_BLOCKS = 1000
local CLOSE_TRACKING_GAIN = 5.0
local CLOSE_TRACKING_MIN_SPEED = 120
local MIN_TARGET_MEMORY_SECONDS = 5.0
local MAX_TARGET_MEMORY_SECONDS = 10.0
local DEFAULT_DISPLAY_RANGE_BLOCKS = 1000
local MAX_DISPLAY_RANGE_BLOCKS = 5000
local TWO_PI = math.pi * 2

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function getRandomTargetMemorySeconds()
    return MIN_TARGET_MEMORY_SECONDS
        + math.random() * (MAX_TARGET_MEMORY_SECONDS - MIN_TARGET_MEMORY_SECONDS)
end

local function formatTargetData(targetId, targetData, targetPosition)
    local data = type(targetData) == "table" and targetData or {}
    return string.format(
        "%.0f km/h\n%.0f m",
        tonumber(data.speedKmh) or 0,
        tonumber(data.altitude) or (targetPosition ~= nil and targetPosition.z or 0)
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

local function normalizeAngle(angle)
    while angle > math.pi do angle = angle - TWO_PI end
    while angle < -math.pi do angle = angle + TWO_PI end
    return angle
end

-- Polar mode is a horizontal compass/range display. Do not let the target's
-- world height change either its azimuth or its displayed range.
local function horizontalize(vector)
    return sm.vec3.new(vector.x, vector.y, 0)
end

local function normalizeHorizontal(vector)
    local horizontal = horizontalize(vector)
    local length = horizontal:length()
    if length <= 0.001 then return nil end
    return horizontal / length
end

local function getHorizontalTrackingFrame(sensorForward, sensorSide)
    -- Plane Radar's actual PoV is centered on its local Right axis. Build a
    -- horizontal forward/side pair from that physical frame for bearing
    -- guidance; the data screen's own orientation is never used here.
    local forward = normalizeHorizontal(sensorForward)
    local side = normalizeHorizontal(sensorSide)
    if forward == nil and side ~= nil then
        forward = sm.vec3.new(-side.y, side.x, 0)
    elseif side == nil and forward ~= nil then
        side = sm.vec3.new(forward.y, -forward.x, 0)
    end
    if forward == nil or side == nil then return nil, nil end

    side = side - forward * side:dot(forward)
    local sideLength = side:length()
    if sideLength <= 0.001 then
        side = sm.vec3.new(forward.y, -forward.x, 0)
        sideLength = side:length()
    end
    if sideLength <= 0.001 then return nil, nil end
    return forward, side / sideLength
end

local function getPolarFrame(sensorRight, sensorAt)
    -- The polar scope's zero-degree direction is the radar's At axis. Its
    -- Right axis supplies the side direction. Flatten both axes first so
    -- target height cannot leak into the polar angle.
    local forward = normalizeHorizontal(sensorAt)
    local side = normalizeHorizontal(sensorRight)

    -- If the published frame is edge-on to the world-horizontal plane, one
    -- axis can have no horizontal component. Rebuild that missing axis from
    -- the other one instead of dropping every marker from the display.
    if forward == nil and side ~= nil then
        forward = sm.vec3.new(-side.y, side.x, 0)
    elseif side == nil and forward ~= nil then
        side = sm.vec3.new(forward.y, -forward.x, 0)
    end
    if forward == nil or side == nil then return nil, nil end

    -- Re-orthogonalize the flattened axes. This matters if the radar is
    -- pitched or rolled, because simply dropping Z can make the two vectors
    -- slightly non-perpendicular.
    side = side - forward * side:dot(forward)
    local sideLength = side:length()
    if sideLength <= 0.001 then
        side = sm.vec3.new(forward.y, -forward.x, 0)
        sideLength = side:length()
    end
    -- Reverse the radial screen axis so a target directly ahead is drawn at
    -- the top, and keep the side axis in the clockwise screen direction so a
    -- target moving clockwise also moves clockwise on the display. Bearing
    -- guidance uses the separate physical radar frame above.
    return forward * -1, side / sideLength
end

local function registryKey(interactable)
    return REGISTRY_PREFIX .. tostring(interactable:getId())
end

local function isColorInputActive(self, colors)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            local shape = parent:getShape()
            if shape ~= nil and colors[string.lower(tostring(shape:getColor()))] then return true end
        end
    end
    return false
end

local function isYellowInputActive(self)
    return isColorInputActive(self, YELLOW_LOGIC_COLORS)
end

local function isBasicInputActive(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            local shape = parent:getShape()
            local color = shape ~= nil and string.lower(tostring(shape:getColor())) or ""
            if not YELLOW_LOGIC_COLORS[color] and not BLACK_LOGIC_COLORS[color] and not WHITE_LOGIC_COLORS[color] then return true end
        end
    end
    return false
end

local function getTargetDistanceSquared(self, position)
    local sensorPosition = self.sv.sensorPosition or self.shape.worldPosition
    local offset = position - sensorPosition
    return offset:dot(offset)
end

local function getTargetScreenHorizontal(self, position)
    local sensorPosition = self.sv.sensorPosition or self.shape.worldPosition
    local sensorRight = self.sv.sensorRight or self.shape:getRight()
    local sensorAt = self.sv.sensorAt or self.shape:getAt()
    local offset = position - sensorPosition
    local distance = offset:length()
    if distance <= 0.001 then return 0 end

    if self.sv.polarRadar then
        local horizontalDirection = normalizeHorizontal(offset)
        local _, sideAxis = getPolarFrame(sensorRight, sensorAt)
        if horizontalDirection ~= nil and sideAxis ~= nil then
            return sideAxis:dot(horizontalDirection)
        end
    end

    -- The display's local Y axis is its horizontal screen axis. Negative is
    -- left and positive is right, matching cl_getMarkerPosition below.
    return sensorRight:dot(offset / distance)
end

function RadarDataScreen.server_onCreate(self) self:sv_initialize() end
function RadarDataScreen.server_onRefresh(self) self:sv_initialize() end
function RadarDataScreen.server_onDestroy(self)
    self.interactable:setActive(false)
    _G[registryKey(self.interactable)] = nil
end

function RadarDataScreen.sv_initialize(self)
    local stored = self.storage:load()
    self.sv = {
        selectedPlayerId = type(stored) == "table" and tonumber(stored.selectedPlayerId) or nil,
        bearingSpeed = clamp(type(stored) == "table" and tonumber(stored.bearingSpeed) or 30, 1, 360),
        polarRadar = type(stored) == "table" and stored.polarRadar == true or false,
        stationaryRadar = type(stored) == "table" and stored.stationaryRadar == true or false,
        rememberTargets = type(stored) == "table" and stored.rememberTargets == true or false,
        targetDataEnabled = true,
        knownTargets = {}, knownTargetData = {}, visibleTargets = {}, visibleTargetData = {},
        previousYellow = false, previousBlack = false,
        previousWhite = false, selectionCancelled = false, scanAngle = 0, sourceFovDegrees = 60,
        sourceMaximumDistanceBlocks = DEFAULT_DISPLAY_RANGE_BLOCKS,
        sensorPosition = nil, sensorRight = nil, sensorAt = nil, sensorUp = nil,
        trackingTargetId = nil, trackingError = nil, targetAges = {}, targetMemorySeconds = {},
        polarReferenceTargetId = nil, polarReferenceForward = nil,
        polarReferenceSide = nil, polarReferenceBearingAngles = {},
        sourceInRangeTargets = {}, outOfRangeTargets = {},
        reentryCorrectionPending = {}
    }
    self:sv_save()
    self:sv_publish()
end

function RadarDataScreen.sv_save(self)
    self.storage:save({
        selectedPlayerId = self.sv.selectedPlayerId,
        bearingSpeed = self.sv.bearingSpeed,
        polarRadar = self.sv.polarRadar,
        stationaryRadar = self.sv.stationaryRadar,
        rememberTargets = self.sv.rememberTargets
    })
end

function RadarDataScreen.sv_publish(self)
    local selectedTargetData = self.sv.knownTargetData[self.sv.selectedPlayerId]
    _G[registryKey(self.interactable)] = {
        selectedPlayerId = self.sv.selectedPlayerId,
        selectedTargetKind = type(selectedTargetData) == "table"
            and selectedTargetData.kind
            or nil,
        outputActive = self.interactable:isActive()
    }

    local displaySensorPosition = self.sv.sensorPosition
    local displaySensorRight = self.sv.sensorRight
    local displaySensorAt = self.sv.sensorAt
    local displaySensorUp = self.sv.sensorUp
    if self.sv.stationaryRadar then
        -- Stationary mode is a fixed map on this screen. Use this screen's
        -- own axes instead of freezing an arbitrary snapshot of the rotating
        -- radar, otherwise the map can start with a large angular offset.
        displaySensorRight = self.shape:getRight()
        displaySensorAt = self.shape:getAt()
        displaySensorUp = self.shape:getUp()
    end
    self.network:setClientData({
        selectedPlayerId = self.sv.selectedPlayerId, knownTargets = self.sv.knownTargets,
        targetData = self.sv.knownTargetData,
        targetDataEnabled = self.sv.targetDataEnabled ~= false,
        bearingSpeed = self.sv.bearingSpeed, polarRadar = self.sv.polarRadar,
        stationaryRadar = self.sv.stationaryRadar, rememberTargets = self.sv.rememberTargets,
        hasBearing = #self.interactable:getBearings() > 0,
        maximumDistanceBlocks = self.sv.sourceMaximumDistanceBlocks,
        sensorPosition = displaySensorPosition,
        sensorRight = displaySensorRight,
        sensorAt = displaySensorAt,
        sensorUp = displaySensorUp
    })
end

function RadarDataScreen.sv_getVisibleTargets(self)
    local targets = {}
    local inRangeTargets = {}
    local targetData = {}
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        local shape = parent:getShape()
        if shape ~= nil and tostring(sm.shape.getShapeUuid(shape)) == RADAR_GLASS_UUID then
            local data = _G[registryKey(parent)]
            if type(data) == "table" and type(data.visibleTargets) == "table" then
                self.sv.sourceFovDegrees = clamp(tonumber(data.fovDegrees) or 60, 10, 180)
                self.sv.sourceMaximumDistanceBlocks = clamp(
                    tonumber(data.maximumDistanceBlocks) or DEFAULT_DISPLAY_RANGE_BLOCKS,
                    1,
                    MAX_DISPLAY_RANGE_BLOCKS
                )
                self.sv.sensorPosition = data.sensorPosition
                self.sv.sensorRight = data.sensorRight
                self.sv.sensorAt = data.sensorAt
                self.sv.sensorUp = data.sensorUp
                self.sv.targetDataEnabled = data.targetDataEnabled ~= false
                for targetId, position in pairs(data.visibleTargets) do
                    local numericId = tonumber(targetId)
                    if numericId ~= nil and position ~= nil then targets[numericId] = position end
                end
                for targetId, value in pairs(data.targetData or {}) do
                    local numericId = tonumber(targetId)
                    if numericId ~= nil and type(value) == "table" then
                        targetData[numericId] = value
                    end
                end
                if type(data.inRangeTargets) == "table" then
                    for targetId, isInRange in pairs(data.inRangeTargets) do
                        local numericId = tonumber(targetId)
                        if numericId ~= nil and isInRange == true then inRangeTargets[numericId] = true end
                    end
                end
            end
        end
    end
    return targets, inRangeTargets, targetData
end

function RadarDataScreen.sv_cycleSelection(self)
    local targets = {}
    for targetId, position in pairs(self.sv.knownTargets) do
        table.insert(targets, {
            id = targetId,
            distanceSquared = getTargetDistanceSquared(self, position),
            screenHorizontal = getTargetScreenHorizontal(self, position)
        })
    end
    table.sort(targets, function(left, right)
        if self.sv.stationaryRadar and self.sv.polarRadar then
            if left.distanceSquared ~= right.distanceSquared then
                return left.distanceSquared < right.distanceSquared
            end
        elseif left.screenHorizontal ~= right.screenHorizontal then
            return left.screenHorizontal < right.screenHorizontal
        end
        return left.id < right.id
    end)

    local ids = {}
    for _, target in ipairs(targets) do table.insert(ids, target.id) end
    if #ids == 0 then self.sv.selectedPlayerId = nil return end
    local index = 0
    for i, targetId in ipairs(ids) do if targetId == self.sv.selectedPlayerId then index = i break end end
    self.sv.selectedPlayerId = ids[index % #ids + 1]
    self:sv_save()
end

function RadarDataScreen.sv_updateBearing(self, timeStep)
    local bearings = self.interactable:getBearings()
    if #bearings == 0 then return end

    -- Guidance may use only a target currently visible to the connected Plane
    -- Radar. The data screen keeps each last known position only until its
    -- individual memory timeout, and stale positions must never drive bearing.
    local selectedPosition = self.sv.selectedPlayerId
        and self.sv.visibleTargets[self.sv.selectedPlayerId]
        or nil

    local trackingError = nil
    local trackingDistanceBlocks = nil
    if selectedPosition ~= nil then
        local sensorPosition = self.sv.sensorPosition
        local sensorForward = self.sv.sensorRight
        local sensorSide = self.sv.sensorAt
        if sensorPosition ~= nil and sensorForward ~= nil and sensorSide ~= nil then
            local trackingForward, trackingSide = getHorizontalTrackingFrame(sensorForward, sensorSide)
            local direction = selectedPosition - sensorPosition
            trackingDistanceBlocks = direction:length() * BLOCKS_PER_WORLD_UNIT
            local horizontalDirection = normalizeHorizontal(direction)
            if horizontalDirection ~= nil and trackingForward ~= nil and trackingSide ~= nil then
                -- Zero error means the target is exactly in front of the
                -- physical Plane Radar. Guidance deliberately uses the radar
                -- frame, never the separately mounted data-screen frame.
                trackingError = math.atan2(
                    horizontalDirection:dot(trackingSide),
                    horizontalDirection:dot(trackingForward)
                )
            elseif horizontalDirection == nil then
                -- A target directly above/below has no horizontal azimuth.
                trackingError = 0
            end
        end
    end

    local scanVelocity = math.rad(self.sv.bearingSpeed)
    local trackingGain = TRACKING_GAIN
    local trackingMinimumSpeed = TRACKING_MIN_SPEED
    if trackingDistanceBlocks ~= nil and trackingDistanceBlocks < CLOSE_TRACKING_RANGE_BLOCKS then
        trackingGain = CLOSE_TRACKING_GAIN
        trackingMinimumSpeed = CLOSE_TRACKING_MIN_SPEED
    end
    local trackingMaxSpeed = math.rad(math.max(self.sv.bearingSpeed, trackingMinimumSpeed))
    for _, bearing in ipairs(bearings) do
        if trackingError ~= nil then
            if self.sv.trackingTargetId ~= self.sv.selectedPlayerId
                or self.sv.trackingError == nil then
                self.sv.trackingTargetId = self.sv.selectedPlayerId
                self.sv.trackingError = trackingError
            else
                local errorDelta = normalizeAngle(trackingError - self.sv.trackingError)
                self.sv.trackingError = normalizeAngle(
                    self.sv.trackingError + errorDelta * TRACKING_ERROR_SMOOTHING
                )
            end

            local filteredError = self.sv.trackingError
            if math.abs(filteredError) > TRACKING_DEAD_ZONE then
                -- The selected target's live PoV error is the control input.
                -- Apply the calibrated bearing direction so the normal
                -- connection turns toward the target.
                local trackingVelocity = clamp(
                    filteredError * trackingGain * TRACKING_ROTATION_SIGN,
                    -trackingMaxSpeed,
                    trackingMaxSpeed
                )
                bearing:setMotorVelocity(trackingVelocity, MAX_IMPULSE)
            else
                bearing:setMotorVelocity(0, MAX_IMPULSE)
            end
        else
            self.sv.trackingTargetId = nil
            self.sv.trackingError = nil
            -- Motor velocity provides a true continuous sweep. Repeatedly
            -- advancing a target angle can settle instead of rotating when
            -- the target list is empty.
            if self.sv.stationaryRadar then
                bearing:setMotorVelocity(scanVelocity, MAX_IMPULSE)
            else
                -- With Stationary radar disabled, leave the bearing still
                -- until selected-target guidance has an angle to apply.
                bearing:setMotorVelocity(0, MAX_IMPULSE)
            end
        end
    end
end

function RadarDataScreen.server_onFixedUpdate(self, timeStep)
    local currentInRangeTargets
    self.sv.visibleTargets, currentInRangeTargets, self.sv.visibleTargetData = self:sv_getVisibleTargets()
    for targetId in pairs(self.sv.knownTargets) do
        local wasInRange = self.sv.sourceInRangeTargets[targetId] == true
        local isInRange = currentInRangeTargets[targetId] == true
        if wasInRange and not isInRange then
            self.sv.outOfRangeTargets[targetId] = true
        elseif isInRange and self.sv.outOfRangeTargets[targetId] then
            -- Mark the transition only. The actual correction waits until the
            -- target is visible again so its current azimuth is available.
            self.sv.reentryCorrectionPending[targetId] = true
            self.sv.outOfRangeTargets[targetId] = nil
        end
    end
    self.sv.sourceInRangeTargets = currentInRangeTargets
    local whiteActive = isColorInputActive(self, WHITE_LOGIC_COLORS)
    local blackActive = isColorInputActive(self, BLACK_LOGIC_COLORS)
    if whiteActive and not self.sv.previousWhite then
        self.sv.knownTargets = {}
        self.sv.knownTargetData = {}
        self.sv.targetAges = {}
        self.sv.targetMemorySeconds = {}
        self.sv.sourceInRangeTargets = {}
        self.sv.outOfRangeTargets = {}
        self.sv.reentryCorrectionPending = {}
        self.sv.selectedPlayerId = nil
        self.sv.selectionCancelled = true
        self:sv_save()
    elseif not whiteActive then
        if not self.sv.rememberTargets then
            -- Without memory, the display mirrors the radar's current view.
            -- This also removes every client marker as soon as its target is no
            -- longer reported by the connected Plane Radar Screen.
            self.sv.knownTargets = {}
            self.sv.knownTargetData = {}
            self.sv.targetAges = {}
            self.sv.targetMemorySeconds = {}
            self.sv.outOfRangeTargets = {}
            self.sv.reentryCorrectionPending = {}
            for targetId, position in pairs(self.sv.visibleTargets) do
                self.sv.knownTargets[targetId] = position
                self.sv.knownTargetData[targetId] = self.sv.visibleTargetData[targetId]
            end
            if self.sv.selectedPlayerId ~= nil
                and self.sv.knownTargets[self.sv.selectedPlayerId] == nil then
                self.sv.selectedPlayerId = nil
            end
        else
            local deltaTime = tonumber(timeStep) or 0.025
            for targetId, age in pairs(self.sv.targetAges) do
                self.sv.targetAges[targetId] = age + deltaTime
            end
            for targetId, position in pairs(self.sv.visibleTargets) do
                if self.sv.targetMemorySeconds[targetId] == nil then
                    self.sv.targetMemorySeconds[targetId] = getRandomTargetMemorySeconds()
                end
                self.sv.knownTargets[targetId] = position
                self.sv.knownTargetData[targetId] = self.sv.visibleTargetData[targetId]
                self.sv.targetAges[targetId] = 0
            end
            for targetId, age in pairs(self.sv.targetAges) do
                if age > (self.sv.targetMemorySeconds[targetId] or MIN_TARGET_MEMORY_SECONDS) then
                    -- Remove the remembered position as well as its timer so the
                    -- client stops rendering the target marker after its individual
                    -- randomized memory window expires.
                    self.sv.targetAges[targetId] = nil
                    self.sv.targetMemorySeconds[targetId] = nil
                    self.sv.knownTargets[targetId] = nil
                    self.sv.knownTargetData[targetId] = nil
                    self.sv.outOfRangeTargets[targetId] = nil
                    self.sv.reentryCorrectionPending[targetId] = nil
                    if self.sv.selectedPlayerId == targetId then
                        self.sv.selectedPlayerId = nil
                    end
                end
            end
        end
    end
    if blackActive and not self.sv.previousBlack then
        self.sv.selectedPlayerId = nil
        self.sv.selectionCancelled = true
        self:sv_save()
    end
    if self.sv.selectedPlayerId == nil and not self.sv.selectionCancelled then self:sv_cycleSelection() end
    local yellowActive = isYellowInputActive(self)
    if yellowActive and not self.sv.previousYellow then
        self.sv.selectionCancelled = false
        self:sv_cycleSelection()
    end
    self.sv.previousYellow = yellowActive
    self.sv.previousBlack = blackActive
    self.sv.previousWhite = whiteActive
    local canCommit = self.sv.selectedPlayerId ~= nil and self.sv.visibleTargets[self.sv.selectedPlayerId] ~= nil
    self.interactable:setActive(isBasicInputActive(self) and canCommit)
    self:sv_updateBearing(timeStep)
    self:sv_publish()
end

function RadarDataScreen.sv_setBearingSpeed(self, value)
    local speed = clamp(math.floor((tonumber(value) or 1) + 0.5), 1, 360)
    if speed ~= self.sv.bearingSpeed then self.sv.bearingSpeed = speed self:sv_save() self:sv_publish() end
end

function RadarDataScreen.sv_setPolarRadar(self, requestedState)
    local polarRadar = requestedState == true
    if polarRadar == self.sv.polarRadar then return end
    self.sv.polarRadar = polarRadar
    self.sv.polarReferenceTargetId = nil
    self.sv.polarReferenceForward = nil
    self.sv.polarReferenceSide = nil
    self.sv.polarReferenceBearingAngles = {}
    self.sv.trackingTargetId = nil
    self.sv.trackingError = nil
    self:sv_save()
    self:sv_publish()
end

function RadarDataScreen.sv_setStationaryRadar(self, requestedState)
    local stationaryRadar = requestedState == true
    if stationaryRadar == self.sv.stationaryRadar then return end
    self.sv.stationaryRadar = stationaryRadar
    self.sv.polarReferenceTargetId = nil
    self.sv.polarReferenceForward = nil
    self.sv.polarReferenceSide = nil
    self.sv.polarReferenceBearingAngles = {}
    self.sv.trackingTargetId = nil
    self.sv.trackingError = nil
    self:sv_save()
    self:sv_publish()
end

function RadarDataScreen.sv_setRememberTargets(self, requestedState)
    local rememberTargets = requestedState == true
    if rememberTargets == self.sv.rememberTargets then return end
    self.sv.rememberTargets = rememberTargets
    if not rememberTargets then
        self.sv.knownTargets = {}
        self.sv.knownTargetData = {}
        self.sv.targetAges = {}
        self.sv.targetMemorySeconds = {}
        self.sv.outOfRangeTargets = {}
        self.sv.reentryCorrectionPending = {}
        self.sv.selectedPlayerId = nil
    end
    self:sv_save()
    self:sv_publish()
end

function RadarDataScreen.client_onCreate(self)
    self.cl = {
        selectedPlayerId = nil, knownTargets = {}, targetData = {}, bearingSpeed = 30, polarRadar = false,
        stationaryRadar = false, rememberTargets = false, hasBearing = false, sensorPosition = nil,
        maximumDistanceBlocks = DEFAULT_DISPLAY_RANGE_BLOCKS,
        sensorRight = nil, sensorAt = nil,
        sensorUp = nil, markers = {}, markerUuids = {}, polarRangeRings = {}, targetLabels = {}, gui = nil,
        targetLabelVisibility = {},
        targetDataEnabled = DEFAULT_TARGET_DATA_ENABLED
    }
end

function RadarDataScreen.client_onClientDataUpdate(self, data)
    self.cl.selectedPlayerId = tonumber(data.selectedPlayerId)
    self.cl.knownTargets = data.knownTargets or {}
    self.cl.targetData = data.targetData or {}
    self.cl.targetDataEnabled = data.targetDataEnabled ~= false
    self.cl.bearingSpeed = data.bearingSpeed or 30
    self.cl.polarRadar = data.polarRadar == true
    self.cl.stationaryRadar = data.stationaryRadar == true
    self.cl.rememberTargets = data.rememberTargets == true
    self.cl.hasBearing = data.hasBearing == true
    self.cl.maximumDistanceBlocks = data.maximumDistanceBlocks or DEFAULT_DISPLAY_RANGE_BLOCKS
    self.cl.sensorPosition = data.sensorPosition
    self.cl.sensorRight = data.sensorRight
    self.cl.sensorAt = data.sensorAt
    self.cl.sensorUp = data.sensorUp
    self:cl_refreshPolarRangeRings()
    self:cl_refreshGui()
end

function RadarDataScreen.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_radar_data_screen"))
    return true
end

function RadarDataScreen.client_onInteract(self, _, state)
    if not state then return end
    if self.cl.gui then self.cl.gui:destroy() end
    self.cl.gui = sm.gui.createGuiFromLayout(PC_L.layout("RadarDataScreen.layout"), false, { backgroundAlpha = 0.5 })
    self.cl.gui:createHorizontalSlider("BearingSpeedSlider", 360, self.cl.bearingSpeed - 1, "cl_onBearingSpeedChanged")
    self.cl.gui:setButtonCallback("PolarRadarButton", "cl_onPolarRadarPressed")
    self.cl.gui:setButtonCallback("PolarRadarButtonCompact", "cl_onPolarRadarPressed")
    self.cl.gui:setButtonCallback("StationaryRadarButton", "cl_onStationaryRadarPressed")
    self.cl.gui:setButtonCallback("RememberTargetsButton", "cl_onRememberTargetsPressed")
    self.cl.gui:setButtonCallback("RememberTargetsButtonCompact", "cl_onRememberTargetsPressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function RadarDataScreen.cl_onBearingSpeedChanged(self, position)
    self.cl.bearingSpeed = position + 1
    self:cl_refreshGui()
    self.network:sendToServer("sv_setBearingSpeed", self.cl.bearingSpeed)
end
function RadarDataScreen.cl_onPolarRadarPressed(self)
    self.cl.polarRadar = not self.cl.polarRadar
    self:cl_refreshPolarRangeRings()
    self:cl_refreshGui()
    self.network:sendToServer("sv_setPolarRadar", self.cl.polarRadar)
end
function RadarDataScreen.cl_onStationaryRadarPressed(self)
    self.cl.stationaryRadar = not self.cl.stationaryRadar
    self:cl_refreshGui()
    self.network:sendToServer("sv_setStationaryRadar", self.cl.stationaryRadar)
end
function RadarDataScreen.cl_onRememberTargetsPressed(self)
    self.cl.rememberTargets = not self.cl.rememberTargets
    self:cl_refreshGui()
    self.network:sendToServer("sv_setRememberTargets", self.cl.rememberTargets)
end
function RadarDataScreen.cl_onGuiClosed(self) if self.cl.gui then self.cl.gui:destroy() self.cl.gui = nil end end
function RadarDataScreen.cl_refreshGui(self)
    if self.cl.gui == nil then return end
    self.cl.gui:setText("BearingSpeedValueText", PC_L.get("scan_speed", self.cl.bearingSpeed))
    self.cl.gui:setButtonState("PolarRadarButton", self.cl.polarRadar)
    self.cl.gui:setButtonState("PolarRadarButtonCompact", self.cl.polarRadar)
    self.cl.gui:setButtonState("StationaryRadarButton", self.cl.stationaryRadar)
    self.cl.gui:setButtonState("RememberTargetsButton", self.cl.rememberTargets)
    self.cl.gui:setButtonState("RememberTargetsButtonCompact", self.cl.rememberTargets)
    self.cl.gui:setVisible("BearingSpeedValue", self.cl.hasBearing)
    self.cl.gui:setVisible("BearingSpeedSlider", self.cl.hasBearing)
    self.cl.gui:setVisible("BearingHint", not self.cl.hasBearing)
    self.cl.gui:setVisible("PolarRadarButton", self.cl.hasBearing)
    self.cl.gui:setVisible("PolarRadarLabel", self.cl.hasBearing)
    self.cl.gui:setVisible("StationaryRadarButton", self.cl.hasBearing)
    self.cl.gui:setVisible("StationaryRadarLabel", self.cl.hasBearing)
    self.cl.gui:setVisible("RememberTargetsButton", self.cl.hasBearing)
    self.cl.gui:setVisible("RememberTargetsLabel", self.cl.hasBearing)
    self.cl.gui:setVisible("PolarRadarButtonCompact", not self.cl.hasBearing)
    self.cl.gui:setVisible("PolarRadarLabelCompact", not self.cl.hasBearing)
    self.cl.gui:setVisible("RememberTargetsButtonCompact", not self.cl.hasBearing)
    self.cl.gui:setVisible("RememberTargetsLabelCompact", not self.cl.hasBearing)
end

function RadarDataScreen.cl_destroyPolarRangeRings(self)
    for _, ring in pairs(self.cl.polarRangeRings or {}) do
        if ring:isPlaying() then ring:stop() end
        ring:destroy()
    end
    self.cl.polarRangeRings = {}
end

function RadarDataScreen.cl_refreshPolarRangeRings(self)
    if self.cl == nil then return end

    if not self.cl.polarRadar then
        self:cl_destroyPolarRangeRings()
        return
    end

    -- The rings are static scope marks, so do not recreate them on every
    -- target update. They only need to exist while polar radar is enabled.
    if #self.cl.polarRangeRings == POLAR_RING_COUNT then return end

    self:cl_destroyPolarRangeRings()
    local rotation = sm.vec3.getRotation(
        sm.vec3.new(0, 1, 0),
        sm.vec3.new(1, 0, 0)
    )

    for index = 1, POLAR_RING_COUNT do
        local ring = sm.effect.createEffect("ShapeRenderable", self.shape)
        ring:setParameter("uuid", POLAR_RING_UUIDS[index])
        ring:setParameter("color", POLAR_RING_COLOR)
        ring:setOffsetPosition(sm.vec3.new(POLAR_RING_DEPTH_OFFSET, 0, 0))
        ring:setOffsetRotation(rotation)

        ring:setScale(sm.vec3.new(1, 1, 1))
        ring:start()
        self.cl.polarRangeRings[index] = ring
    end
end

function RadarDataScreen.cl_getMarkerPosition(self, worldPosition)
    -- The data screen is only a display for the connected Plane Radar Screen.
    -- In normal mode, project targets in the radar's coordinate frame so this
    -- screen can be placed independently. In polar mode, use the same frame
    -- to calculate azimuth and range, then draw a top-down radar scope.
    local sensorPosition = self.cl.sensorPosition or self.shape.worldPosition
    local sensorRight = self.cl.sensorRight or self.shape:getRight()
    local sensorAt = self.cl.sensorAt or self.shape:getAt()
    local sensorUp = self.cl.sensorUp or self.shape:getUp()
    local offset = worldPosition - sensorPosition
    local distance = offset:length()
    if distance <= 0.001 then return nil end

    if self.cl.polarRadar then
        local horizontalOffset = horizontalize(offset)
        local horizontalDistance = horizontalOffset:length()
        local forwardAxis, sideAxis = getPolarFrame(sensorRight, sensorAt)
        if forwardAxis == nil or sideAxis == nil then return nil end
        local range = clamp(
            horizontalDistance * BLOCKS_PER_WORLD_UNIT / math.max(self.cl.maximumDistanceBlocks, 1),
            0,
            1
        ) * 0.38

        -- 0 degrees is forward/up on the scope; positive angles progress
        -- clockwise. The screen's local Y/Z plane becomes the scope plane.
        if horizontalDistance <= 0.001 then
            return sm.vec3.new(MARKER_DEPTH_OFFSET, 0, 0)
        end
        local horizontalDirection = horizontalOffset / horizontalDistance
        return sm.vec3.new(
            MARKER_DEPTH_OFFSET,
            sideAxis:dot(horizontalDirection) * range,
            forwardAxis:dot(horizontalDirection) * range
        )
    end

    local direction = offset / distance
    local localDirection = sm.vec3.new(
        sensorRight:dot(direction),
        sensorAt:dot(direction),
        sensorUp:dot(direction)
    )
    return sm.vec3.new(0.106, clamp(localDirection.y * 0.38, -0.38, 0.38), clamp(localDirection.z * 0.38, -0.38, 0.38))
end

function RadarDataScreen.client_onUpdate(self, _)
    local active = {}
    for targetId, position in pairs(self.cl.knownTargets) do
        local markerPosition = self:cl_getMarkerPosition(position)
        if markerPosition ~= nil then
            local selected = tonumber(targetId) == self.cl.selectedPlayerId
            local uuid = selected and SELECTED_MARKER_UUID or MARKER_UUID
            local marker = self.cl.markers[targetId]
            if marker == nil or self.cl.markerUuids[targetId] ~= uuid then
                if marker ~= nil then marker:stop() marker:destroy() end
                marker = sm.effect.createEffect("ShapeRenderable", self.shape)
                marker:setParameter("uuid", uuid)
                self.cl.markers[targetId], self.cl.markerUuids[targetId] = marker, uuid
            end
            marker:setOffsetPosition(markerPosition)
            marker:setOffsetRotation(sm.vec3.getRotation(sm.vec3.new(0, 1, 0), sm.vec3.new(1, 0, 0)))
            local scale = selected and 0.19 or 0.15
            marker:setScale(sm.vec3.new(scale, 1, scale))
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
                local labelPosition = sm.vec3.new(
                    TARGET_LABEL_DEPTH_OFFSET,
                    clamp(markerPosition.y + TARGET_LABEL_HORIZONTAL_OFFSET, -0.38, 0.38),
                    clamp(markerPosition.z + TARGET_LABEL_VERTICAL_OFFSET, -0.38, 0.38)
                )
                label:setText(
                    "TargetText",
                    formatTargetData(targetId, self.cl.targetData[targetId], position)
                )
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
            active[targetId] = true
        end
    end
    for targetId, marker in pairs(self.cl.markers) do
        if not active[targetId] then
            if marker:isPlaying() then marker:stop() end
            marker:destroy()
            self.cl.markers[targetId] = nil
            self.cl.markerUuids[targetId] = nil
            local label = self.cl.targetLabels[targetId]
            if label ~= nil then label:close() end
            self.cl.targetLabelVisibility[targetId] = nil
        end
    end
end

function RadarDataScreen.client_onDestroy(self)
    if self.cl == nil then return end
    if self.cl.gui then self.cl.gui:destroy() end
    self:cl_destroyPolarRangeRings()
    for _, marker in pairs(self.cl.markers) do if marker:isPlaying() then marker:stop() end marker:destroy() end
    for _, label in pairs(self.cl.targetLabels or {}) do label:close() label:destroy() end
    self.cl.targetLabels = {}
end
