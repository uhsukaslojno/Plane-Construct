dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
-- Ordinary Driving Seat support for Plane Construct.
-- Includes seat input, bearing controls, and optional seat action playback.

dofile("$SURVIVAL_DATA/Scripts/game/survival_constants.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_shapes.lua")
dofile("$SURVIVAL_DATA/Scripts/game/survival_units.lua")
dofile("$SURVIVAL_DATA/Scripts/util.lua")
dofile("ModPaths.lua")


PlaneConstructOrdinaryDrivingSeat = class()
PlaneConstructOrdinaryDrivingSeat.maxChildCount = -1
PlaneConstructOrdinaryDrivingSeat.connectionOutput = sm.interactable.connectionType.seated + sm.interactable.connectionType.power + sm.interactable.connectionType.bearing
PlaneConstructOrdinaryDrivingSeat.colorNormal = sm.color.new( 0x80ff00ff )
PlaneConstructOrdinaryDrivingSeat.colorHighlight = sm.color.new( 0xb4ff68ff )
local SpeedPerStep = 1 / math.rad( 27 ) / 3

-- 操作编辑器集成：开始
function PlaneConstructOrdinaryDrivingSeat.server_onCreate( self )
	AESeat.onSeatCreate( self )
end
-- 操作编辑器集成：结束

function PlaneConstructOrdinaryDrivingSeat.server_onFixedUpdate( self )
	if not self.interactable then return end
	local ID = self.interactable.id
	
	local currentActive = self.interactable:getSeatCharacter() ~= nil
	self.interactable:setActive(currentActive)

	if self.clearScrollUp then
		_G[ID.."scrollUp"] = false
		self.clearScrollUp = false
	end	
	if _G[ID.."scrollUp"] then
		self.clearScrollUp = true
	end

	if self.clearScrollDown then
		_G[ID.."scrollDown"] = false
		self.clearScrollDown = false
	end	
	if _G[ID.."scrollDown"] then
		self.clearScrollDown = true
	end

	if self.interactable:isActive() then
		self.interactable:setPower( self.interactable:getSteeringPower() )
	else
		self.interactable:setPower( 0 )
		-- 无人时清除转向标志。异常离座时客户端不会补发松开消息，残留的方向与逻辑电平在此清除
		self.interactable:setSteeringFlag( 0 )
		_G[ID.."space"] = false
		_G[ID.."thrustIncrease"] = false
		_G[ID.."thrustDecrease"] = false
		_G[ID.."leftClick"] = false
		_G[ID.."rightClick"] = false
	end

	-- 操作编辑器集成：开始
	AESeat.applyToSeat( self )
	-- 操作编辑器集成：结束
end

function PlaneConstructOrdinaryDrivingSeat.sv_setGlobalFlag( self, props, player )
	if not self.interactable then return end
	-- 只接受当前乘员的调用。按住按键离座时，松开消息可能在下一位乘员入座后才送达
	local rider = self.interactable:getSeatCharacter()
	if not rider or rider:getPlayer() ~= player then return end
	_G[self.interactable.id..props.key] = props.state
end
function PlaneConstructOrdinaryDrivingSeat.server_onDestroy( self )
	if not self.interactable then return end
	local ID = self.interactable.id
	_G[ID.."space"] = nil
	_G[ID.."thrustIncrease"] = nil
	_G[ID.."thrustDecrease"] = nil
	_G[ID.."leftClick"] = nil
	_G[ID.."rightClick"] = nil
	_G[ID.."scrollUp"] = nil
	_G[ID.."scrollDown"] = nil

	-- 操作编辑器集成：开始
	AESeat.onSeatGone( self )
	-- 操作编辑器集成：结束
end

-- 操作编辑器集成：开始
-- 建造物离开加载范围时整体卸载，引擎不调用 server_onDestroy。全局逻辑键与共享区的
-- 登记、占用与通道均为会话级状态，在此清理
function PlaneConstructOrdinaryDrivingSeat.server_onUnload( self )
	self:server_onDestroy()
end
-- 操作编辑器集成：结束

