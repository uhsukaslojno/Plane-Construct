-- Lift behavior derived from the airfoil script included with Scoob's Plane Parts.
-- Original copyright (c) 2018 DasEtwas.

local maxLiftPerSquareMeter = 17000 -- high-speed lift cap, reached around 400 km/h
local minimumLiftSpeed = 15 -- 60 Scrap Mechanic blocks per second
local liftPerSpeedPerSquareMeter = 1000
local maxLiftChangePerSquareMeterPerSecond = 80000
local sleepTime = 5
local maxVel = 600
local maxVelTimeout = 10 * 40
local minimumLiftSpeed = 50.0 / 3.6
local fullLiftSpeed = 150.0 / 3.6
local highSpeedLiftStart = 500.0 / 3.6
local highSpeedLiftEnd = 1500.0 / 3.6
local highSpeedEquivalent = 75.0 / 3.6
local groundEffectHeight = 20
local groundEffectFactor = 1.5
local groundEffectCurve = 1.4
local groundEffectChance = 0.15
local groundRay = sm.vec3.new(0, 0, -groundEffectHeight)

local function sign(number)
    if number < 0 then return -1 end
    if number > 0 then return 1 end
    return 0
end

local function highSpeedEffectiveNormalVelocity(normalVelocity, totalSpeed)
    local cappedVelocity = math.max(-highSpeedEquivalent, math.min(highSpeedEquivalent, normalVelocity))
    if totalSpeed <= highSpeedLiftStart then
        return normalVelocity
    elseif totalSpeed >= highSpeedLiftEnd then
        return cappedVelocity
    end
    local transition = (totalSpeed - highSpeedLiftStart) / (highSpeedLiftEnd - highSpeedLiftStart)
    return normalVelocity + (cappedVelocity - normalVelocity) * transition
end

local function highSpeedEffectiveSpeed(speed)
    if speed <= highSpeedLiftStart then
        return speed
    elseif speed >= highSpeedLiftEnd then
        return highSpeedEquivalent
    end
    local transition = (speed - highSpeedLiftStart) / (highSpeedLiftEnd - highSpeedLiftStart)
    return speed + (highSpeedEquivalent - speed) * transition
end

local function applyAirfoil(self, dt)
    if self.sleepTimer == nil then self.sleepTimer = 0 end

    local globalVelocity = sm.shape.getVelocity(self.shape)
    local speed = globalVelocity:length()
    if globalVelocity.x ~= globalVelocity.x then return end

    if speed > 0.08 then
        self.sleepTimer = self.sleepTimer + 1
    else
        self.sleepTimer = math.max(-sleepTime, math.min(self.sleepTimer - 1, 0))
    end

    if speed > maxVel and self.sleepTimer > -sleepTime then
        self.sleepTimer = -maxVelTimeout
        print("[Sided Wings] Disabled wing for " .. (maxVelTimeout / 40) .. " seconds due to high velocity (>" .. maxVel .. "m/s)")
    end

    if self.sleepTimer <= 0 then return end

    local position = sm.shape.getWorldPosition(self.shape)
    if math.random() <= groundEffectChance then
        local hit, result = sm.physics.raycast(position, position + groundRay, self.shape:getBody())
        if hit and (result.type == "terrainSurface" or result.type == "terrainAsset") then
            self.lastGroundHeight = result.pointWorld.z
        end
    end

    local groundDistance = position.z - self.lastGroundHeight
    if groundDistance < groundEffectHeight then
        local effect = math.pow(1 - math.min(1, math.max(0, groundDistance / groundEffectHeight)), groundEffectCurve) * groundEffectFactor
        local lateralEffect = effect * 0.2 + 1
        sm.vec3.setX(self.factor, lateralEffect)
        sm.vec3.setY(self.factor, lateralEffect)
        sm.vec3.setZ(self.factor, effect + 1)
    else
        sm.vec3.setX(self.factor, 1)
        sm.vec3.setY(self.factor, 1)
        sm.vec3.setZ(self.factor, 1)
    end

    local angleSin = -math.sin(math.rad(self.angle))
    local angleCos = math.cos(math.rad(self.angle))
    local globalUp = sm.shape.getAt(self.shape) * -angleCos + sm.shape.getRight(self.shape) * angleSin
    local normalVelocity = highSpeedEffectiveNormalVelocity(globalVelocity:dot(globalUp), speed)
    local previousLift = self.lift or 0
    -- This wing set intentionally uses a linear response above 60 blocks/s.
    -- The area-scaled cap prevents runaway force at extreme velocities.
    local liftLimit = maxLiftPerSquareMeter * self.area
    local liftSpeed = math.max(0, math.abs(normalVelocity) - minimumLiftSpeed)
    local requestedLift = liftPerSpeedPerSquareMeter * liftSpeed * self.area * sign(normalVelocity)
    requestedLift = math.max(-liftLimit, math.min(liftLimit, requestedLift))

    -- Smooth both increasing and decreasing lift. The inherited script only
    -- smoothed increases, allowing the force to snap to zero on an elevon.
    local maxLiftChange = maxLiftChangePerSquareMeterPerSecond * self.area * dt
    self.lift = previousLift + math.max(-maxLiftChange, math.min(maxLiftChange, requestedLift - previousLift))

    local speedFactor = math.min(1, math.max(0, (speed - minimumLiftSpeed) / (fullLiftSpeed - minimumLiftSpeed)))
    self.lift = self.lift * speedFactor

    -- Convert the locally calculated lift vector into world space before it
    -- is passed to the physics engine. Applying the local vector directly is
    -- unstable when the wing rotates on a bearing.
    local localImpulse = sm.vec3.new(-self.lift * dt * 40 * angleSin, self.lift * dt * 40 * angleCos, 0)
    local worldImpulse = sm.shape.getRight(self.shape) * localImpulse.x
        + sm.shape.getAt(self.shape) * localImpulse.y
        + sm.shape.getUp(self.shape) * localImpulse.z
    worldImpulse = worldImpulse * self.factor
    sm.physics.applyImpulse(self.shape, worldImpulse)
