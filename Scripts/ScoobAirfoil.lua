dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
-------------------------------
--Copyright (c) 2018 DasEtwas--
-------------------------------

airDensity         = 2.75
sleepTime          = 5          -- how long it takes for a wing to fall asleep
maxForce           = 80000      -- max force excerted by a wing in N
maxJerk            = 1.4 + 0.4  -- is multiplied with velocity
maxLiftPerSquareMeter = 17000   -- high-speed lift cap, reached around 400 km/h
maxLiftChangePerSquareMeterPerSecond = 80000 -- smooths lift changes both ways
maxVel             = 600
maxVelTimeout      = 10 * 40
minimumLiftSpeed   = 100.0 / 3.6 -- no lift below 100 km/h
fullLiftSpeed      = 200.0 / 3.6 -- full lift at 200 km/h
highSpeedLiftStart = 500.0 / 3.6 -- start reducing aerodynamic effectiveness
highSpeedLiftEnd   = 1500.0 / 3.6 -- reach the low-speed equivalent here
highSpeedEquivalent = 75.0 / 3.6 -- above the end speed, act like 75 km/h
groundEffectHeight = 20
groundEffectFactor = -1 + (2.5) -- math.pow(dist/height, gEF)
groundEffectCurve  = 1.4
groundEffectChance = 0.15
stallEntryAngle = math.rad(20) -- enter stall above this angle of attack
stallRecoveryMidAngle = math.rad(10) -- lift reaches 30% here while recovering
stallRecoveryFullAngle = math.rad(0.1) -- practically level flight restores 100%
stallLiftFactor = 0.03 -- lift retained at a fully stalled angle
stallRecoveryStartFactor = 0.05 -- lift at the start of the recovery curve
stallRecoveryMidFactor = 0.30 -- lift at 10 degrees during recovery
stallReferenceWingLoading = 100.0 -- reference creation mass per square meter of wing
stallMaxLightweightAngleBonus = math.rad(5) -- extra AoA margin for low wing loading
gefv = sm.vec3.new(0, 0, -groundEffectHeight)

local STALL_MODE_CAN = 1
local STALL_MODE_CANNOT = 2
local STALL_MODE_FOLLOW = 3
local WING_STALL_REGISTRY_NAME = "PlaneConstructWingStallRegistry"
_G[WING_STALL_REGISTRY_NAME] = _G[WING_STALL_REGISTRY_NAME] or {}

local function normalizeStallMode(mode)
	mode = tonumber(mode)
	if mode == nil then return STALL_MODE_CAN end
	return math.max(STALL_MODE_CAN, math.min(STALL_MODE_FOLLOW, math.floor(mode)))
end

local function getWingCreationKey(self)
	local body = self.shape:getBody()
	local lowestBodyId = body:getId()
	for _, creationBody in pairs(body:getCreationBodies()) do
		lowestBodyId = math.min(lowestBodyId, creationBody:getId())
	end
	return tostring(lowestBodyId)
end

local function getWingRegistryEntry(self)
	local registry = _G[WING_STALL_REGISTRY_NAME]
	local creationKey = getWingCreationKey(self)
	local shapeId = tostring(self.shape:getId())

	if self.wingStallCreationKey ~= creationKey then
		if self.wingStallCreationKey ~= nil and registry[self.wingStallCreationKey] ~= nil then
			registry[self.wingStallCreationKey][shapeId] = nil
		end
		self.wingStallCreationKey = creationKey
	end

	registry[creationKey] = registry[creationKey] or {}
	registry[creationKey][shapeId] = registry[creationKey][shapeId] or {}
	return registry[creationKey], registry[creationKey][shapeId]
end

local function removeWingFromStallRegistry(self)
	local registry = _G[WING_STALL_REGISTRY_NAME]
	local creationKey = self.wingStallCreationKey
	if creationKey ~= nil and registry[creationKey] ~= nil then
		registry[creationKey][tostring(self.shape:getId())] = nil
	end
	self.wingStallCreationKey = nil
end

function sign(num)
	if num < 0 then
		return -1
	elseif num > 0 then
		return 1
	else
		return 0
	end
end

function equals(vec1, vec2)
	return sm.vec3.getX(vec1) == sm.vec3.getX(vec2) and sm.vec3.getY(vec1) == sm.vec3.getY(vec2) and sm.vec3.getZ(vec1) == sm.vec3.getZ(vec2)
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