-- 回复对象取网络回调附带的调用者，不采用载荷中自述的目标玩家
function PlaneConstructOrdinaryDrivingSeat.sv_getSeatInfo( self, data, player )
	local infoData = {}
	for i, interactable in pairs(self.interactable:getSeatInteractables()) do
		if i > 10 then break end
		local name = interactable:getType()
		if name == "lever" then
			name = "开关 Switch"
		elseif name == "button" then
			name = "按钮 Button"
		elseif name == "scripted" then
			local publicData = interactable:getPublicData()
			if publicData and publicData.name then
				name = publicData.name
			end
		end
		infoData[i] = name:upper()
	end
	self.network:sendToClient(player, "cl_openInfoGui", infoData)
end


function PlaneConstructOrdinaryDrivingSeat.client_onCreate( self )
	self.animWeight = 0.5
	if self.interactable:hasAnim("steering") then
		self.hasAnimation = true
		self.interactable:setAnimEnabled("steering", true)
	end

	self.cl = {}
	self.cl.updateDelay = 0.0
	self.cl.updateSettings = {}
	self.cl.seatedCharacter = nil
end

function PlaneConstructOrdinaryDrivingSeat.client_onDestroy( self )
	if self.gui then
		self.gui:destroy()
		self.gui = nil
	end
end

function PlaneConstructOrdinaryDrivingSeat.client_canInteract( self, character )
	local interactKey = sm.gui.getKeyBinding("Use", true)
	local tinkerKey = sm.gui.getKeyBinding("Tinker", true)
	sm.gui.setInteractionText("", interactKey, PC_L.get("seat_use"))
	sm.gui.setInteractionText("", tinkerKey, PC_L.get("seat_connections"))
	
	if character:getCharacterType() == unit_mechanic and not character:isTumbling() then
		return true
	end
	return false
end

-- when the player "tinkers" with the part (U)
function PlaneConstructOrdinaryDrivingSeat.client_onTinker( self, character, lookAt )
	if lookAt then
		self.network:sendToServer("sv_getSeatInfo")
	end
end

function PlaneConstructOrdinaryDrivingSeat.cl_openInfoGui( self, infoData )
	if not self.infoGui then self.infoGui = sm.gui.createGuiFromLayout(PC_L.layout('SeatInfo.layout')) end
	for i = 1, 10 do
		if infoData[i] then
			self.infoGui:setText("Con"..i, infoData[i])
		else
			self.infoGui:setText("Con"..i, "")
		end
	end
	self.infoGui:open()
end

-- when the player "uses" the part (E)
function PlaneConstructOrdinaryDrivingSeat.client_onInteract( self, character, lookAt )
	if lookAt then
		
		self:cl_seat()
		if self.shape.interactable:getSeatCharacter() ~= nil then
			sm.gui.displayAlertText( "#{ALERT_DRIVERS_SEAT_OCCUPIED}", 4.0 )
		elseif self.shape.body:isOnLift() and not self.shape.body:isOnVirtualLift() then
			sm.gui.displayAlertText( "#{ALERT_DRIVERS_SEAT_ON_LIFT}", 8.0 )
		end
	end
end

function PlaneConstructOrdinaryDrivingSeat.cl_seat( self )
	if sm.localPlayer.getPlayer() and sm.localPlayer.getPlayer():getCharacter() then
		self.interactable:setSeatCharacter( sm.localPlayer.getPlayer():getCharacter() )
	end
end

function PlaneConstructOrdinaryDrivingSeat.cl_checkForReSeat( self )
	for k,child in pairs(self.interactable:getChildren()) do
		local cUuid = tostring(sm.shape.getShapeUuid(child:getShape()))
		if cUuid == "8002aada-5494-11e6-beb8-9e71128cae77" then -- Seat ReExiter Teleporter
			self.reSeatTarget = child
			self.reSeatChar = sm.localPlayer.getPlayer():getCharacter()
		end
	end
end

