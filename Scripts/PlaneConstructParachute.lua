--[[
Made by DasEtwas
All rights reserved
]]--

dofile("airfoil.lua")

sleepTime = 5
chuteAirDensity = 2.25
chuteMaxAcc = 12 --m/s
maxAngVel = 0.7 -- rad/s
minTiltForceFactor = 0.08 -- retain a small stabilizing force near vertical
speedForceReference = 200 -- m/s; softer reduction at higher speed
minSpeedForceFactor = 0.05 -- never completely disable the parachute

-- gets local pos from relative global-space pos
function getLocal(shape, vec)
	return sm.vec3.new(sm.shape.getRight(shape):dot(vec), sm.shape.getAt(shape):dot(vec), sm.shape.getUp(shape):dot(vec))
end

function getGlobal(shape, vec)
	return sm.shape.getRight(shape) * vec.x + sm.shape.getAt(shape) * vec.y + sm.shape.getUp(shape) * vec.z
end

PlaneConstructParachute = class(nil)
PlaneConstructParachute.active = false
PlaneConstructParachute.maxChildCount = 0
PlaneConstructParachute.maxParentCount = 1 --in
PlaneConstructParachute.connectionInput = sm.interactable.connectionType.logic
PlaneConstructParachute.connectionOutput = sm.interactable.connectionType.none
PlaneConstructParachute.colorNormal = sm.color.new( 0xCC0600ff )
PlaneConstructParachute.colorHighlight = sm.color.new( 0xEF3C39ff )
PlaneConstructParachute.poseWeightCount = 2
PlaneConstructParachute.area = 28 -- 28m²
PlaneConstructParachute.size = 7 -- extended radius
PlaneConstructParachute.driftCoef = 0.15
PlaneConstructParachute.dragCoef = 1.0
PlaneConstructParachute.deployTime = 1.25
PlaneConstructParachute.activeCounter = 0
PlaneConstructParachute.minDeploy = 0.3
PlaneConstructParachute.windCoef = 0.15
PlaneConstructParachute.pos = PlaneConstructParachute.minDeploy * PlaneConstructParachute.size
PlaneConstructParachute.sleep = movementSleep
PlaneConstructParachute.closeAnimPos = nil
PlaneConstructParachute.poseWeight1 = 0
PlaneConstructParachute.poseWeight2 = 0
PlaneConstructParachute.angVelFac = 1.0

