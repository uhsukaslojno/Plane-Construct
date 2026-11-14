dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneControllerTest = class()

PlaneControllerTest.maxParentCount = 4
PlaneControllerTest.maxChildCount = -1
PlaneControllerTest.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.logic
PlaneControllerTest.connectionOutput = sm.interactable.connectionType.bearing + sm.interactable.connectionType.logic
PlaneControllerTest.colorNormal = sm.color.new(0x0a3ee2ff)
PlaneControllerTest.colorHighlight = sm.color.new(0x4c6fe3ff)

local DEFAULT_ANGLE_LIMIT = 25
local MIN_ANGLE_LIMIT = 1
local MAX_ANGLE_LIMIT = 90
local DEFAULT_SENSITIVITY = 3
local MIN_SENSITIVITY = 1
local MAX_SENSITIVITY = 10
local DEFAULT_AXIS_OFFSET = 0
local MIN_AXIS_OFFSET = -90
local MAX_AXIS_OFFSET = 90
local DEFAULT_DAMPING = 0
local MIN_DAMPING = 0
local MAX_DAMPING = 20
local DAMPING_SPEED_REFERENCES = {
    500, 450, 400, 350, 300, 250, 200, 150, 100, 50,
    45, 40, 35, 30, 25, 20, 15, 10, 5, 1
}
local DEFAULT_WHITE_BEARING_ANGLE = 90
local MIN_WHITE_BEARING_ANGLE = 0
local MAX_WHITE_BEARING_ANGLE = 180
local DEFAULT_TRACK_CLOSEST_PLAYER = false
local DEFAULT_TRACK_TARGET = "closest"
local DEFAULT_PREDICT_TARGET = false
local DEFAULT_DISTANCE_ACTIVATION = 50
local MIN_DISTANCE_ACTIVATION = 0
local MAX_DISTANCE_ACTIVATION = 200
local DEFAULT_TRACKING_POV_ENABLED = true
local DEFAULT_TRACKING_FOV_DEGREES = 60
local MIN_TRACKING_FOV_DEGREES = 10
local MAX_TRACKING_FOV_DEGREES = 180
local TRACK_ROLL_LEVELING_THRESHOLD = math.rad(12)
local TRACK_ROLL_LEVELING_STRENGTH = 0.35
local PREDICTION_MAX_TIME = 2.5
local PREDICTION_MIN_CLOSING_SPEED = 5.0
local PREDICTION_MAX_ACCELERATION = 30.0
local PREDICTION_ACCELERATION_SMOOTHING = 0.25
local MAX_FINAL_TARGET_ANGLE = math.rad(180)
local TARGET_VELOCITY = 3.0
local MAX_IMPULSE = 5000
local SIDE_DEAD_ZONE = 0.05
local BLOCKS_PER_WORLD_UNIT = 4.0
local ACCELERATION_OUTPUT_THRESHOLD = 650.0
local OVERSHOOT_MAX_DISTANCE_BLOCKS = 300.0
local OVERSHOOT_MIN_DISTANCE_INCREASE_PER_SECOND = 10.0
local OVERSHOOT_REQUIRED_INCREASING_SAMPLES = 2
local OVERSHOOT_TARGET_RETENTION_SECONDS = 5.0
local TRACK_LOSS_DISTANCE_BLOCKS = 500.0
local PLANE_RADAR_SCREEN_UUID = "0307d97e-1016-4131-9ca2-7c1d653d3f69"
local RADAR_DATA_SCREEN_UUID = "9e1fd450-3e60-4ce8-86dd-e0ee5ced4b77"
local PLANE_RADAR_REGISTRY_PREFIX = "PlaneRadarScreen:"
local PRESENCE_REGISTRY_NAME = "PlaneConstructPresenceTargets"
local WORLD_UP = sm.vec3.new(0, 0, 1)
local TWO_PI = math.pi * 2
local WHITE_LOGIC_COLOR = "eeeeeeff"
local BLACK_LOGIC_COLOR = "222222ff"
local RED_LOGIC_COLORS = {
    f06767ff = true,
    d02525ff = true,
    ["7c0000ff"] = true,
    ["560202ff"] = true
}
local BLUE_LOGIC_COLOR = "0a3ee2ff"
local WHITE_BEARING_COLOR = "eeeeeeff"

-- Every shade in the corresponding vanilla paint-tool column is accepted.
local AILERON_COLORS = {
    f06767ff = true,
    d02525ff = true,
    ["7c0000ff"] = true,
    ["560202ff"] = true
}

local ELEVATOR_COLORS = {
    ["4c6fe3ff"] = true,
    ["0a3ee2ff"] = true,
    ["0f2e91ff"] = true,
    ["0a1d5aff"] = true
}

local RUDDER_COLORS = {
    f5f071ff = true,
    e2db13ff = true,
    ["817c00ff"] = true,
    ["323000ff"] = true
}