-- During the takeoff/landing transition, let each individual wing element
-- vary its effective lift by a small, independent amount. The factor is held
-- briefly before being regenerated so it is a visible variation, not noise
-- from every physics tick.
local transitionLiftVariationMin = 0.10
local transitionLiftVariationMax = 0.20
local transitionLiftVariationMinTime = 0.45
local transitionLiftVariationMaxTime = 1.00

local function applyTransitionLiftVariation(self, speed, dt, lift)
	local transition = (speed - minimumLiftSpeed) / (fullLiftSpeed - minimumLiftSpeed)
	if transition > 0 and transition < 1 then
		if self.liftVariationTimer == nil or self.liftVariationTimer <= 0 then
			local variation = transitionLiftVariationMin +
				math.random() * (transitionLiftVariationMax - transitionLiftVariationMin)
			self.liftVariationFactor = 1 + variation * (math.random(0, 1) == 0 and -1 or 1)
			self.liftVariationTimer = transitionLiftVariationMinTime +
				math.random() * (transitionLiftVariationMaxTime - transitionLiftVariationMinTime)
		end
		self.liftVariationTimer = self.liftVariationTimer - dt
		return lift * (self.liftVariationFactor or 1)
	end

	-- Keep the next transition independent of the previous one.
	self.liftVariationFactor = 1
	self.liftVariationTimer = 0
	return lift
end

local function getStallAngleOffset(self, group, entry)
	-- Keep the area in the shared creation registry so the calculation sees
	-- all wing elements, not only the wing currently being updated.
	entry.area = self.area or 0
	local totalWingArea = 0
	for _, wing in pairs(group) do
		totalWingArea = totalWingArea + (wing.area or 0)
	end
	if totalWingArea <= 0 then
		return 0
	end

	local body = self.shape:getBody()
	local totalMass = 0
	for _, creationBody in pairs(body:getCreationBodies()) do
		totalMass = totalMass + creationBody:getMass()
	end
	if totalMass <= 0 then
		totalMass = body:getMass()
	end

	local wingLoading = totalMass / totalWingArea
	-- Only low wing loading gets an additional margin. This prevents the
	-- correction from making heavier aircraft stall earlier than before.
	local lightweightFactor = math.max(0, math.min(1,
		(stallReferenceWingLoading - wingLoading) / stallReferenceWingLoading))
	return stallMaxLightweightAngleBonus * lightweightFactor
end

local function applyStall(self, totalSpeed, lift)
	local mode = normalizeStallMode(self.stallMode)
	self.stallMode = mode
	local stallFactor = 1
	local group, entry = getWingRegistryEntry(self)
	local stallAngleOffset = getStallAngleOffset(self, group, entry)
	local effectiveStallEntryAngle = stallEntryAngle + stallAngleOffset
	local effectiveRecoveryMidAngle = stallRecoveryMidAngle + stallAngleOffset

	-- Only the first mode is allowed to initiate a stall from its own
	-- angle of attack. The third mode can only follow another wing.
	if mode == STALL_MODE_CAN and totalSpeed > 0.001 then
		local normalRatio = math.abs(self.normalVel) / totalSpeed
		normalRatio = math.min(1, math.max(0, normalRatio))
		local angleOfAttack = math.asin(normalRatio)

		if not self.stalled and angleOfAttack > effectiveStallEntryAngle then
			self.stalled = true
		end

		if self.stalled then
			if angleOfAttack <= stallRecoveryFullAngle then
				self.stalled = false
			elseif angleOfAttack > effectiveStallEntryAngle then
				stallFactor = stallLiftFactor
			elseif angleOfAttack > effectiveRecoveryMidAngle then
				local progress = (effectiveStallEntryAngle - angleOfAttack) /
					(effectiveStallEntryAngle - effectiveRecoveryMidAngle)
				stallFactor = stallRecoveryStartFactor +
					(stallRecoveryMidFactor - stallRecoveryStartFactor) * progress
			else
				local progress = (effectiveRecoveryMidAngle - angleOfAttack) /
					(effectiveRecoveryMidAngle - stallRecoveryFullAngle)
				stallFactor = stallRecoveryMidFactor +
					(1 - stallRecoveryMidFactor) * progress
			end
		end
	else
		self.stalled = false
	end

	entry.mode = mode
	entry.stalled = mode == STALL_MODE_CAN and self.stalled == true
	entry.stallFactor = entry.stalled and stallFactor or 1

	local anotherWingIsStalled = false
	local groupStallFactor = 1
	for _, wing in pairs(group) do
		if wing.mode == STALL_MODE_CAN and wing.stalled then
			anotherWingIsStalled = true
			groupStallFactor = math.min(groupStallFactor, wing.stallFactor or stallLiftFactor)
		end
	end

	if self.stalled then
		return lift * stallFactor
	elseif mode == STALL_MODE_FOLLOW and anotherWingIsStalled then
		return lift * groupStallFactor
	end
	return lift
