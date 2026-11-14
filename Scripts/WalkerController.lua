dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
WalkerController = class()

WalkerController.maxParentCount = 4
WalkerController.maxChildCount = -1
WalkerController.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.logic
WalkerController.connectionOutput = sm.interactable.connectionType.bearing + sm.interactable.connectionType.logic
WalkerController.colorNormal = sm.color.new(0x6b3fa0ff)
WalkerController.colorHighlight = sm.color.new(0x9b6bd1ff)

-- The controller uses the same idea as a small robotic biped: generate a
-- foot path with a swing phase and a stance phase, then solve the two-link
-- hip/knee geometry when an ankle bearing is present.  A fourth lateral
-- bearing can widen the support on the low side when the body rolls. A
-- two-bearing leg still works through the fallback joint trajectory, but
-- four bearings (lateral, hip, knee, ankle) are the recommended construction.
local HIP_COLORS = {
    f06767ff = true,
    d02525ff = true,
    ["7c0000ff"] = true,
    ["560202ff"] = true
}

local KNEE_COLORS = {
    ["4c6fe3ff"] = true,
    ["0a3ee2ff"] = true,
    ["0f2e91ff"] = true,
    ["0a1d5aff"] = true
}

local ANKLE_COLORS = {
    f5f071ff = true,
    e2db13ff = true,
    ["817c00ff"] = true,
    ["323000ff"] = true
}

local LATERAL_COLORS = {
    ae79f0ff = true,
    ["7514edff"] = true,
    ["500aa6ff"] = true,
    ["35086cff"] = true,
    ["6b3fa0ff"] = true,
    ["9b6bd1ff"] = true
}

local DEFAULT_STRIDE_PERCENT = 45
local MIN_STRIDE_PERCENT = 10
local MAX_STRIDE_PERCENT = 100
local DEFAULT_STEP_HEIGHT_PERCENT = 35
local MIN_STEP_HEIGHT_PERCENT = 0
local MAX_STEP_HEIGHT_PERCENT = 80
local DEFAULT_CADENCE_TENTHS = 10
local MIN_CADENCE_TENTHS = 2
local MAX_CADENCE_TENTHS = 30
local DEFAULT_FORCE = 65
local MIN_FORCE = 0
local MAX_FORCE = 200
local DEFAULT_TURN_PERCENT = 25
local MIN_TURN_PERCENT = 0
local MAX_TURN_PERCENT = 100
local DEFAULT_HOLD_BEARINGS_ON_SEAT_EXIT = false
local MAX_MOTOR_IMPULSE = 5000
local TARGET_DEAD_ZONE = math.rad(0.25)
local MIN_DRIVE_INPUT = 0.05
local TWO_PI = math.pi * 2
local SIDE_EPSILON = 0.05
local SWING_FRACTION = 0.40
local MIN_LINK_LENGTH = 0.001
local SWING_FOOT_PITCH_DEGREES = 10
local STANCE_FOOT_PITCH_DEGREES = -6
local ANKLE_COMPENSATION_GAIN = 1.50
local BALANCE_DEAD_ZONE_DEGREES = 0.50
local ROLL_BALANCE_GAIN = 1.80
local MAX_ROLL_CORRECTION_DEGREES = 18
local PITCH_BALANCE_GAIN = 1.60
local MAX_PITCH_CORRECTION_DEGREES = 14
local PITCH_BALANCE_LENGTH_GAIN = 0.75

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function clampInteger(value, minimum, maximum, defaultValue)
    local numericValue = tonumber(value)
    if numericValue == nil then numericValue = defaultValue end
    return clamp(math.floor(numericValue + 0.5), minimum, maximum)
end

local function bearingColor(bearing)
    return string.lower(tostring(bearing:getColor()))
end

local function bearingRole(bearing)
    local color = bearingColor(bearing)
    if HIP_COLORS[color] then return "hip" end
    if KNEE_COLORS[color] then return "knee" end
    if ANKLE_COLORS[color] then return "ankle" end
    if LATERAL_COLORS[color] then return "lateral" end
    return nil
end

local function motorImpulse(forcePercent)
    return MAX_MOTOR_IMPULSE * clamp(forcePercent, MIN_FORCE, MAX_FORCE) / 100
end