function PlaneConstructOrdinaryDrivingSeat.client_onInteractThroughJoint( self, character, state, joint )
	self.cl.bearingGui = sm.gui.createSteeringBearingGui()
	self.cl.bearingGui:open()
	self.cl.bearingGui:setOnCloseCallback( "cl_onGuiClosed" )

	self.cl.currentJoint = joint

	self.cl.bearingGui:setSliderCallback("LeftAngle", "cl_onLeftAngleChanged")
	self.cl.bearingGui:setSliderData("LeftAngle", 120, self.interactable:getSteeringJointLeftAngleLimit( joint ) - 1 )

	self.cl.bearingGui:setSliderCallback("RightAngle", "cl_onRightAngleChanged")
	self.cl.bearingGui:setSliderData("RightAngle", 120, self.interactable:getSteeringJointRightAngleLimit( joint ) - 1 )

	local leftSpeedValue = self.interactable:getSteeringJointLeftAngleSpeed( joint ) / SpeedPerStep
	local rightSpeedValue = self.interactable:getSteeringJointRightAngleSpeed( joint ) / SpeedPerStep

	self.cl.bearingGui:setSliderCallback("LeftSpeed", "cl_onLeftSpeedChanged")
	self.cl.bearingGui:setSliderData("LeftSpeed", 10, leftSpeedValue - 1)

	self.cl.bearingGui:setSliderCallback("RightSpeed", "cl_onRightSpeedChanged")
	self.cl.bearingGui:setSliderData("RightSpeed", 10, rightSpeedValue - 1)

	local unlocked = self.interactable:getSteeringJointUnlocked( joint )

	if unlocked then
		self.cl.bearingGui:setButtonState( "Off", true )
	else
		self.cl.bearingGui:setButtonState( "On", true )
	end

	self.cl.bearingGui:setButtonCallback( "On", "cl_onLockButtonClicked" )
	self.cl.bearingGui:setButtonCallback( "Off", "cl_onLockButtonClicked" )

	--print("Character "..character:getId().." interacted with joint "..joint:getId())
end