end

function airfoil(self, dt)
	if self.sleepTimer == nil then self.sleepTimer = 0 end
	
	local globalVel = sm.shape.getVelocity(self.shape)
	local globalVelL = globalVel:length()
	if globalVel.x ~= globalVel.x then -- nan
		return
	end
	
	if globalVelL > 0.08 then
		self.sleepTimer = self.sleepTimer + 1
	else
		self.sleepTimer = math.max(-sleepTime, math.min(self.sleepTimer - 1, 0))
	end
	
	-- spazzing out protection
	if globalVelL > maxVel and self.sleepTimer > -sleepTime then
		self.sleepTimer = -maxVelTimeout
		print("[Wings] Disabled wing for " .. (maxVelTimeout / 40) .. " seconds due to high velocity (>" .. maxVel .. "m/s)")
	end
	
	
	if self.sleepTimer > 0 then
		local pos = sm.shape.getWorldPosition(self.shape)
		if math.random() <= groundEffectChance then
			local hit, rcr = sm.physics.raycast(pos, pos + gefv, self.shape:getBody())
			
			if hit and (rcr.type == "terrainSurface" or rcr.type == "terrainAsset") then
				self.lastGroundHeight = rcr.pointWorld.z
end	
  end

		local groundDist = pos.z - self.lastGroundHeight;
		if groundDist < groundEffectHeight then
			local temp = math.pow(1 - math.min(1, math.max(0, groundDist / groundEffectHeight)), groundEffectCurve) * groundEffectFactor
			local temp2 = temp * 0.2 + 1
			sm.vec3.setX(self.factor, temp2)
			sm.vec3.setY(self.factor, temp2)
			sm.vec3.setZ(self.factor, temp + 1)
		else
			sm.vec3.setX(self.factor, 1)
			sm.vec3.setY(self.factor, 1)
			sm.vec3.setZ(self.factor, 1)
		end
		
		local aSin = -math.sin(math.rad(self.angle))
		local aCos = math.cos(math.rad(self.angle))
		local globalUp = sm.shape.getAt(self.shape) * -aCos + sm.shape.getRight(self.shape) * aSin
		
		self.normalVel = highSpeedEffectiveNormalVelocity(globalVel:dot(globalUp), globalVelL)
		local lastLift = self.lift or 0
		self.lift = airDensity * self.normalVel * self.normalVel * 0.5 * self.area * sign(self.normalVel) 

		-- At high speed lift grows with velocity squared. Cap it by wing area
		-- before converting it to an impulse, otherwise small corrections can
		-- become a rapidly alternating shake on the whole aircraft.
		local liftLimit = maxLiftPerSquareMeter * self.area
		self.lift = math.max(-liftLimit, math.min(liftLimit, self.lift))
		
		--if math.abs(self.lift - lastLift) > maxJerk then
			--self.sleepTimer = -sleepTime - 2
			---return
		--end
		
		local maxLiftChange = maxLiftChangePerSquareMeterPerSecond * self.area * dt
		self.lift = lastLift + math.max(
			-maxLiftChange,
			math.min(maxLiftChange, self.lift - lastLift)
		)

	local speedFactor = math.min(1, math.max(0, (globalVelL - minimumLiftSpeed) / (fullLiftSpeed - minimumLiftSpeed)))
	local effectiveLift = self.lift * speedFactor
	effectiveLift = applyTransitionLiftVariation(self, globalVelL, dt, effectiveLift)
	effectiveLift = applyStall(self, globalVelL, effectiveLift)
			
		--print(self.lift - lastLift)
		--print(globalVelL)
		
	local lift = sm.vec3.new(-effectiveLift * dt * 40 * aSin, effectiveLift * dt * 40 * aCos, 0) * self.factor
		self.lastLift = sm.shape.getRight(self.shape) * lift.x + sm.shape.getAt(self.shape) * lift.y + sm.shape.getUp(self.shape) * lift.z
		sm.physics.applyImpulse(self.shape, lift)