local function smoothStep(value)
    local t = clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
end

local function atan2(y, x)
    if math.atan2 ~= nil then
        return math.atan2(y, x)
    end
    return math.atan(y, x)
end

function WalkerController.server_onCreate(self)
    self:sv_initialize()
end

function WalkerController.server_onRefresh(self)
    self:sv_initialize()
end

function WalkerController.server_onDestroy(self)
    self:sv_setBearingsNeutral(self.interactable:getBearings())
end

function WalkerController.sv_initialize(self)
    local stored = self.storage:load()
    local storedTable = type(stored) == "table" and stored or {}

    self.sv = {
        stridePercent = clampInteger(
            storedTable.stridePercent,
            MIN_STRIDE_PERCENT,
            MAX_STRIDE_PERCENT,
            DEFAULT_STRIDE_PERCENT
        ),
        stepHeightPercent = clampInteger(
            storedTable.stepHeightPercent,
            MIN_STEP_HEIGHT_PERCENT,
            MAX_STEP_HEIGHT_PERCENT,
            DEFAULT_STEP_HEIGHT_PERCENT
        ),
        cadenceTenths = clampInteger(
            storedTable.cadenceTenths,
            MIN_CADENCE_TENTHS,
            MAX_CADENCE_TENTHS,
            DEFAULT_CADENCE_TENTHS
        ),
        force = clampInteger(storedTable.force, MIN_FORCE, MAX_FORCE, DEFAULT_FORCE),
        turnPercent = clampInteger(
            storedTable.turnPercent,
            MIN_TURN_PERCENT,
            MAX_TURN_PERCENT,
            DEFAULT_TURN_PERCENT
        ),
        holdBearingsOnSeatExit = storedTable.holdBearingsOnSeatExit == true,
        phase = 0.0,
        assignments = nil,
        calibrations = {}
    }

    self.interactable:setActive(false)
    self.storage:save({
        stridePercent = self.sv.stridePercent,
        stepHeightPercent = self.sv.stepHeightPercent,
        cadenceTenths = self.sv.cadenceTenths,
        force = self.sv.force,
        turnPercent = self.sv.turnPercent,
        holdBearingsOnSeatExit = self.sv.holdBearingsOnSeatExit
    })
    self:sv_syncClientData()
end

function WalkerController.sv_syncClientData(self)
    self.network:setClientData({
        stridePercent = self.sv.stridePercent,
        stepHeightPercent = self.sv.stepHeightPercent,
        cadenceTenths = self.sv.cadenceTenths,
        force = self.sv.force,
        turnPercent = self.sv.turnPercent,
        holdBearingsOnSeatExit = self.sv.holdBearingsOnSeatExit
    })
end

function WalkerController.sv_setStridePercent(self, value)
    self.sv.stridePercent = clampInteger(value, MIN_STRIDE_PERCENT, MAX_STRIDE_PERCENT, DEFAULT_STRIDE_PERCENT)
    self:sv_saveSettings()
end

function WalkerController.sv_setStepHeightPercent(self, value)
    self.sv.stepHeightPercent = clampInteger(
        value,
        MIN_STEP_HEIGHT_PERCENT,
        MAX_STEP_HEIGHT_PERCENT,
        DEFAULT_STEP_HEIGHT_PERCENT
    )
    self:sv_saveSettings()
end

function WalkerController.sv_setCadenceTenths(self, value)
    self.sv.cadenceTenths = clampInteger(value, MIN_CADENCE_TENTHS, MAX_CADENCE_TENTHS, DEFAULT_CADENCE_TENTHS)
    self:sv_saveSettings()
end

function WalkerController.sv_setForce(self, value)
    self.sv.force = clampInteger(value, MIN_FORCE, MAX_FORCE, DEFAULT_FORCE)
    self:sv_saveSettings()
end

function WalkerController.sv_setTurnPercent(self, value)
    self.sv.turnPercent = clampInteger(value, MIN_TURN_PERCENT, MAX_TURN_PERCENT, DEFAULT_TURN_PERCENT)
    self:sv_saveSettings()
end

function WalkerController.sv_setHoldBearingsOnSeatExit(self, value)
    self.sv.holdBearingsOnSeatExit = value == true
    self:sv_saveSettings()
end