function PlaneConstructOrdinaryDrivingSeat.client_onAction( self, controllerAction, state )
	local consumeAction = true
	  if state == true then
	    
		if controllerAction == sm.interactable.actions.forward then
			self.interactable:setSteeringFlag( sm.interactable.steering.forward )
			
		elseif controllerAction == sm.interactable.actions.backward then
			self.interactable:setSteeringFlag( sm.interactable.steering.backward )
		elseif controllerAction == sm.interactable.actions.left then
			self.interactable:setSteeringFlag( sm.interactable.steering.left )
		elseif controllerAction == sm.interactable.actions.right then
			self.interactable:setSteeringFlag( sm.interactable.steering.right )
		elseif controllerAction == sm.interactable.actions.sprint then
			self.interactable:setSteeringFlag( sm.interactable.steering.sprint )
			if self.thrustControl then
				self.network:sendToServer('sv_setGlobalFlag', { key = "thrustDecrease", state = true })
			end
		elseif controllerAction == sm.interactable.actions.use then
			self:cl_checkForReSeat()
			self:cl_seat()
		elseif controllerAction == sm.interactable.actions.jump then
			if self.thrustControl then
				self.network:sendToServer('sv_setGlobalFlag', { key = "thrustIncrease", state = true })
			elseif self.spaceLogic then
				self.network:sendToServer('sv_setGlobalFlag', { key = "space", state = true })
			else
				self:cl_checkForReSeat()
				self:cl_seat()
			end
		elseif controllerAction == sm.interactable.actions.item0 then
		        
			self.interactable:pressSeatInteractable( 0 )
		elseif controllerAction == sm.interactable.actions.item1 then
			self.interactable:pressSeatInteractable( 1 )
		elseif controllerAction == sm.interactable.actions.item2 then
			self.interactable:pressSeatInteractable( 2 )
		elseif controllerAction == sm.interactable.actions.item3 then
			self.interactable:pressSeatInteractable( 3 )
		elseif controllerAction == sm.interactable.actions.item4 then
			self.interactable:pressSeatInteractable( 4 )
		elseif controllerAction == sm.interactable.actions.item5 then
			self.interactable:pressSeatInteractable( 5 )
		elseif controllerAction == sm.interactable.actions.item6 then
			self.interactable:pressSeatInteractable( 6 )
		elseif controllerAction == sm.interactable.actions.item7 then
			self.interactable:pressSeatInteractable( 7 )
		elseif controllerAction == sm.interactable.actions.item8 then
			self.interactable:pressSeatInteractable( 8 )
		elseif controllerAction == sm.interactable.actions.item9 then
			self.interactable:pressSeatInteractable( 9 )
		elseif controllerAction == sm.interactable.actions.create then
			if self.leftClickLogic then
				self.network:sendToServer('sv_setGlobalFlag', { key = "leftClick", state = true })
			end
		elseif controllerAction == sm.interactable.actions.attack then
			if self.rightClickLogic then
				self.network:sendToServer('sv_setGlobalFlag', { key = "rightClick", state = true })
			end
		else
			
			consumeAction = false
		end
		
	else
		
		if controllerAction == sm.interactable.actions.forward then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.forward )
		elseif controllerAction == sm.interactable.actions.backward then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.backward )
		elseif controllerAction == sm.interactable.actions.left then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.left )
		elseif controllerAction == sm.interactable.actions.right then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.right )
		elseif controllerAction == sm.interactable.actions.sprint then
			self.interactable:unsetSteeringFlag( sm.interactable.steering.sprint )
			if self.thrustControl then
				self.network:sendToServer('sv_setGlobalFlag', { key = "thrustDecrease", state = false })
			end
		elseif controllerAction == sm.interactable.actions.jump then

			if self.thrustControl then
				self.network:sendToServer('sv_setGlobalFlag', { key = "thrustIncrease", state = false })
			elseif self.spaceLogic then
				self.network:sendToServer('sv_setGlobalFlag', { key = "space", state = false })
			end
		elseif controllerAction == sm.interactable.actions.item0 then
			self.interactable:releaseSeatInteractable( 0 )
		elseif controllerAction == sm.interactable.actions.item1 then
			self.interactable:releaseSeatInteractable( 1 )
		elseif controllerAction == sm.interactable.actions.item2 then
			self.interactable:releaseSeatInteractable( 2 )
		elseif controllerAction == sm.interactable.actions.item3 then
			self.interactable:releaseSeatInteractable( 3 )
		elseif controllerAction == sm.interactable.actions.item4 then
			self.interactable:releaseSeatInteractable( 4 )
		elseif controllerAction == sm.interactable.actions.item5 then
			self.interactable:releaseSeatInteractable( 5 )
		elseif controllerAction == sm.interactable.actions.item6 then
			self.interactable:releaseSeatInteractable( 6 )
		elseif controllerAction == sm.interactable.actions.item7 then
			self.interactable:releaseSeatInteractable( 7 )
		elseif controllerAction == sm.interactable.actions.item8 then
			self.interactable:releaseSeatInteractable( 8 )
		elseif controllerAction == sm.interactable.actions.item9 then
			self.interactable:releaseSeatInteractable( 9 )
		elseif controllerAction == sm.interactable.actions.create then
			if self.leftClickLogic then
				self.network:sendToServer('sv_setGlobalFlag', { key = "leftClick", state = false })
			end
		elseif controllerAction == sm.interactable.actions.attack then
			if self.rightClickLogic then	
				self.network:sendToServer('sv_setGlobalFlag', { key = "rightClick", state = false })
			end

		else
			
			consumeAction = false
			
		end
		 
	end
       
          
	-- 操作编辑器集成：开始
	local aeReleaseUse = AESeat.shouldReleaseUse( self, controllerAction )
	AESeat.onClientInput( self, controllerAction, state, consumeAction )
	if aeReleaseUse then return false end
	-- 操作编辑器集成：结束
	return consumeAction
end

