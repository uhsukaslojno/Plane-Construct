dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneController = class()

if PlaneConstructLaserGuidanceTargets == nil then PlaneConstructLaserGuidanceTargets = {} end

PlaneController.maxParentCount = 4
PlaneController.maxChildCount = -1
PlaneController.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.logic
PlaneController.connectionOutput = sm.interactable.connectionType.bearing + sm.interactable.connectionType.logic
PlaneController.colorNormal = sm.color.new(0x0a3ee2ff)
PlaneController.colorHighlight = sm.color.new(0x4c6fe3ff)

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
local DEFAULT_HEAT_SEEKER = false
local DEFAULT_OBSTACLES = false
local DEFAULT_OVERSHOOT_ENABLED = true
local DEFAULT_ACCELERATION_OUTPUT_ENABLED = true
local DEFAULT_IMPACT_SENSITIVITY = 500
local MIN_IMPACT_SENSITIVITY = 100
local MAX_IMPACT_SENSITIVITY = 2000
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
local PREDICTION_NEAR_DISTANCE_BLOCKS = 100.0
local PREDICTION_MIN_DISTANCE_SCALE = 0.35
local PREDICTION_SHALLOW_APPROACH_DEGREES = 30.0
local PREDICTION_MIN_SHALLOW_APPROACH_SCALE = 0.5
local MAX_FINAL_TARGET_ANGLE = math.rad(180)
local TARGET_VELOCITY = 3.0
local MAX_IMPULSE = 5000
local SIDE_DEAD_ZONE = 0.05
local BLOCKS_PER_WORLD_UNIT = 4.0
local OVERSHOOT_MAX_DISTANCE_BLOCKS = 300.0
local OVERSHOOT_MIN_DISTANCE_INCREASE_PER_SECOND = 10.0
local OVERSHOOT_REQUIRED_INCREASING_SAMPLES = 2
local OVERSHOOT_TARGET_RETENTION_SECONDS = 5.0
local OVERSHOOT_LEAVE_POV_DELAY_SECONDS = 0.5
local TRACK_LOSS_DISTANCE_BLOCKS = 500.0
local HEAT_SEEKER_SCAN_RADIUS_BLOCKS = 3000.0
local HEAT_COUNTERMEASURE_KINDS = {
    flare = true
}
local CHAFF_COUNTERMEASURE_KINDS = {
    chaff = true
}
local PLANE_RADAR_SCREEN_UUID = "0307d97e-1016-4131-9ca2-7c1d653d3f69"
local RADAR_DATA_SCREEN_UUID = "9e1fd450-3e60-4ce8-86dd-e0ee5ced4b77"
local LASER_GUIDANCE_MODULE_UUID = "e5a7b9c1-0d23-4f56-9a78-1b2c3d4e5678"
local PLANE_RADAR_REGISTRY_PREFIX = "PlaneRadarScreen:"
local LASER_GUIDANCE_REGISTRY_PREFIX = "PlaneConstructLaserGuidance:"
local PLAYER_LOCK_REGISTRY_PREFIX = "PlaneConstructPlaneControllerLock:"
local PRESENCE_REGISTRY_NAME = "PlaneConstructPresenceTargets"
local PLANE_CONTROLLER_REGISTRY_NAME = "PlaneConstructPlaneControllers"
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

-- Vanilla engine and thruster shape UUIDs, including their Creative variants.
-- Unknown modded parts can also be discovered from their reported shape title.
local HEAT_SEEKER_SHAPE_UUIDS = {
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
    -- New Legend Mod thrusters/engines.
    ["4001aaad-5494-11e6-beb8-9e71128cae77"] = true,
    ["3048aaab-5494-11e6-beb8-9e71128cae77"] = true,
    -- Plane Construct Doppler engine.
    ["b7c8d9e0-1234-4abc-8def-0123456789ab"] = true
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

local function targetId(target)
    if target == nil then return nil end
    if type(target) == "table" then
        return target.id
    end

    return target:getId()
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

function PlaneController.server_onCreate(self)
    self:sv_initialize()
end

function PlaneController.server_onRefresh(self)
    self:sv_initialize()
end

function PlaneController.server_onDestroy(self)
    _G[PLAYER_LOCK_REGISTRY_PREFIX .. tostring(self.interactable:getId())] = nil
    _G[PLANE_CONTROLLER_REGISTRY_NAME] = _G[PLANE_CONTROLLER_REGISTRY_NAME] or {}
    _G[PLANE_CONTROLLER_REGISTRY_NAME][self.interactable:getId()] = nil
end

function PlaneController.sv_initialize(self)
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
    local storedTrackTargetKind = type(stored) == "table" and stored.trackTargetKind or nil
    if storedTrackTargetKind ~= "player"
        and storedTrackTargetKind ~= "plane_controller"
        and storedTrackTargetKind ~= "presence"
        and storedTrackTargetKind ~= "chaff" then
        storedTrackTargetKind = nil
    end
    local storedHeatSeeker = type(stored) == "table" and stored.heatSeeker == true or false
    if storedHeatSeeker then
        storedTrackClosestPlayer = false
    end
    local storedPredictTarget = (type(stored) == "table" and stored.predictTarget == true or false)
        and (storedTrackClosestPlayer or storedHeatSeeker)
    local storedObstacles = type(stored) == "table" and stored.obstacles == true or false
    local storedOvershootEnabled = not (type(stored) == "table" and stored.overshootEnabled == false)
    local storedAccelerationOutputEnabled = not (
        type(stored) == "table" and stored.accelerationOutputEnabled == false
    )
    local storedImpactSensitivity = type(stored) == "table" and tonumber(stored.impactSensitivity) or nil
    local storedDistanceActivationEnabled = type(stored) == "table"
        and stored.distanceActivationEnabled == true
        and (storedTrackClosestPlayer or storedHeatSeeker)
    local storedDistanceActivation = type(stored) == "table" and tonumber(stored.distanceActivation) or nil
    local storedTrackingPovEnabled = not (
        type(stored) == "table" and stored.trackingPovEnabled == false
    )
    if storedHeatSeeker then
        storedObstacles = true
        storedTrackingPovEnabled = true
    end
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
        trackTargetKind = storedTrackTargetKind,
        predictTarget = storedPredictTarget,
        heatSeeker = storedHeatSeeker,
        obstacles = storedObstacles,
        overshootEnabled = storedOvershootEnabled,
        accelerationOutputEnabled = storedAccelerationOutputEnabled,
        impactSensitivity = clamp(
            math.floor((storedImpactSensitivity or DEFAULT_IMPACT_SENSITIVITY) + 0.5),
            MIN_IMPACT_SENSITIVITY,
            MAX_IMPACT_SENSITIVITY
        ),
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
    self.svHeatCountermeasureTargetId = nil
    self.svHeatCountermeasureSeenSequences = {}
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
    self:sv_publishControllerRegistry()
end

function PlaneController.sv_publishControllerRegistry(self)
    local registry = _G[PLANE_CONTROLLER_REGISTRY_NAME]
    if registry == nil then
        registry = {}
        _G[PLANE_CONTROLLER_REGISTRY_NAME] = registry
    end

    local controllerId = self.interactable:getId()
    registry[controllerId] = {
        id = controllerId,
        kind = "plane_controller",
        name = "Plane Controller",
        active = true,
        position = self.shape.worldPosition,
        velocity = self.shape:getVelocity(),
        sourceShape = self.shape
    }
end

function PlaneController.sv_syncClientData(self)
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
        heatSeeker = self.sv.heatSeeker,
        obstacles = self.sv.obstacles,
        overshootEnabled = self.sv.overshootEnabled,
        accelerationOutputEnabled = self.sv.accelerationOutputEnabled,
        impactSensitivity = self.sv.impactSensitivity,
        distanceActivationEnabled = self.sv.distanceActivationEnabled,
        distanceActivation = self.sv.distanceActivation,
        trackingPovEnabled = self.sv.trackingPovEnabled,
        trackingFovDegrees = self.sv.trackingFovDegrees
    })
end