end

local function initializeWing(self)
    -- Mutable vectors must be per instance; a class-level vector makes every
    -- wing on the creation overwrite every other wing's ground-effect state.
    self.factor = sm.vec3.new(1, 1, 1)
    self.lastGroundHeight = -100
    self.lift = 0
    self.sleepTimer = 0
end

SidedWing1x1 = class(nil)
SidedWing1x1.area = 0.0625
SidedWing1x1.angle = 0
SidedWing1x1.width = 0.5
SidedWing1x1.chord = 0.125

function SidedWing1x1.server_onCreate(self)
    initializeWing(self)
end

function SidedWing1x1.server_onFixedUpdate(self, timeStep)
    applyAirfoil(self, timeStep)
end

CenteredWing1x1 = class(nil)
CenteredWing1x1.area = 0.0625
CenteredWing1x1.angle = 0
CenteredWing1x1.width = 0.5
CenteredWing1x1.chord = 0.125

function CenteredWing1x1.server_onCreate(self)
    initializeWing(self)
end

function CenteredWing1x1.server_onFixedUpdate(self, timeStep)
    applyAirfoil(self, timeStep)
end

-- Experimental centered wing with a simple aerodynamic model.
-- The force is based on angle of attack rather than only normal velocity:
-- lift rises up to the critical angle, then drops as the wing stalls.
-- Scrap Mechanic velocities are expressed in block-units and the physics API
-- expects an impulse, so these values are deliberately conservative.
local experimentalAirDensity = 2.0
local experimentalArea = 0.0625
local experimentalStallAngle = math.rad(16.0)
local experimentalFullStallAngle = math.rad(45.0)
local experimentalLiftSlope = 4.0
local experimentalMaxLiftCoefficient = 1.0
local experimentalMaxLift = 250.0
local experimentalMaxDrag = 60.0
local experimentalMaxImpulsePerTick = 4.0