function PlaneConstructOrdinaryDrivingSeat.client_onFixedUpdate( self, dt )
	if not self.interactable then return end

	if self.reSeatTarget then
		-- 先清空字段。目标在上一帧被拆除时下方会抛错
		local target, character = self.reSeatTarget, self.reSeatChar
		self.reSeatTarget = nil
		self.reSeatChar = nil
		if sm.exists( target ) then
			target:setSeatCharacter( character )
		end
	end
	
	local currentActive = self.interactable:isActive()
	if currentActive then
		self:cl_setLogicFlags()
	end
	self.prevActive = currentActive

	if self.cl.updateDelay > 0.0 then
		self.cl.updateDelay = math.max( 0.0, self.cl.updateDelay - dt )

		if self.cl.updateDelay == 0 then
			self:cl_applyBearingSettings()
			self.cl.updateSettings = {}
			self.cl.updateGuiCooldown = 0.2
		end
	else
		if self.cl.updateGuiCooldown then
			self.cl.updateGuiCooldown = self.cl.updateGuiCooldown - dt
			if self.cl.updateGuiCooldown <= 0 then
				self.cl.updateGuiCooldown = nil
			end
		end
		if not self.cl.updateGuiCooldown then
			self:cl_updateBearingGuiValues()
		end
	end
end

function PlaneConstructOrdinaryDrivingSeat.client_onUpdate( self, dt )
	if not self.interactable then return end

	-- Update gui upon character change in seat
	local seatedCharacter = self.interactable:getSeatCharacter()
	if self.cl.seatedCharacter ~= seatedCharacter then
		if seatedCharacter and seatedCharacter:getPlayer() and seatedCharacter:getPlayer():getId() == sm.localPlayer.getId() then
			self.gui = sm.gui.createSeatGui()
			self.gui:open()
		else
			if self.gui then
				self.gui:destroy()
				self.gui = nil
			end
		end
		self.cl.seatedCharacter = seatedCharacter
	end
	-- Update gui upon toolbar updates
	if self.gui then
		local interactables = self.interactable:getSeatInteractables()

		for i=1, 10 do
			local value = interactables[i]
			-- 连接类型为位掩码，座椅位可能与其他类型同时出现，按位取值
			if value and bit.band( value:getConnectionInputType(), sm.interactable.connectionType.seated ) ~= 0 then
				self.gui:setGridItem( "ButtonGrid", i-1, {
					["itemId"] = tostring(value:getShape():getShapeUuid()),
					["active"] = value:isActive()
				})
				
			else
				-- 清空一格的方式是把 itemId 填为全零。官方签名要求 table 类型
				self.gui:setGridItem( "ButtonGrid", i-1, {
					["itemId"] = tostring(sm.uuid.getNil()),
					["active"] = false
				})
			end
		end
		
	end

	local steeringAngle = self.interactable:getSteeringAngle();
	local angle = self.animWeight * 2.0 - 1.0 -- Convert anim weight 0,1 to angle -1,1

	if angle < steeringAngle then
		angle = min( angle + 4.2441*dt, steeringAngle )
	elseif angle > steeringAngle then
		angle = max( angle - 4.2441*dt, steeringAngle )
	end

	self.animWeight = angle * 0.5 + 0.5; -- Convert back to 0,1
	if self.hasAnimation then
		self.interactable:setAnimProgress("steering", self.animWeight)
	end
end

function PlaneConstructOrdinaryDrivingSeat.cl_onLeftAngleChanged( self, sliderName, sliderPos )
	self.cl.updateSettings.leftAngle = sliderPos + 1
	self.cl.updateDelay = 0.1
end

function PlaneConstructOrdinaryDrivingSeat.cl_onRightAngleChanged( self, sliderName, sliderPos )
	self.cl.updateSettings.rightAngle = sliderPos + 1
	self.cl.updateDelay = 0.1
end

function PlaneConstructOrdinaryDrivingSeat.cl_onLeftSpeedChanged( self, sliderName, sliderPos )
	self.cl.updateSettings.leftSpeed = ( sliderPos + 1 ) * SpeedPerStep
	self.cl.updateDelay = 0.1
end

function PlaneConstructOrdinaryDrivingSeat.cl_onRightSpeedChanged( self, sliderName, sliderPos )
	self.cl.updateSettings.rightSpeed = ( sliderPos + 1 ) * SpeedPerStep
	self.cl.updateDelay = 0.1
end

function PlaneConstructOrdinaryDrivingSeat.cl_onLockButtonClicked( self, buttonName )
	self.cl.updateSettings.unlocked = buttonName == "Off"
	self.cl.updateDelay = 0.1
end