end	
 end
Wing1x1 = class(nil)
Wing1x1.area = 0.0625
Wing1x1.sleep = movementSleep
Wing1x1.angle = 0
Wing1x1.width = 0.5
Wing1x1.chord = 0.125
Wing1x1.factor = sm.vec3.new(1, 1, 1)
Wing1x1.lastGroundHeight = -100

function Wing1x1.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

Wing2x2 = class(nil)
Wing2x2.area = 0.25
Wing2x2.sleep = movementSleep
Wing2x2.angle = 0
Wing2x2.width = 0.5
Wing2x2.chord = 0.5
Wing2x2.factor = sm.vec3.new(1, 1, 1)
Wing2x2.lastGroundHeight = -100

function Wing2x2.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

Wing3x3 = class(nil)
Wing3x3.area = 0.5625
Wing3x3.sleep = movementSleep
Wing3x3.angle = 0
Wing3x3.width = 0.75
Wing3x3.chord = 0.75
Wing3x3.factor = sm.vec3.new(1, 1, 1)
Wing3x3.lastGroundHeight = -100

function Wing3x3.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

Wing4x4 = class(nil)
Wing4x4.area = 1.0
Wing4x4.sleep = movementSleep
Wing4x4.angle = 0
Wing4x4.width = 1.0
Wing4x4.chord = 1.0
Wing4x4.factor = sm.vec3.new(1, 1, 1)
Wing4x4.lastGroundHeight = -100

function Wing4x4.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x1 = class(nil)
WingWedge1x1.area = 0.0625
WingWedge1x1.sleep = movementSleep
WingWedge1x1.angle = 0
WingWedge1x1.width = 0.5
WingWedge1x1.chord = 0.125
WingWedge1x1.factor = sm.vec3.new(1, 1, 1)
WingWedge1x1.lastGroundHeight = -100

function WingWedge1x1.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x2 = class(nil)
WingWedge1x2.area = 0.125
WingWedge1x2.sleep = movementSleep
WingWedge1x2.angle = 0
WingWedge1x2.width = 0.25
WingWedge1x2.chord = 0.25
WingWedge1x2.factor = sm.vec3.new(1, 1, 1)WingWedge1x1.lastGroundHeight = -100

function WingWedge1x2.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x3 = class(nil)
WingWedge1x3.area = 0.375
WingWedge1x3.sleep = movementSleep
WingWedge1x3.angle = 0
WingWedge1x3.width = 0.375
WingWedge1x3.chord = 0.375
WingWedge1x3.factor = sm.vec3.new(1, 1, 1)
WingWedge1x3.lastGroundHeight = -100

function WingWedge1x3.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x4 = class(nil)
WingWedge1x4.area = 0.50
WingWedge1x4.sleep = movementSleep
WingWedge1x4.angle = 0
WingWedge1x4.width = 0.5
WingWedge1x4.chord = 0.5
WingWedge1x4.factor = sm.vec3.new(1, 1, 1)WingWedge1x4.lastGroundHeight = -100

function WingWedge1x4.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x5 = class(nil)
WingWedge1x5.area = 0.625
WingWedge1x5.sleep = movementSleep
WingWedge1x5.angle = 0
WingWedge1x5.width = 0.625
WingWedge1x5.chord = 0.625
WingWedge1x5.factor = sm.vec3.new(1, 1, 1)
WingWedge1x5.lastGroundHeight = -100

function WingWedge1x5.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x6 = class(nil)
WingWedge1x6.area = 0.75
WingWedge1x6.sleep = movementSleep
WingWedge1x6.angle = 0
WingWedge1x6.width = 0.75
WingWedge1x6.chord = 0.75
WingWedge1x6.factor = sm.vec3.new(1, 1, 1)
WingWedge1x6.lastGroundHeight = -100

function WingWedge1x6.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x7 = class(nil)
WingWedge1x7.area = 0.875
WingWedge1x7.sleep = movementSleep
WingWedge1x7.angle = 0
WingWedge1x7.width = 0.875
WingWedge1x7.chord = 0.875
WingWedge1x7.factor = sm.vec3.new(1, 1, 1)
WingWedge1x7.lastGroundHeight = -100

function WingWedge1x7.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x8 = class(nil)
WingWedge1x8.area = 1
WingWedge1x8.sleep = movementSleep
WingWedge1x8.angle = 0
WingWedge1x8.width = 1
WingWedge1x8.chord = 1
WingWedge1x8.factor = sm.vec3.new(1, 1, 1)
WingWedge1x8.lastGroundHeight = -100