local function clampValue(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function initializeExperimentalWing(self)
    self.experimentalLift = 0.0
end

local function applyExperimentalAirfoil(self, timeStep)
    local velocity = sm.shape.getVelocity(self.shape)
    local speed = velocity:length()
    if speed < 0.5 or velocity.x ~= velocity.x then
        self.experimentalLift = 0.0
        return
    end

    -- These are the same local axes used by the already working Scoob wing:
    -- shape.at is its lift-normal axis and shape.right is the chord/airflow
    -- axis. Using shape.up here makes the lift point in the wrong direction.
    local normal = sm.shape.getAt(self.shape)
    local forward = sm.shape.getRight(self.shape)
    local flowDirection = velocity / speed
    local forwardComponent = velocity:dot(forward)
    local normalComponent = velocity:dot(normal)
    local angleOfAttack = math.atan2(normalComponent, math.max(0.01, math.abs(forwardComponent)))
    local liftCoefficient
    local absoluteAngle = math.abs(angleOfAttack)
    if absoluteAngle <= experimentalStallAngle then
        liftCoefficient = experimentalLiftSlope * angleOfAttack
        liftCoefficient = clampValue(liftCoefficient, -experimentalMaxLiftCoefficient, experimentalMaxLiftCoefficient)
    else
        local stallProgress = clampValue(
            (absoluteAngle - experimentalStallAngle) / (experimentalFullStallAngle - experimentalStallAngle),
            0.0,
            1.0
        )
        local preStallCoefficient = experimentalMaxLiftCoefficient * (angleOfAttack < 0 and -1 or 1)
        local stalledCoefficient = 0.12 * (angleOfAttack < 0 and -1 or 1)
        liftCoefficient = preStallCoefficient + (stalledCoefficient - preStallCoefficient) * stallProgress
    end

    local effectiveSpeed = highSpeedEffectiveSpeed(speed)
    local dynamicPressure = 0.5 * experimentalAirDensity * effectiveSpeed * effectiveSpeed
    local lift = clampValue(dynamicPressure * experimentalArea * liftCoefficient, -experimentalMaxLift, experimentalMaxLift)
    local dragCoefficient = 0.035 + 0.08 * liftCoefficient * liftCoefficient
    if absoluteAngle > experimentalStallAngle then
        dragCoefficient = dragCoefficient + 0.45 * clampValue(
            (absoluteAngle - experimentalStallAngle) / (experimentalFullStallAngle - experimentalStallAngle),
            0.0,
            1.0
        )
    end
    local drag = math.min(experimentalMaxDrag, dynamicPressure * experimentalArea * dragCoefficient)

    local liftDirection = normal - flowDirection * normal:dot(flowDirection)
    if liftDirection:length() < 0.001 then return end
    liftDirection = liftDirection:normalize()
    -- One fixed update is already a physics step. The previous *40 multiplier
    -- turned a per-second force into a full impulse every tick and launched
    -- multi-wing aircraft out of the world.
    -- Keep the experimental wing stable when several wings are used together.
    -- A larger multiplier amplified small rotational differences into runaway
    -- spin and launch velocity on flat aircraft such as a frisbee.
    local liftImpulse = liftDirection * (lift * timeStep * 0.5)
    local dragImpulse = flowDirection * (-drag * timeStep * 0.5)
    local impulse = liftImpulse + dragImpulse
    local impulseLength = impulse:length()
    if impulseLength > experimentalMaxImpulsePerTick then
        impulse = impulse:normalize() * experimentalMaxImpulsePerTick
    end
    sm.physics.applyImpulse(self.shape, impulse)
    self.experimentalLift = lift
end

-- Experimental version intentionally follows ScoobAirfoil.lua line-for-line
-- for the force axes and impulse timing. Only stall behavior and a small lift
-- scale are added on top of the proven implementation.
local experimentalOriginalLiftScale = 1.0
local experimentalOriginalStallAngle = 16.0
local experimentalOriginalFullStallAngle = 42.0
-- Keep the experimental original wing under the same 400 km/h-equivalent
-- per-area cap as every other wing in this mod.
local experimentalOriginalMaxLift = maxLiftPerSquareMeter * experimentalArea

local function applyExperimentalOriginalAirfoil(self, dt)
    if self.sleepTimer == nil then self.sleepTimer = 0 end

    local globalVel = sm.shape.getVelocity(self.shape)
    local globalVelL = globalVel:length()
    if globalVel.x ~= globalVel.x then return end

    if globalVelL > 0.08 then
        self.sleepTimer = self.sleepTimer + 1
    else
        self.sleepTimer = math.max(-5, math.min(self.sleepTimer - 1, 0))
    end

    if self.sleepTimer <= 0 then return end

    -- This is the same lift axis used by the working centered wing.
    local aSin = 0.0
    local aCos = 1.0
    local globalUp = sm.shape.getAt(self.shape) * -aCos + sm.shape.getRight(self.shape) * aSin
    local normalVel = globalVel:dot(globalUp)

    -- Estimate angle of attack only to attenuate lift after stall. The lift
    -- vector itself remains exactly the original ScoobAirfoil vector.
    local chordVel = globalVel:dot(sm.shape.getRight(self.shape))
    local angle = math.deg(math.atan2(math.abs(normalVel), math.max(0.01, math.abs(chordVel))))
    local stallFactor = 1.0
    if angle > experimentalOriginalStallAngle then
        stallFactor = 1.0 - clampValue(
            (angle - experimentalOriginalStallAngle) /
            (experimentalOriginalFullStallAngle - experimentalOriginalStallAngle),
            0.0,
            0.85
        )
    end

    -- Match ScoobAirfoil's original air-density value. Only stallFactor is
    -- different from the working wing's lift calculation.
    local effectiveNormalVel = highSpeedEffectiveNormalVelocity(normalVel, globalVelL)
    local lift = 2.75 * effectiveNormalVel * effectiveNormalVel * 0.5
        * experimentalArea * (normalVel < 0 and -1 or 1)
    lift = lift * experimentalOriginalLiftScale * stallFactor
    lift = clampValue(lift, -experimentalOriginalMaxLift, experimentalOriginalMaxLift)

    -- Keep ScoobAirfoil's lift magnitude, but remove the component parallel
    -- to the airflow. This prevents climb/descent speed from turning lift
    -- into forward or sideways thrust and avoids the unwanted yaw/roll.
    local flowDirection = globalVel / globalVelL
    local liftDirection = globalUp - flowDirection * globalUp:dot(flowDirection)
    if liftDirection:length() < 0.001 then return end
    liftDirection = liftDirection:normalize()
    local worldImpulse = liftDirection * (lift * dt * 40.0)
    sm.physics.applyImpulse(self.shape, worldImpulse)
end

ExperimentalCenteredWingTMount1x1 = class(nil)
ExperimentalCenteredWingTMount1x1.area = experimentalArea
ExperimentalCenteredWingTMount1x1.angle = 0
ExperimentalCenteredWingTMount1x1.width = 0.5
ExperimentalCenteredWingTMount1x1.chord = 0.125

function ExperimentalCenteredWingTMount1x1.server_onCreate(self)
    initializeExperimentalWing(self)
end

function ExperimentalCenteredWingTMount1x1.server_onFixedUpdate(self, timeStep)
    applyExperimentalOriginalAirfoil(self, timeStep)
end

ExperimentalCenteredWingRealistic1x1 = class(nil)
ExperimentalCenteredWingRealistic1x1.area = experimentalArea
ExperimentalCenteredWingRealistic1x1.angle = 0
ExperimentalCenteredWingRealistic1x1.width = 0.5
ExperimentalCenteredWingRealistic1x1.chord = 0.125

function ExperimentalCenteredWingRealistic1x1.server_onCreate(self)
    initializeExperimentalWing(self)
end

function ExperimentalCenteredWingRealistic1x1.server_onFixedUpdate(self, timeStep)
    applyExperimentalOriginalAirfoil(self, timeStep)
end

-- A 1x1 wing variant that can be destroyed by any active logic trigger.
-- This keeps the same lift model as the regular sided wing, but exposes one
-- logic input so it can be connected to a Flight Sensor, button, timer, etc.
BreakableSidedWing1x1 = class(nil)
BreakableSidedWing1x1.maxParentCount = 1
BreakableSidedWing1x1.maxChildCount = 0
BreakableSidedWing1x1.connectionInput = sm.interactable.connectionType.logic
BreakableSidedWing1x1.connectionOutput = sm.interactable.connectionType.none
BreakableSidedWing1x1.area = 0.0625
BreakableSidedWing1x1.angle = 0
BreakableSidedWing1x1.width = 0.5
BreakableSidedWing1x1.chord = 0.125

function BreakableSidedWing1x1.server_onCreate(self)
    initializeWing(self)
end

function BreakableSidedWing1x1.server_onFixedUpdate(self, timeStep)
    local parent = self.interactable:getSingleParent()
    if parent and parent:isActive() then
        sm.shape.destroyPart(self.shape)
        return
    end

    applyAirfoil(self, timeStep)
end
