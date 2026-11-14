dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
TurretController = class()

if PlaneConstructLaserGuidanceTargets == nil then PlaneConstructLaserGuidanceTargets = {} end

TurretController.maxParentCount = 4
TurretController.maxChildCount = -1
TurretController.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.logic
TurretController.connectionOutput = sm.interactable.connectionType.bearing + sm.interactable.connectionType.logic
TurretController.colorNormal = sm.color.new(0x4b4b4bff)
TurretController.colorHighlight = sm.color.new(0x777777ff)

local DEFAULT_HORIZONTAL_LIMIT = 360
local MIN_HORIZONTAL_LIMIT = 0
local MAX_HORIZONTAL_LIMIT = 360
local DEFAULT_VERTICAL_LIMIT = 90
local MIN_VERTICAL_LIMIT = 0
local MAX_VERTICAL_LIMIT = 90
local DEFAULT_ROTATION_SPEED = 30
local MIN_ROTATION_SPEED = 0
local MAX_ROTATION_SPEED = 300
local DEFAULT_YAW_ROTATION_SPEED = DEFAULT_ROTATION_SPEED
local DEFAULT_PITCH_ROTATION_SPEED = DEFAULT_ROTATION_SPEED
local DEFAULT_PITCH_OFFSET_BLOCKS = 0
local MIN_PITCH_OFFSET_BLOCKS = -50
local MAX_PITCH_OFFSET_BLOCKS = 50
local DEFAULT_HOLD_BEARINGS_ON_SEAT_EXIT = false
local DEFAULT_FORCE = 50
local MIN_FORCE = 0
local MAX_FORCE = 100
local DEFAULT_TRACK_PLAYER = false
local DEFAULT_TRACK_TARGET = "closest"
local DEFAULT_PREDICT_TARGET = false
local DEFAULT_PROJECTILE_SPEED = 700
local MIN_PROJECTILE_SPEED = 0.1
local MAX_PROJECTILE_SPEED = 999999
local DEFAULT_PROJECTILE_GRAVITY = 10
local MIN_PROJECTILE_GRAVITY = -999999
local MAX_PROJECTILE_GRAVITY = 999999
local DEFAULT_BOMB_CALCULATOR = false
local DEFAULT_FINNED_BOMBS = false
local BOMB_CALCULATOR_GRAVITY = DEFAULT_PROJECTILE_GRAVITY
local DEFAULT_TRACKING_POV_ENABLED = true
local DEFAULT_TRACKING_FOV_DEGREES = 60
local MIN_TRACKING_FOV_DEGREES = 10
local MAX_TRACKING_FOV_DEGREES = 180

-- Bearing:setMotorVelocity uses angular velocity in degrees/second and the
-- second argument as the bearing motor's maximum impulse. The UI exposes the
-- latter as a percentage so builders do not need to know engine units.
local MIN_MOTOR_IMPULSE = 0
local MAX_MOTOR_IMPULSE = 5000
local TARGET_DEAD_ZONE = math.rad(0.25)
local MAX_PREDICTION_TIME = 10.0
local PREDICTION_ITERATIONS = 8
local PREDICTION_MAX_ACCELERATION = 30.0
local PREDICTION_ACCELERATION_SMOOTHING = 0.25
local BOMB_DRAG_COEFFICIENT = 0.00025
-- Cannons Pack's projectile implementation uses friction = 0.003 on each
-- fixed step. Using 0.025 here over-damps the forward velocity and produces
-- the roughly four-times-too-short sight seen with the 2.5% assumption.
local BOMB_BASE_FRICTION = 0.003
local BOMB_SIMULATION_TIME_STEP = 1 / 40
local BOMB_VELOCITY_DAMPING = 1 - BOMB_BASE_FRICTION
-- Small empirical correction for the remaining difference between the
-- calculator trajectory and the tested bomb's observed ground range.
local BOMB_RANGE_SCALE = 0.75
-- Finned bombs lose additional horizontal range at high altitude.  This
-- correction is applied on top of the baseline range scale and is measured
-- in blocks above the sampled ground point: 1.10 at ground level and 0.73 at
-- 4,000 blocks.  Keep a floor for extreme heights.
local FINNED_BOMB_ALTITUDE_FACTOR_FLOOR = 0.5
local BOMB_MAX_SIMULATION_TIME = 12.0
local BOMB_MAX_DYNAMIC_SIMULATION_TIME = 60.0
local BLOCKS_PER_WORLD_UNIT = 4.0
local TRACK_LOSS_DISTANCE_BLOCKS = 500.0
local PLANE_RADAR_SCREEN_UUID = "0307d97e-1016-4131-9ca2-7c1d653d3f69"
local RADAR_DATA_SCREEN_UUID = "9e1fd450-3e60-4ce8-86dd-e0ee5ced4b77"
local SEAT_CAMERA_UUID = "2e0055c8-90ca-4a5f-9491-da57b5f3fe42"
local LASER_GUIDANCE_MODULE_UUID = "e5a7b9c1-0d23-4f56-9a78-1b2c3d4e5678"
local PLANE_RADAR_REGISTRY_PREFIX = "PlaneRadarScreen:"
local LASER_GUIDANCE_REGISTRY_PREFIX = "PlaneConstructLaserGuidance:"
local PLAYER_LOCK_REGISTRY_PREFIX = "PlaneConstructTurretControllerLock:"
local PRESENCE_REGISTRY_NAME = "PlaneConstructPresenceTargets"
local DEFAULT_TRACKING_LOGIC_IS_REQUIRED = false
local WORLD_UP = sm.vec3.new(0, 0, 1)
local TWO_PI = math.pi * 2
local GEOLOCK_RAY_DISTANCE = 10000
local CAMERA_MOVEMENT_DEAD_ZONE = math.rad(0.35)
local CAMERA_SETTLE_TICKS = 4

local RED_BEARING_COLORS = {
    f06767ff = true,
    d02525ff = true,
    ["7c0000ff"] = true,
    ["560202ff"] = true
}

local BLUE_BEARING_COLORS = {
    ["4c6fe3ff"] = true,
    ["0a3ee2ff"] = true,
    ["0f2e91ff"] = true,
    ["0a1d5aff"] = true
}

local RED_LOGIC_COLORS = {
    f06767ff = true,
    d02525ff = true,
    ["7c0000ff"] = true,
    ["560202ff"] = true
}

local WHITE_LOGIC_COLORS = {
    eeeeeeFF = true,
    eeeeee = true
}