function PlaneConstructParachute.server_onFixedUpdate(self, dt)
	if self.interactable:getSingleParent() then
		if self.interactable:getSingleParent():isActive() and (not self.active) then
			self.active = true
			self.activeCounter = 0
		end
	else
		self.active = false
	end
	
	self.pos = math.max(self.size * self.minDeploy, math.min(self.size, self.pos)) -- clamp
	
	if self.active then 
		if self.activeCounter < self.deployTime then
			self.activeCounter = self.activeCounter + dt
			
			if self.activeCounter > self.deployTime / 2 then				
				local deployPos = math.min((self.activeCounter - self.deployTime / 2) / self.deployTime * 2, 1) * self.minDeploy
				self.poseWeight1 = (1 - deployPos)
				self.poseWeight2 = (deployPos)
			else
				self.poseWeight1 = math.min(self.activeCounter / self.deployTime * 2, 1)
				self.closeAnimPos = nil
			end
		end
	else
		if self.activeCounter > 0 then
			self.activeCounter = math.min(self.deployTime, self.activeCounter) - dt
			
			if self.activeCounter > self.deployTime / 2 then
				if not self.closeAnimPos then self.closeAnimPos = self.pos / self.size end
				
				local deployPos = math.min((self.activeCounter - self.deployTime / 2) / self.deployTime * 2, 1) * self.closeAnimPos
				self.poseWeight2 = deployPos
				self.poseWeight1 = 1 - deployPos
			else
				self.poseWeight2 = 0
				self.poseWeight1 = math.min(self.activeCounter / self.deployTime * 2, 1)
				self.closeAnimPos = nil
			end
			
			self.pos = 0
		end
	end
	
	if self.active and self.activeCounter >= self.deployTime then
		local currentPos = self.shape.worldPosition + sm.shape.getUp(self.shape):normalize() * self.pos
	
		local angvel = self.shape:getBody():getAngularVelocity()
		local len1 = angvel:length()
		if len1 ~= 0 then
			angvel = angvel / len1 * math.min(len1, maxAngVel)
		end
		sm.vec3.setZ(angvel, 0)
		
		local bodyMass = self.shape:getBody():getMass()
		local angVelFac = self.angVelFac
		local globalVel = sm.shape.getVelocity(self.shape) + angvel:cross(sm.shape.getUp(self.shape):normalize() * self.pos) * angVelFac
		local globalVelL = globalVel:length()
		
		local up = sm.shape.getUp(self.shape)
			local at = sm.shape.getAt(self.shape)
			local right = sm.shape.getRight(self.shape)
			
			local extendMult = math.pow(self.pos / self.size, 1.5) / (self.size / (self.size - 0.1)) + 0.1

			local upVel = globalVel:dot(up)
			local atVel = globalVel:dot(at)
			local rightVel = globalVel:dot(right)

			local upVel2 = upVel * math.abs(upVel)
			local atVel2 = atVel * math.abs(atVel)
			local rightVel2 = rightVel * math.abs(rightVel)
			local chuteForce = sm.vec3.new(0, 0, 0)
			local fac1 = extendMult * self.area * chuteAirDensity * 0.5
			chuteForce = chuteForce + at * fac1 * atVel2 * self.driftCoef
			chuteForce = chuteForce + right * fac1 * rightVel2 * self.driftCoef
			chuteForce = chuteForce - up * math.min(0, fac1 * upVel2 * self.dragCoef)

			-- Near the vertical position the original full force over-corrects
			-- small errors and causes the seat to oscillate. Scale the existing
			-- force by the canopy's angle from world vertical: a small residual
			-- force remains near vertical, reaching the original force at 90 deg.
			local verticalDot = math.max(-1, math.min(1, up.z))
			local tiltAngle = math.acos(verticalDot) / (math.pi * 0.5)
			local tiltForceFactor = minTiltForceFactor +
				(math.min(1, tiltAngle) * (1 - minTiltForceFactor))

			-- Reduce the relative influence at higher speed without cancelling
			-- the quadratic growth of the actual drag force. An inverse-square
			-- factor made the total force almost constant, allowing gravity to
			-- win and look like a timed parachute failure.
			local speedRatio = globalVelL / speedForceReference
			local speedForceFactor = 1 / (1 + speedRatio)
			speedForceFactor = math.max(minSpeedForceFactor, speedForceFactor)
			chuteForce = chuteForce * tiltForceFactor * speedForceFactor
			
			self.pos = math.max(self.size * self.minDeploy, math.min(self.size, self.pos - globalVel:dot(sm.shape.getUp(self.shape)) * dt * self.windCoef - sm.shape.getUp(self.shape).z * 0.35 * dt))
			self.poseWeight2 = self.pos / self.size
			self.poseWeight1 = 1 - self.pos / self.size
			
			chuteForce = chuteForce * dt
			
			local chuteForceL = chuteForce:length()

			-- chuteForce is an impulse after multiplication by dt. The original
			-- Wings limiter used chuteMaxAcc / bodyMass here, which made the
			-- impulse almost zero for any real creation once the cap was reached.
			-- Limit it to the intended maximum acceleration instead.
			-- Very light ejection-seat bodies otherwise receive an imperceptible
			-- impulse, so use a small minimum effective mass for this limiter only.
			local effectiveMass = math.max(bodyMass, 1.0)
			local maxImpulse = chuteMaxAcc * effectiveMass * dt
			if chuteForceL > maxImpulse and chuteForceL > 0 then
				chuteForce = chuteForce * (maxImpulse / chuteForceL)
			end

		local offset = self.shape.worldPosition - currentPos
		sm.physics.applyTorque(self.shape:getBody(), offset:cross(chuteForce) * 0.8, true)
		sm.physics.applyImpulse(self.shape, chuteForce, true, nil)
	end
	
	self.client_anims = {[0] = self.poseWeight1, [1] = self.poseWeight2}
	self.network:sendToClients("client_syncAnim", self.client_anims)
end

function PlaneConstructParachute.client_syncAnim(self, client_anims)
	self.client_anims = client_anims
end

function PlaneConstructParachute.client_onUpdate(self, dt)
	if self.client_anims then
		self.interactable:setPoseWeight(0, self.client_anims[0])
		self.interactable:setPoseWeight(1, self.client_anims[1])
	end
end

function PlaneConstructParachute.server_repack(self)
	self.active = false
end

function PlaneConstructParachute.client_onInteract(self)
	if self.interactable:getSingleParent() then
		if not self.interactable:getSingleParent():isActive() then
			self.network:sendToServer("server_repack")
		end
	else
		self.network:sendToServer("server_repack")
	end
end

-- end of file --