function WalkerController.sv_saveSettings(self)
    self.storage:save({
        stridePercent = self.sv.stridePercent,
        stepHeightPercent = self.sv.stepHeightPercent,
        cadenceTenths = self.sv.cadenceTenths,
        force = self.sv.force,
        turnPercent = self.sv.turnPercent,
        holdBearingsOnSeatExit = self.sv.holdBearingsOnSeatExit
    })
    self:sv_syncClientData()
end

function WalkerController.sv_getSeatParent(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.seated) then
            return parent
        end
    end
    return nil
end

function WalkerController.sv_getSeatControls(self)
    local seat = self:sv_getSeatParent()
    if seat == nil then return nil, nil end

    local seatedCharacter = seat:getSeatCharacter()
    if seatedCharacter == nil or not sm.exists(seatedCharacter) then
        return nil, nil
    end

    local forward = clamp(tonumber(seat:getPower()) or 0, -1, 1)
    local turn = clamp(tonumber(seat:getSteeringAngle()) or 0, -1, 1)
    return forward, turn
end

function WalkerController.sv_isLogicEnabled(self)
    local parents = self.interactable:getParents(sm.interactable.connectionType.logic)
    if #parents == 0 then return true end

    for _, parent in ipairs(parents) do
        if parent:isActive() then return true end
    end
    return false
end

function WalkerController.sv_getSide(self, bearing)
    local offset = bearing.worldPosition - self.shape.worldPosition
    local sideOffset = offset:dot(self.shape:getRight())
    if sideOffset < -SIDE_EPSILON then return "left" end
    if sideOffset > SIDE_EPSILON then return "right" end
    return nil
end

function WalkerController.sv_getBodyTilt(self)
    local worldUp = sm.vec3.new(0, 0, 1)
    local bodyRight = self.shape:getRight()
    local bodyForward = self.shape:getAt()

    -- The vertical component of the right axis is the roll angle. The
    -- vertical component of the front axis is the fore/aft pitch angle.
    local rollVertical = clamp(bodyRight:dot(worldUp), -1, 1)
    local rollHorizontal = math.sqrt(math.max(0, 1 - rollVertical * rollVertical))
    local pitchVertical = clamp(bodyForward:dot(worldUp), -1, 1)
    local pitchHorizontal = math.sqrt(math.max(0, 1 - pitchVertical * pitchVertical))
    return atan2(rollVertical, rollHorizontal), atan2(pitchVertical, pitchHorizontal)
end

function WalkerController.sv_getBalanceCorrections(self)
    local rollRadians, pitchRadians = self:sv_getBodyTilt()
    local rollDegrees = math.deg(rollRadians)
    local pitchDegrees = math.deg(pitchRadians)

    if math.abs(rollDegrees) < BALANCE_DEAD_ZONE_DEGREES then rollDegrees = 0 end
    if math.abs(pitchDegrees) < BALANCE_DEAD_ZONE_DEGREES then
        pitchDegrees = 0
        pitchRadians = 0
    end

    local rollCorrection = clamp(
        rollDegrees * ROLL_BALANCE_GAIN,
        -MAX_ROLL_CORRECTION_DEGREES,
        MAX_ROLL_CORRECTION_DEGREES
    )
    -- If the front of the body drops, move the support foot forward to catch
    -- the fall. The sign is the opposite of the measured pitch.
    local pitchCorrection = clamp(
        -pitchDegrees * PITCH_BALANCE_GAIN,
        -MAX_PITCH_CORRECTION_DEGREES,
        MAX_PITCH_CORRECTION_DEGREES
    )
    return rollCorrection, pitchCorrection, pitchRadians
end