function WingWedge1x8.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x9 = class(nil)
WingWedge1x9.area = 1.125
WingWedge1x9.sleep = movementSleep
WingWedge1x9.angle = 0
WingWedge1x9.width = 1.125
WingWedge1x9.chord = 1.125
WingWedge1x9.factor = sm.vec3.new(1, 1, 1)
WingWedge1x9.lastGroundHeight = -100

function WingWedge1x9.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

WingWedge1x10 = class(nil)
WingWedge1x10.area = 1.25
WingWedge1x10.sleep = movementSleep
WingWedge1x10.angle = 0
WingWedge1x10.width = 1.25
WingWedge1x10.chord = 1.25
WingWedge1x10.factor = sm.vec3.new(1, 1, 1)
WingWedge1x10.lastGroundHeight = -100

function WingWedge1x10.server_onFixedUpdate(self, timeStep)
	airfoil(self, timeStep)
end

-- end of file --

local function wing_serverInitialize(self)
	local stored = self.storage:load()
	if type(stored) == "table" and stored.stallMode ~= nil then
		self.stallMode = normalizeStallMode(stored.stallMode)
	elseif type(stored) == "table" and stored.canStall == false then
		-- Migrate the previous two-state format.
		self.stallMode = STALL_MODE_CANNOT
	else
		self.stallMode = STALL_MODE_CAN
	end

	self.canStall = self.stallMode == STALL_MODE_CAN
	self.storage:save({ stallMode = self.stallMode })
	self.network:setClientData({ stallMode = self.stallMode })
end

local function wing_serverToggleStall(self)
	self.stallMode = normalizeStallMode((self.stallMode or STALL_MODE_CAN) % STALL_MODE_FOLLOW + 1)
	self.canStall = self.stallMode == STALL_MODE_CAN
	self.storage:save({ stallMode = self.stallMode })
	self.network:setClientData({ stallMode = self.stallMode })
	self.network:sendToClients("cl_showStallNotification", self.stallMode)
end

local function wing_clientCreate(self)
	self.wingClient = { stallMode = STALL_MODE_CAN }
end

local function wing_clientDataUpdate(self, data)
	if self.wingClient == nil then
		wing_clientCreate(self)
	end

	self.wingClient.stallMode = normalizeStallMode(data and data.stallMode)
end

local function wing_clientShowStallNotification(self, stallMode)
	stallMode = normalizeStallMode(stallMode)
	local messageKey = "wing_can_stall"
	if stallMode == STALL_MODE_CANNOT then
		messageKey = "wing_cannot_stall"
	elseif stallMode == STALL_MODE_FOLLOW then
		messageKey = "wing_follow_stall"
	end
	sm.gui.displayAlertText(PC_L.get(messageKey), 3.0)
end

local function wing_clientCanInteract(self)
	sm.gui.setInteractionText(
		"",
		sm.gui.getKeyBinding("Use", true),
		PC_L.get("wing_toggle_mode")
	)
	return true
end

local function wing_clientInteract(self, _, state)
	if state then
		self.network:sendToServer("sv_toggleStall")
	end
end

local function wing_serverDestroy(self)
	removeWingFromStallRegistry(self)
end

-- All current wing variants use this script. Assigning the common callbacks
-- here keeps the aerodynamic implementation shared while giving every
-- individual wing element its own saved stall mode.
local wingClasses = {
	Wing1x1, Wing2x2, Wing3x3, Wing4x4,
	WingWedge1x1, WingWedge1x2, WingWedge1x3, WingWedge1x4,
	WingWedge1x5, WingWedge1x6, WingWedge1x7, WingWedge1x8,
	WingWedge1x9, WingWedge1x10
}

for _, wingClass in ipairs(wingClasses) do
	wingClass.server_onCreate = wing_serverInitialize
	wingClass.server_onRefresh = wing_serverInitialize
	wingClass.server_onDestroy = wing_serverDestroy
	wingClass.sv_toggleStall = wing_serverToggleStall
	wingClass.client_onCreate = wing_clientCreate
	wingClass.client_onClientDataUpdate = wing_clientDataUpdate
	wingClass.cl_showStallNotification = wing_clientShowStallNotification
	wingClass.client_canInteract = wing_clientCanInteract
	wingClass.client_onInteract = wing_clientInteract
end