local BLACK_LOGIC_COLORS = {
    ["222222ff"] = true,
    ["111111ff"] = true,
    ["000000ff"] = true
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function clampInteger(value, minimum, maximum, defaultValue)
    local numericValue = tonumber(value)
    if numericValue == nil then numericValue = defaultValue end
    return clamp(math.floor(numericValue + 0.5), minimum, maximum)
end

local function clampNumber(value, minimum, maximum, defaultValue)
    local numericValue = tonumber(value)
    if numericValue == nil then numericValue = defaultValue end
    return clamp(numericValue, minimum, maximum)
end

local function normalizeAngle(angle)
    while angle > math.pi do angle = angle - TWO_PI end
    while angle < -math.pi do angle = angle + TWO_PI end
    return angle
end

local function bearingColor(bearing)
    return string.lower(tostring(bearing:getColor()))
end

local function configuredBearingRole(bearing)
    local color = bearingColor(bearing)
    if RED_BEARING_COLORS[color] then return "horizontal" end
    if BLUE_BEARING_COLORS[color] then return "vertical" end
    return nil
end

local function motorImpulse(forcePercent)
    return MAX_MOTOR_IMPULSE * clamp(forcePercent, 0, 100) / 100
end

local function isValidTargetId(targetId)
    return targetId == DEFAULT_TRACK_TARGET or type(targetId) == "number"
end

function TurretController.server_onCreate(self)
    self:sv_initialize()
end

function TurretController.server_onRefresh(self)
    self:sv_initialize()
end

function TurretController.server_onDestroy(self)
    _G[PLAYER_LOCK_REGISTRY_PREFIX .. tostring(self.interactable:getId())] = nil
end

function TurretController.sv_initialize(self)
    local stored = self.storage:load()
    local storedTable = type(stored) == "table" and stored or {}
    local legacyRotationSpeed = clampInteger(
        storedTable.rotationSpeed,
        MIN_ROTATION_SPEED,
        MAX_ROTATION_SPEED,
        DEFAULT_ROTATION_SPEED
    )
    local storedTrackTarget = storedTable.trackTarget or DEFAULT_TRACK_TARGET
    if not isValidTargetId(storedTrackTarget) then
        storedTrackTarget = DEFAULT_TRACK_TARGET
    end
    local storedBombCalculator = storedTable.bombCalculator == true
    local storedTrackPlayer = storedTable.trackPlayer == true and not storedBombCalculator

    local storedExceptions = storedTable.exceptionPlayerIds or {}
    if type(storedExceptions) ~= "table" then storedExceptions = {} end

    self.sv = {
        horizontalLimit = clampInteger(
            storedTable.horizontalLimit,
            MIN_HORIZONTAL_LIMIT,
            MAX_HORIZONTAL_LIMIT,
            DEFAULT_HORIZONTAL_LIMIT
        ),
        verticalLimit = clampInteger(
            storedTable.verticalLimit,
            MIN_VERTICAL_LIMIT,
            MAX_VERTICAL_LIMIT,
            DEFAULT_VERTICAL_LIMIT
        ),
        yawRotationSpeed = clampInteger(
            storedTable.yawRotationSpeed,
            MIN_ROTATION_SPEED,
            MAX_ROTATION_SPEED,
            legacyRotationSpeed
        ),
        pitchRotationSpeed = clampInteger(
            storedTable.pitchRotationSpeed,
            MIN_ROTATION_SPEED,
            MAX_ROTATION_SPEED,
            legacyRotationSpeed
        ),
        pitchOffsetBlocks = clampInteger(
            storedTable.pitchOffsetBlocks,
            MIN_PITCH_OFFSET_BLOCKS,
            MAX_PITCH_OFFSET_BLOCKS,
            DEFAULT_PITCH_OFFSET_BLOCKS
        ),
        force = clampInteger(storedTable.force, MIN_FORCE, MAX_FORCE, DEFAULT_FORCE),
        holdBearingsOnSeatExit = storedTable.holdBearingsOnSeatExit == true,
        trackPlayer = storedTrackPlayer,
        trackTarget = storedTrackTarget,
        predictTarget = storedTable.predictTarget == true and storedTrackPlayer,
        projectileSpeed = clampNumber(
            storedTable.projectileSpeed,
            MIN_PROJECTILE_SPEED,
            MAX_PROJECTILE_SPEED,
            DEFAULT_PROJECTILE_SPEED
        ),
        projectileGravity = clampNumber(
            storedTable.projectileGravity,
            MIN_PROJECTILE_GRAVITY,
            MAX_PROJECTILE_GRAVITY,
            DEFAULT_PROJECTILE_GRAVITY
        ),
        bombCalculator = storedBombCalculator,
        finnedBombs = storedTable.finnedBombs == true and storedBombCalculator,
        trackingPovEnabled = storedTable.trackingPovEnabled ~= false,
        trackingFovDegrees = clampInteger(
            storedTable.trackingFovDegrees,
            MIN_TRACKING_FOV_DEGREES,
            MAX_TRACKING_FOV_DEGREES,
            DEFAULT_TRACKING_FOV_DEGREES
        ),
        exceptionPlayerIds = storedExceptions
    }

    self.svTrackedTargetId = nil
    self.svTrackedTargetVelocity = nil
    self.svTrackedTargetAcceleration = sm.vec3.new(0, 0, 0)
    self.svPreviousRedLogicActive = false
    self.svBlackLockedPoint = nil
    self.svPreviousBlackLogicActive = false
    self.svBlackCameraMoving = false
    self.svBlackStationaryTicks = 0
    self.svPreviousCameraLocalYaw = nil
    self.svPreviousCameraLocalPitch = nil
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_syncClientData(self)
    self.network:setClientData({
        horizontalLimit = self.sv.horizontalLimit,
        verticalLimit = self.sv.verticalLimit,
        yawRotationSpeed = self.sv.yawRotationSpeed,
        pitchRotationSpeed = self.sv.pitchRotationSpeed,
        pitchOffsetBlocks = self.sv.pitchOffsetBlocks,
        holdBearingsOnSeatExit = self.sv.holdBearingsOnSeatExit,
        force = self.sv.force,
        trackPlayer = self.sv.trackPlayer,
        trackTarget = self.sv.trackTarget,
        predictTarget = self.sv.predictTarget,
        projectileSpeed = self.sv.projectileSpeed,
        projectileGravity = self.sv.projectileGravity,
        bombCalculator = self.sv.bombCalculator,
        finnedBombs = self.sv.finnedBombs,
        trackingPovEnabled = self.sv.trackingPovEnabled,
        trackingFovDegrees = self.sv.trackingFovDegrees
    })
end

function TurretController.sv_setInteger(self, field, requestedValue, minimum, maximum)
    local numericValue = tonumber(requestedValue)
    if numericValue == nil then return end
    local value = clamp(math.floor(numericValue + 0.5), minimum, maximum)
    if value == self.sv[field] then return end
    self.sv[field] = value
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setNumber(self, field, requestedValue, minimum, maximum)
    local numericValue = tonumber(requestedValue)
    if numericValue == nil then return end
    local value = clamp(numericValue, minimum, maximum)
    if value == self.sv[field] then return end
    self.sv[field] = value
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setHorizontalLimit(self, value)
    self:sv_setInteger("horizontalLimit", value, MIN_HORIZONTAL_LIMIT, MAX_HORIZONTAL_LIMIT)
end

function TurretController.sv_setVerticalLimit(self, value)
    self:sv_setInteger("verticalLimit", value, MIN_VERTICAL_LIMIT, MAX_VERTICAL_LIMIT)
end

function TurretController.sv_setYawRotationSpeed(self, value)
    self:sv_setInteger("yawRotationSpeed", value, MIN_ROTATION_SPEED, MAX_ROTATION_SPEED)
end

function TurretController.sv_setPitchRotationSpeed(self, value)
    self:sv_setInteger("pitchRotationSpeed", value, MIN_ROTATION_SPEED, MAX_ROTATION_SPEED)
end

function TurretController.sv_setRotationSpeed(self, value)
    -- Compatibility handler for controllers configured by an older client.
    self:sv_setYawRotationSpeed(value)
    self:sv_setPitchRotationSpeed(value)
end

function TurretController.sv_setPitchOffsetBlocks(self, value)
    self:sv_setInteger(
        "pitchOffsetBlocks",
        value,
        MIN_PITCH_OFFSET_BLOCKS,
        MAX_PITCH_OFFSET_BLOCKS
    )
end

function TurretController.sv_setHoldBearingsOnSeatExit(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.holdBearingsOnSeatExit then return end
    self.sv.holdBearingsOnSeatExit = requestedState
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setForce(self, value)
    self:sv_setInteger("force", value, MIN_FORCE, MAX_FORCE)
end

function TurretController.sv_setTrackPlayer(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    local bombCalculatorChanged = false
    if requestedState and self.sv.bombCalculator then
        self.sv.bombCalculator = false
        self.sv.finnedBombs = false
        bombCalculatorChanged = true
    end
    if requestedState == self.sv.trackPlayer and not bombCalculatorChanged then return end
    self.sv.trackPlayer = requestedState
    if not requestedState then self.sv.predictTarget = false end
    self:sv_resetPredictionState()
    self.svBlackLockedPoint = nil
    self.svBlackCameraMoving = false
    self.svBlackStationaryTicks = 0
    self.svPreviousCameraLocalYaw = nil
    self.svPreviousCameraLocalPitch = nil
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setTrackTarget(self, requestedTarget)
    if not isValidTargetId(requestedTarget) then return end
    if type(requestedTarget) == "number"
        and self:sv_getPlayerById(requestedTarget) == nil
        and self:sv_getPresenceTargetById(requestedTarget) == nil then
        return
    end
    if requestedTarget == self.sv.trackTarget then return end
    self.sv.trackTarget = requestedTarget
    self:sv_resetPredictionState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setPredictTarget(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.predictTarget then return end
    self.sv.predictTarget = requestedState and self.sv.trackPlayer
    self:sv_resetPredictionState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setProjectileSpeed(self, value)
    self:sv_setNumber("projectileSpeed", value, MIN_PROJECTILE_SPEED, MAX_PROJECTILE_SPEED)
end

function TurretController.sv_setProjectileGravity(self, value)
    self:sv_setNumber("projectileGravity", value, MIN_PROJECTILE_GRAVITY, MAX_PROJECTILE_GRAVITY)
end

function TurretController.sv_setBombCalculator(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    local trackPlayerChanged = false
    if requestedState and self.sv.trackPlayer then
        self.sv.trackPlayer = false
        self.sv.predictTarget = false
        trackPlayerChanged = true
    end
    if requestedState == self.sv.bombCalculator and not trackPlayerChanged then return end
    self.sv.bombCalculator = requestedState
    if not requestedState then self.sv.finnedBombs = false end
    self:sv_resetPredictionState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setFinnedBombs(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    local value = requestedState and self.sv.bombCalculator
    if value == self.sv.finnedBombs then return end
    self.sv.finnedBombs = value
    self:sv_resetPredictionState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setTrackingPovEnabled(self, requestedState)
    if type(requestedState) ~= "boolean" then return end
    if requestedState == self.sv.trackingPovEnabled then return end
    self.sv.trackingPovEnabled = requestedState
    self:sv_resetPredictionState()
    self.storage:save(self.sv)
    self:sv_syncClientData()
end

function TurretController.sv_setTrackingFovDegrees(self, value)
    self:sv_setInteger(
        "trackingFovDegrees",
        value,
        MIN_TRACKING_FOV_DEGREES,
        MAX_TRACKING_FOV_DEGREES
    )
end

function TurretController.sv_getPlayerById(self, playerId)
    for _, player in ipairs(sm.player.getAllPlayers()) do
        if player:getId() == playerId then return player end
    end
    return nil
end

function TurretController.sv_getPresenceTargetById(self, targetId)
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

function TurretController.sv_isPlayerException(self, playerId)
    for _, exceptionPlayerId in ipairs(self.sv.exceptionPlayerIds) do
        if tonumber(exceptionPlayerId) == playerId then return true end
    end
    return false
end

function TurretController.sv_addPlayerException(self, playerId)
    if playerId == nil or self:sv_isPlayerException(playerId) then return end
    table.insert(self.sv.exceptionPlayerIds, playerId)
    self.storage:save(self.sv)
end

function TurretController.sv_isTargetInsideTrackingPov(self, targetPosition)
    if not self.sv.trackingPovEnabled then return true end
    local toTarget = targetPosition - self.shape.worldPosition
    local distance = toTarget:length()
    if distance <= 0.001 then return true end
    if distance * BLOCKS_PER_WORLD_UNIT > TRACK_LOSS_DISTANCE_BLOCKS then return true end

    local forward = self.shape:getUp()
    if forward:length() <= 0.001 then return true end
    local direction = toTarget / distance
    local facingDot = clamp((forward / forward:length()):dot(direction), -1, 1)
    return math.acos(facingDot) <= math.rad(self.sv.trackingFovDegrees) * 0.5
end

function TurretController.sv_getClosestPlayer(self)
    local closestPlayer, closestCharacter = nil, nil
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
                    closestPlayer, closestCharacter = player, character
                end
            end
        end
    end
    return closestPlayer, closestCharacter
end

function TurretController.sv_getConnectedRadarTarget(self)
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
                    if selectedPlayerId ~= nil then return selectedPlayerId end
                end
            end
        end
    end
    return nil
end

function TurretController.sv_getConnectedLaserGuidance(self)
    local connected = self.interactable:getParents(sm.interactable.connectionType.logic)
    for _, child in ipairs(self.interactable:getChildren(sm.interactable.connectionType.logic)) do
        table.insert(connected, child)
    end

    for _, interactable in ipairs(connected) do
        local shape = interactable:getShape()
        if shape ~= nil and tostring(sm.shape.getShapeUuid(shape)) == LASER_GUIDANCE_MODULE_UUID then
            -- The module owns this server-side record.  Reading it directly
            -- preserves the exact world-space raycast point and avoids stale
            -- public-data snapshots when the two blocks are on different
            -- creations.
            local data = PlaneConstructLaserGuidanceTargets[interactable:getId()]
            -- The connection itself selects laser mode.  The module may not
            -- have published this tick's spot yet; that must not make the
            -- controller fall back to the player's camera.
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

function TurretController.sv_getLaserGuidanceShape(self)
    local connected = self.interactable:getParents(sm.interactable.connectionType.logic)
    for _, child in ipairs(self.interactable:getChildren(sm.interactable.connectionType.logic)) do
        table.insert(connected, child)
    end

    for _, interactable in ipairs(connected) do
        local shape = interactable:getShape()
        if shape ~= nil and tostring(sm.shape.getShapeUuid(shape)) == LASER_GUIDANCE_MODULE_UUID then
            return shape
        end
    end
    return nil
end

function TurretController.sv_getConnectedSeatCamera(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) then
            local parentShape = parent:getShape()
            if parentShape ~= nil
                and tostring(sm.shape.getShapeUuid(parentShape)) == SEAT_CAMERA_UUID then
                return parentShape
            end
        end
    end
    return nil
end

function TurretController.sv_getSeatParent(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.seated) then return parent end
    end
    return nil
end

function TurretController.sv_getControllingCharacter(self)
    local seat = self:sv_getSeatParent()
    -- The seat may be connected only to the copied Seat Camera. In that
    -- layout the camera forwards the seat's view to this controller through
    -- its logic output, so follow the camera's seated parent as well.
    if seat == nil then
        local cameraShape = self:sv_getConnectedSeatCamera()
        if cameraShape ~= nil and cameraShape.interactable ~= nil then
            for _, parent in ipairs(cameraShape.interactable:getParents()) do
                if parent:hasOutputType(sm.interactable.connectionType.seated) then
                    seat = parent
                    break
                end
            end
        end
    end
    if seat == nil then return nil end
    local seatedCharacter = seat:getSeatCharacter()
    return seatedCharacter ~= nil and sm.exists(seatedCharacter) and seatedCharacter or nil
end

function TurretController.sv_getTrackTarget(self)
    if self.sv.trackTarget == DEFAULT_TRACK_TARGET then
        local _, closestCharacter = self:sv_getClosestPlayer()
        return closestCharacter
    end

    local presence = self:sv_getPresenceTargetById(self.sv.trackTarget)
    if presence ~= nil then
        return self:sv_isTargetInsideTrackingPov(presence.worldPosition) and presence or nil
    end

    local player = self:sv_getPlayerById(self.sv.trackTarget)
    if player == nil or self:sv_isPlayerException(player:getId()) then return nil end
    local character = player:getCharacter()
    if character == nil or not sm.exists(character) then return nil end
    return self:sv_isTargetInsideTrackingPov(character.worldPosition) and character or nil
end

function TurretController.sv_publishPlayerLock(self)
    local targetPlayerId = nil
    local targetPlayerName = nil
    local laserGuidanceConnected = self:sv_getConnectedLaserGuidance()
    if not laserGuidanceConnected and self.sv.trackPlayer and self:sv_isLogicInputActive() then
        local target = self:sv_getTrackTarget()
        if target ~= nil and target.isPlayer ~= nil and target:isPlayer() then
            local player = target:getPlayer()
            if player ~= nil then
                targetPlayerId = player:getId()
                targetPlayerName = player:getName()
            end
        end
    end

    _G[PLAYER_LOCK_REGISTRY_PREFIX .. tostring(self.interactable:getId())] = {
        lockActive = targetPlayerId ~= nil,
        targetPlayerId = targetPlayerId,
        targetPlayerName = targetPlayerName,
        sourcePosition = self.shape.worldPosition
    }
end

function TurretController.sv_isLogicInputActive(self)
    local hasLogicParent = false
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) then
            local parentShape = parent:getShape()
            local isSeatCamera = parentShape ~= nil
                and tostring(sm.shape.getShapeUuid(parentShape)) == SEAT_CAMERA_UUID
            local parentColor = parentShape ~= nil
                and string.lower(tostring(parentShape:getColor()))
                or ""
            local isModeInput = BLACK_LOGIC_COLORS[parentColor]
                or RED_LOGIC_COLORS[parentColor]

            -- Black selects geo-lock and red performs the target-exception
            -- action. They are control inputs, not the controller's enable
            -- input. In particular, an OFF black wire must still leave the
            -- normal camera/bomb-sight path running.
            if not isSeatCamera and not isModeInput then
                hasLogicParent = true
                if parent:isActive() then return true end
            end
        end
    end
    -- A standalone controller is useful for a simple turret. Once a logic
    -- source is connected, its active state becomes the enable signal, just
    -- like Plane Controller and the radar blocks.
    return not hasLogicParent and not DEFAULT_TRACKING_LOGIC_IS_REQUIRED
end

function TurretController.sv_isAnyLogicInputActive(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            return true
        end
    end
    return false
end

function TurretController.sv_isLogicColorActive(self, colors)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            local parentShape = parent:getShape()
            local color = parentShape ~= nil and string.lower(tostring(parentShape:getColor())) or ""
            if colors[color] then return true end
        end
    end
    return false
end

function TurretController.sv_resetPredictionState(self)
    self.svTrackedTargetId = nil
    self.svTrackedTargetVelocity = nil
    self.svTrackedTargetAcceleration = sm.vec3.new(0, 0, 0)
end

function TurretController.sv_getAimOrigin(self)
    -- Positive values treat the pitch bearing as being above the controller;
    -- negative values treat it as being below the controller.
    return self.shape.worldPosition
        + WORLD_UP * (self.sv.pitchOffsetBlocks / BLOCKS_PER_WORLD_UNIT)
end

function TurretController.sv_getGeoLockPoint(self, origin, direction, ignoredBody)
    if direction == nil or direction:length() <= 0.001 then return nil end
    local normalizedDirection = direction / direction:length()
    origin = origin or self:sv_getAimOrigin()
    local hit, result = sm.physics.raycast(
        origin,
        origin + normalizedDirection * GEOLOCK_RAY_DISTANCE,
        ignoredBody or self.shape.body,
        sm.physics.filter.terrainSurface
    )
    if hit and result ~= nil and result.pointWorld ~= nil then
        return result.pointWorld
    end
    return nil
end

function TurretController.sv_getCameraLocalAngles(self, direction)
    local forward = self.shape:getUp()
    local right = self.shape:getRight()
    local up = self.shape:getAt()
    if forward == nil or right == nil or up == nil
        or forward:length() <= 0.001
        or right:length() <= 0.001
        or up:length() <= 0.001 then
        return 0, 0
    end

    forward = forward / forward:length()
    right = right / right:length()
    up = up / up:length()
    local forwardAmount = direction:dot(forward)
    local rightAmount = direction:dot(right)
    local upAmount = direction:dot(up)
    local horizontalAmount = math.sqrt(forwardAmount * forwardAmount + rightAmount * rightAmount)
    return math.atan2(rightAmount, forwardAmount), math.atan2(upAmount, horizontalAmount)
end

function TurretController.sv_hasCameraMoved(self, direction)
    local localYaw, localPitch = self:sv_getCameraLocalAngles(direction)
    local moved = self.svPreviousCameraLocalYaw == nil
        or self.svPreviousCameraLocalPitch == nil
        or math.abs(normalizeAngle(localYaw - self.svPreviousCameraLocalYaw)) > CAMERA_MOVEMENT_DEAD_ZONE
        or math.abs(localPitch - self.svPreviousCameraLocalPitch) > CAMERA_MOVEMENT_DEAD_ZONE
    self.svPreviousCameraLocalYaw = localYaw
    self.svPreviousCameraLocalPitch = localPitch
    return moved
end

function TurretController.sv_getPredictedAimPosition(self, target, timeStep, applyGravity)
    if applyGravity == nil then applyGravity = true end
    local origin = self:sv_getAimOrigin()
    local targetPosition = target.worldPosition
    local targetVelocity = target.velocity or sm.vec3.new(0, 0, 0)
    local targetId = target.id or (target.getId ~= nil and target:getId()) or nil

    if self.svTrackedTargetId ~= targetId or self.svTrackedTargetVelocity == nil then
        self.svTrackedTargetId = targetId
        self.svTrackedTargetVelocity = targetVelocity
        self.svTrackedTargetAcceleration = sm.vec3.new(0, 0, 0)
    elseif timeStep ~= nil and timeStep > 0 then
        local measuredAcceleration = (targetVelocity - self.svTrackedTargetVelocity) / timeStep
        local accelerationLength = measuredAcceleration:length()
        if accelerationLength > PREDICTION_MAX_ACCELERATION then
            measuredAcceleration = measuredAcceleration / accelerationLength * PREDICTION_MAX_ACCELERATION
        end
        self.svTrackedTargetAcceleration = self.svTrackedTargetAcceleration
            + (measuredAcceleration - self.svTrackedTargetAcceleration)
            * PREDICTION_ACCELERATION_SMOOTHING
        self.svTrackedTargetVelocity = targetVelocity
    end

    local projectileSpeed = self.sv.projectileSpeed
    if projectileSpeed <= MIN_PROJECTILE_SPEED then return targetPosition end

    local distance = (targetPosition - origin):length()
    local predictionTime = clamp(distance / projectileSpeed, 0.02, MAX_PREDICTION_TIME)
    local gravityVector = WORLD_UP * (-self.sv.projectileGravity)
    local predictedTarget = targetPosition
    local aimDisplacement = targetPosition - origin

    for _ = 1, PREDICTION_ITERATIONS do
        predictedTarget = targetPosition
            + targetVelocity * predictionTime
            + self.svTrackedTargetAcceleration * (0.5 * predictionTime * predictionTime)
        if applyGravity then
            -- Projectile position is origin + direction * speed * t + 1/2*g*t^2.
            -- Remove gravity from the desired displacement to obtain the launch
            -- direction that reaches the moving target at this time.
            aimDisplacement = predictedTarget - origin
                - gravityVector * (0.5 * predictionTime * predictionTime)
        else
            aimDisplacement = predictedTarget - origin
        end
        local nextTime = aimDisplacement:length() / projectileSpeed
        predictionTime = clamp((predictionTime + nextTime) * 0.5, 0.02, MAX_PREDICTION_TIME)
    end

    return applyGravity and origin + aimDisplacement or predictedTarget
end

function TurretController.sv_getGroundPoint(self, position, ignoredBody)
    if position == nil then return nil end

    -- Start the vertical ray at the aircraft's height instead of placing its
    -- start point thousands of units above the world.  The latter can be
    -- outside the physics/raycast volume and makes the calculator silently
    -- fall back to the camera's old aim point.
    local controllerPosition = self.shape.worldPosition
    local rayTop = math.max(position.z + 1, controllerPosition.z + 1)
    local rayOrigin = sm.vec3.new(position.x, position.y, rayTop)
    local rayEnd = rayOrigin - WORLD_UP * GEOLOCK_RAY_DISTANCE
    local hit, result = sm.physics.raycast(
        rayOrigin,
        rayEnd,
        ignoredBody or self.shape.body,
        sm.physics.filter.terrainSurface
    )
    if hit and result ~= nil and result.pointWorld ~= nil then
        return result.pointWorld
    end
    return nil
end

local function simulateBombFall(
    origin,
    initialVelocity,
    groundHeight,
    gravity,
    withDrag,
    maxSimulationTime
)
    local position = origin
    local velocity = initialVelocity
    local elapsed = 0
    maxSimulationTime = maxSimulationTime or BOMB_MAX_SIMULATION_TIME

    while elapsed < maxSimulationTime do
        local previousPosition = position

        local dampingMultiplier = BOMB_VELOCITY_DAMPING
        local velocityLength = velocity:length()
        if withDrag then
            local finDrag = clamp(
                1 - BOMB_DRAG_COEFFICIENT
                    * velocityLength
                    * BOMB_SIMULATION_TIME_STEP,
                0.05,
                1
            )
            dampingMultiplier = dampingMultiplier * finDrag
        end

        -- Match the game's projectile implementation exactly: damping is
        -- applied to the existing velocity first, then gravity is integrated.
        -- Gravity must not itself be reduced by the friction multiplier.
        velocity = velocity * dampingMultiplier
            - WORLD_UP * gravity * BOMB_SIMULATION_TIME_STEP
        position = position + velocity * BOMB_SIMULATION_TIME_STEP
        elapsed = elapsed + BOMB_SIMULATION_TIME_STEP

        if position.z <= groundHeight then
            local span = previousPosition.z - position.z
            local fraction = span > 0
                and clamp((previousPosition.z - groundHeight) / span, 0, 1)
                or 1
            return sm.vec3.new(
                previousPosition.x + (position.x - previousPosition.x) * fraction,
                previousPosition.y + (position.y - previousPosition.y) * fraction,
                groundHeight
            )
        end
    end

    return nil
end

local function getFinnedBombAltitudeFactor(altitudeBlocks)
    altitudeBlocks = math.max(0, altitudeBlocks)
    return clamp(
        1.10 - 0.37 * (altitudeBlocks / 4000),
        FINNED_BOMB_ALTITUDE_FACTOR_FLOOR,
        1.10
    )
end

function TurretController.sv_getBombLandingPosition(self, origin)
    local groundPoint = self:sv_getGroundPoint(origin, self.shape.body)
    if groundPoint == nil then return nil end

    local aircraftVelocity = self.shape:getVelocity()
    local gravity = math.max(0, BOMB_CALCULATOR_GRAVITY)
    local landingPoint = groundPoint

    -- Re-sample the terrain below the estimated impact point so the sight
    -- follows slopes and hills instead of treating the whole world as flat.
    for _ = 1, 3 do
        -- Both modes include the projectile's baseline friction. Finned
        -- bombs additionally apply the aerodynamic fin-drag term.
        local verticalDrop = math.max(0, origin.z - groundPoint.z)
        local upwardVelocity = math.max(0, aircraftVelocity.z)
        local simulationTimeLimit = BOMB_MAX_DYNAMIC_SIMULATION_TIME
        if gravity > 0.001 then
            -- Use a conservative free-fall estimate so high-altitude bombs
            -- do not hit the old fixed timeout before reaching the ground.
            local estimatedFallTime = (
                upwardVelocity
                + math.sqrt(upwardVelocity * upwardVelocity + 2 * gravity * verticalDrop)
            ) / gravity
            simulationTimeLimit = clamp(
                estimatedFallTime * 2 + 2,
                BOMB_MAX_SIMULATION_TIME,
                BOMB_MAX_DYNAMIC_SIMULATION_TIME
            )
        end
        landingPoint = simulateBombFall(
            origin,
            aircraftVelocity,
            groundPoint.z,
            gravity,
            self.sv.finnedBombs,
            simulationTimeLimit
        )
        if landingPoint == nil then return groundPoint end

        local futureGround = self:sv_getGroundPoint(landingPoint, self.shape.body)
        if futureGround == nil then break end
        groundPoint = futureGround
    end
    local rangeScale = BOMB_RANGE_SCALE
    if self.sv.finnedBombs then
        local altitudeBlocks = math.max(0, origin.z - groundPoint.z) * BLOCKS_PER_WORLD_UNIT
        rangeScale = rangeScale * getFinnedBombAltitudeFactor(altitudeBlocks)
    end

    local horizontalOffset = landingPoint - origin
    horizontalOffset = sm.vec3.new(
        horizontalOffset.x * rangeScale,
        horizontalOffset.y * rangeScale,
        0
    )
    return sm.vec3.new(
        origin.x + horizontalOffset.x,
        origin.y + horizontalOffset.y,
        groundPoint.z
    )
end

function TurretController.sv_getAimAngles(self, direction)
    if direction == nil or direction:length() <= 0.001 then return 0, 0 end

    -- Convert the world-space target into the controller's neutral bearing
    -- frame. A world elevation is not the same thing as a bearing pitch when
    -- the aircraft is pitched, and aircraft roll couples yaw into pitch.
    local shapeForward = self.shape:getUp()
    local shapeForwardLength = shapeForward:length()
    if shapeForwardLength <= 0.001 then return 0, 0 end
    shapeForward = shapeForward / shapeForwardLength

    local levelForward = shapeForward - WORLD_UP * shapeForward:dot(WORLD_UP)
    local levelForwardLength = levelForward:length()
    if levelForwardLength <= 0.001 then
        local fallbackForward = self.shape:getAt()
        fallbackForward = fallbackForward - WORLD_UP * fallbackForward:dot(WORLD_UP)
        levelForwardLength = fallbackForward:length()
        if levelForwardLength > 0.001 then
            levelForward = fallbackForward
        end
    end
    if levelForwardLength <= 0.001 then
        levelForward = sm.vec3.new(1, 0, 0)
        levelForwardLength = 1
    end
    levelForward = levelForward / levelForwardLength

    local worldRight = levelForward:cross(WORLD_UP)
    local normalizedDirection = direction / direction:length()
    local forwardAmount = normalizedDirection:dot(levelForward)
    local rightAmount = normalizedDirection:dot(worldRight)
    local upAmount = normalizedDirection:dot(WORLD_UP)
    local horizontalAmount = math.sqrt(forwardAmount * forwardAmount + rightAmount * rightAmount)

    local targetElevation = math.atan2(upAmount, horizontalAmount)
    local controllerElevation = math.atan2(shapeForward:dot(WORLD_UP), levelForwardLength)
    local horizontalError = math.atan2(rightAmount, forwardAmount)
    local verticalError = targetElevation - controllerElevation

    local shapeRight = self.shape:getRight()
    local shapeAt = self.shape:getAt()
    local rollProjectionLength = math.sqrt(shapeRight.z * shapeRight.z + shapeAt.z * shapeAt.z)
    local creationRoll = 0
    if rollProjectionLength > 0.001 then
        creationRoll = math.atan2(shapeRight.z, shapeAt.z)
    end

    local rollCos = math.cos(creationRoll)
    local rollSin = math.sin(creationRoll)
    local rollAdjustedVerticalError = verticalError * rollCos + horizontalError * rollSin
    local rollAdjustedHorizontalError = -verticalError * rollSin + horizontalError * rollCos

    local horizontalLimit = math.rad(self.sv.horizontalLimit) * 0.5
    local verticalLimit = math.rad(self.sv.verticalLimit)
    if self.sv.horizontalLimit >= MAX_HORIZONTAL_LIMIT then
        horizontalLimit = math.pi
    end

    return clamp(rollAdjustedHorizontalError, -horizontalLimit, horizontalLimit),
        clamp(rollAdjustedVerticalError, -verticalLimit, verticalLimit)
end

function TurretController.sv_getLaserAimAngles(self, direction)
    if direction == nil or direction:length() <= 0.001 then return 0, 0 end

    -- Laser guidance is purely geometric: convert the vector from the
    -- controller to the laser spot into the controller's own frame.
    local forward = self.shape:getAt()
    local right = self.shape:getRight()
    local up = self.shape:getUp()
    if forward == nil or right == nil or up == nil
        or forward:length() <= 0.001
        or right:length() <= 0.001
        or up:length() <= 0.001 then
        return 0, 0
    end

    forward = forward / forward:length()
    right = right / right:length()
    up = up / up:length()
    local normalizedDirection = direction / direction:length()
    local forwardAmount = normalizedDirection:dot(forward)
    local rightAmount = normalizedDirection:dot(right)
    local upAmount = normalizedDirection:dot(up)
    local horizontalAmount = math.sqrt(
        forwardAmount * forwardAmount + rightAmount * rightAmount
    )

    local horizontalAngle
    if horizontalAmount <= 0.05 and self.svLaserHorizontalAngle ~= nil then
        -- At exactly vertical aim, yaw has no mathematical meaning. Keep the
        -- last yaw instead of allowing tiny floating-point values to choose
        -- the opposite side and flip the turret by 180 degrees.
        horizontalAngle = self.svLaserHorizontalAngle
    else
        horizontalAngle = math.atan2(rightAmount, forwardAmount)
        while horizontalAngle > math.pi do horizontalAngle = horizontalAngle - math.pi * 2 end
        while horizontalAngle < -math.pi do horizontalAngle = horizontalAngle + math.pi * 2 end
        if self.svLaserHorizontalAngle ~= nil then
            local delta = horizontalAngle - self.svLaserHorizontalAngle
            while delta > math.pi do delta = delta - math.pi * 2 end
            while delta < -math.pi do delta = delta + math.pi * 2 end
            horizontalAngle = self.svLaserHorizontalAngle + delta
        end
    end

    self.svLaserHorizontalAngle = horizontalAngle
    return horizontalAngle, math.atan2(upAmount, horizontalAmount)
end

function TurretController.sv_applyLaserGuidance(self, bearings, target)
    if self:sv_getLaserGuidanceShape() == nil or target == nil or target.worldPosition == nil then
        self.svLaserHorizontalAngle = nil
        self.svLaserYawError = nil
        self:sv_setBearingsNeutral(bearings)
        return false
    end

    -- The module publishes an absolute world-space laser spot.  Build the
    -- vector from the module's current world position to that spot.  The
    -- module position is important because it moves with the guided turret;
    -- using the controller position introduces a parallax error.
    local origin = target.receiverPosition or self.shape.worldPosition
    local aimDirection = target.worldPosition - origin
    if aimDirection:length() <= 0.001 then
        self.svLaserHorizontalAngle = nil
        self.svLaserYawError = nil
        self:sv_setBearingsNeutral(bearings)
        return false
    end

    -- Convert the vector to the laser spot directly into the controller's
    -- neutral frame.  This is an absolute aim command: neither the emitter's
    -- orientation nor the receiver's current orientation is used as a
    -- reference.  That prevents the receiver from chasing the emitter's
    -- rotation and keeps atan2 valid in all four horizontal quadrants.
    local horizontalAngle, verticalAngle = self:sv_getAimAngles(aimDirection)

    local impulse = motorImpulse(self.sv.force)
    local roles = self:sv_getBearingRoles(bearings)

    for index, bearing in ipairs(bearings) do
        local role = roles[index]
        if role ~= nil then
            local targetAngle = role == "horizontal" and horizontalAngle
                or role == "vertical" and verticalAngle
                or 0
            local targetVelocity = role == "vertical"
                and self.sv.pitchRotationSpeed or self.sv.yawRotationSpeed
            targetVelocity = math.rad(targetVelocity)
            if math.abs(targetAngle) <= TARGET_DEAD_ZONE then targetAngle = 0 end
            bearing:setTargetAngle(targetAngle, targetVelocity, impulse)
        end
    end
    return true
end

function TurretController.sv_setBearingsNeutral(self, bearings)
    local impulse = motorImpulse(self.sv.force)
    for _, bearing in ipairs(bearings) do
        local role = configuredBearingRole(bearing)
        if role ~= nil then
            local speed = role == "vertical"
                and self.sv.pitchRotationSpeed
                or self.sv.yawRotationSpeed
            bearing:setTargetAngle(0, math.rad(speed), impulse)
        end
    end
end

function TurretController.sv_getBearingRoles(self, bearings)
    local roles = {}
    local hasHorizontal = false
    local hasVertical = false
    for index, bearing in ipairs(bearings) do
        local role = configuredBearingRole(bearing)
        if role == "horizontal" then hasHorizontal = true end
        if role == "vertical" then hasVertical = true end
        roles[index] = role
    end

    -- Preserve the easy two-bearing setup: unpainted first bearing is yaw,
    -- unpainted second bearing is pitch. Explicit red/blue paint wins.
    for index, bearing in ipairs(bearings) do
        if roles[index] == nil then
            local color = bearingColor(bearing)
            if color ~= "eeeeeeff" then
                if not hasHorizontal then
                    roles[index], hasHorizontal = "horizontal", true
                elseif not hasVertical then
                    roles[index], hasVertical = "vertical", true
                end
            end
        end
    end
    return roles
end

function TurretController.server_onFixedUpdate(self, timeStep)
    local bearings = self.interactable:getBearings()
    -- Black is the geo-lock input. When it is on, the controller holds a
    -- ground point; when it is off, the camera is always in normal free aim.
    local geoLockActive = self:sv_isLogicColorActive(BLACK_LOGIC_COLORS)
    local geoLockRising = geoLockActive and not self.svPreviousBlackLogicActive
    local geoLockFalling = not geoLockActive and self.svPreviousBlackLogicActive
    local radarTargetId = self:sv_getConnectedRadarTarget()
    if self.sv.trackPlayer and radarTargetId ~= nil and self.sv.trackTarget ~= radarTargetId then
        self.sv.trackTarget = radarTargetId
        self:sv_resetPredictionState()
        self.storage:save(self.sv)
        self:sv_syncClientData()
    end
    self:sv_publishPlayerLock()

    local laserGuidanceConnected, laserTarget = self:sv_getConnectedLaserGuidance()
    if not laserGuidanceConnected or laserTarget == nil then
        self.svLaserReference = nil
    end

    local redLogicActive = self:sv_isLogicColorActive(RED_LOGIC_COLORS)
    if self.sv.trackPlayer and redLogicActive and not self.svPreviousRedLogicActive then
        local closestPlayer = self:sv_getClosestPlayer()
        if closestPlayer ~= nil then self:sv_addPlayerException(closestPlayer:getId()) end
    end
    self.svPreviousRedLogicActive = redLogicActive

    -- Turning geo-lock on starts a fresh acquisition. Turning it off clears
    -- every lock state so the normal camera path cannot inherit a stale point.
	if geoLockRising then
		self.svBlackLockedPoint = nil
		self.svBlackCameraMoving = false
		self.svBlackStationaryTicks = 0
    end
    if geoLockFalling then
        self.svBlackLockedPoint = nil
        self.svBlackCameraMoving = false
        self.svBlackStationaryTicks = 0
        self.svPreviousCameraLocalYaw = nil
        self.svPreviousCameraLocalPitch = nil
    end
    self.svPreviousBlackLogicActive = geoLockActive

    -- The guidance module owns its enable input. The controller may receive
    -- the module through either side of the logic connection, so requiring a
    -- second active input here could incorrectly force the bearings neutral.
    if not laserGuidanceConnected and self.sv.trackPlayer and not self:sv_isLogicInputActive() then
        self.interactable:setActive(false)
        self:sv_resetPredictionState()
        self:sv_setBearingsNeutral(bearings)
        return
    end

    -- Never fall back to the seated player's camera while a laser module is
    -- connected.  Before a matching spot exists, hold neutral instead; doing
    -- otherwise makes the receiver appear to copy the emitter/operator.
    local target
    if laserGuidanceConnected then
        target = laserTarget
    else
        target = self.sv.trackPlayer and self:sv_getTrackTarget()
            or self:sv_getControllingCharacter()
    end
    if target == nil then
        self.interactable:setActive(false)
        self:sv_resetPredictionState()
        if self.sv.trackPlayer or not self.sv.holdBearingsOnSeatExit then
            self:sv_setBearingsNeutral(bearings)
        end
        return
    end

    self.interactable:setActive(true)

    local targetPosition
    local aimOrigin = self:sv_getAimOrigin()
    if laserGuidanceConnected then
        self.svBlackLockedPoint = nil
        self.svBlackCameraMoving = false
        self.svBlackStationaryTicks = 0
        self.svPreviousCameraLocalYaw = nil
        self.svPreviousCameraLocalPitch = nil
        targetPosition = target.worldPosition
    elseif self.sv.trackPlayer then
        self.svBlackLockedPoint = nil
        self.svBlackCameraMoving = false
        self.svBlackStationaryTicks = 0
        self.svPreviousCameraLocalYaw = nil
        self.svPreviousCameraLocalPitch = nil
        targetPosition = target.worldPosition
    else
        -- With Track Player disabled, a connected seat turns this block into
        -- a camera controller: the seated character's view direction is used
        -- as an aim ray instead of the character's body position.
        local direction = target.direction
        local directionValid = direction ~= nil and direction:length() > 0.001

        local cameraShape = self:sv_getConnectedSeatCamera()
        local rayDirection = direction
        local rayBody = self.shape.body
        if cameraShape ~= nil and sm.exists(cameraShape) then
            local cameraAt = cameraShape:getAt()
            if cameraAt ~= nil and cameraAt:length() > 0.001 then
                rayDirection = cameraAt
                rayBody = cameraShape.body
            end
        end

        -- A bomb sight does not need a valid player look vector: it derives
        -- its own ground impact point from altitude and aircraft velocity.
        -- Keep the old requirement for the ordinary camera-control path.
        if not directionValid and not self.sv.bombCalculator then
            self:sv_resetPredictionState()
            self:sv_setBearingsNeutral(bearings)
            return
        end

        local rayOrigin = aimOrigin
        if cameraShape ~= nil and sm.exists(cameraShape) then
            local cameraAt = cameraShape:getAt()
            if cameraAt ~= nil and cameraAt:length() > 0.001 then
                rayOrigin = cameraShape.worldPosition + cameraAt / cameraAt:length() * 0.1
                rayDirection = cameraAt
                rayBody = cameraShape.body
            end
        end

        -- Bearing angles must be calculated from the actual camera lens. When
        -- the camera is mounted away from this controller, using the
        -- controller's origin introduces a visible parallax error at range.
        aimOrigin = rayOrigin

        -- The player's direction is the normal control input. The camera's
        -- direction is used only to acquire the geo-lock point. Feeding the
        -- bearing-driven camera direction back as the command direction makes
        -- the bearings chase themselves and spin.
        if not directionValid then direction = rayDirection end
        if direction == nil or direction:length() <= 0.001 then
            self:sv_resetPredictionState()
            self:sv_setBearingsNeutral(bearings)
            return
        end
        local aimDirection = direction / direction:length()
		if geoLockActive then
            -- Geo-lock is a strict hold mode: acquire once, then never use
            -- player/camera movement to change the point until black turns
            -- off and the mode is explicitly reacquired.
			if self.svBlackLockedPoint == nil then
				local lockPoint = self:sv_getGeoLockPoint(rayOrigin, rayDirection, rayBody)
				if lockPoint ~= nil then self.svBlackLockedPoint = lockPoint end
			end
			self.svBlackCameraMoving = false
			local normalAimPosition = aimOrigin + aimDirection * 100
			if self.svBlackLockedPoint ~= nil then
				-- The camera's physical bearing can be a fraction behind the
				-- player's view when the black signal rises. Blend from the
				-- current aim line to the raycast point to avoid a visible first
				-- frame pitch jump while retaining the precise camera raycast.
				local lockBlend = clamp(
					self.svBlackStationaryTicks / CAMERA_SETTLE_TICKS,
					0,
					1
				)
				targetPosition = normalAimPosition
					+ (self.svBlackLockedPoint - normalAimPosition) * lockBlend
				self.svBlackStationaryTicks = math.min(
					CAMERA_SETTLE_TICKS,
					self.svBlackStationaryTicks + 1
				)
			else
				targetPosition = normalAimPosition
			end
		else
            -- Black off is deliberately a pure normal-camera path. Do not
            -- raycast, retain a lock point, or let old geo-lock state affect
            -- the player's movement.
            self.svBlackLockedPoint = nil
            self.svBlackCameraMoving = false
            self.svBlackStationaryTicks = 0
            targetPosition = aimOrigin + aimDirection * 100
        end
    end

    if self.sv.trackPlayer and self.sv.predictTarget and not laserGuidanceConnected then
        targetPosition = self:sv_getPredictedAimPosition(
            target,
            timeStep,
            not self.sv.bombCalculator
        )
    else
        self:sv_resetPredictionState()
    end

    if self.sv.bombCalculator then
        local bombLandingPosition = self:sv_getBombLandingPosition(aimOrigin)
        if bombLandingPosition ~= nil then
            targetPosition = bombLandingPosition
        end
    end

    if laserGuidanceConnected then
        -- Laser mode is a closed-loop controller.  It uses the receiver's
        -- current physical axis and each bearing's real rotation axis, so two
        -- turrets on opposite sides of the same spot receive opposite motor
        -- commands automatically.
        self:sv_applyLaserGuidance(bearings, laserTarget)
        return
    end

    local aimDirection = targetPosition - aimOrigin
    local horizontalAngle, verticalAngle = self:sv_getAimAngles(aimDirection)
    local impulse = motorImpulse(self.sv.force)
    local roles = self:sv_getBearingRoles(bearings)

    for index, bearing in ipairs(bearings) do
        local role = roles[index]
        local targetAngle = role == "horizontal" and horizontalAngle
            or role == "vertical" and verticalAngle
            or 0
        local targetVelocity = self.sv.bombCalculator
            and MAX_ROTATION_SPEED
            or (role == "vertical" and self.sv.pitchRotationSpeed or self.sv.yawRotationSpeed)
        targetVelocity = math.rad(targetVelocity)
        if math.abs(targetAngle) <= TARGET_DEAD_ZONE then targetAngle = 0 end
        -- Target angles are relative to each bearing's neutral creation angle,
        -- so the sensor block does not need to rotate with the gun assembly.
        -- The Connect Tool's reverse option remains the direction correction.
        bearing:setTargetAngle(targetAngle, targetVelocity, impulse)
    end
end

function TurretController.client_onCreate(self)
    self.cl = {
        horizontalLimit = DEFAULT_HORIZONTAL_LIMIT,
        verticalLimit = DEFAULT_VERTICAL_LIMIT,
        yawRotationSpeed = DEFAULT_YAW_ROTATION_SPEED,
        pitchRotationSpeed = DEFAULT_PITCH_ROTATION_SPEED,
        pitchOffsetBlocks = DEFAULT_PITCH_OFFSET_BLOCKS,
        force = DEFAULT_FORCE,
        holdBearingsOnSeatExit = DEFAULT_HOLD_BEARINGS_ON_SEAT_EXIT,
        trackPlayer = DEFAULT_TRACK_PLAYER,
        trackTarget = DEFAULT_TRACK_TARGET,
        predictTarget = DEFAULT_PREDICT_TARGET,
        projectileSpeed = DEFAULT_PROJECTILE_SPEED,
        projectileGravity = DEFAULT_PROJECTILE_GRAVITY,
        projectileSpeedInput = tostring(DEFAULT_PROJECTILE_SPEED),
        projectileGravityInput = tostring(DEFAULT_PROJECTILE_GRAVITY),
        bombCalculator = DEFAULT_BOMB_CALCULATOR,
        finnedBombs = DEFAULT_FINNED_BOMBS,
        trackingPovEnabled = DEFAULT_TRACKING_POV_ENABLED,
        trackingFovDegrees = DEFAULT_TRACKING_FOV_DEGREES,
        targetOptionIds = {},
        targetOptionNames = {},
        gui = nil
    }
end

function TurretController.client_onClientDataUpdate(self, data)
    self.cl.horizontalLimit = data.horizontalLimit or DEFAULT_HORIZONTAL_LIMIT
    self.cl.verticalLimit = data.verticalLimit or DEFAULT_VERTICAL_LIMIT
    local legacyRotationSpeed = data.rotationSpeed or DEFAULT_ROTATION_SPEED
    self.cl.yawRotationSpeed = data.yawRotationSpeed or legacyRotationSpeed
    self.cl.pitchRotationSpeed = data.pitchRotationSpeed or legacyRotationSpeed
    self.cl.pitchOffsetBlocks = data.pitchOffsetBlocks or DEFAULT_PITCH_OFFSET_BLOCKS
    self.cl.force = data.force or DEFAULT_FORCE
    self.cl.holdBearingsOnSeatExit = data.holdBearingsOnSeatExit == true
    self.cl.trackPlayer = data.trackPlayer == true
    self.cl.trackTarget = data.trackTarget or DEFAULT_TRACK_TARGET
    self.cl.predictTarget = data.predictTarget == true
    self.cl.projectileSpeed = data.projectileSpeed or DEFAULT_PROJECTILE_SPEED
    self.cl.projectileGravity = data.projectileGravity or DEFAULT_PROJECTILE_GRAVITY
    self.cl.projectileSpeedInput = string.format("%g", self.cl.projectileSpeed)
    self.cl.projectileGravityInput = string.format("%g", self.cl.projectileGravity)
    self.cl.bombCalculator = data.bombCalculator == true
    self.cl.finnedBombs = data.finnedBombs == true and self.cl.bombCalculator
    self.cl.trackingPovEnabled = data.trackingPovEnabled ~= false
    self.cl.trackingFovDegrees = data.trackingFovDegrees or DEFAULT_TRACKING_FOV_DEGREES
    self:cl_refreshGui()
end

function TurretController.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function TurretController.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_turret_controller"))
    return true
end

function TurretController.cl_buildTargetOptions(self)
    local options = { "Closest" }
    local optionIds = { Closest = DEFAULT_TRACK_TARGET }
    local optionNames = { [DEFAULT_TRACK_TARGET] = "Closest" }
    local usedNames = { Closest = true }

    for _, player in ipairs(sm.player.getAllPlayers()) do
        local playerId = player:getId()
        local playerName = player:getName()
        if playerName == nil or playerName == "" then playerName = string.format("Player %d", playerId) end
        local optionName = playerName
        if usedNames[optionName] then optionName = string.format("%s [%d]", playerName, playerId) end
        while usedNames[optionName] do optionName = optionName .. " " end
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
    table.sort(presenceOptions, function(left, right) return left.id < right.id end)
    for _, presence in ipairs(presenceOptions) do
        local optionName = presence.name
        while usedNames[optionName] do optionName = optionName .. " " end
        usedNames[optionName] = true
        optionIds[optionName] = presence.id
        optionNames[presence.id] = optionName
        table.insert(options, optionName)
    end

    self.cl.targetOptionIds = optionIds
    self.cl.targetOptionNames = optionNames
    return options
end

function TurretController.client_onInteract(self, _, state)
    if not state then return end
    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("TurretController.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "HorizontalSlider", MAX_HORIZONTAL_LIMIT - MIN_HORIZONTAL_LIMIT + 1, self.cl.horizontalLimit - MIN_HORIZONTAL_LIMIT, "cl_onHorizontalSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "VerticalSlider", MAX_VERTICAL_LIMIT - MIN_VERTICAL_LIMIT + 1, self.cl.verticalLimit - MIN_VERTICAL_LIMIT, "cl_onVerticalSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "YawRotationSpeedSlider",
        MAX_ROTATION_SPEED - MIN_ROTATION_SPEED + 1,
        self.cl.yawRotationSpeed - MIN_ROTATION_SPEED,
        "cl_onYawRotationSpeedSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "PitchRotationSpeedSlider",
        MAX_ROTATION_SPEED - MIN_ROTATION_SPEED + 1,
        self.cl.pitchRotationSpeed - MIN_ROTATION_SPEED,
        "cl_onPitchRotationSpeedSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "ForceSlider", MAX_FORCE - MIN_FORCE + 1, self.cl.force - MIN_FORCE, "cl_onForceSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "PitchOffsetSlider",
        MAX_PITCH_OFFSET_BLOCKS - MIN_PITCH_OFFSET_BLOCKS + 1,
        self.cl.pitchOffsetBlocks - MIN_PITCH_OFFSET_BLOCKS,
        "cl_onPitchOffsetSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "TrackingFovSlider",
        MAX_TRACKING_FOV_DEGREES - MIN_TRACKING_FOV_DEGREES + 1,
        self.cl.trackingFovDegrees - MIN_TRACKING_FOV_DEGREES,
        "cl_onTrackingFovSliderChanged"
    )
    self.cl.gui:createDropDown(
        "TargetPlayerDropDown", "cl_onTargetPlayerSelected", self:cl_buildTargetOptions()
    )
    self.cl.gui:setButtonCallback("TrackPlayerButton", "cl_onTrackPlayerPressed")
    self.cl.gui:setButtonCallback("TrackingPovButton", "cl_onTrackingPovPressed")
    self.cl.gui:setButtonCallback("PredictTargetButton", "cl_onPredictTargetPressed")
    self.cl.gui:setButtonCallback("BombCalculatorButton", "cl_onBombCalculatorPressed")
    self.cl.gui:setButtonCallback("BombCalculatorModeButton", "cl_onBombCalculatorPressed")
    self.cl.gui:setButtonCallback("FinnedBombsButton", "cl_onFinnedBombsPressed")
    self.cl.gui:setButtonCallback(
        "HoldBearingsOnSeatExitButton",
        "cl_onHoldBearingsOnSeatExitPressed"
    )
    self.cl.gui:setTextChangedCallback("ProjectileSpeedInput", "cl_onProjectileSpeedChanged")
    self.cl.gui:setTextChangedCallback("ProjectileGravityInput", "cl_onProjectileGravityChanged")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self.cl.gui:setText("ProjectileSpeedInput", self.cl.projectileSpeedInput)
    self.cl.gui:setText("ProjectileGravityInput", self.cl.projectileGravityInput)
    self:cl_refreshGui()
    self.cl.gui:open()
end

function TurretController.cl_onHorizontalSliderChanged(self, sliderPosition)
    self.cl.horizontalLimit = sliderPosition
    self:cl_refreshGui()
    self.network:sendToServer("sv_setHorizontalLimit", self.cl.horizontalLimit)
end

function TurretController.cl_onVerticalSliderChanged(self, sliderPosition)
    self.cl.verticalLimit = sliderPosition
    self:cl_refreshGui()
    self.network:sendToServer("sv_setVerticalLimit", self.cl.verticalLimit)
end

function TurretController.cl_onYawRotationSpeedSliderChanged(self, sliderPosition)
    self.cl.yawRotationSpeed = sliderPosition
    self:cl_refreshGui()
    self.network:sendToServer("sv_setYawRotationSpeed", self.cl.yawRotationSpeed)
end

function TurretController.cl_onPitchRotationSpeedSliderChanged(self, sliderPosition)
    self.cl.pitchRotationSpeed = sliderPosition
    self:cl_refreshGui()
    self.network:sendToServer("sv_setPitchRotationSpeed", self.cl.pitchRotationSpeed)
end

function TurretController.cl_onForceSliderChanged(self, sliderPosition)
    self.cl.force = sliderPosition
    self:cl_refreshGui()
    self.network:sendToServer("sv_setForce", self.cl.force)
end

function TurretController.cl_onPitchOffsetSliderChanged(self, sliderPosition)
    self.cl.pitchOffsetBlocks = sliderPosition + MIN_PITCH_OFFSET_BLOCKS
    self:cl_refreshGui()
    self.network:sendToServer("sv_setPitchOffsetBlocks", self.cl.pitchOffsetBlocks)
end

function TurretController.cl_onHoldBearingsOnSeatExitPressed(self)
    self.cl.holdBearingsOnSeatExit = not self.cl.holdBearingsOnSeatExit
    self:cl_refreshGui()
    self.network:sendToServer(
        "sv_setHoldBearingsOnSeatExit",
        self.cl.holdBearingsOnSeatExit
    )
end

function TurretController.cl_onTrackPlayerPressed(self)
    self.cl.trackPlayer = not self.cl.trackPlayer
    if self.cl.trackPlayer then
        self.cl.bombCalculator = false
        self.cl.finnedBombs = false
    else
        self.cl.predictTarget = false
    end
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackPlayer", self.cl.trackPlayer)
end

function TurretController.cl_onTrackingPovPressed(self)
    self.cl.trackingPovEnabled = not self.cl.trackingPovEnabled
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackingPovEnabled", self.cl.trackingPovEnabled)
end

function TurretController.cl_onTargetPlayerSelected(self, selectedOption)
    local target = self.cl.targetOptionIds[selectedOption]
    if target == nil then return end
    self.cl.trackTarget = target
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackTarget", target)
end

function TurretController.cl_onPredictTargetPressed(self)
    self.cl.predictTarget = not self.cl.predictTarget
    self:cl_refreshGui()
    self.network:sendToServer("sv_setPredictTarget", self.cl.predictTarget)
end

function TurretController.cl_onBombCalculatorPressed(self)
    self.cl.bombCalculator = not self.cl.bombCalculator
    if self.cl.bombCalculator then
        self.cl.trackPlayer = false
        self.cl.predictTarget = false
    else
        self.cl.finnedBombs = false
    end
    self:cl_refreshGui()
    self.network:sendToServer("sv_setBombCalculator", self.cl.bombCalculator)
end

function TurretController.cl_onFinnedBombsPressed(self)
    if not self.cl.bombCalculator then return end
    self.cl.finnedBombs = not self.cl.finnedBombs
    self:cl_refreshGui()
    self.network:sendToServer("sv_setFinnedBombs", self.cl.finnedBombs)
end

function TurretController.cl_onProjectileSpeedChanged(self, _, text)
    self.cl.projectileSpeedInput = text
    local value = tonumber(text)
    if value ~= nil then
        self.cl.projectileSpeed = clamp(value, MIN_PROJECTILE_SPEED, MAX_PROJECTILE_SPEED)
        self.network:sendToServer("sv_setProjectileSpeed", self.cl.projectileSpeed)
    end
end

function TurretController.cl_onProjectileGravityChanged(self, _, text)
    self.cl.projectileGravityInput = text
    local value = tonumber(text)
    if value ~= nil then
        self.cl.projectileGravity = clamp(value, MIN_PROJECTILE_GRAVITY, MAX_PROJECTILE_GRAVITY)
        self.network:sendToServer("sv_setProjectileGravity", self.cl.projectileGravity)
    end
end

function TurretController.cl_onTrackingFovSliderChanged(self, sliderPosition)
    self.cl.trackingFovDegrees = sliderPosition + MIN_TRACKING_FOV_DEGREES
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTrackingFovDegrees", self.cl.trackingFovDegrees)
end

function TurretController.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText("HorizontalValue", PC_L.get("horizontal_limit", self.cl.horizontalLimit))
    self.cl.gui:setText("VerticalValue", PC_L.get("vertical_limit", self.cl.verticalLimit))
    self.cl.gui:setText(
        "YawRotationSpeedValue",
        PC_L.get("yaw_speed", self.cl.yawRotationSpeed)
    )
    self.cl.gui:setText(
        "PitchRotationSpeedValue",
        PC_L.get("pitch_speed", self.cl.pitchRotationSpeed)
    )
    self.cl.gui:setText(
        "PitchOffsetValue",
        PC_L.get("pitch_height_offset", self.cl.pitchOffsetBlocks)
    )
    self.cl.gui:setText(
        "ForceValue",
        PC_L.get("motor_force", self.cl.force)
    )
    self.cl.gui:setText(
        "TrackingFovValueText",
        PC_L.get("tracking_pov_value", self.cl.trackingFovDegrees)
    )
    self.cl.gui:setButtonState("TrackPlayerButton", self.cl.trackPlayer)
    self.cl.gui:setButtonState("TrackingPovButton", self.cl.trackingPovEnabled)
    self.cl.gui:setButtonState("PredictTargetButton", self.cl.predictTarget)
    self.cl.gui:setButtonState("BombCalculatorButton", self.cl.bombCalculator)
    self.cl.gui:setButtonState("BombCalculatorModeButton", self.cl.bombCalculator)
    self.cl.gui:setButtonState("FinnedBombsButton", self.cl.finnedBombs)
    self.cl.gui:setButtonState(
        "HoldBearingsOnSeatExitButton",
        self.cl.holdBearingsOnSeatExit
    )

    local selectedOption = self.cl.targetOptionNames[self.cl.trackTarget]
    if selectedOption ~= nil then
        self.cl.gui:setSelectedDropDownItem("TargetPlayerDropDown", selectedOption)
    end

    local bombMode = self.cl.bombCalculator
    local trackingVisible = self.cl.trackPlayer and not bombMode
    local predictionVisible = trackingVisible and self.cl.predictTarget
    local projectileInputsVisible = predictionVisible and not self.cl.bombCalculator
    self.cl.gui:setVisible("MainControls", not bombMode)
    self.cl.gui:setVisible("MainBackground", not bombMode and not trackingVisible)
    self.cl.gui:setVisible("TrackingBackground", not bombMode and trackingVisible and not predictionVisible)
    self.cl.gui:setVisible("PredictionBackground", not bombMode and predictionVisible)
    self.cl.gui:setVisible("BombCalculatorBackground", bombMode)
    self.cl.gui:setVisible("TrackPlayerButton", not bombMode)
    self.cl.gui:setVisible("TrackPlayerLabel", not bombMode)
    self.cl.gui:setVisible("HoldBearingsOnSeatExitButton", not bombMode)
    self.cl.gui:setVisible("HoldBearingsOnSeatExitLabel", not bombMode)
    self.cl.gui:setVisible("BombCalculatorButton", not self.cl.trackPlayer and not bombMode)
    self.cl.gui:setVisible("BombCalculatorLabel", not self.cl.trackPlayer and not bombMode)
    self.cl.gui:setVisible("BombCalculatorModeButton", bombMode)
    self.cl.gui:setVisible("BombCalculatorModeLabel", bombMode)
    self.cl.gui:setVisible("FinnedBombsButton", bombMode)
    self.cl.gui:setVisible("FinnedBombsLabel", bombMode)
    self.cl.gui:setVisible("TrackingPovButton", trackingVisible)
    self.cl.gui:setVisible("TrackingPovLabel", trackingVisible)
    self.cl.gui:setVisible("TargetPlayerLabel", trackingVisible)
    self.cl.gui:setVisible("TargetPlayerDropDown", trackingVisible)
    self.cl.gui:setVisible("PredictTargetButton", trackingVisible)
    self.cl.gui:setVisible("PredictTargetLabel", trackingVisible)
    self.cl.gui:setVisible("ProjectileSpeedLabel", projectileInputsVisible)
    self.cl.gui:setVisible("ProjectileSpeedInput", projectileInputsVisible)
    self.cl.gui:setVisible("ProjectileSpeedBackground", projectileInputsVisible)
    self.cl.gui:setVisible("ProjectileGravityLabel", projectileInputsVisible)
    self.cl.gui:setVisible("ProjectileGravityInput", projectileInputsVisible)
    self.cl.gui:setVisible("ProjectileGravityBackground", projectileInputsVisible)
    self.cl.gui:setVisible("TrackingFovValue", trackingVisible and self.cl.trackingPovEnabled)
    self.cl.gui:setVisible("TrackingFovSlider", trackingVisible and self.cl.trackingPovEnabled)
end

function TurretController.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