function WalkerController.sv_getBearingAssignments(self, bearings)
    local assignments = {
        left = {},
        right = {},
        unknown = {}
    }

    for _, bearing in ipairs(bearings) do
        local role = bearingRole(bearing)
        if role ~= nil then
            local side = self:sv_getSide(bearing)
            if side == nil then
                assignments.unknown[#assignments.unknown + 1] = bearing
            elseif assignments[side][role] == nil then
                assignments[side][role] = bearing
            end
        end
    end

    return assignments
end

function WalkerController.sv_setBearingsNeutral(self, bearings)
    for _, bearing in ipairs(bearings) do
        if sm.exists(bearing) then
            bearing:setTargetAngle(0, math.rad(90), motorImpulse(self.sv and self.sv.force or DEFAULT_FORCE))
        end
    end
end

function WalkerController.sv_hasValidAssignments(self, assignments)
    return assignments ~= nil
        and assignments.left.hip ~= nil
        and assignments.left.knee ~= nil
        and assignments.right.hip ~= nil
        and assignments.right.knee ~= nil
end

function WalkerController.sv_setBearingTarget(self, bearing, degrees, speedDegrees)
    if bearing == nil or not sm.exists(bearing) then return end
    local targetAngle = math.rad(degrees)
    while targetAngle > math.pi do targetAngle = targetAngle - TWO_PI end
    while targetAngle < -math.pi do targetAngle = targetAngle + TWO_PI end
    if math.abs(targetAngle) <= TARGET_DEAD_ZONE then targetAngle = 0 end
    bearing:setTargetAngle(targetAngle, math.rad(speedDegrees), motorImpulse(self.sv.force))
end

function WalkerController.sv_getPlanarBasis(self)
    local worldUp = sm.vec3.new(0, 0, 1)
    local forward = self.shape:getUp()
    forward = forward - worldUp * forward:dot(worldUp)
    if forward:length() <= MIN_LINK_LENGTH then
        forward = self.shape:getAt()
        forward = forward - worldUp * forward:dot(worldUp)
    end
    if forward:length() <= MIN_LINK_LENGTH then
        forward = sm.vec3.new(0, 1, 0)
    end
    return forward / forward:length(), worldUp
end

function WalkerController.sv_projectPoint(self, point, origin, forward, worldUp)
    local offset = point - origin
    return offset:dot(forward), offset:dot(worldUp)
end

function WalkerController.sv_normalizeAngle(angle)
    while angle > math.pi do angle = angle - TWO_PI end
    while angle < -math.pi do angle = angle + TWO_PI end
    return angle
end

function WalkerController.sv_calibrateLeg(self, leg)
    if leg == nil or leg.hip == nil or leg.knee == nil or leg.ankle == nil then
        return nil
    end
    if not sm.exists(leg.hip) or not sm.exists(leg.knee) or not sm.exists(leg.ankle) then
        return nil
    end

    local forward, worldUp = self:sv_getPlanarBasis()
    local hipPosition = leg.hip.worldPosition
    local kneePosition = leg.knee.worldPosition
    local anklePosition = leg.ankle.worldPosition
    local hipX, hipZ = self:sv_projectPoint(hipPosition, self.shape.worldPosition, forward, worldUp)
    local kneeX, kneeZ = self:sv_projectPoint(kneePosition, self.shape.worldPosition, forward, worldUp)
    local ankleX, ankleZ = self:sv_projectPoint(anklePosition, self.shape.worldPosition, forward, worldUp)

    local firstX = kneeX - hipX
    local firstZ = kneeZ - hipZ
    local secondX = ankleX - kneeX
    local secondZ = ankleZ - kneeZ
    local firstLength = math.sqrt(firstX * firstX + firstZ * firstZ)
    local secondLength = math.sqrt(secondX * secondX + secondZ * secondZ)
    if firstLength <= MIN_LINK_LENGTH or secondLength <= MIN_LINK_LENGTH then
        return nil
    end

    local firstAngle = atan2(firstZ, firstX)
    local secondAngle = atan2(secondZ, secondX)
    local relativeKneeAngle = self:sv_normalizeAngle(secondAngle - firstAngle)
    return {
        hipBearing = leg.hip,
        kneeBearing = leg.knee,
        ankleBearing = leg.ankle,
        hipX = hipX,
        hipZ = hipZ,
        ankleX = ankleX,
        ankleZ = ankleZ,
        firstLength = firstLength,
        secondLength = secondLength,
        neutralHipAngle = firstAngle,
        neutralKneeAngle = relativeKneeAngle,
        elbowSign = relativeKneeAngle < 0 and -1 or 1
    }
end

function WalkerController.sv_refreshCalibrations(self, assignments)
    if self.sv.calibrations == nil then self.sv.calibrations = {} end
    for _, side in ipairs({ "left", "right" }) do
        local leg = assignments[side]
        local cached = self.sv.calibrations[side]
        local sameBearings = cached ~= nil
            and cached.hipBearing == leg.hip
            and cached.kneeBearing == leg.knee
            and cached.ankleBearing == leg.ankle
        if not sameBearings then
            local ok, calibration = pcall(self.sv_calibrateLeg, self, leg)
            if ok and calibration ~= nil then
                self.sv.calibrations[side] = calibration
            else
                -- A bad three-bearing setup must fall back to the two-bearing
                -- gait instead of stopping the whole controller.
                self.sv.calibrations[side] = {
                    failed = true,
                    hipBearing = leg.hip,
                    kneeBearing = leg.knee,
                    ankleBearing = leg.ankle
                }
            end
        end
    end
end

function WalkerController.sv_solvePlanarIk(self, firstLength, secondLength, targetX, targetZ, elbowSign)
    local distance = math.sqrt(targetX * targetX + targetZ * targetZ)
    local minimumDistance = math.abs(firstLength - secondLength) + MIN_LINK_LENGTH
    local maximumDistance = firstLength + secondLength - MIN_LINK_LENGTH
    if distance <= MIN_LINK_LENGTH then
        targetX = minimumDistance
        targetZ = 0
        distance = minimumDistance
    elseif distance < minimumDistance then
        local scale = minimumDistance / distance
        targetX = targetX * scale
        targetZ = targetZ * scale
        distance = minimumDistance
    elseif distance > maximumDistance then
        local scale = maximumDistance / distance
        targetX = targetX * scale
        targetZ = targetZ * scale
        distance = maximumDistance
    end

    local cosine = clamp(
        (distance * distance - firstLength * firstLength - secondLength * secondLength)
            / (2 * firstLength * secondLength),
        -1,
        1
    )
    local kneeAngle = math.acos(cosine) * elbowSign
    local hipAngle = atan2(targetZ, targetX)
        - atan2(secondLength * math.sin(kneeAngle), firstLength + secondLength * math.cos(kneeAngle))
    return hipAngle, kneeAngle
end

function WalkerController.sv_getFootPathProfile(self, phase)
    if phase < SWING_FRACTION then
        local swingProgress = smoothStep(phase / SWING_FRACTION)
        local lift = math.sin(math.pi * swingProgress)
        -- Without an ankle joint the knee must stay folded until the foot is
        -- almost at the front of the step. Extending halfway through the
        -- swing makes the foot scrape the ground.
        local kneeLift
        if swingProgress < 0.20 then
            kneeLift = smoothStep(swingProgress / 0.20)
        elseif swingProgress < 0.94 then
            kneeLift = 1
        else
            -- Keep part of the bend until the foot has already reached the
            -- front of the step. The remaining extension happens on stance.
            kneeLift = 0.25 + 0.75 * (1 - smoothStep((swingProgress - 0.94) / 0.06))
        end

        -- Keep the toe lifted during most of the transfer, then actively
        -- rotate the foot into the stance angle just before touchdown.
        local footPitch
        if swingProgress < 0.72 then
            footPitch = SWING_FOOT_PITCH_DEGREES
        else
            local touchdownProgress = smoothStep((swingProgress - 0.72) / 0.28)
            footPitch = SWING_FOOT_PITCH_DEGREES
                + (STANCE_FOOT_PITCH_DEGREES - SWING_FOOT_PITCH_DEGREES) * touchdownProgress
        end
        return -1 + swingProgress * 2, lift, kneeLift, footPitch
    end

    local stanceProgress = smoothStep((phase - SWING_FRACTION) / (1 - SWING_FRACTION))
    local kneeRelaxProgress = smoothStep(stanceProgress / 0.18)
    local kneeLift = 0.25 * (1 - kneeRelaxProgress)
    return 1 - stanceProgress * 2, 0, kneeLift, STANCE_FOOT_PITCH_DEGREES
end

function WalkerController.sv_applyIdlePose(self, assignments)
    if assignments == nil then return end
    for _, side in ipairs({ "left", "right" }) do
        local leg = assignments[side]
        self:sv_setBearingTarget(leg.hip, 0, 90)
        self:sv_setBearingTarget(leg.knee, 0, 90)
        self:sv_setBearingTarget(leg.ankle, 0, 90)
        self:sv_setBearingTarget(leg.lateral, 0, 90)
    end
end

function WalkerController.sv_applyLateralBalance(self, leg, sideSign, rollCorrection, targetSpeed)
    if leg.lateral == nil then return end

    -- The legs use mirrored signs: a roll to one side produces an opposite
    -- target on each purple bearing, widening the support on the low side.
    self:sv_setBearingTarget(leg.lateral, sideSign * rollCorrection, targetSpeed)
end

function WalkerController.sv_applyTwoJointPose(
    self,
    leg,
    phase,
    direction,
    drive,
    turn,
    sideSign,
    targetSpeed,
    pitchCorrection
)
    local pathPosition, _, kneeLift = self:sv_getFootPathProfile(phase)
    local strideDegrees = (8 + self.sv.stridePercent * 0.42) * drive
    local kneeDegrees = (12 + self.sv.stepHeightPercent * 0.75) * drive
    local turnDegrees = self.sv.turnPercent * 0.20 * turn
    local hipTarget = direction * pathPosition * strideDegrees + sideSign * turnDegrees + pitchCorrection
    self:sv_setBearingTarget(leg.hip, hipTarget, targetSpeed)
    self:sv_setBearingTarget(leg.knee, kneeLift * kneeDegrees, targetSpeed)
end

function WalkerController.sv_applyThreeJointPose(
    self,
    leg,
    calibration,
    phase,
    direction,
    drive,
    turn,
    sideSign,
    targetSpeed,
    pitchRadians
)
    local pathPosition, lift, _, footPitchDegrees = self:sv_getFootPathProfile(phase)
    local totalLength = calibration.firstLength + calibration.secondLength
    local strideDistance = totalLength * 0.45 * (self.sv.stridePercent / 100.0) * drive
    local liftDistance = totalLength * 0.30 * (self.sv.stepHeightPercent / 100.0) * drive
    local turnDistance = strideDistance * (self.sv.turnPercent / 100.0) * turn * sideSign
    local pitchBalanceDistance = -math.sin(pitchRadians) * totalLength * PITCH_BALANCE_LENGTH_GAIN
    local targetX = calibration.ankleX
        + direction * pathPosition * strideDistance
        + turnDistance
        + pitchBalanceDistance
    local targetZ = calibration.ankleZ + lift * liftDistance
    local desiredHipAngle, desiredKneeAngle = self:sv_solvePlanarIk(
        calibration.firstLength,
        calibration.secondLength,
        targetX - calibration.hipX,
        targetZ - calibration.hipZ,
        calibration.elbowSign
    )
    local hipTarget = math.deg(self:sv_normalizeAngle(desiredHipAngle - calibration.neutralHipAngle))
    local kneeTarget = math.deg(self:sv_normalizeAngle(desiredKneeAngle - calibration.neutralKneeAngle))
    -- Keep the foot approximately level by cancelling the hip and knee
    -- changes at the optional ankle joint.
    local ankleTarget = -(hipTarget + kneeTarget) * ANKLE_COMPENSATION_GAIN + footPitchDegrees
    self:sv_setBearingTarget(leg.hip, hipTarget, targetSpeed)
    self:sv_setBearingTarget(leg.knee, kneeTarget, targetSpeed)
    self:sv_setBearingTarget(leg.ankle, ankleTarget, targetSpeed)
end

function WalkerController.sv_applyWalkPose(self, assignments, forward, turn)
    local drive = math.max(math.abs(forward), math.abs(turn))
    local rollCorrection, pitchCorrection, pitchRadians = self:sv_getBalanceCorrections()
    if drive < MIN_DRIVE_INPUT then
        self:sv_applyIdlePose(assignments)
        local hasLateralBalance = false
        for _, side in ipairs({ "left", "right" }) do
            local sideSign = side == "left" and -1 or 1
            self:sv_applyLateralBalance(assignments[side], sideSign, rollCorrection, 90)
            hasLateralBalance = hasLateralBalance or assignments[side].lateral ~= nil
        end
        return hasLateralBalance and math.abs(rollCorrection) >= BALANCE_DEAD_ZONE_DEGREES
    end

    local direction = forward < -MIN_DRIVE_INPUT and -1 or 1
    local targetSpeed = clamp(110 + self.sv.cadenceTenths * 8, 110, 350)
    self:sv_refreshCalibrations(assignments)

    for _, side in ipairs({ "left", "right" }) do
        local leg = assignments[side]
        local calibration = self.sv.calibrations[side]
        local sideSign = side == "left" and -1 or 1
        local phase = self.sv.phase + (side == "right" and 0.5 or 0)
        phase = phase - math.floor(phase)
        self:sv_applyLateralBalance(leg, sideSign, rollCorrection, targetSpeed)
        if calibration ~= nil and not calibration.failed then
            local ok = pcall(
                self.sv_applyThreeJointPose,
                self,
                leg,
                calibration,
                phase,
                direction,
                drive,
                turn,
                sideSign,
                targetSpeed,
                pitchRadians
            )
            if not ok then
                calibration.failed = true
                self:sv_applyTwoJointPose(
                    leg,
                    phase,
                    direction,
                    drive,
                    turn,
                    sideSign,
                    targetSpeed,
                    pitchCorrection
                )
            end
        else
            self:sv_applyTwoJointPose(
                leg,
                phase,
                direction,
                drive,
                turn,
                sideSign,
                targetSpeed,
                pitchCorrection
            )
        end
    end

    return true
end

function WalkerController.server_onFixedUpdate(self, timeStep)
    local bearings = self.interactable:getBearings()
    local assignments = self:sv_getBearingAssignments(bearings)
    self.sv.assignments = assignments

    if not self:sv_hasValidAssignments(assignments) then
        self:sv_setBearingsNeutral(bearings)
        self.interactable:setActive(false)
        return
    end

    local forward, turn = self:sv_getSeatControls()
    local canWalk = forward ~= nil and turn ~= nil and self:sv_isLogicEnabled()
    if not canWalk then
        if not self.sv.holdBearingsOnSeatExit then
            self:sv_applyIdlePose(assignments)
        end
        self.interactable:setActive(false)
        return
    end

    local drive = math.max(math.abs(forward), math.abs(turn))
    if drive >= MIN_DRIVE_INPUT then
        self.sv.phase = (self.sv.phase + (self.sv.cadenceTenths / 10.0) * drive * timeStep) % 1.0
    else
        self.sv.phase = 0.0
    end

    local walking = self:sv_applyWalkPose(assignments, forward, turn)
    self.interactable:setActive(walking)
end

function WalkerController.client_onCreate(self)
    self.cl = {
        stridePercent = DEFAULT_STRIDE_PERCENT,
        stepHeightPercent = DEFAULT_STEP_HEIGHT_PERCENT,
        cadenceTenths = DEFAULT_CADENCE_TENTHS,
        force = DEFAULT_FORCE,
        turnPercent = DEFAULT_TURN_PERCENT,
        holdBearingsOnSeatExit = DEFAULT_HOLD_BEARINGS_ON_SEAT_EXIT,
        gui = nil
    }
end

function WalkerController.client_onClientDataUpdate(self, data)
    if self.cl == nil then self:client_onCreate() end
    self.cl.stridePercent = clampInteger(data.stridePercent, MIN_STRIDE_PERCENT, MAX_STRIDE_PERCENT, DEFAULT_STRIDE_PERCENT)
    self.cl.stepHeightPercent = clampInteger(
        data.stepHeightPercent,
        MIN_STEP_HEIGHT_PERCENT,
        MAX_STEP_HEIGHT_PERCENT,
        DEFAULT_STEP_HEIGHT_PERCENT
    )
    self.cl.cadenceTenths = clampInteger(data.cadenceTenths, MIN_CADENCE_TENTHS, MAX_CADENCE_TENTHS, DEFAULT_CADENCE_TENTHS)
    self.cl.force = clampInteger(data.force, MIN_FORCE, MAX_FORCE, DEFAULT_FORCE)
    self.cl.turnPercent = clampInteger(data.turnPercent, MIN_TURN_PERCENT, MAX_TURN_PERCENT, DEFAULT_TURN_PERCENT)
    self.cl.holdBearingsOnSeatExit = data.holdBearingsOnSeatExit == true
    self:cl_refreshGui()
end

function WalkerController.client_onDestroy(self)
    self:cl_closeGui()
end

function WalkerController.cl_closeGui(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function WalkerController.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_walker_controller"))
    return true
end

function WalkerController.client_onInteract(self, _, state)
    if not state then return end
    self:cl_closeGui()
    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("WalkerController.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "StrideSlider",
        MAX_STRIDE_PERCENT - MIN_STRIDE_PERCENT + 1,
        self.cl.stridePercent - MIN_STRIDE_PERCENT,
        "cl_onStrideSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "StepHeightSlider",
        MAX_STEP_HEIGHT_PERCENT - MIN_STEP_HEIGHT_PERCENT + 1,
        self.cl.stepHeightPercent - MIN_STEP_HEIGHT_PERCENT,
        "cl_onStepHeightSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CadenceSlider",
        MAX_CADENCE_TENTHS - MIN_CADENCE_TENTHS + 1,
        self.cl.cadenceTenths - MIN_CADENCE_TENTHS,
        "cl_onCadenceSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "ForceSlider",
        MAX_FORCE - MIN_FORCE + 1,
        self.cl.force - MIN_FORCE,
        "cl_onForceSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "TurnSlider",
        MAX_TURN_PERCENT - MIN_TURN_PERCENT + 1,
        self.cl.turnPercent - MIN_TURN_PERCENT,
        "cl_onTurnSliderChanged"
    )
    self.cl.gui:setButtonCallback("HoldButton", "cl_onHoldButtonPressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function WalkerController.cl_onStrideSliderChanged(self, position)
    self.cl.stridePercent = clampInteger(position + MIN_STRIDE_PERCENT, MIN_STRIDE_PERCENT, MAX_STRIDE_PERCENT, DEFAULT_STRIDE_PERCENT)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setStridePercent", self.cl.stridePercent)
end

function WalkerController.cl_onStepHeightSliderChanged(self, position)
    self.cl.stepHeightPercent = clampInteger(position + MIN_STEP_HEIGHT_PERCENT, MIN_STEP_HEIGHT_PERCENT, MAX_STEP_HEIGHT_PERCENT, DEFAULT_STEP_HEIGHT_PERCENT)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setStepHeightPercent", self.cl.stepHeightPercent)
end

function WalkerController.cl_onCadenceSliderChanged(self, position)
    self.cl.cadenceTenths = clampInteger(position + MIN_CADENCE_TENTHS, MIN_CADENCE_TENTHS, MAX_CADENCE_TENTHS, DEFAULT_CADENCE_TENTHS)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setCadenceTenths", self.cl.cadenceTenths)
end

function WalkerController.cl_onForceSliderChanged(self, position)
    self.cl.force = clampInteger(position + MIN_FORCE, MIN_FORCE, MAX_FORCE, DEFAULT_FORCE)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setForce", self.cl.force)
end

function WalkerController.cl_onTurnSliderChanged(self, position)
    self.cl.turnPercent = clampInteger(position + MIN_TURN_PERCENT, MIN_TURN_PERCENT, MAX_TURN_PERCENT, DEFAULT_TURN_PERCENT)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setTurnPercent", self.cl.turnPercent)
end

function WalkerController.cl_onHoldButtonPressed(self)
    self.cl.holdBearingsOnSeatExit = not self.cl.holdBearingsOnSeatExit
    self:cl_refreshGui()
    self.network:sendToServer("sv_setHoldBearingsOnSeatExit", self.cl.holdBearingsOnSeatExit)
end

function WalkerController.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText("StrideValue", PC_L.get("stride_length", self.cl.stridePercent))
    self.cl.gui:setText("StepHeightValue", PC_L.get("foot_lift", self.cl.stepHeightPercent))
    self.cl.gui:setText("CadenceValue", PC_L.get("cadence", self.cl.cadenceTenths / 10.0))
    self.cl.gui:setText("ForceValue", PC_L.get("motor_force", self.cl.force))
    self.cl.gui:setText("TurnValue", PC_L.get("turn_bias", self.cl.turnPercent))
    self.cl.gui:setText(
        "HoldButton",
        self.cl.holdBearingsOnSeatExit and "On seat exit: hold pose" or "On seat exit: return to neutral"
    )
end

function WalkerController.cl_onGuiClosed(self)
    self:cl_closeGui()
end