local ELEVON_COLORS = {
    ae79f0ff = true,
    ["7514edff"] = true,
    ["500aa6ff"] = true,
    ["35086cff"] = true
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function sensitivityMultiplier(level)
    if level == 1 then return 0.25 end
    if level == 2 then return 0.5 end
    if level == 3 then return 1.0 end
    return (level - 3) * 2.0
end

local function bearingRole(bearing)
    local color = string.lower(tostring(bearing:getColor()))
    if color == WHITE_BEARING_COLOR then return "logic" end
    if AILERON_COLORS[color] then return "aileron" end
    if ELEVATOR_COLORS[color] then return "elevator" end
    if RUDDER_COLORS[color] then return "rudder" end
    if ELEVON_COLORS[color] then return "elevon" end
    return nil
end

function PlaneControllerTest.server_onCreate(self)
    self:sv_initialize()
end

function PlaneControllerTest.server_onRefresh(self)
    self:sv_initialize()
end

function PlaneControllerTest.sv_initialize(self)
    local stored = self.storage:load()
    local storedLimit = type(stored) == "table" and tonumber(stored.angleLimit) or nil
    local storedSensitivity = type(stored) == "table" and tonumber(stored.sensitivity) or nil
    local storedRollOffset = type(stored) == "table" and tonumber(stored.rollOffset) or nil
    local storedPitchOffset = type(stored) == "table" and tonumber(stored.pitchOffset) or nil
    local storedYawOffset = type(stored) == "table" and tonumber(stored.yawOffset) or nil
    local storedDamping = type(stored) == "table" and tonumber(stored.damping) or nil
    local storedWhiteBearingAngle = type(stored) == "table" and tonumber(stored.whiteBearingAngle) or nil
    local storedTrackClosestPlayer = type(stored) == "table" and stored.trackClosestPlayer == true or false
    local storedTrackTarget = type(stored) == "table" and stored.trackTarget or DEFAULT_TRACK_TARGET
    if type(storedTrackTarget) ~= "number" and storedTrackTarget ~= DEFAULT_TRACK_TARGET then
        storedTrackTarget = DEFAULT_TRACK_TARGET
    end
    local storedPredictTarget = (type(stored) == "table" and stored.predictTarget == true or false)
        and storedTrackClosestPlayer
    local storedDistanceActivationEnabled = type(stored) == "table"
        and stored.distanceActivationEnabled == true
        and storedTrackClosestPlayer
    local storedDistanceActivation = type(stored) == "table" and tonumber(stored.distanceActivation) or nil
    local storedTrackingPovEnabled = not (
        type(stored) == "table" and stored.trackingPovEnabled == false
    )
    local storedTrackingFovDegrees = type(stored) == "table" and tonumber(stored.trackingFovDegrees) or nil
    local storedExceptionPlayerIds = type(stored) == "table" and stored.exceptionPlayerIds or {}
    if type(storedExceptionPlayerIds) ~= "table" then
        storedExceptionPlayerIds = {}
    end

    self.sv = {
        angleLimit = clamp(math.floor((storedLimit or DEFAULT_ANGLE_LIMIT) + 0.5), MIN_ANGLE_LIMIT, MAX_ANGLE_LIMIT),
        sensitivity = clamp(
            math.floor((storedSensitivity or DEFAULT_SENSITIVITY) + 0.5),
            MIN_SENSITIVITY,
            MAX_SENSITIVITY
        ),
        rollOffset = clamp(math.floor((storedRollOffset or DEFAULT_AXIS_OFFSET) + 0.5), MIN_AXIS_OFFSET, MAX_AXIS_OFFSET),
        pitchOffset = clamp(math.floor((storedPitchOffset or DEFAULT_AXIS_OFFSET) + 0.5), MIN_AXIS_OFFSET, MAX_AXIS_OFFSET),
        yawOffset = clamp(math.floor((storedYawOffset or DEFAULT_AXIS_OFFSET) + 0.5), MIN_AXIS_OFFSET, MAX_AXIS_OFFSET),
        damping = clamp(math.floor((storedDamping or DEFAULT_DAMPING) + 0.5), MIN_DAMPING, MAX_DAMPING),
        whiteBearingAngle = clamp(
            math.floor((storedWhiteBearingAngle or DEFAULT_WHITE_BEARING_ANGLE) + 0.5),
            MIN_WHITE_BEARING_ANGLE,
            MAX_WHITE_BEARING_ANGLE
        ),
        trackClosestPlayer = storedTrackClosestPlayer,
        trackTarget = storedTrackTarget,
        predictTarget = storedPredictTarget,
        distanceActivationEnabled = storedDistanceActivationEnabled,
        distanceActivation = clamp(
            math.floor((storedDistanceActivation or DEFAULT_DISTANCE_ACTIVATION) + 0.5),
            MIN_DISTANCE_ACTIVATION,
            MAX_DISTANCE_ACTIVATION
        ),
        trackingPovEnabled = storedTrackingPovEnabled,
        trackingFovDegrees = clamp(
            math.floor((storedTrackingFovDegrees or DEFAULT_TRACKING_FOV_DEGREES) + 0.5),
            MIN_TRACKING_FOV_DEGREES,
            MAX_TRACKING_FOV_DEGREES
        ),
        exceptionPlayerIds = storedExceptionPlayerIds
    }

    self.svPreviousVelocity = self.shape:getVelocity()
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_syncClientData(self)
    self.network:setClientData({
        angleLimit = self.sv.angleLimit,
        sensitivity = self.sv.sensitivity,
        rollOffset = self.sv.rollOffset,
        pitchOffset = self.sv.pitchOffset,
        yawOffset = self.sv.yawOffset,
        damping = self.sv.damping,
        whiteBearingAngle = self.sv.whiteBearingAngle,
        trackClosestPlayer = self.sv.trackClosestPlayer,
        trackTarget = self.sv.trackTarget,
        predictTarget = self.sv.predictTarget,
        distanceActivationEnabled = self.sv.distanceActivationEnabled,
        distanceActivation = self.sv.distanceActivation,
        trackingPovEnabled = self.sv.trackingPovEnabled,
        trackingFovDegrees = self.sv.trackingFovDegrees
    })
end

function PlaneControllerTest.sv_setAngleLimit(self, requestedLimit)
    local numericLimit = tonumber(requestedLimit)
    if numericLimit == nil then return end

    local angleLimit = clamp(math.floor(numericLimit + 0.5), MIN_ANGLE_LIMIT, MAX_ANGLE_LIMIT)
    if angleLimit == self.sv.angleLimit then return end

    self.sv.angleLimit = angleLimit
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setSensitivity(self, requestedSensitivity)
    local numericSensitivity = tonumber(requestedSensitivity)
    if numericSensitivity == nil then return end

    local sensitivity = clamp(
        math.floor(numericSensitivity + 0.5),
        MIN_SENSITIVITY,
        MAX_SENSITIVITY
    )
    if sensitivity == self.sv.sensitivity then return end

    self.sv.sensitivity = sensitivity
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setAxisOffset(self, params)
    if type(params) ~= "table" then return end

    local field = params.axis == "roll" and "rollOffset"
        or params.axis == "pitch" and "pitchOffset"
        or params.axis == "yaw" and "yawOffset"
        or nil
    local numericOffset = tonumber(params.value)
    if field == nil or numericOffset == nil then return end

    local offset = clamp(math.floor(numericOffset + 0.5), MIN_AXIS_OFFSET, MAX_AXIS_OFFSET)
    if offset == self.sv[field] then return end

    self.sv[field] = offset
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setDamping(self, requestedDamping)
    local numericDamping = tonumber(requestedDamping)
    if numericDamping == nil then return end

    local damping = clamp(math.floor(numericDamping + 0.5), MIN_DAMPING, MAX_DAMPING)
    if damping == self.sv.damping then return end

    self.sv.damping = damping
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setWhiteBearingAngle(self, requestedAngle)
    local numericAngle = tonumber(requestedAngle)
    if numericAngle == nil then return end

    local angle = clamp(
        math.floor(numericAngle + 0.5),
        MIN_WHITE_BEARING_ANGLE,
        MAX_WHITE_BEARING_ANGLE
    )
    if angle == self.sv.whiteBearingAngle then return end

    self.sv.whiteBearingAngle = angle
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setTrackClosestPlayer(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.trackClosestPlayer then return end

    self.sv.trackClosestPlayer = requestedState
    if not requestedState then
        self.sv.predictTarget = false
    end
    self.svPreviousHorizontalError = nil
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setTrackTarget(self, requestedTarget)
    if requestedTarget ~= DEFAULT_TRACK_TARGET and type(requestedTarget) ~= "number" then
        return
    end

    if type(requestedTarget) == "number" then
        local player = self:sv_getPlayerById(requestedTarget)
        local presence = self:sv_getPresenceTargetById(requestedTarget)
        if player == nil and presence == nil then return end
    end

    if requestedTarget == self.sv.trackTarget then return end

    self.sv.trackTarget = requestedTarget
    self.svPreviousHorizontalError = nil
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setPredictTarget(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.predictTarget then return end

    self.sv.predictTarget = requestedState
    self:sv_resetPredictionState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setDistanceActivationEnabled(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.distanceActivationEnabled then return end

    self.sv.distanceActivationEnabled = requestedState
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setDistanceActivation(self, requestedDistance)
    local numericDistance = tonumber(requestedDistance)
    if numericDistance == nil then return end

    local distance = clamp(
        math.floor(numericDistance + 0.5),
        MIN_DISTANCE_ACTIVATION,
        MAX_DISTANCE_ACTIVATION
    )
    if distance == self.sv.distanceActivation then return end

    self.sv.distanceActivation = distance
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setTrackingFovDegrees(self, requestedFov)
    local numericFov = tonumber(requestedFov)
    if numericFov == nil then return end

    local fovDegrees = clamp(
        math.floor(numericFov + 0.5),
        MIN_TRACKING_FOV_DEGREES,
        MAX_TRACKING_FOV_DEGREES
    )
    if fovDegrees == self.sv.trackingFovDegrees then return end

    self.sv.trackingFovDegrees = fovDegrees
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_setTrackingPovEnabled(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.trackingPovEnabled then return end

    self.sv.trackingPovEnabled = requestedState
    self.svPreviousHorizontalError = nil
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneControllerTest.sv_resetPredictionState(self)
    self.svTrackedPlayerId = nil
    self.svTrackedPlayerVelocity = nil
    self.svTrackedPlayerAcceleration = sm.vec3.new(0, 0, 0)
    self.svTrackedPlayerSpeed = 0
end

function PlaneControllerTest.sv_resetOvershootState(self)
    self.svPreviousTargetId = nil
    self.svPreviousTargetDistanceBlocks = nil
    self.svPreviousTargetDistanceDeltaBlocks = nil
    self.svOvershootWasClosing = false
    self.svOvershootIncreasingSamples = 0
    self.svOvershootTargetId = nil
    self.svOvershootTargetKind = nil
    self.svOvershootTargetMissingTime = 0
end

function PlaneControllerTest.sv_getOvershootTargetCharacter(self)
    if self.svOvershootTargetId == nil then return nil end

    -- A "Closest" target is stored by character ID so the controller keeps
    -- monitoring the same player even after that player leaves the tracking
    -- cone. Explicit player/presence selections are stored by configured ID.
    if self.svOvershootTargetKind == "character" then
        for _, player in ipairs(sm.player.getAllPlayers()) do
            local character = player:getCharacter()
            if character ~= nil and sm.exists(character) then
                local characterId = character.id or character:getId()
                if characterId == self.svOvershootTargetId then
                    return character
                end
            end
        end
        return nil
    end

    local presence = self:sv_getPresenceTargetById(self.svOvershootTargetId)
    if presence ~= nil then
        return presence
    end

    local player = self:sv_getPlayerById(self.svOvershootTargetId)
    if player == nil then return nil end

    local character = player:getCharacter()
    return character ~= nil and sm.exists(character) and character or nil
end

function PlaneControllerTest.sv_getPredictedTargetPosition(self, targetCharacter, timeStep)
    local currentPosition = targetCharacter.worldPosition
    local currentVelocity = targetCharacter.velocity or sm.vec3.new(0, 0, 0)
    local targetId = targetCharacter.id or targetCharacter:getId()
    local acceleration = sm.vec3.new(0, 0, 0)

    if self.svTrackedPlayerId == targetId and self.svTrackedPlayerVelocity ~= nil and timeStep ~= nil and timeStep > 0 then
        local measuredAcceleration = (currentVelocity - self.svTrackedPlayerVelocity) / timeStep
        local accelerationLength = measuredAcceleration:length()
        if accelerationLength > PREDICTION_MAX_ACCELERATION then
            measuredAcceleration = measuredAcceleration / accelerationLength * PREDICTION_MAX_ACCELERATION
        end

        local previousAcceleration = self.svTrackedPlayerAcceleration or sm.vec3.new(0, 0, 0)
        acceleration = previousAcceleration * (1.0 - PREDICTION_ACCELERATION_SMOOTHING)
            + measuredAcceleration * PREDICTION_ACCELERATION_SMOOTHING
    end

    self.svTrackedPlayerId = targetId
    self.svTrackedPlayerVelocity = currentVelocity
    self.svTrackedPlayerAcceleration = acceleration
    self.svTrackedPlayerSpeed = currentVelocity:length()

    local toTarget = currentPosition - self.shape.worldPosition
    local distance = toTarget:length()
    if distance <= 0.001 then
        return currentPosition
    end

    local targetDirection = toTarget / distance
    local aircraftSpeed = self.shape:getVelocity():length()
    local targetSpeedAlongLine = currentVelocity:dot(targetDirection)
    local closingSpeed = math.max(aircraftSpeed - targetSpeedAlongLine, PREDICTION_MIN_CLOSING_SPEED)
    local predictionTime = math.min(distance / closingSpeed, PREDICTION_MAX_TIME)

    return currentPosition + currentVelocity * predictionTime
        + acceleration * (0.5 * predictionTime * predictionTime)
end

function PlaneControllerTest.sv_getSeatParent(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.seated) then
            return parent
        end
    end

    return nil
end

function PlaneControllerTest.sv_getControllingCharacter(self)
    local seat = self:sv_getSeatParent()
    if seat == nil then return nil end

    local seatedCharacter = seat:getSeatCharacter()
    return seatedCharacter ~= nil and sm.exists(seatedCharacter) and seatedCharacter or nil
end

function PlaneControllerTest.sv_getSeatControls(self)
    local seat = self:sv_getSeatParent()
    if seat == nil then return 0, 0 end

    local seatedCharacter = seat:getSeatCharacter()
    if seatedCharacter == nil or not sm.exists(seatedCharacter) then return 0, 0 end

    local rollInput = clamp(tonumber(seat:getSteeringAngle()) or 0, -1, 1)
    local pitchInput = clamp(tonumber(seat:getPower()) or 0, -1, 1)
    -- W pitches down and S pitches up, matching conventional aircraft controls.
    return rollInput, -pitchInput
end

function PlaneControllerTest.sv_getPlayerById(self, playerId)
    for _, player in ipairs(sm.player.getAllPlayers()) do
        if player:getId() == playerId then
            return player
        end
    end

    return nil
end

function PlaneControllerTest.sv_getPresenceTargetById(self, targetId)
    local target = (_G[PRESENCE_REGISTRY_NAME] or {})[targetId]
    if type(target) ~= "table" or target.active ~= true or target.position == nil then
        return nil
    end

    return {
        id = target.id or targetId,
        worldPosition = target.position,
        velocity = target.velocity or sm.vec3.new(0, 0, 0)
    }
end

function PlaneControllerTest.sv_getConnectedRadarTarget(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            local parentShape = parent:getShape()
            if parentShape ~= nil and (
                tostring(sm.shape.getShapeUuid(parentShape)) == PLANE_RADAR_SCREEN_UUID
                or tostring(sm.shape.getShapeUuid(parentShape)) == RADAR_DATA_SCREEN_UUID
            ) then
                local radarData = _G[PLANE_RADAR_REGISTRY_PREFIX .. tostring(parent:getId())]
                if type(radarData) == "table" then
                    local selectedPlayerId = tonumber(radarData.selectedPlayerId)
                    if selectedPlayerId ~= nil then
                        return selectedPlayerId
                    end
                end
            end
        end
    end

    return nil
end

function PlaneControllerTest.sv_isPlayerException(self, playerId)
    for _, exceptionPlayerId in ipairs(self.sv.exceptionPlayerIds) do
        if tonumber(exceptionPlayerId) == playerId then
            return true
        end
    end

    return false
end

function PlaneControllerTest.sv_addPlayerException(self, playerId)
    if playerId == nil or self:sv_isPlayerException(playerId) then
        return
    end

    table.insert(self.sv.exceptionPlayerIds, playerId)
    self.storage:save(self.sv)
end

function PlaneControllerTest.sv_getClosestPlayer(self)
    local closestPlayer = nil
    local closestCharacter = nil
    local closestDistanceSquared = math.huge

    for _, player in ipairs(sm.player.getAllPlayers()) do
        if not self:sv_isPlayerException(player:getId()) then
            local character = player:getCharacter()
            if character ~= nil and sm.exists(character)
                and self:sv_isTargetInsideTrackingPov(character.worldPosition) then
                local offset = character.worldPosition - self.shape.worldPosition
                local distanceSquared = offset:dot(offset)
                if distanceSquared < closestDistanceSquared then
                    closestDistanceSquared = distanceSquared
                    closestPlayer = player
                    closestCharacter = character
                end
            end
        end
    end

    return closestPlayer, closestCharacter
end

function PlaneControllerTest.sv_isTargetInsideTrackingPov(self, targetPosition)
    if not self.sv.trackingPovEnabled then return true end

    local toTarget = targetPosition - self.shape.worldPosition
    local distance = toTarget:length()
    if distance <= 0.001 then return true end

    -- This is a near-range lock-loss rule. At long range the controller
    -- keeps its target; at 500 blocks or closer, it uses its configured cone.
    if distance * BLOCKS_PER_WORLD_UNIT > TRACK_LOSS_DISTANCE_BLOCKS then
        return true
    end

    local forward = self.shape:getUp()
    local forwardLength = forward:length()
    if forwardLength <= 0.001 then return true end

    local direction = toTarget / distance
    local facingDot = clamp((forward / forwardLength):dot(direction), -1, 1)
    return math.acos(facingDot) <= math.rad(self.sv.trackingFovDegrees) * 0.5
end

function PlaneControllerTest.sv_getClosestPlayerCharacter(self)
    local _, closestCharacter = self:sv_getClosestPlayer()
    return closestCharacter
end

function PlaneControllerTest.sv_getTrackTargetCharacter(self)
    if self.sv.trackTarget == DEFAULT_TRACK_TARGET then
        return self:sv_getClosestPlayerCharacter()
    end

    local presence = self:sv_getPresenceTargetById(self.sv.trackTarget)
    if presence ~= nil then
        return self:sv_isTargetInsideTrackingPov(presence.worldPosition) and presence or nil
    end

    local player = self:sv_getPlayerById(self.sv.trackTarget)
    if player == nil then return nil end

    local character = player:getCharacter()
    if character == nil or not sm.exists(character) then return nil end
    return self:sv_isTargetInsideTrackingPov(character.worldPosition) and character or nil
end

function PlaneControllerTest.sv_isLogicInputActive(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            return true
        end
    end

    return false
end

function PlaneControllerTest.sv_isLogicColorActive(self, color)
    for _, parent in ipairs(self.interactable:getParents()) do
        local parentColor = string.lower(tostring(parent:getShape():getColor()))
        local colorMatches = type(color) == "table" and color[parentColor] == true or parentColor == color
        if parent:hasOutputType(sm.interactable.connectionType.logic)
            and parent:isActive()
            and colorMatches then
            return true
        end
    end

    return false
end

function PlaneControllerTest.sv_getHorizonDemands(self)
    local shapeForward = self.shape:getUp()
    local horizontalForwardLength = math.sqrt(
        shapeForward.x * shapeForward.x + shapeForward.y * shapeForward.y
    )
    local pitchDemand = -math.atan2(shapeForward.z, horizontalForwardLength)
    local rollDemand = -math.atan2(self.shape:getRight().z, self.shape:getAt().z)
    local limit = math.rad(self.sv.angleLimit)

    return clamp(rollDemand, -limit, limit), clamp(pitchDemand, -limit, limit)
end

function PlaneControllerTest.sv_updateLogicOutput(self, timeStep)
    local targetInRange = false
    local overshootDetected = false

    if self.sv.trackClosestPlayer then
        local targetCharacter = self:sv_getTrackTargetCharacter()
        if targetCharacter ~= nil then
            if self.sv.trackTarget == DEFAULT_TRACK_TARGET then
                self.svOvershootTargetId = targetCharacter.id or targetCharacter:getId()
                self.svOvershootTargetKind = "character"
            else
                self.svOvershootTargetId = self.sv.trackTarget
                self.svOvershootTargetKind = "configured"
            end
            self.svOvershootTargetMissingTime = 0
        elseif self.svOvershootTargetId ~= nil then
            -- Steering still obeys PoV, but distance monitoring keeps the
            -- acquired target briefly after it moves behind the aircraft.
            self.svOvershootTargetMissingTime = self.svOvershootTargetMissingTime
                + math.max(tonumber(timeStep) or 0, 0)
            if self.svOvershootTargetMissingTime <= OVERSHOOT_TARGET_RETENTION_SECONDS then
                targetCharacter = self:sv_getOvershootTargetCharacter()
            else
                self:sv_resetOvershootState()
            end
        end

        if targetCharacter ~= nil then
            local targetId = targetCharacter.id or targetCharacter:getId()
            local distanceBlocks = (targetCharacter.worldPosition - self.shape.worldPosition):length()
                * BLOCKS_PER_WORLD_UNIT
            targetInRange = distanceBlocks <= self.sv.distanceActivation

            if self.svPreviousTargetId == targetId
                and self.svPreviousTargetDistanceBlocks ~= nil
                and timeStep ~= nil and timeStep > 0 then
                local distanceDeltaBlocks = distanceBlocks - self.svPreviousTargetDistanceBlocks
                local distanceIncreasePerSecond = distanceDeltaBlocks / timeStep

                -- Keep the closing state across the closest-approach frame. In
                -- an aerial flyby, range normally starts growing slowly before
                -- it reaches the configured increase threshold.
                if distanceDeltaBlocks < 0 then
                    self.svOvershootWasClosing = true
                    self.svOvershootIncreasingSamples = 0
                elseif distanceDeltaBlocks > 0 and self.svOvershootWasClosing then
                    self.svOvershootIncreasingSamples = self.svOvershootIncreasingSamples + 1
                elseif distanceDeltaBlocks > 0 then
                    self.svOvershootIncreasingSamples = 0
                end

                overshootDetected = distanceBlocks <= OVERSHOOT_MAX_DISTANCE_BLOCKS
                    and self.svOvershootWasClosing
                    and self.svOvershootIncreasingSamples >= OVERSHOOT_REQUIRED_INCREASING_SAMPLES
                    and distanceIncreasePerSecond >= OVERSHOOT_MIN_DISTANCE_INCREASE_PER_SECOND

                if overshootDetected then
                    -- Emit a one-update pulse. A later closing phase can arm
                    -- the detector again for the same target.
                    self.svOvershootWasClosing = false
                    self.svOvershootIncreasingSamples = 0
                end

                self.svPreviousTargetDistanceDeltaBlocks = distanceDeltaBlocks
            else
                self.svOvershootWasClosing = false
                self.svOvershootIncreasingSamples = 0
                self.svPreviousTargetDistanceDeltaBlocks = nil
            end

            self.svPreviousTargetId = targetId
            self.svPreviousTargetDistanceBlocks = distanceBlocks
        else
            self:sv_resetOvershootState()
        end
    else
        self:sv_resetOvershootState()
    end

    if self.sv.trackClosestPlayer and self.sv.distanceActivationEnabled then
        self.interactable:setActive(targetInRange or overshootDetected)
        return
    end

    local currentVelocity = self.shape:getVelocity()
    local previousVelocity = self.svPreviousVelocity or currentVelocity
    self.svPreviousVelocity = currentVelocity

    local accelerationBlocks = 0
    if timeStep ~= nil and timeStep > 0 then
        accelerationBlocks = (currentVelocity - previousVelocity):length()
            * BLOCKS_PER_WORLD_UNIT / timeStep
    end

    self.interactable:setActive(
        accelerationBlocks > ACCELERATION_OUTPUT_THRESHOLD or overshootDetected
    )
end

function PlaneControllerTest.sv_getTargetAngles(self, direction)
    if direction == nil then return 0, 0 end

    -- Keep the input frame level with the world. The sensor lens defines the
    -- aircraft's compass heading, while roll cannot tilt the input frame.
    local shapeForward = self.shape:getUp()
    local levelForward = shapeForward - WORLD_UP * shapeForward:dot(WORLD_UP)
    local levelForwardLength = levelForward:length()

    if levelForwardLength > 0.001 then
        levelForward = levelForward / levelForwardLength
        self.svLastLevelForward = levelForward
    elseif self.svLastLevelForward ~= nil then
        levelForward = self.svLastLevelForward
    else
        local lookForward = direction - WORLD_UP * direction:dot(WORLD_UP)
        local lookForwardLength = lookForward:length()
        levelForward = lookForwardLength > 0.001 and lookForward / lookForwardLength or sm.vec3.new(1, 0, 0)
        self.svLastLevelForward = levelForward
    end

    local worldRight = levelForward:cross(WORLD_UP)
    local forwardAmount = direction:dot(levelForward)
    local rightAmount = direction:dot(worldRight)
    local upAmount = direction:dot(WORLD_UP)
    local horizontalAmount = math.sqrt(forwardAmount * forwardAmount + rightAmount * rightAmount)
    local targetElevation = math.atan2(upAmount, horizontalAmount)
    local controllerElevation = math.atan2(shapeForward:dot(WORLD_UP), levelForwardLength)

    local horizontalError = math.atan2(rightAmount, forwardAmount)
    if forwardAmount <= 0 and self.svPreviousHorizontalError ~= nil then
        while horizontalError - self.svPreviousHorizontalError > math.pi do
            horizontalError = horizontalError - TWO_PI
        end
        while horizontalError - self.svPreviousHorizontalError < -math.pi do
            horizontalError = horizontalError + TWO_PI
        end
    end
    self.svPreviousHorizontalError = horizontalError

    -- Compute the target error in world yaw/elevation, then rotate that error
    -- pair by the creation's roll so a banked aircraft keeps pitch and yaw
    -- stable.
    local verticalError = targetElevation - controllerElevation
    local rightZ = self.shape:getRight().z
    local upZ = self.shape:getAt().z
    local rollProjectionLength = math.sqrt(rightZ * rightZ + upZ * upZ)
    local creationRoll = self.svLastCreationRoll or 0
    if rollProjectionLength > 0.001 then
        creationRoll = math.atan2(rightZ, upZ)
        self.svLastCreationRoll = creationRoll
    end
    local rollCos = math.cos(creationRoll)
    local rollSin = math.sin(creationRoll)
    local rollAdjustedVerticalError = verticalError * rollCos + horizontalError * rollSin
    local rollAdjustedHorizontalError = -verticalError * rollSin + horizontalError * rollCos

    local multiplier = sensitivityMultiplier(self.sv.sensitivity)
    local scaledHorizontalError = rollAdjustedHorizontalError * multiplier
    local scaledVerticalError = rollAdjustedVerticalError * multiplier
    local limit = math.rad(self.sv.angleLimit)

    return clamp(scaledHorizontalError, -limit, limit), clamp(scaledVerticalError, -limit, limit), horizontalError
end

function PlaneControllerTest.sv_getSideSign(self, bearing)
    local lateralOffset = (bearing.worldPosition - self.shape.worldPosition):dot(self.shape:getRight())
    if lateralOffset > SIDE_DEAD_ZONE then return 1 end
    if lateralOffset < -SIDE_DEAD_ZONE then return -1 end

    -- A centered bearing has no discoverable left/right side. Treat it as the
    -- right side; the Connect Tool's reverse option can correct its direction.
    return 1
end

function PlaneControllerTest.sv_setBearingsNeutral(self, bearings)
    self.svPreviousHorizontalError = nil
    for _, bearing in ipairs(bearings) do
        bearing:setTargetAngle(0, TARGET_VELOCITY, MAX_IMPULSE)
    end
end

function PlaneControllerTest.server_onFixedUpdate(self, timeStep)
    self:sv_updateLogicOutput(timeStep)

    local bearings = self.interactable:getBearings()

    -- A connected Radar Screen publishes its yellow-selected player through
    -- the shared server registry. The radar's active basic output both starts
    -- tracking and commits the selected target here.
    if self.sv.trackClosestPlayer then
        local radarTargetId = self:sv_getConnectedRadarTarget()
        if radarTargetId ~= nil and self.sv.trackTarget ~= radarTargetId then
            self.sv.trackTarget = radarTargetId
            self.storage:save(self.sv)
            self:sv_syncClientData()
        end
    end

    local redLogicActive = self:sv_isLogicColorActive(RED_LOGIC_COLORS)
    if self.sv.trackClosestPlayer and redLogicActive and not self.svPreviousRedLogicActive then
        local closestPlayer = self:sv_getClosestPlayer()
        if closestPlayer ~= nil then
            self:sv_addPlayerException(closestPlayer:getId())
        end
    end
    self.svPreviousRedLogicActive = redLogicActive

    if #bearings == 0 then return end

    local character = nil
    local targetCharacter = nil
    if self.sv.trackClosestPlayer then
        if not self:sv_isLogicInputActive() then
            self:sv_resetPredictionState()
            self:sv_setBearingsNeutral(bearings)
            return
        end
        targetCharacter = self:sv_getTrackTargetCharacter()
    else
        self:sv_resetPredictionState()
        character = self:sv_getControllingCharacter()
        targetCharacter = character
    end

    -- Camera mode requires an occupied connected seat. Player tracking mode
    -- can use either the closest eligible player or a manually selected player.
    if targetCharacter == nil then
        self:sv_resetPredictionState()
        self:sv_setBearingsNeutral(bearings)
        return
    end

    local rollInput, pitchInput = 0, 0
    if not self.sv.trackClosestPlayer then
        rollInput, pitchInput = self:sv_getSeatControls()
    end
    local blueLogicActive = self:sv_isLogicColorActive(BLUE_LOGIC_COLOR)
    local manualInputLimit = math.rad(self.sv.angleLimit)
    local rollDemand, pitchDemand, yawDemand

    if self:sv_isLogicColorActive(BLACK_LOGIC_COLOR) then
        self:sv_resetPredictionState()
        self.svPreviousHorizontalError = nil
        local horizonRollDemand, horizonPitchDemand = self:sv_getHorizonDemands()
        rollDemand = horizonRollDemand + math.rad(self.sv.rollOffset)
        pitchDemand = horizonPitchDemand + math.rad(self.sv.pitchOffset)
        yawDemand = math.rad(self.sv.yawOffset)
    elseif self.sv.trackClosestPlayer then
        local targetPosition = targetCharacter.worldPosition
        if self.sv.predictTarget then
            targetPosition = self:sv_getPredictedTargetPosition(targetCharacter, timeStep)
        else
            self:sv_resetPredictionState()
        end

        local targetDirection = targetPosition - self.shape.worldPosition
        if targetDirection:length() <= 0.001 then
            self:sv_setBearingsNeutral(bearings)
            return
        end

        local horizontalError, verticalError, targetHeadingError = self:sv_getTargetAngles(targetDirection)
        local targetRollDemand = horizontalError + math.rad(self.sv.rollOffset)
        rollDemand = targetRollDemand
        if math.abs(targetHeadingError) <= TRACK_ROLL_LEVELING_THRESHOLD then
            local horizonRollDemand = self:sv_getHorizonDemands()
            local levelledRollDemand = horizonRollDemand + math.rad(self.sv.rollOffset)
            rollDemand = targetRollDemand
                + (levelledRollDemand - targetRollDemand) * TRACK_ROLL_LEVELING_STRENGTH
        end
        pitchDemand = verticalError + math.rad(self.sv.pitchOffset)
        yawDemand = horizontalError + math.rad(self.sv.yawOffset)
    else
        local manualInputActive = math.abs(rollInput) > 0.001 or math.abs(pitchInput) > 0.001
        local cameraDisabled = manualInputActive or self:sv_isLogicColorActive(WHITE_LOGIC_COLOR)
        local horizontalError, verticalError = 0, 0
        if cameraDisabled then
            self.svPreviousHorizontalError = nil
        else
            horizontalError, verticalError = self:sv_getTargetAngles(character.direction)
        end

        rollDemand = horizontalError + rollInput * manualInputLimit + math.rad(self.sv.rollOffset)
        pitchDemand = verticalError + pitchInput * manualInputLimit + math.rad(self.sv.pitchOffset)
        yawDemand = horizontalError + math.rad(self.sv.yawOffset)
    end

    local dampingMultiplier = 1.0
    if self.sv.damping > 0 then
        local dampingLevelValue = DAMPING_SPEED_REFERENCES[self.sv.damping] or 1
        local linearSpeed = self.shape:getVelocity():length()
        dampingMultiplier = dampingLevelValue / (linearSpeed + dampingLevelValue)
    end

    for _, bearing in ipairs(bearings) do
        local role = bearingRole(bearing)
        if role ~= nil then
            local sideSign = self:sv_getSideSign(bearing)
            local targetAngle = 0

            if role == "logic" then
                targetAngle = blueLogicActive and math.rad(self.sv.whiteBearingAngle) or 0
            elseif role == "aileron" then
                targetAngle = -rollDemand * sideSign
            elseif role == "elevator" then
                targetAngle = pitchDemand
            elseif role == "rudder" then
                targetAngle = yawDemand
            elseif role == "elevon" then
                targetAngle = pitchDemand - rollDemand * sideSign
            end

            if role ~= "logic" then
                targetAngle = targetAngle * dampingMultiplier
            end
            -- Target movement was already capped by Degrees limit before the
            -- axis offset was added. Keep only a broad physical safety bound,
            -- allowing offsets to shift beyond the first slider's range.
            targetAngle = clamp(targetAngle, -MAX_FINAL_TARGET_ANGLE, MAX_FINAL_TARGET_ANGLE)
            -- Target angles are expressed in the bearing's own coordinate
            -- system. The Connect Tool reverses that coordinate system, so
            -- compensating for bearing.reversed here would cancel reversal.
            bearing:setTargetAngle(targetAngle, TARGET_VELOCITY, MAX_IMPULSE)
        end
    end
end

function PlaneControllerTest.client_onCreate(self)
    self.cl = {
        angleLimit = DEFAULT_ANGLE_LIMIT,
        sensitivity = DEFAULT_SENSITIVITY,
        rollOffset = DEFAULT_AXIS_OFFSET,
        pitchOffset = DEFAULT_AXIS_OFFSET,
        yawOffset = DEFAULT_AXIS_OFFSET,
        damping = DEFAULT_DAMPING,
        whiteBearingAngle = DEFAULT_WHITE_BEARING_ANGLE,
        trackClosestPlayer = DEFAULT_TRACK_CLOSEST_PLAYER,
        trackTarget = DEFAULT_TRACK_TARGET,
        predictTarget = DEFAULT_PREDICT_TARGET,
        distanceActivationEnabled = false,
        distanceActivation = DEFAULT_DISTANCE_ACTIVATION,
        trackingPovEnabled = DEFAULT_TRACKING_POV_ENABLED,
        trackingFovDegrees = DEFAULT_TRACKING_FOV_DEGREES,
        targetOptionIds = {},
        targetOptionNames = {},
        gui = nil
    }
end

function PlaneControllerTest.client_onClientDataUpdate(self, data)
    self.cl.angleLimit = data.angleLimit or DEFAULT_ANGLE_LIMIT
    self.cl.sensitivity = data.sensitivity or DEFAULT_SENSITIVITY
    self.cl.rollOffset = data.rollOffset or DEFAULT_AXIS_OFFSET
    self.cl.pitchOffset = data.pitchOffset or DEFAULT_AXIS_OFFSET
    self.cl.yawOffset = data.yawOffset or DEFAULT_AXIS_OFFSET
    self.cl.damping = data.damping or DEFAULT_DAMPING
    self.cl.whiteBearingAngle = data.whiteBearingAngle or DEFAULT_WHITE_BEARING_ANGLE
    self.cl.trackClosestPlayer = data.trackClosestPlayer or DEFAULT_TRACK_CLOSEST_PLAYER
    self.cl.trackTarget = data.trackTarget or DEFAULT_TRACK_TARGET
    self.cl.predictTarget = data.predictTarget or DEFAULT_PREDICT_TARGET
    self.cl.distanceActivationEnabled = data.distanceActivationEnabled == true
    self.cl.distanceActivation = data.distanceActivation or DEFAULT_DISTANCE_ACTIVATION
    self.cl.trackingPovEnabled = data.trackingPovEnabled ~= false
    self.cl.trackingFovDegrees = data.trackingFovDegrees or DEFAULT_TRACKING_FOV_DEGREES
    self:cl_refreshGui()
end

function PlaneControllerTest.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneControllerTest.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_plane_controller"))
    return true
end

function PlaneControllerTest.cl_buildTargetOptions(self)
    local options = { "Closest" }
    local optionIds = { Closest = DEFAULT_TRACK_TARGET }
    local optionNames = { [DEFAULT_TRACK_TARGET] = "Closest" }
    local usedNames = { Closest = true }

    for _, player in ipairs(sm.player.getAllPlayers()) do
        local playerId = player:getId()
        local playerName = player:getName()
        if playerName == nil or playerName == "" then
            playerName = string.format("Player %d", playerId)
        end

        local optionName = playerName
        if usedNames[optionName] then
            optionName = string.format("%s [%d]", playerName, playerId)
        end
        while usedNames[optionName] do
            optionName = optionName .. " "
        end

        usedNames[optionName] = true
        optionIds[optionName] = playerId
        optionNames[playerId] = optionName
        table.insert(options, optionName)
    end

    local presenceOptions = {}
    for targetId, target in pairs(_G[PRESENCE_REGISTRY_NAME] or {}) do
        local numericTargetId = tonumber(targetId) or tonumber(target.id)
        if numericTargetId ~= nil and target.active == true then
            table.insert(presenceOptions, {
                id = numericTargetId,
                name = target.name or ("Player Presence [" .. tostring(numericTargetId) .. "]")
            })
        end
    end
    table.sort(presenceOptions, function(left, right)
        return left.id < right.id
    end)

    for _, presence in ipairs(presenceOptions) do
        local optionName = presence.name
        while usedNames[optionName] do
            optionName = optionName .. " "
        end

        usedNames[optionName] = true
        optionIds[optionName] = presence.id
        optionNames[presence.id] = optionName
        table.insert(options, optionName)
    end

    self.cl.targetOptionIds = optionIds
    self.cl.targetOptionNames = optionNames
    return options
end

function PlaneControllerTest.client_onInteract(self, _, state)
    if not state then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneControllerTest.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "AngleSlider",
        MAX_ANGLE_LIMIT,
        self.cl.angleLimit - MIN_ANGLE_LIMIT,
        "cl_onAngleSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "SensitivitySlider",
        MAX_SENSITIVITY,
        self.cl.sensitivity - MIN_SENSITIVITY,
        "cl_onSensitivitySliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "RollOffsetSlider",
        MAX_AXIS_OFFSET - MIN_AXIS_OFFSET + 1,
        self.cl.rollOffset - MIN_AXIS_OFFSET,
        "cl_onRollOffsetSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "PitchOffsetSlider",
        MAX_AXIS_OFFSET - MIN_AXIS_OFFSET + 1,
        self.cl.pitchOffset - MIN_AXIS_OFFSET,
        "cl_onPitchOffsetSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "YawOffsetSlider",
        MAX_AXIS_OFFSET - MIN_AXIS_OFFSET + 1,
        self.cl.yawOffset - MIN_AXIS_OFFSET,
        "cl_onYawOffsetSliderChanged"
    )
    self.cl.gui:createVerticalSlider(
        "DampingSlider",
        MAX_DAMPING - MIN_DAMPING + 1,
        self.cl.damping - MIN_DAMPING,
        "cl_onDampingSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "WhiteBearingAngleSlider",
        MAX_WHITE_BEARING_ANGLE - MIN_WHITE_BEARING_ANGLE + 1,
        self.cl.whiteBearingAngle - MIN_WHITE_BEARING_ANGLE,
        "cl_onWhiteBearingAngleSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "DistanceActivationSlider",
        MAX_DISTANCE_ACTIVATION - MIN_DISTANCE_ACTIVATION + 1,
        self.cl.distanceActivation - MIN_DISTANCE_ACTIVATION,
        "cl_onDistanceActivationSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "TrackingFovSlider",
        MAX_TRACKING_FOV_DEGREES - MIN_TRACKING_FOV_DEGREES + 1,
        self.cl.trackingFovDegrees - MIN_TRACKING_FOV_DEGREES,
        "cl_onTrackingFovSliderChanged"
    )
    self.cl.gui:createDropDown(
        "TargetPlayerDropDown",
        "cl_onTargetPlayerSelected",
        self:cl_buildTargetOptions()
    )
    self.cl.gui:setButtonCallback("TrackClosestPlayerButton", "cl_onTrackClosestPlayerPressed")
    self.cl.gui:setButtonCallback("TrackingPovButton", "cl_onTrackingPovPressed")
    self.cl.gui:setButtonCallback("PredictTargetButton", "cl_onPredictTargetPressed")
    self.cl.gui:setButtonCallback("DistanceActivationButton", "cl_onDistanceActivationPressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneControllerTest.cl_onAngleSliderChanged(self, sliderPosition)
    self.cl.angleLimit = sliderPosition + MIN_ANGLE_LIMIT
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAngleLimit", self.cl.angleLimit)
end

function PlaneControllerTest.cl_onSensitivitySliderChanged(self, sliderPosition)
    self.cl.sensitivity = sliderPosition + MIN_SENSITIVITY
    self:cl_refreshGui()
    self.network:sendToServer("sv_setSensitivity", self.cl.sensitivity)
end

function PlaneControllerTest.cl_onRollOffsetSliderChanged(self, sliderPosition)
    self.cl.rollOffset = sliderPosition + MIN_AXIS_OFFSET
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAxisOffset", { axis = "roll", value = self.cl.rollOffset })
end

function PlaneControllerTest.cl_onPitchOffsetSliderChanged(self, sliderPosition)
    self.cl.pitchOffset = sliderPosition + MIN_AXIS_OFFSET
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAxisOffset", { axis = "pitch", value = self.cl.pitchOffset })
end

function PlaneControllerTest.cl_onYawOffsetSliderChanged(self, sliderPosition)
    self.cl.yawOffset = sliderPosition + MIN_AXIS_OFFSET
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAxisOffset", { axis = "yaw", value = self.cl.yawOffset })
end

function PlaneControllerTest.cl_onDampingSliderChanged(self, sliderPosition)
    self.cl.damping = sliderPosition + MIN_DAMPING
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDamping", self.cl.damping)
end

function PlaneControllerTest.cl_onWhiteBearingAngleSliderChanged(self, sliderPosition)
    self.cl.whiteBearingAngle = sliderPosition + MIN_WHITE_BEARING_ANGLE
    self:cl_refreshGui()
    self.network:sendToServer("sv_setWhiteBearingAngle", self.cl.whiteBearingAngle)
end

function PlaneControllerTest.cl_onTrackClosestPlayerPressed(self)
    self.cl.trackClosestPlayer = not self.cl.trackClosestPlayer
    if not self.cl.trackClosestPlayer then
        self.cl.predictTarget = false
    end
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackClosestPlayer", self.cl.trackClosestPlayer)
end

function PlaneControllerTest.cl_onTrackingPovPressed(self)
    self.cl.trackingPovEnabled = not self.cl.trackingPovEnabled
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackingPovEnabled", self.cl.trackingPovEnabled)
end

function PlaneControllerTest.cl_onTargetPlayerSelected(self, selectedOption)
    local target = self.cl.targetOptionIds[selectedOption]
    if target == nil then return end

    self.cl.trackTarget = target
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackTarget", target)
end

function PlaneControllerTest.cl_onPredictTargetPressed(self)
    self.cl.predictTarget = not self.cl.predictTarget
    self:cl_refreshGui()
    self.network:sendToServer("sv_setPredictTarget", self.cl.predictTarget)
end

function PlaneControllerTest.cl_onDistanceActivationPressed(self)
    self.cl.distanceActivationEnabled = not self.cl.distanceActivationEnabled
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDistanceActivationEnabled", self.cl.distanceActivationEnabled)
end

function PlaneControllerTest.cl_onDistanceActivationSliderChanged(self, sliderPosition)
    self.cl.distanceActivation = sliderPosition + MIN_DISTANCE_ACTIVATION
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDistanceActivation", self.cl.distanceActivation)
end

function PlaneControllerTest.cl_onTrackingFovSliderChanged(self, sliderPosition)
    self.cl.trackingFovDegrees = sliderPosition + MIN_TRACKING_FOV_DEGREES
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackingFovDegrees", self.cl.trackingFovDegrees)
end

function PlaneControllerTest.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    if not self.cl.trackClosestPlayer then
        self.cl.predictTarget = false
    end
    self.cl.gui:setText("AngleValue", PC_L.get("angle_limit", self.cl.angleLimit))
    self.cl.gui:setText("SensitivityValue", PC_L.get("sensitivity_value", self.cl.sensitivity))
    self.cl.gui:setText("RollOffsetValue", PC_L.get("roll_offset_value", self.cl.rollOffset))
    self.cl.gui:setText("PitchOffsetValue", PC_L.get("pitch_offset_value", self.cl.pitchOffset))
    self.cl.gui:setText("YawOffsetValue", PC_L.get("yaw_offset_value", self.cl.yawOffset))
    self.cl.gui:setText("DampingValue", PC_L.get("damping_value", self.cl.damping))
    self.cl.gui:setText(
        "WhiteBearingAngleValue",
        PC_L.get("flaps_angle", self.cl.whiteBearingAngle)
    )
    self.cl.gui:setButtonState("TrackClosestPlayerButton", self.cl.trackClosestPlayer)
    self.cl.gui:setButtonState("TrackingPovButton", self.cl.trackingPovEnabled)
    self.cl.gui:setButtonState("PredictTargetButton", self.cl.predictTarget)
    self.cl.gui:setButtonState("DistanceActivationButton", self.cl.distanceActivationEnabled)
    self.cl.gui:setText(
        "DistanceActivationValueText",
        PC_L.get("distance_activation", self.cl.distanceActivation)
    )
    self.cl.gui:setText(
        "TrackingFovValueText",
        PC_L.get("tracking_pov_value", self.cl.trackingFovDegrees)
    )
    local selectedOption = self.cl.targetOptionNames[self.cl.trackTarget]
    if selectedOption ~= nil then
        self.cl.gui:setSelectedDropDownItem("TargetPlayerDropDown", selectedOption)
    end
    self.cl.gui:setVisible("TrackPlayerLabel", true)
    self.cl.gui:setVisible("TrackingPovButton", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("TrackingPovLabel", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("TargetPlayerLabel", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("TargetPlayerDropDown", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("PredictTargetButton", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("PredictTargetLabel", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("DistanceActivationButton", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("DistanceActivationLabel", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible(
        "DistanceActivationValue",
        self.cl.trackClosestPlayer and self.cl.distanceActivationEnabled
    )
    self.cl.gui:setVisible(
        "DistanceActivationSlider",
        self.cl.trackClosestPlayer and self.cl.distanceActivationEnabled
    )
    self.cl.gui:setVisible("TrackingFovValue", self.cl.trackClosestPlayer and self.cl.trackingPovEnabled)
    self.cl.gui:setVisible("TrackingFovSlider", self.cl.trackClosestPlayer and self.cl.trackingPovEnabled)
    self.cl.gui:setVisible("DampingHint", self.cl.damping > 10)
end

function PlaneControllerTest.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