function PlaneController.sv_setAngleLimit(self, requestedLimit)
    local numericLimit = tonumber(requestedLimit)
    if numericLimit == nil then return end

    local angleLimit = clamp(math.floor(numericLimit + 0.5), MIN_ANGLE_LIMIT, MAX_ANGLE_LIMIT)
    if angleLimit == self.sv.angleLimit then return end

    self.sv.angleLimit = angleLimit
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setSensitivity(self, requestedSensitivity)
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

function PlaneController.sv_setAxisOffset(self, params)
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

function PlaneController.sv_setDamping(self, requestedDamping)
    local numericDamping = tonumber(requestedDamping)
    if numericDamping == nil then return end

    local damping = clamp(math.floor(numericDamping + 0.5), MIN_DAMPING, MAX_DAMPING)
    if damping == self.sv.damping then return end

    self.sv.damping = damping
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setWhiteBearingAngle(self, requestedAngle)
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

function PlaneController.sv_setTrackClosestPlayer(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.trackClosestPlayer then return end

    self.sv.trackClosestPlayer = requestedState
    if requestedState then
        self.sv.heatSeeker = false
    end
    self.svHeatCountermeasureTargetId = nil
    self.svHeatCountermeasureSeenSequences = {}
    if not requestedState then
        self.sv.predictTarget = false
    end
    self.svPreviousHorizontalError = nil
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setHeatSeeker(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.heatSeeker then return end

    self.sv.heatSeeker = requestedState
    if requestedState then
        self.sv.trackClosestPlayer = false
        self.sv.obstacles = true
        self.sv.trackingPovEnabled = true
    elseif not self.sv.trackClosestPlayer then
        self.sv.predictTarget = false
    end
    self.svHeatCountermeasureTargetId = nil
    self.svHeatCountermeasureSeenSequences = {}
    self.svPreviousHorizontalError = nil
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setTrackTarget(self, requestedTarget)
    if requestedTarget ~= DEFAULT_TRACK_TARGET and type(requestedTarget) ~= "number" then
        return
    end

    local requestedTargetKind = nil
    if type(requestedTarget) == "number" then
        local player = self:sv_getPlayerById(requestedTarget)
        local presence = self:sv_getPresenceTargetById(requestedTarget)
        local controller = self:sv_getPlaneControllerById(requestedTarget)
        if player == nil and presence == nil and controller == nil then return end
        requestedTargetKind = self:sv_getTrackTargetKind(requestedTarget)
    end

    if requestedTarget == self.sv.trackTarget
        and requestedTargetKind == self.sv.trackTargetKind then return end

    self.sv.trackTarget = requestedTarget
    self.sv.trackTargetKind = requestedTargetKind
    self.svPreviousHorizontalError = nil
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setPredictTarget(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.predictTarget then return end

    self.sv.predictTarget = requestedState
    self:sv_resetPredictionState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setObstacles(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if self.sv.heatSeeker then
        requestedState = true
    end
    if requestedState == self.sv.obstacles then return end

    self.sv.obstacles = requestedState
    self.svPreviousHorizontalError = nil
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setOvershootEnabled(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.overshootEnabled then return end

    self.sv.overshootEnabled = requestedState
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setAccelerationOutputEnabled(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.accelerationOutputEnabled then return end

    self.sv.accelerationOutputEnabled = requestedState
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setImpactSensitivity(self, requestedSensitivity)
    local numericSensitivity = tonumber(requestedSensitivity)
    if numericSensitivity == nil then return end

    local sensitivity = clamp(
        math.floor(numericSensitivity + 0.5),
        MIN_IMPACT_SENSITIVITY,
        MAX_IMPACT_SENSITIVITY
    )
    if sensitivity == self.sv.impactSensitivity then return end

    self.sv.impactSensitivity = sensitivity
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setDistanceActivationEnabled(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.distanceActivationEnabled then return end

    self.sv.distanceActivationEnabled = requestedState
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_setDistanceActivation(self, requestedDistance)
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

function PlaneController.sv_setTrackingFovDegrees(self, requestedFov)
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

function PlaneController.sv_setTrackingPovEnabled(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if self.sv.heatSeeker then
        requestedState = true
    end
    if requestedState == self.sv.trackingPovEnabled then return end

    self.sv.trackingPovEnabled = requestedState
    self.svPreviousHorizontalError = nil
    self:sv_resetPredictionState()
    self:sv_resetOvershootState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function PlaneController.sv_resetPredictionState(self)
    self.svTrackedPlayerId = nil
    self.svTrackedPlayerVelocity = nil
    self.svTrackedPlayerAcceleration = sm.vec3.new(0, 0, 0)
    self.svTrackedPlayerSpeed = 0
end

function PlaneController.sv_resetOvershootState(self)
    self.svPreviousTargetId = nil
    self.svPreviousTargetDistanceBlocks = nil
    self.svPreviousTargetDistanceDeltaBlocks = nil
    self.svOvershootWasClosing = false
    self.svOvershootIncreasingSamples = 0
    self.svOvershootTargetId = nil
    self.svOvershootTargetKind = nil
    self.svOvershootTargetMissingTime = 0
    self.svOvershootLeavePovTime = 0
    self.svOvershootLeavePovTriggered = false
    self.svHeatSeekerTargetShape = nil
end

function PlaneController.sv_getOvershootTargetCharacter(self)
    if self.svOvershootTargetId == nil then return nil end

    -- A "Closest" target is stored by character ID so the controller keeps
    -- monitoring the same player even after that player leaves the tracking
    -- cone. Explicit player/presence selections are stored by configured ID.
    if self.svOvershootTargetKind == "character" then
        for _, player in ipairs(sm.player.getAllPlayers()) do
            local character = player:getCharacter()
            if character ~= nil and sm.exists(character) then
                local characterId = targetId(character)
                if characterId == self.svOvershootTargetId then
                    return character
                end
            end
        end
        return nil
    end

    if self.svOvershootTargetKind == "heat" then
        return self:sv_makeHeatSeekerTarget(self.svHeatSeekerTargetShape)
    end

    if self.svOvershootTargetKind == "countermeasure" then
        return self:sv_getPresenceTargetById(self.svOvershootTargetId)
    end

    if self.svOvershootTargetKind == "player" then
        local player = self:sv_getPlayerById(self.svOvershootTargetId)
        local character = player ~= nil and player:getCharacter() or nil
        return character ~= nil and sm.exists(character) and character or nil
    elseif self.svOvershootTargetKind == "plane_controller" then
        return self:sv_getPlaneControllerById(self.svOvershootTargetId)
    elseif self.svOvershootTargetKind == "presence" or self.svOvershootTargetKind == "chaff" then
        return self:sv_getPresenceTargetById(self.svOvershootTargetId)
    end

    local controller = self:sv_getPlaneControllerById(self.svOvershootTargetId)
    if controller ~= nil then
        return controller
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

function PlaneController.sv_getPredictedTargetPosition(self, targetCharacter, timeStep)
    local currentPosition = targetCharacter.worldPosition
    local currentVelocity = targetCharacter.velocity or sm.vec3.new(0, 0, 0)
    local currentTargetId = targetId(targetCharacter)
    local acceleration = sm.vec3.new(0, 0, 0)

    if self.svTrackedPlayerId == currentTargetId and self.svTrackedPlayerVelocity ~= nil and timeStep ~= nil and timeStep > 0 then
        local measuredAcceleration = (currentVelocity - self.svTrackedPlayerVelocity) / timeStep
        local accelerationLength = measuredAcceleration:length()
        if accelerationLength > PREDICTION_MAX_ACCELERATION then
            measuredAcceleration = measuredAcceleration / accelerationLength * PREDICTION_MAX_ACCELERATION
        end

        local previousAcceleration = self.svTrackedPlayerAcceleration or sm.vec3.new(0, 0, 0)
        acceleration = previousAcceleration * (1.0 - PREDICTION_ACCELERATION_SMOOTHING)
            + measuredAcceleration * PREDICTION_ACCELERATION_SMOOTHING
    end

    self.svTrackedPlayerId = currentTargetId
    self.svTrackedPlayerVelocity = currentVelocity
    self.svTrackedPlayerAcceleration = acceleration
    self.svTrackedPlayerSpeed = currentVelocity:length()

    local toTarget = currentPosition - self.shape.worldPosition
    local distance = toTarget:length()
    if distance <= 0.001 then
        return currentPosition
    end

    local targetDirection = toTarget / distance
    local aircraftVelocity = self.shape:getVelocity()
    local aircraftSpeed = aircraftVelocity:length()
    local targetSpeedAlongLine = currentVelocity:dot(targetDirection)
    local closingSpeed = math.max(aircraftSpeed - targetSpeedAlongLine, PREDICTION_MIN_CLOSING_SPEED)
    local predictionTime = math.min(distance / closingSpeed, PREDICTION_MAX_TIME)

    -- Reduce lead as the missile gets close to the target. A fast missile
    -- approaching nearly straight-on is especially sensitive to small target
    -- velocity changes, so reduce the lead again below the shallow-approach
    -- angle threshold to prevent guidance wiggle.
    local distanceBlocks = distance * BLOCKS_PER_WORLD_UNIT
    local distanceProgress = clamp(distanceBlocks / PREDICTION_NEAR_DISTANCE_BLOCKS, 0, 1)
    local distanceScale = PREDICTION_MIN_DISTANCE_SCALE
        + (1.0 - PREDICTION_MIN_DISTANCE_SCALE) * distanceProgress
    local approachScale = 1.0
    local relativeVelocity = aircraftVelocity - currentVelocity
    local relativeSpeed = relativeVelocity:length()
    if relativeSpeed > 0.001 then
        local approachDot = clamp(relativeVelocity:dot(targetDirection) / relativeSpeed, -1, 1)
        local approachAngle = math.deg(math.acos(approachDot))
        if approachAngle < PREDICTION_SHALLOW_APPROACH_DEGREES then
            local angleProgress = approachAngle / PREDICTION_SHALLOW_APPROACH_DEGREES
            approachScale = PREDICTION_MIN_SHALLOW_APPROACH_SCALE
                + (1.0 - PREDICTION_MIN_SHALLOW_APPROACH_SCALE) * angleProgress
        end
    end
    predictionTime = predictionTime * distanceScale * approachScale

    return currentPosition + currentVelocity * predictionTime
        + acceleration * (0.5 * predictionTime * predictionTime)
end

function PlaneController.sv_getSeatParent(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.seated) then
            return parent
        end
    end

    return nil
end

function PlaneController.sv_getControllingCharacter(self)
    local seat = self:sv_getSeatParent()
    if seat == nil then return nil end

    local seatedCharacter = seat:getSeatCharacter()
    return seatedCharacter ~= nil and sm.exists(seatedCharacter) and seatedCharacter or nil
end

function PlaneController.sv_getSeatControls(self)
    local seat = self:sv_getSeatParent()
    if seat == nil then return 0, 0 end

    local seatedCharacter = seat:getSeatCharacter()
    if seatedCharacter == nil or not sm.exists(seatedCharacter) then return 0, 0 end

    local rollInput = clamp(tonumber(seat:getSteeringAngle()) or 0, -1, 1)
    local pitchInput = clamp(tonumber(seat:getPower()) or 0, -1, 1)
    -- W pitches down and S pitches up, matching conventional aircraft controls.
    return rollInput, -pitchInput
end

function PlaneController.sv_getPlayerById(self, playerId)
    for _, player in ipairs(sm.player.getAllPlayers()) do
        if player:getId() == playerId then
            return player
        end
    end

    return nil
end

function PlaneController.sv_getPresenceTargetById(self, targetId)
    local registry = _G[PRESENCE_REGISTRY_NAME] or {}
    local target = registry[targetId] or registry[tostring(targetId)]
    if type(target) ~= "table" or target.active ~= true or target.position == nil then
        return nil
    end

    return {
        id = target.id or targetId,
        worldPosition = target.position,
        velocity = target.velocity or sm.vec3.new(0, 0, 0),
        kind = target.kind,
        countermeasure = target.countermeasure == true,
        spawnSequence = target.spawnSequence
    }
end

function PlaneController.sv_getPlaneControllerById(self, targetId)
    local registry = _G[PLANE_CONTROLLER_REGISTRY_NAME] or {}
    local target = registry[targetId] or registry[tostring(targetId)]
    if type(target) ~= "table" or target.active ~= true or target.position == nil then
        return nil
    end

    return {
        id = target.id or targetId,
        worldPosition = target.position,
        velocity = target.velocity or sm.vec3.new(0, 0, 0),
        kind = "plane_controller",
        name = target.name or "Plane Controller",
        sourceShape = target.sourceShape
    }
end

function PlaneController.sv_getConnectedRadarTarget(self)
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
                        return selectedPlayerId, radarData.selectedTargetKind
                    end
                end
            end
        end
    end

    return nil
end

function PlaneController.sv_getConnectedLaserGuidance(self)
    local connected = self.interactable:getParents(sm.interactable.connectionType.logic)
    for _, child in ipairs(self.interactable:getChildren(sm.interactable.connectionType.logic)) do
        table.insert(connected, child)
    end

    for _, interactable in ipairs(connected) do
        local shape = interactable:getShape()
        if shape ~= nil and tostring(sm.shape.getShapeUuid(shape)) == LASER_GUIDANCE_MODULE_UUID then
            local data = PlaneConstructLaserGuidanceTargets[interactable:getId()]
            if type(data) ~= "table" or data.active ~= true then return true, nil end
            if data.point == nil then
                return true, nil
            end
            return true, {
                id = data.emitterId or interactable:getId(),
                worldPosition = data.point,
                velocity = sm.vec3.new(0, 0, 0),
                receiverPosition = data.receiverPosition,
                receiverDirection = data.receiverDirection,
                kind = "laser"
            }
        end
    end

    return false, nil
end

function PlaneController.sv_getTrackTargetKind(self, targetId)
    if self:sv_getPlayerById(targetId) ~= nil then
        return "player"
    end
    local presence = self:sv_getPresenceTargetById(targetId)
    if presence ~= nil then
        return presence.countermeasure == true and "chaff" or "presence"
    end
    if self:sv_getPlaneControllerById(targetId) ~= nil then
        return "plane_controller"
    end
    return nil
end

function PlaneController.sv_isPlayerException(self, playerId)
    for _, exceptionPlayerId in ipairs(self.sv.exceptionPlayerIds) do
        if tonumber(exceptionPlayerId) == playerId then
            return true
        end
    end

    return false
end

function PlaneController.sv_addPlayerException(self, playerId)
    if playerId == nil or self:sv_isPlayerException(playerId) then
        return
    end

    table.insert(self.sv.exceptionPlayerIds, playerId)
    self.storage:save(self.sv)
end

function PlaneController.sv_isHeatSeekerShape(self, shape)
    if shape == nil or not sm.exists(shape) or shape == self.shape then return false end

    local shapeUuid = string.lower(tostring(sm.shape.getShapeUuid(shape)))
    if not HEAT_SEEKER_SHAPE_UUIDS[shapeUuid] then
        local title = ""
        local titleResolved, resolvedTitle = pcall(
            sm.shape.getShapeTitle,
            sm.shape.getShapeUuid(shape)
        )
        if titleResolved then
            title = string.lower(tostring(resolvedTitle or ""))
        end

        local isNamedHeatSource = string.find(title, "thruster", 1, true) ~= nil
            or string.find(title, "engine", 1, true) ~= nil
        if not isNamedHeatSource then return false end
    end

    -- Do not let a missile lock onto its own active engine or thruster.
    local controllerBody = self.shape:getBody()
    local targetBody = shape:getBody()
    if controllerBody ~= nil and targetBody ~= nil and controllerBody == targetBody then
        return false
    end

    local interactable = shape.interactable
    if interactable == nil then return false end

    -- Vanilla engines publish their real running state through public data;
    -- isActive() alone only reflects the input signal for those engines.
    local publicData = interactable:getPublicData()
    if type(publicData) == "table" and publicData.isActive ~= nil then
        return publicData.isActive == true
    end

    return interactable:isActive()
end

function PlaneController.sv_makeHeatSeekerTarget(self, shape)
    if shape == nil or not sm.exists(shape) then return nil end

    return {
        id = shape.id,
        worldPosition = shape.worldPosition,
        velocity = shape:getVelocity(),
        heatSeekerShape = shape
    }
end

function PlaneController.sv_isHeatCountermeasureTarget(self, target, allowedKinds)
    local countermeasureKinds = allowedKinds or HEAT_COUNTERMEASURE_KINDS
    return type(target) == "table"
        and target.active == true
        and target.position ~= nil
        and target.countermeasure == true
        and countermeasureKinds[target.kind] == true
end

function PlaneController.sv_makeHeatCountermeasureTarget(self, targetId, target, allowedKinds)
    if not self:sv_isHeatCountermeasureTarget(target, allowedKinds) then return nil end
    return {
        id = target.id or targetId,
        worldPosition = target.position,
        velocity = target.velocity or sm.vec3.new(0, 0, 0),
        countermeasure = true,
        countermeasureKind = target.kind,
        spawnSequence = target.spawnSequence
    }
end

function PlaneController.sv_getClosestActiveHeatCountermeasureTarget(self, allowedKinds)
    local radius = HEAT_SEEKER_SCAN_RADIUS_BLOCKS / BLOCKS_PER_WORLD_UNIT
    local radiusSquared = radius * radius
    local closestTarget = nil
    local closestDistanceSquared = math.huge

    for targetId, target in pairs(_G[PRESENCE_REGISTRY_NAME] or {}) do
        local numericTargetId = tonumber(targetId)
            or (type(target) == "table" and tonumber(target.id) or nil)
        if numericTargetId ~= nil and self:sv_isHeatCountermeasureTarget(target, allowedKinds)
            and self:sv_isTargetInsideTrackingPov(target.position)
            and not self:sv_isTerrainBlocked(target.position) then
            local offset = target.position - self.shape.worldPosition
            local distanceSquared = offset:dot(offset)
            if distanceSquared <= radiusSquared and distanceSquared < closestDistanceSquared then
                closestDistanceSquared = distanceSquared
                closestTarget = self:sv_makeHeatCountermeasureTarget(numericTargetId, target, allowedKinds)
            end
        end
    end

    return closestTarget
end

function PlaneController.sv_getHeatCountermeasureTargetById(self, targetId, allowedKinds)
    if targetId == nil then return nil end
    local registry = _G[PRESENCE_REGISTRY_NAME] or {}
    local target = registry[targetId] or registry[tostring(targetId)]
    return self:sv_makeHeatCountermeasureTarget(targetId, target, allowedKinds)
end

function PlaneController.sv_updateCountermeasureLock(self, allowedKinds, fallbackTarget, acquireWhenEmpty)
    local closestCountermeasure = self:sv_getClosestActiveHeatCountermeasureTarget(allowedKinds)
    local seenSequences = self.svHeatCountermeasureSeenSequences or {}
    local lockedCountermeasure = self:sv_getHeatCountermeasureTargetById(
        self.svHeatCountermeasureTargetId,
        allowedKinds
    )

    -- Every new deployment is considered once. Heat-seeker mode acquires the
    -- first visible flare when no heat source exists; all later flare changes,
    -- and every chaff change outside heat-seeker mode, have a 50% chance.
    for targetId, target in pairs(_G[PRESENCE_REGISTRY_NAME] or {}) do
        local numericTargetId = tonumber(targetId)
            or (type(target) == "table" and tonumber(target.id) or nil)
        if numericTargetId ~= nil and self:sv_isHeatCountermeasureTarget(target, allowedKinds) then
            local spawnSequence = tonumber(target.spawnSequence) or 0
            if spawnSequence > 0 and seenSequences[numericTargetId] ~= spawnSequence then
                seenSequences[numericTargetId] = spawnSequence
                local candidate = self:sv_makeHeatCountermeasureTarget(
                    numericTargetId,
                    target,
                    allowedKinds
                )
                local candidateVisible = candidate ~= nil
                    and self:sv_isTargetInsideTrackingPov(candidate.worldPosition)
                    and not self:sv_isTerrainBlocked(candidate.worldPosition)
                local hasCurrentTarget = lockedCountermeasure ~= nil or fallbackTarget ~= nil
                local shouldChange = (not hasCurrentTarget and acquireWhenEmpty)
                    or math.random() < 0.5
                if candidateVisible and shouldChange then
                    self.svHeatCountermeasureTargetId = numericTargetId
                    lockedCountermeasure = candidate
                    self.svPreviousHorizontalError = nil
                    self:sv_resetPredictionState()
                end
            end
        end
    end

    for targetId in pairs(seenSequences) do
        local registry = _G[PRESENCE_REGISTRY_NAME] or {}
        if registry[targetId] == nil and registry[tostring(targetId)] == nil then
            seenSequences[targetId] = nil
        end
    end
    self.svHeatCountermeasureSeenSequences = seenSequences

    lockedCountermeasure = self:sv_getHeatCountermeasureTargetById(
        self.svHeatCountermeasureTargetId,
        allowedKinds
    )
    if lockedCountermeasure ~= nil then
        return lockedCountermeasure
    end

    if fallbackTarget ~= nil then
        return fallbackTarget
    end

    return acquireWhenEmpty and closestCountermeasure or nil
end

function PlaneController.sv_getClosestActiveHeatSeekerTarget(self)
    local radius = HEAT_SEEKER_SCAN_RADIUS_BLOCKS / BLOCKS_PER_WORLD_UNIT
    local nearbyShapes = sm.shape.shapesInSphere(self.shape.worldPosition, radius)
    local closestHeatSource = nil
    local closestDistanceSquared = math.huge

    for _, shape in ipairs(nearbyShapes) do
        if self:sv_isHeatSeekerShape(shape)
            and self:sv_isTargetInsideTrackingPov(shape.worldPosition)
            and not self:sv_isTerrainBlocked(shape.worldPosition) then
            local offset = shape.worldPosition - self.shape.worldPosition
            local distanceSquared = offset:dot(offset)
            if distanceSquared < closestDistanceSquared then
                local target = self:sv_makeHeatSeekerTarget(shape)
                if target ~= nil then
                    closestDistanceSquared = distanceSquared
                    closestHeatSource = target
                end
            end
        end
    end

    return self:sv_updateCountermeasureLock(
        HEAT_COUNTERMEASURE_KINDS,
        closestHeatSource,
        true
    )
end

function PlaneController.sv_getClosestActiveChaffTarget(self, fallbackTarget)
    -- Chaff is only a distraction for the explicit player-tracking mode.
    -- Without this guard, a controller with all targeting modes disabled can
    -- acquire a chaff particle and start steering toward it.
    if not self.sv.trackClosestPlayer then return nil end
    return self:sv_updateCountermeasureLock(
        CHAFF_COUNTERMEASURE_KINDS,
        fallbackTarget,
        false
    )
end

function PlaneController.sv_isTerrainBlocked(self, targetPosition)
    if not self.sv.obstacles then return false end

    local origin = self.shape.worldPosition
    local offset = targetPosition - origin
    if offset:length() <= 0.001 then return false end

    -- Obstacles use the same terrain-only line of sight as Plane Radar Screen.
    -- The controller's own body is ignored, while built blocks remain ignored.
    local hit, result = sm.physics.raycast(
        origin,
        targetPosition,
        self.shape:getBody(),
        sm.physics.filter.allTerrain
    )
    return hit == true and result ~= nil
end

function PlaneController.sv_getClosestPlayer(self)
    local closestPlayer = nil
    local closestCharacter = nil
    local closestDistanceSquared = math.huge

    for _, player in ipairs(sm.player.getAllPlayers()) do
        if not self:sv_isPlayerException(player:getId()) then
            local character = player:getCharacter()
            if character ~= nil and sm.exists(character)
                and self:sv_isTargetInsideTrackingPov(character.worldPosition)
                and not self:sv_isTerrainBlocked(character.worldPosition) then
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

function PlaneController.sv_isTargetInsideTrackingPov(self, targetPosition)
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

function PlaneController.sv_getClosestPlayerCharacter(self)
    local _, closestCharacter = self:sv_getClosestPlayer()
    return closestCharacter
end

function PlaneController.sv_getTrackTargetCharacter(self)
    if self.sv.trackTarget == DEFAULT_TRACK_TARGET then
        return self:sv_getClosestPlayerCharacter()
    end

    -- Radar selections carry their target kind because player IDs and
    -- interactable IDs can overlap. Resolve the explicit kind first.
    if self.sv.trackTargetKind == "player" then
        local player = self:sv_getPlayerById(self.sv.trackTarget)
        if player == nil then return nil end
        local character = player:getCharacter()
        if character == nil or not sm.exists(character) then return nil end
        return self:sv_isTargetInsideTrackingPov(character.worldPosition)
            and not self:sv_isTerrainBlocked(character.worldPosition)
            and character
            or nil
    elseif self.sv.trackTargetKind == "plane_controller" then
        local controller = self:sv_getPlaneControllerById(self.sv.trackTarget)
        if controller == nil then return nil end
        return self:sv_isTargetInsideTrackingPov(controller.worldPosition)
            and not self:sv_isTerrainBlocked(controller.worldPosition)
            and controller
            or nil
    elseif self.sv.trackTargetKind == "presence" or self.sv.trackTargetKind == "chaff" then
        local presence = self:sv_getPresenceTargetById(self.sv.trackTarget)
        if presence == nil then return nil end
        return self:sv_isTargetInsideTrackingPov(presence.worldPosition)
            and not self:sv_isTerrainBlocked(presence.worldPosition)
            and presence
            or nil
    end

    local controller = self:sv_getPlaneControllerById(self.sv.trackTarget)
    if controller ~= nil then
        return self:sv_isTargetInsideTrackingPov(controller.worldPosition)
            and not self:sv_isTerrainBlocked(controller.worldPosition)
            and controller
            or nil
    end

    local presence = self:sv_getPresenceTargetById(self.sv.trackTarget)
    if presence ~= nil then
        return self:sv_isTargetInsideTrackingPov(presence.worldPosition)
            and not self:sv_isTerrainBlocked(presence.worldPosition)
            and presence
            or nil
    end

    local player = self:sv_getPlayerById(self.sv.trackTarget)
    if player == nil then return nil end

    local character = player:getCharacter()
    if character == nil or not sm.exists(character) then return nil end
    return self:sv_isTargetInsideTrackingPov(character.worldPosition)
        and not self:sv_isTerrainBlocked(character.worldPosition)
        and character
        or nil
end

function PlaneController.sv_publishPlayerLock(self)
    local targetPlayerId = nil
    local targetPlayerName = nil
    local targetKind = nil
    local targetPosition = nil
    local laserGuidanceConnected = self:sv_getConnectedLaserGuidance()
    if not laserGuidanceConnected and self.sv.trackClosestPlayer and self:sv_isLogicInputActive() then
        local target = self:sv_getTrackTargetCharacter()
        if target ~= nil then
            if target.isPlayer ~= nil and target:isPlayer() then
                local player = target:getPlayer()
                if player ~= nil then
                    targetPlayerId = player:getId()
                    targetPlayerName = player:getName()
                    targetKind = "player"
                    targetPosition = target.worldPosition
                end
            elseif target.kind == "plane_controller" then
                targetPlayerId = target.id
                targetPlayerName = target.name or "Plane Controller"
                targetKind = "plane_controller"
                targetPosition = target.worldPosition
            end
        end
    end

    _G[PLAYER_LOCK_REGISTRY_PREFIX .. tostring(self.interactable:getId())] = {
        lockActive = targetPlayerId ~= nil,
        targetPlayerId = targetPlayerId,
        targetPlayerName = targetPlayerName,
        targetKind = targetKind,
        targetPosition = targetPosition,
        sourcePosition = self.shape.worldPosition
    }
end

function PlaneController.sv_isLogicInputActive(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            return true
        end
    end

    return false
end

function PlaneController.sv_isLogicColorActive(self, color)
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

function PlaneController.sv_getHorizonDemands(self)
    local shapeForward = self.shape:getUp()
    local horizontalForwardLength = math.sqrt(
        shapeForward.x * shapeForward.x + shapeForward.y * shapeForward.y
    )
    local pitchDemand = -math.atan2(shapeForward.z, horizontalForwardLength)
    local rollDemand = -math.atan2(self.shape:getRight().z, self.shape:getAt().z)
    local limit = math.rad(self.sv.angleLimit)

    return clamp(rollDemand, -limit, limit), clamp(pitchDemand, -limit, limit)
end

function PlaneController.sv_updateLogicOutput(self, timeStep)
    local targetInRange = false
    local overshootDetected = false
    local deltaTime = math.max(tonumber(timeStep) or 0, 0)
    local monitorTarget = nil
    local laserGuidanceConnected, laserTarget = self:sv_getConnectedLaserGuidance()
    if laserGuidanceConnected then
        if laserTarget ~= nil then
            local distanceBlocks = (laserTarget.worldPosition - self.shape.worldPosition):length()
                * BLOCKS_PER_WORLD_UNIT
            targetInRange = distanceBlocks <= self.sv.distanceActivation
        end
        self.interactable:setActive(self.sv.distanceActivationEnabled and targetInRange)
        return
    end
    local targetingEnabled = self.sv.trackClosestPlayer or self.sv.heatSeeker
    local visibleTarget = nil

    if self.sv.heatSeeker then
        visibleTarget = self:sv_getClosestActiveHeatSeekerTarget()
    else
        local playerTarget = nil
        if self.sv.trackClosestPlayer then
            playerTarget = self:sv_getTrackTargetCharacter()
        end
        visibleTarget = self:sv_getClosestActiveChaffTarget(playerTarget)
        targetingEnabled = targetingEnabled or visibleTarget ~= nil
    end

    if targetingEnabled then
        if visibleTarget ~= nil then
            local visibleDistanceBlocks = (visibleTarget.worldPosition - self.shape.worldPosition):length()
                * BLOCKS_PER_WORLD_UNIT
            targetInRange = visibleDistanceBlocks <= self.sv.distanceActivation
        end

        if self.sv.overshootEnabled then
            if visibleTarget ~= nil then
                monitorTarget = visibleTarget
                local isCountermeasure = type(visibleTarget) == "table"
                    and visibleTarget.countermeasure == true
                if isCountermeasure then
                    self.svOvershootTargetId = visibleTarget.id
                    self.svOvershootTargetKind = "countermeasure"
                    self.svHeatSeekerTargetShape = nil
                elseif self.sv.heatSeeker then
                    self.svOvershootTargetId = visibleTarget.id
                    self.svOvershootTargetKind = "heat"
                    self.svHeatSeekerTargetShape = visibleTarget.heatSeekerShape
                elseif self.sv.trackTarget == DEFAULT_TRACK_TARGET then
                    self.svOvershootTargetId = targetId(visibleTarget)
                    self.svOvershootTargetKind = "character"
                else
                    self.svOvershootTargetId = self.sv.trackTarget
                    self.svOvershootTargetKind = self.sv.trackTargetKind or "configured"
                end
                self.svOvershootTargetMissingTime = 0
                self.svOvershootLeavePovTime = 0
                self.svOvershootLeavePovTriggered = false
            elseif self.svOvershootTargetId ~= nil then
                -- Keep monitoring the exact acquired target even when it is
                -- outside the steering cone. This makes a flyby detectable.
                local retainedTarget = self:sv_getOvershootTargetCharacter()
                if retainedTarget ~= nil then
                    monitorTarget = retainedTarget
                    local terrainBlocked = self.sv.obstacles
                        and self:sv_isTerrainBlocked(retainedTarget.worldPosition)
                    local outsidePov = self.sv.trackingPovEnabled
                        and not self:sv_isTargetInsideTrackingPov(retainedTarget.worldPosition)

                    if terrainBlocked then
                        -- An occluded target may reappear and be reacquired.
                        -- Do not emit the leave-PoV fallback while occluded.
                        self.svOvershootTargetMissingTime = 0
                        self.svOvershootLeavePovTime = 0
                        self.svOvershootLeavePovTriggered = false
                    elseif outsidePov then
                        self.svOvershootTargetMissingTime = self.svOvershootTargetMissingTime + deltaTime
                        self.svOvershootLeavePovTime = self.svOvershootLeavePovTime + deltaTime

                        if self.svOvershootTargetMissingTime > OVERSHOOT_TARGET_RETENTION_SECONDS then
                            self:sv_resetOvershootState()
                            monitorTarget = nil
                        elseif not self.svOvershootLeavePovTriggered
                            and self.svOvershootWasClosing
                            and self.svOvershootLeavePovTime >= OVERSHOOT_LEAVE_POV_DELAY_SECONDS then
                            -- Losing a closing target from the steering cone is
                            -- sufficient evidence of a flyby after the grace
                            -- period, unless terrain occluded it first.
                            overshootDetected = true
                            self.svOvershootLeavePovTriggered = true
                            self.svOvershootWasClosing = false
                            self.svOvershootIncreasingSamples = 0
                        end
                    else
                        self:sv_resetOvershootState()
                        monitorTarget = nil
                    end
                else
                    self:sv_resetOvershootState()
                end
            end
        end

        if monitorTarget ~= nil then
            local monitorTargetId = targetId(monitorTarget)
            local distanceBlocks = (monitorTarget.worldPosition - self.shape.worldPosition):length()
                * BLOCKS_PER_WORLD_UNIT

            if self.svPreviousTargetId == monitorTargetId
                and self.svPreviousTargetDistanceBlocks ~= nil
                and deltaTime > 0 then
                local distanceDeltaBlocks = distanceBlocks - self.svPreviousTargetDistanceBlocks
                local distanceIncreasePerSecond = distanceDeltaBlocks / deltaTime

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

                local distanceOvershootDetected = distanceBlocks <= OVERSHOOT_MAX_DISTANCE_BLOCKS
                    and self.svOvershootWasClosing
                    and self.svOvershootIncreasingSamples >= OVERSHOOT_REQUIRED_INCREASING_SAMPLES
                    and distanceIncreasePerSecond >= OVERSHOOT_MIN_DISTANCE_INCREASE_PER_SECOND

                if distanceOvershootDetected then
                    overshootDetected = true
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

            self.svPreviousTargetId = monitorTargetId
            self.svPreviousTargetDistanceBlocks = distanceBlocks
        else
            self:sv_resetOvershootState()
        end
    else
        self:sv_resetOvershootState()
    end

    local currentVelocity = self.shape:getVelocity()
    local previousVelocity = self.svPreviousVelocity or currentVelocity
    self.svPreviousVelocity = currentVelocity

    local accelerationBlocks = 0
    if deltaTime > 0 then
        accelerationBlocks = (currentVelocity - previousVelocity):length()
            * BLOCKS_PER_WORLD_UNIT / deltaTime
    end

    self.interactable:setActive(
        (targetingEnabled and self.sv.distanceActivationEnabled and targetInRange)
            or (self.sv.accelerationOutputEnabled and accelerationBlocks > self.sv.impactSensitivity)
            or (self.sv.overshootEnabled and overshootDetected)
    )
end

function PlaneController.sv_getTargetAngles(self, direction)
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

function PlaneController.sv_getSideSign(self, bearing)
    local lateralOffset = (bearing.worldPosition - self.shape.worldPosition):dot(self.shape:getRight())
    if lateralOffset > SIDE_DEAD_ZONE then return 1 end
    if lateralOffset < -SIDE_DEAD_ZONE then return -1 end

    -- A centered bearing has no discoverable left/right side. Treat it as the
    -- right side; the Connect Tool's reverse option can correct its direction.
    return 1
end

function PlaneController.sv_setBearingsNeutral(self, bearings)
    self.svPreviousHorizontalError = nil
    for _, bearing in ipairs(bearings) do
        bearing:setTargetAngle(0, TARGET_VELOCITY, MAX_IMPULSE)
    end
end

function PlaneController.server_onFixedUpdate(self, timeStep)
    self:sv_publishControllerRegistry()
    self:sv_updateLogicOutput(timeStep)

    local bearings = self.interactable:getBearings()

    -- A connected Radar Screen publishes its yellow-selected player through
    -- the shared server registry. The radar's active basic output both starts
    -- tracking and commits the selected target here.
    if self.sv.trackClosestPlayer then
        local radarTargetId, radarTargetKind = self:sv_getConnectedRadarTarget()
        if radarTargetId ~= nil
            and (self.sv.trackTarget ~= radarTargetId
                or self.sv.trackTargetKind ~= radarTargetKind) then
            self.sv.trackTarget = radarTargetId
            self.sv.trackTargetKind = radarTargetKind
            self.storage:save(self.sv)
            self:sv_syncClientData()
        end
    end
    self:sv_publishPlayerLock()

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
    local laserGuidanceConnected, laserTarget = self:sv_getConnectedLaserGuidance()
    local targetingEnabled = laserGuidanceConnected or self.sv.trackClosestPlayer or self.sv.heatSeeker
    if laserGuidanceConnected then
        targetCharacter = laserTarget
    elseif self.sv.heatSeeker then
        targetCharacter = self:sv_getClosestActiveHeatSeekerTarget()
    else
        local playerTarget = nil
        if self.sv.trackClosestPlayer then
            playerTarget = self:sv_getTrackTargetCharacter()
        end
        targetCharacter = self:sv_getClosestActiveChaffTarget(playerTarget)
        targetingEnabled = targetingEnabled or targetCharacter ~= nil
    end
    if targetingEnabled then
        -- Laser Guidance Module already validates its own enable input. Do
        -- not require a second controller-side signal, because the module
        -- can be connected to either side of this controller's logic port.
        if not laserGuidanceConnected and not self:sv_isLogicInputActive() then
            self:sv_resetPredictionState()
            self:sv_setBearingsNeutral(bearings)
            return
        end
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
    if not targetingEnabled then
        rollInput, pitchInput = self:sv_getSeatControls()
    end
    local blueLogicActive = self:sv_isLogicColorActive(BLUE_LOGIC_COLOR)
    local manualInputLimit = math.rad(self.sv.angleLimit)
    local rollDemand, pitchDemand, yawDemand

    if self:sv_isLogicColorActive(BLACK_LOGIC_COLOR) and not laserGuidanceConnected then
        self:sv_resetPredictionState()
        self.svPreviousHorizontalError = nil
        local horizonRollDemand, horizonPitchDemand = self:sv_getHorizonDemands()
        rollDemand = horizonRollDemand + math.rad(self.sv.rollOffset)
        pitchDemand = horizonPitchDemand + math.rad(self.sv.pitchOffset)
        yawDemand = math.rad(self.sv.yawOffset)
    elseif targetingEnabled then
        local targetPosition = targetCharacter.worldPosition
        -- A laser spot is already the exact ground point: do not lead it as
        -- though it were a moving player or countermeasure.
        if self.sv.predictTarget and not laserGuidanceConnected then
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

function PlaneController.client_onCreate(self)
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
        heatSeeker = DEFAULT_HEAT_SEEKER,
        obstacles = DEFAULT_OBSTACLES,
        overshootEnabled = DEFAULT_OVERSHOOT_ENABLED,
        accelerationOutputEnabled = DEFAULT_ACCELERATION_OUTPUT_ENABLED,
        impactSensitivity = DEFAULT_IMPACT_SENSITIVITY,
        distanceActivationEnabled = false,
        distanceActivation = DEFAULT_DISTANCE_ACTIVATION,
        trackingPovEnabled = DEFAULT_TRACKING_POV_ENABLED,
        trackingFovDegrees = DEFAULT_TRACKING_FOV_DEGREES,
        targetOptionIds = {},
        targetOptionNames = {},
        gui = nil
    }
end

function PlaneController.client_onClientDataUpdate(self, data)
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
    self.cl.heatSeeker = data.heatSeeker == true
    if self.cl.heatSeeker then
        self.cl.trackClosestPlayer = false
    end
    self.cl.obstacles = data.obstacles == true
    self.cl.overshootEnabled = data.overshootEnabled ~= false
    self.cl.accelerationOutputEnabled = data.accelerationOutputEnabled ~= false
    self.cl.impactSensitivity = data.impactSensitivity or DEFAULT_IMPACT_SENSITIVITY
    self.cl.distanceActivationEnabled = data.distanceActivationEnabled == true
    self.cl.distanceActivation = data.distanceActivation or DEFAULT_DISTANCE_ACTIVATION
    self.cl.trackingPovEnabled = data.trackingPovEnabled ~= false
    if self.cl.heatSeeker then
        self.cl.obstacles = true
        self.cl.trackingPovEnabled = true
    end
    self.cl.trackingFovDegrees = data.trackingFovDegrees or DEFAULT_TRACKING_FOV_DEGREES
    self:cl_refreshGui()
end

function PlaneController.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneController.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_plane_controller"))
    return true
end

function PlaneController.cl_buildTargetOptions(self)
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
        if type(target) == "table" then
            local numericTargetId = tonumber(targetId) or tonumber(target.id)
            if numericTargetId ~= nil and target.active == true
                and target.countermeasure ~= true then
                table.insert(presenceOptions, {
                    id = numericTargetId,
                    name = target.name or ("Player Presence [" .. tostring(numericTargetId) .. "]")
                })
            end
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

function PlaneController.client_onInteract(self, _, state)
    if not state then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneController.layout"),
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
        "ImpactSensitivityTopSlider",
        MAX_IMPACT_SENSITIVITY - MIN_IMPACT_SENSITIVITY + 1,
        self.cl.impactSensitivity - MIN_IMPACT_SENSITIVITY,
        "cl_onImpactSensitivitySliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "ImpactSensitivityBottomSlider",
        MAX_IMPACT_SENSITIVITY - MIN_IMPACT_SENSITIVITY + 1,
        self.cl.impactSensitivity - MIN_IMPACT_SENSITIVITY,
        "cl_onImpactSensitivitySliderChanged"
    )
    self.cl.gui:createVerticalSlider(
        "DistanceActivationSlider",
        MAX_DISTANCE_ACTIVATION - MIN_DISTANCE_ACTIVATION + 1,
        self.cl.distanceActivation - MIN_DISTANCE_ACTIVATION,
        "cl_onDistanceActivationSliderChanged"
    )
    self.cl.gui:createVerticalSlider(
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
    self.cl.gui:setButtonCallback("HeatSeekerButton", "cl_onHeatSeekerPressed")
    self.cl.gui:setButtonCallback("TrackingPovButton", "cl_onTrackingPovPressed")
    self.cl.gui:setButtonCallback("PredictTargetButton", "cl_onPredictTargetPressed")
    self.cl.gui:setButtonCallback("ObstaclesButton", "cl_onObstaclesPressed")
    self.cl.gui:setButtonCallback("OvershootButton", "cl_onOvershootPressed")
    self.cl.gui:setButtonCallback("AccelerationOutputButton", "cl_onAccelerationOutputPressed")
    self.cl.gui:setButtonCallback("ImpactTopButton", "cl_onAccelerationOutputPressed")
    self.cl.gui:setButtonCallback("DistanceActivationButton", "cl_onDistanceActivationPressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneController.cl_onAngleSliderChanged(self, sliderPosition)
    self.cl.angleLimit = sliderPosition + MIN_ANGLE_LIMIT
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAngleLimit", self.cl.angleLimit)
end

function PlaneController.cl_onSensitivitySliderChanged(self, sliderPosition)
    self.cl.sensitivity = sliderPosition + MIN_SENSITIVITY
    self:cl_refreshGui()
    self.network:sendToServer("sv_setSensitivity", self.cl.sensitivity)
end

function PlaneController.cl_onRollOffsetSliderChanged(self, sliderPosition)
    self.cl.rollOffset = sliderPosition + MIN_AXIS_OFFSET
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAxisOffset", { axis = "roll", value = self.cl.rollOffset })
end

function PlaneController.cl_onPitchOffsetSliderChanged(self, sliderPosition)
    self.cl.pitchOffset = sliderPosition + MIN_AXIS_OFFSET
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAxisOffset", { axis = "pitch", value = self.cl.pitchOffset })
end

function PlaneController.cl_onYawOffsetSliderChanged(self, sliderPosition)
    self.cl.yawOffset = sliderPosition + MIN_AXIS_OFFSET
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAxisOffset", { axis = "yaw", value = self.cl.yawOffset })
end

function PlaneController.cl_onDampingSliderChanged(self, sliderPosition)
    self.cl.damping = sliderPosition + MIN_DAMPING
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDamping", self.cl.damping)
end

function PlaneController.cl_onWhiteBearingAngleSliderChanged(self, sliderPosition)
    self.cl.whiteBearingAngle = sliderPosition + MIN_WHITE_BEARING_ANGLE
    self:cl_refreshGui()
    self.network:sendToServer("sv_setWhiteBearingAngle", self.cl.whiteBearingAngle)
end

function PlaneController.cl_onTrackClosestPlayerPressed(self)
    self.cl.trackClosestPlayer = not self.cl.trackClosestPlayer
    if self.cl.trackClosestPlayer then
        self.cl.heatSeeker = false
    end
    if not self.cl.trackClosestPlayer then
        self.cl.predictTarget = false
    end
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackClosestPlayer", self.cl.trackClosestPlayer)
end

function PlaneController.cl_onHeatSeekerPressed(self)
    self.cl.heatSeeker = not self.cl.heatSeeker
    if self.cl.heatSeeker then
        self.cl.trackClosestPlayer = false
        self.cl.obstacles = true
        self.cl.trackingPovEnabled = true
    end
    if not self.cl.heatSeeker and not self.cl.trackClosestPlayer then
        self.cl.predictTarget = false
    end
    self:cl_refreshGui()
    self.network:sendToServer("sv_setHeatSeeker", self.cl.heatSeeker)
end

function PlaneController.cl_onTrackingPovPressed(self)
    if self.cl.heatSeeker then
        self.cl.trackingPovEnabled = true
        self:cl_refreshGui()
        return
    end
    self.cl.trackingPovEnabled = not self.cl.trackingPovEnabled
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackingPovEnabled", self.cl.trackingPovEnabled)
end

function PlaneController.cl_onTargetPlayerSelected(self, selectedOption)
    local target = self.cl.targetOptionIds[selectedOption]
    if target == nil then return end

    self.cl.trackTarget = target
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackTarget", target)
end

function PlaneController.cl_onPredictTargetPressed(self)
    self.cl.predictTarget = not self.cl.predictTarget
    self:cl_refreshGui()
    self.network:sendToServer("sv_setPredictTarget", self.cl.predictTarget)
end

function PlaneController.cl_onObstaclesPressed(self)
    if self.cl.heatSeeker then
        self.cl.obstacles = true
        self:cl_refreshGui()
        return
    end
    self.cl.obstacles = not self.cl.obstacles
    self:cl_refreshGui()
    self.network:sendToServer("sv_setObstacles", self.cl.obstacles)
end

function PlaneController.cl_onOvershootPressed(self)
    self.cl.overshootEnabled = not self.cl.overshootEnabled
    self:cl_refreshGui()
    self.network:sendToServer("sv_setOvershootEnabled", self.cl.overshootEnabled)
end

function PlaneController.cl_onAccelerationOutputPressed(self)
    self.cl.accelerationOutputEnabled = not self.cl.accelerationOutputEnabled
    self:cl_refreshGui()
    self.network:sendToServer("sv_setAccelerationOutputEnabled", self.cl.accelerationOutputEnabled)
end

function PlaneController.cl_onImpactSensitivitySliderChanged(self, sliderPosition)
    self.cl.impactSensitivity = clamp(
        math.floor(sliderPosition + 0.5) + MIN_IMPACT_SENSITIVITY,
        MIN_IMPACT_SENSITIVITY,
        MAX_IMPACT_SENSITIVITY
    )
    self:cl_refreshGui()
    self.network:sendToServer("sv_setImpactSensitivity", self.cl.impactSensitivity)
end

function PlaneController.cl_onDistanceActivationPressed(self)
    self.cl.distanceActivationEnabled = not self.cl.distanceActivationEnabled
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDistanceActivationEnabled", self.cl.distanceActivationEnabled)
end

function PlaneController.cl_onDistanceActivationSliderChanged(self, sliderPosition)
    self.cl.distanceActivation = sliderPosition + MIN_DISTANCE_ACTIVATION
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDistanceActivation", self.cl.distanceActivation)
end

function PlaneController.cl_onTrackingFovSliderChanged(self, sliderPosition)
    self.cl.trackingFovDegrees = sliderPosition + MIN_TRACKING_FOV_DEGREES
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackingFovDegrees", self.cl.trackingFovDegrees)
end

function PlaneController.client_onUpdate(self, timeStep)
    if self.cl == nil or self.cl.gui == nil or not self.cl.heatSeeker then
        return
    end

    -- Heat seeker always requires both visibility safeguards. Re-apply this
    -- every frame so the checkbox skin cannot remain visually unchecked after
    -- a click event toggles it internally.
    self.cl.obstacles = true
    self.cl.trackingPovEnabled = true
    self.cl.gui:setButtonState("TrackingPovButton", true)
    self.cl.gui:setButtonState("ObstaclesButton", true)
end

function PlaneController.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    local targetingEnabled = self.cl.trackClosestPlayer or self.cl.heatSeeker
    if self.cl.heatSeeker then
        self.cl.obstacles = true
        self.cl.trackingPovEnabled = true
    end
    if not targetingEnabled then
        self.cl.predictTarget = false
    end
    local impactCompactVisible = self.cl.accelerationOutputEnabled and not targetingEnabled
    local impactBottomVisible = self.cl.accelerationOutputEnabled and targetingEnabled
    self.cl.gui:setText("AngleValueText", string.format("%d°", self.cl.angleLimit))
    self.cl.gui:setText("SensitivityValueText", string.format("%d", self.cl.sensitivity))
    self.cl.gui:setText("RollOffsetValueText", string.format("%+d°", self.cl.rollOffset))
    self.cl.gui:setText("PitchOffsetValueText", string.format("%+d°", self.cl.pitchOffset))
    self.cl.gui:setText("YawOffsetValueText", string.format("%+d°", self.cl.yawOffset))
    self.cl.gui:setText("DampingValueText", string.format("%d", self.cl.damping))
    self.cl.gui:setVisible("DampingHint", self.cl.damping > 10)
    self.cl.gui:setText("WhiteBearingAngleValueText", string.format("%d°", self.cl.whiteBearingAngle))
    self.cl.gui:setButtonState("TrackClosestPlayerButton", self.cl.trackClosestPlayer)
    self.cl.gui:setButtonState("HeatSeekerButton", self.cl.heatSeeker)
    self.cl.gui:setButtonState("TrackingPovButton", self.cl.trackingPovEnabled)
    self.cl.gui:setButtonState("PredictTargetButton", self.cl.predictTarget)
    self.cl.gui:setButtonState("ObstaclesButton", self.cl.obstacles)
    self.cl.gui:setButtonState("OvershootButton", self.cl.overshootEnabled)
    self.cl.gui:setButtonState("AccelerationOutputButton", self.cl.accelerationOutputEnabled)
    self.cl.gui:setButtonState("ImpactTopButton", self.cl.accelerationOutputEnabled)
    self.cl.gui:setButtonState("DistanceActivationButton", self.cl.distanceActivationEnabled)
    self.cl.gui:setText(
        "ImpactSensitivityTopValueText",
        string.format("%d blocks/s^2", self.cl.impactSensitivity)
    )
    self.cl.gui:setText(
        "ImpactSensitivityBottomValueText",
        string.format("%d blocks/s^2", self.cl.impactSensitivity)
    )
    self.cl.gui:setText("DistanceActivationValueText", string.format("%d", self.cl.distanceActivation))
    self.cl.gui:setText("TrackingFovValueText", string.format("%d°", self.cl.trackingFovDegrees))
    local selectedOption = self.cl.targetOptionNames[self.cl.trackTarget]
    if selectedOption ~= nil then
        self.cl.gui:setSelectedDropDownItem("TargetPlayerDropDown", selectedOption)
    end
    self.cl.gui:setVisible("TrackPlayerLabel", true)
    self.cl.gui:setVisible("TrackingPovButton", targetingEnabled)
    self.cl.gui:setVisible("TrackingPovLabel", targetingEnabled)
    self.cl.gui:setVisible("TargetPlayerLabel", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("TargetPlayerDropDown", self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("TrackTargetBackground", targetingEnabled)
    self.cl.gui:setVisible("ImpactSensitivityCompactBackground", impactCompactVisible)
    self.cl.gui:setVisible("ImpactSensitivityBottomBackground", impactBottomVisible)
    self.cl.gui:setVisible("FeatureDivider", targetingEnabled)
    self.cl.gui:setVisible("PredictTargetButton", targetingEnabled)
    self.cl.gui:setVisible("PredictTargetLabel", targetingEnabled)
    self.cl.gui:setVisible("OvershootButton", targetingEnabled)
    self.cl.gui:setVisible("OvershootLabel", targetingEnabled)
    self.cl.gui:setVisible("ObstaclesButton", targetingEnabled)
    self.cl.gui:setVisible("ObstaclesLabel", targetingEnabled)
    self.cl.gui:setVisible("AccelerationOutputButton", targetingEnabled and self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("AccelerationOutputLabel", targetingEnabled and self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("ImpactTopLabel", not self.cl.trackClosestPlayer)
    self.cl.gui:setVisible("ImpactTopButton", not self.cl.trackClosestPlayer)
    self.cl.gui:setVisible(
        "ImpactSensitivityTopLabel",
        impactCompactVisible
    )
    self.cl.gui:setVisible(
        "ImpactSensitivityTopSlider",
        impactCompactVisible
    )
    self.cl.gui:setVisible(
        "ImpactSensitivityTopValue",
        impactCompactVisible
    )
    self.cl.gui:setVisible(
        "ImpactSensitivityBottomLabel",
        impactBottomVisible
    )
    self.cl.gui:setVisible(
        "ImpactSensitivityBottomSlider",
        impactBottomVisible
    )
    self.cl.gui:setVisible(
        "ImpactSensitivityBottomValue",
        impactBottomVisible
    )
    self.cl.gui:setVisible("DistanceActivationButton", targetingEnabled)
    self.cl.gui:setVisible("DistanceActivationLabel", targetingEnabled)
    self.cl.gui:setVisible(
        "TrackingFovLabel",
        targetingEnabled and self.cl.trackingPovEnabled
    )
    self.cl.gui:setVisible(
        "TrackingFovPanel",
        targetingEnabled and self.cl.trackingPovEnabled
    )
    self.cl.gui:setVisible(
        "DistanceRangeLabel",
        targetingEnabled and self.cl.distanceActivationEnabled
    )
    self.cl.gui:setVisible(
        "DistanceActivationPanel",
        targetingEnabled and self.cl.distanceActivationEnabled
    )
    self.cl.gui:setVisible(
        "DistanceActivationValue",
        targetingEnabled and self.cl.distanceActivationEnabled
    )
    self.cl.gui:setVisible(
        "DistanceActivationSlider",
        targetingEnabled and self.cl.distanceActivationEnabled
    )
    self.cl.gui:setVisible("TrackingFovValue", targetingEnabled and self.cl.trackingPovEnabled)
    self.cl.gui:setVisible("TrackingFovSlider", targetingEnabled and self.cl.trackingPovEnabled)
end

function PlaneController.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
