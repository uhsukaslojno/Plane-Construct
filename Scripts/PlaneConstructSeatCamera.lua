PlaneConstructSeatCamera = class()
PlaneConstructSeatCamera.maxParentCount = -1
PlaneConstructSeatCamera.maxChildCount = -1
PlaneConstructSeatCamera.connectionInput = sm.interactable.connectionType.seated
	+ sm.interactable.connectionType.power
PlaneConstructSeatCamera.connectionOutput = sm.interactable.connectionType.logic
PlaneConstructSeatCamera.colorNormal = sm.color.new(0x777777ff)
PlaneConstructSeatCamera.colorHighlight = sm.color.new(0x888888ff)

function PlaneConstructSeatCamera.client_onCreate(self)
	self.active = false
end

function PlaneConstructSeatCamera.client_onUpdate(self, dt)
	if planeConstructSeatCameraId == self.interactable:getId() then
		if not sm.exists(self.sourceInteractable)
			or not self:hasConnectionToSource()
			or self.sourceInteractable:getSeatCharacter() == nil then
			self:client_unlockCamera()
		else
			sm.camera.setCameraState(sm.camera.state.cutsceneTP)
			sm.camera.setPosition(self.shape:getInterpolatedWorldPosition() + self.shape:getInterpolatedAt() * 0.1 + self.shape:getVelocity() * dt)
			sm.camera.setDirection(self.shape:getInterpolatedAt())
		end
	else
		self.active = false
	end
end

function PlaneConstructSeatCamera.hasConnectionToSource(self)
	if self.sourceInteractable then
		local parents = self.interactable:getParents()
		for i = 1, #parents, 1 do
			if parents[i]:getId() == self.sourceInteractable:getId() then
				return true
			end
		end
	end
	return false
end

function PlaneConstructSeatCamera.client_onInteract(self, char, on)
	if not on then return end

	local parents = self.interactable:getParents()
	for i = 1, #parents, 1 do
		if self:seatAction(parents[i], char) then
			self.sourceInteractable = parents[i]
			return
		end
	end
	self:client_unlockCamera()
	self.sourceInteractable = nil
end

function PlaneConstructSeatCamera.seatAction(self, interactable, char)
	if interactable:getSeatCharacter() == char then
		self.active = not self.active
		if self.active then
			planeConstructSeatCameraId = self.interactable:getId()
		else
			sm.camera.setCameraState(1)
			planeConstructSeatCameraId = nil
			self.sourceInteractable = nil
		end
		return true
	end
end

function PlaneConstructSeatCamera.client_scalarProduct(self, v1, v2)
	return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
end

function PlaneConstructSeatCamera.client_onRefresh(self)
	self:client_unlockCamera()
end

function PlaneConstructSeatCamera.client_onDestroy(self)
	self:client_unlockCamera()
end

function PlaneConstructSeatCamera.client_unlockCamera(self)
	if planeConstructSeatCameraId == self.interactable:getId() then
		sm.camera.setCameraState(1)
		planeConstructSeatCameraId = nil
	end
	self.active = false
	self.sourceInteractable = nil
end