function PlaneConstructOrdinaryDrivingSeat.cl_onGuiClosed( self )
	if self.cl.updateDelay > 0.0 then
		self:cl_applyBearingSettings()
		self.cl.updateSettings = {}
		self.cl.updateDelay = 0.0
		self.cl.currentJoint = nil
	end
	self.cl.bearingGui:destroy()
	self.cl.bearingGui = nil
end

function PlaneConstructOrdinaryDrivingSeat.cl_applyBearingSettings( self )

	assert( self.cl.currentJoint )

	if self.cl.updateSettings.leftAngle then
		self.interactable:setSteeringJointLeftAngleLimit( self.cl.currentJoint, self.cl.updateSettings.leftAngle )
	end

	if self.cl.updateSettings.rightAngle then
		self.interactable:setSteeringJointRightAngleLimit( self.cl.currentJoint, self.cl.updateSettings.rightAngle )
	end

	if self.cl.updateSettings.leftSpeed then
		self.interactable:setSteeringJointLeftAngleSpeed( self.cl.currentJoint, self.cl.updateSettings.leftSpeed )
	end

	if self.cl.updateSettings.rightSpeed then
		self.interactable:setSteeringJointRightAngleSpeed( self.cl.currentJoint, self.cl.updateSettings.rightSpeed )
	end

	if self.cl.updateSettings.unlocked ~= nil then
		self.interactable:setSteeringJointUnlocked( self.cl.currentJoint, self.cl.updateSettings.unlocked )
	end
end

function PlaneConstructOrdinaryDrivingSeat.cl_updateBearingGuiValues( self )
	if self.cl.bearingGui and self.cl.bearingGui:isActive() then

		local leftSpeed, rightSpeed, leftAngle, rightAngle, unlocked = self.interactable:getSteeringJointSettings( self.cl.currentJoint )

		if leftSpeed and rightSpeed and leftAngle and rightAngle and unlocked ~= nil then
			self.cl.bearingGui:setSliderPosition( "LeftAngle", leftAngle - 1 )
			self.cl.bearingGui:setSliderPosition( "RightAngle", rightAngle - 1 )
			self.cl.bearingGui:setSliderPosition( "LeftSpeed", ( leftSpeed / SpeedPerStep ) - 1 )
			self.cl.bearingGui:setSliderPosition( "RightSpeed", ( rightSpeed / SpeedPerStep ) - 1 )

			if unlocked then
				self.cl.bearingGui:setButtonState( "Off", true )
			else
				self.cl.bearingGui:setButtonState( "On", true )
			end
		end
	end
end

-- 接上对应的信号门后，座椅才转发该按键
local MouseLeftUuid = "8003aacf-5494-11e6-beb8-9e71128cae77"
local MouseRightUuid = "8004aacf-5494-11e6-beb8-9e71128cae77"
local ThrustControllerUuid = "c81f2a4e-12d9-4ec6-8b33-1e61f230a403"

function PlaneConstructOrdinaryDrivingSeat.cl_setLogicFlags( self )
	self.spaceLogic = false
	self.thrustControl = false
	self.leftClickLogic = false
	self.rightClickLogic = false
	self.scrollUpLogic = false
	self.scrollDownLogic = false
	for _, child in pairs(self.interactable:getChildren()) do
		local cUuid = tostring(sm.shape.getShapeUuid(child:getShape()))
		if cUuid == MouseLeftUuid then
			self.leftClickLogic = true
		elseif cUuid == MouseRightUuid then
			self.rightClickLogic = true
		elseif cUuid == ThrustControllerUuid then
			self.thrustControl = true
		end
	end
end

-- 操作编辑器集成：开始
-- 座椅侧只保留加载入口，桥接逻辑在操作编辑器目录中
dofile "$MOD_DATA/Scripts/ActionEditor/Core/Input.lua"
dofile "$MOD_DATA/Scripts/ActionEditor/Shared/Manager.lua"
dofile "$MOD_DATA/Scripts/ActionEditor/SeatIntegration.lua"

function PlaneConstructOrdinaryDrivingSeat.sv_aeInput( self, data, player )
	AESeat.serverReceiveInput( self, data, player )
end
-- 操作编辑器集成：结束
