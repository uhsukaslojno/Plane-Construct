dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
dofile("$SURVIVAL_DATA/Scripts/util.lua")

PlaneConstructDopplerEngine = class()
PlaneConstructDopplerEngine.maxParentCount = 2
PlaneConstructDopplerEngine.maxChildCount = 255
PlaneConstructDopplerEngine.connectionInput = sm.interactable.connectionType.logic + sm.interactable.connectionType.power
PlaneConstructDopplerEngine.connectionOutput = sm.interactable.connectionType.bearing
PlaneConstructDopplerEngine.poseWeightCount = 1
PlaneConstructDopplerEngine.colorNormal = sm.color.new(0x808080ff)
PlaneConstructDopplerEngine.colorHighlight = sm.color.new(0xa0a0a0ff)

local ENGINE_LEVELS = {
    [1] = { power = 150, bearings = 2, effect = "PlaneConstruct - Gas Engine Level 1" },
    [2] = { power = 390, bearings = 4, effect = "PlaneConstruct - Gas Engine Level 2" },
    [3] = { power = 1020, bearings = 6, effect = "PlaneConstruct - Gas Engine Level 3" },
    [4] = { power = 2670, bearings = 8, effect = "PlaneConstruct - Gas Engine Level 4" },
    [5] = { power = 6990, bearings = 10, effect = "PlaneConstruct - Gas Engine Level 5" }
}

local MAX_LEVEL = 5
local MAX_DOPPLER_SPEED = 50.0
local RAD_PER_SECOND_100_KMH = 74.074074

local function clamp(value, minimum, maximum)
    return math.min(math.max(value, minimum), maximum)
end

local function clampInteger(value, minimum, maximum)
    return math.floor(clamp(tonumber(value) or minimum, minimum, maximum) + 0.5)
end

local function getLevel(level)
    return ENGINE_LEVELS[clampInteger(level, 1, MAX_LEVEL)]
end

local function getEngineInputs(self)
    local active = true
    local direction = 1.0

    local powerParent = nil
    local logicParent = nil
    for _, parent in ipairs(self.interactable:getParents()) do
        if not powerParent and parent:hasOutputType(sm.interactable.connectionType.power) then
            powerParent = parent
        end
        if not logicParent and parent:hasOutputType(sm.interactable.connectionType.logic) then
            logicParent = parent
        end
    end

    if powerParent then
        active = powerParent:isActive()
        direction = clamp(tonumber(powerParent:getPower()) or 0.0, -1.0, 1.0)
        if logicParent then
            active = active and logicParent:isActive()
        end
    elseif logicParent then
        active = logicParent:isActive()
        direction = active and 1.0 or 0.0
    end

    if not active then direction = 0.0 end
    return active, clamp(direction, -1.0, 1.0)
end

function PlaneConstructDopplerEngine.server_sendState(self)
    self.network:setClientData({
        engineLevel = self.engineLevel,
        enginePower = self.enginePower,
        effectPower = self.effectPower
    })
end

function PlaneConstructDopplerEngine.server_onCreate(self)
    local saved = self.storage:load() or {}
    self.engineLevel = clampInteger(saved.engineLevel, 1, MAX_LEVEL)
    self.enginePower = clamp(tonumber(saved.enginePower) or 1.0, 0.0, 1.0)
    self.effectPower = clamp(tonumber(saved.effectPower) or 0.0, 0.0, 1.0)
    self.motorPower = 0.0
    self.serverActive = false
    self:server_sendState()
end

function PlaneConstructDopplerEngine.server_onRefresh(self)
    self:server_onCreate()
end

function PlaneConstructDopplerEngine.server_saveSettings(self)
    self.storage:save({
        engineLevel = self.engineLevel,
        enginePower = self.enginePower,
        effectPower = self.effectPower
    })
    self:server_sendState()
end

function PlaneConstructDopplerEngine.server_setEngineLevel(self, level)
    self.engineLevel = clampInteger(level, 1, MAX_LEVEL)
    self:server_saveSettings()
end

function PlaneConstructDopplerEngine.server_setEnginePower(self, power)
    self.enginePower = clamp(tonumber(power) or self.enginePower, 0.0, 1.0)
    self:server_saveSettings()
end

function PlaneConstructDopplerEngine.server_setEffectPower(self, power)
    self.effectPower = clamp(tonumber(power) or self.effectPower, 0.0, 1.0)
    self:server_saveSettings()
end

function PlaneConstructDopplerEngine.server_onFixedUpdate(self, timeStep)
    local active, direction = getEngineInputs(self)
    local level = getLevel(self.engineLevel)
    local bearings = GetBearingEnabledJoints(self.interactable)
    local canDrive = active and math.abs(direction) > 0.001 and self.enginePower > 0.001 and #bearings > 0
    local targetPower = canDrive and 1.0 or 0.0

    self.motorPower = self.motorPower + clamp(targetPower - self.motorPower, -timeStep * 6.0, timeStep * 6.0)
    self.motorPower = clamp(self.motorPower, 0.0, 1.0)

    local motorVelocity = 0.0
    local motorImpulse = 0.0
    if canDrive then
        motorVelocity = direction * RAD_PER_SECOND_100_KMH * self.enginePower
        motorImpulse = self.motorPower * self.enginePower * level.power
    end

    for _, bearing in ipairs(bearings) do
        bearing:setMotorVelocity(motorVelocity, motorImpulse)
    end

    local isActive = canDrive and self.motorPower > 0.01
    if self.serverActive ~= isActive then
        self.serverActive = isActive
        self.interactable:setActive(isActive)
        self.interactable:setPublicData({ isActive = isActive })
    end
end

function PlaneConstructDopplerEngine.client_onCreate(self)
    self.clientEngineLevel = 1
    self.clientEnginePower = 1.0
    self.clientEffectPower = 0.0
    self.engineEffect = nil
    self.gui = nil
end

function PlaneConstructDopplerEngine.client_onClientDataUpdate(self, data)
    local oldLevel = self.clientEngineLevel
    self.clientEngineLevel = clampInteger(data.engineLevel, 1, MAX_LEVEL)
    self.clientEnginePower = clamp(tonumber(data.enginePower) or self.clientEnginePower, 0.0, 1.0)
    self.clientEffectPower = clamp(tonumber(data.effectPower) or self.clientEffectPower, 0.0, 1.0)

    if oldLevel ~= self.clientEngineLevel then
        self:client_recreateEffect()
    end
    self:client_updateGui()
end

function PlaneConstructDopplerEngine.client_recreateEffect(self)
    if self.engineEffect then
        self.engineEffect:destroy()
        self.engineEffect = nil
    end
    self.engineEffect = sm.effect.createEffect(getLevel(self.clientEngineLevel).effect, self.interactable)
    self.engineEffect:setParameter("rpm", 0.0)
    self.engineEffect:setParameter("load", 0.5)
end

function PlaneConstructDopplerEngine.client_onDestroy(self)
    if self.engineEffect then
        self.engineEffect:destroy()
        self.engineEffect = nil
    end
    if self.gui then
        local oldGui = self.gui
        self.gui = nil
        oldGui:close()
        oldGui:destroy()
    end
end

function PlaneConstructDopplerEngine.client_canInteract(self, character)
    local key = sm.gui.getKeyBinding("Use", true)
    sm.gui.setInteractionText("", key, PC_L.get("open_doppler_engine"))
    return true
end

function PlaneConstructDopplerEngine.client_onInteract(self, character, state)
    if not state then return end

    if self.gui then
        local oldGui = self.gui
        self.gui = nil
        oldGui:close()
        oldGui:destroy()
    end

    self.gui = sm.gui.createGuiFromLayout(PC_L.layout("PlaneConstructDopplerEngine.layout"), false, { backgroundAlpha = 0.5, hidesHotbar = true })
    self.gui:createHorizontalSlider("PowerSlider", 101, math.floor(self.clientEnginePower * 100 + 0.5), "cl_onPowerSliderChanged")
    self.gui:createHorizontalSlider("EffectSlider", 101, math.floor(self.clientEffectPower * 100 + 0.5), "cl_onEffectSliderChanged")
    self.gui:setButtonCallback("LevelLeft", "cl_onLevelLeft")
    self.gui:setButtonCallback("LevelRight", "cl_onLevelRight")
    self.gui:setOnCloseCallback("cl_onGuiClosed")
    self.gui:open()
    self:client_updateGui()
end

function PlaneConstructDopplerEngine.client_updateGui(self)
    if not self.gui then return end
    local effectText = "Doppler effect: OFF"
    if self.clientEffectPower > 0.001 then
        effectText = string.format("Doppler effect: %d%%", math.floor(self.clientEffectPower * 100 + 0.5))
    end
    self.gui:setText("LevelValue", PC_L.get("engine_level", self.clientEngineLevel))
    self.gui:setText("PowerValue", PC_L.get("engine_power", math.floor(self.clientEnginePower * 100 + 0.5)))
    self.gui:setText("EffectValue", effectText)
    self.gui:setSliderPosition("PowerSlider", math.floor(self.clientEnginePower * 100 + 0.5))
    self.gui:setSliderPosition("EffectSlider", math.floor(self.clientEffectPower * 100 + 0.5))
end

function PlaneConstructDopplerEngine.cl_onLevelLeft(self)
    self:client_setLevel(self.clientEngineLevel - 1)
end

function PlaneConstructDopplerEngine.cl_onLevelRight(self)
    self:client_setLevel(self.clientEngineLevel + 1)
end

function PlaneConstructDopplerEngine.client_setLevel(self, level)
    self.clientEngineLevel = clampInteger(level, 1, MAX_LEVEL)
    self.network:sendToServer("server_setEngineLevel", self.clientEngineLevel)
    self:client_recreateEffect()
    self:client_updateGui()
end

function PlaneConstructDopplerEngine.cl_onPowerSliderChanged(self, position)
    self.clientEnginePower = clamp(position / 100.0, 0.0, 1.0)
    self.network:sendToServer("server_setEnginePower", self.clientEnginePower)
    self:client_updateGui()
end

function PlaneConstructDopplerEngine.cl_onEffectSliderChanged(self, position)
    self.clientEffectPower = clamp(position / 100.0, 0.0, 1.0)
    self.network:sendToServer("server_setEffectPower", self.clientEffectPower)
    self:client_updateGui()
end

function PlaneConstructDopplerEngine.cl_onGuiClosed(self)
    if self.gui then
        self.gui:destroy()
        self.gui = nil
    end
end

function PlaneConstructDopplerEngine.client_updateEffect(self)
    if not self.engineEffect then
        self:client_recreateEffect()
    end

    -- FMOD's spatial Doppler uses the velocity assigned to the effect instance.
    -- The effect is attached to the block, but the engine does not infer the
    -- moving body's velocity reliably, so pass it explicitly every frame.
    local sourceVelocity = self.shape.velocity or sm.vec3.new(0.0, 0.0, 0.0)
    self.engineEffect:setVelocity(sourceVelocity)

    local active, direction = getEngineInputs(self)
    local bearings = GetBearingEnabledJoints(self.interactable)
    local shouldPlay = self.clientEnginePower > 0.001 and active and math.abs(direction) > 0.001 and #bearings > 0

    if not shouldPlay then
        self.interactable:setPoseWeight(0, 0.0)
        if self.engineEffect:isPlaying() then
            self.engineEffect:setParameter("rpm", 0.0)
            self.engineEffect:setParameter("load", 0.5)
            self.engineEffect:stopBreakSustain()
        end
        return
    end

    if not self.engineEffect:isPlaying() or self.engineEffect:isBreakSustaining() then
        self.engineEffect:start()
    end
    local throttle = clamp(math.abs(direction) * self.clientEnginePower, 0.0, 1.0)
    self.interactable:setPoseWeight(0, throttle)

    local averageBearingVelocity = 0.0
    if #bearings > 0 then
        for _, bearing in ipairs(bearings) do
            averageBearingVelocity = averageBearingVelocity + math.abs(tonumber(bearing.angularVelocity) or 0.0)
        end
        averageBearingVelocity = averageBearingVelocity / #bearings
    end
    local rotationFraction = clamp(averageBearingVelocity / (RAD_PER_SECOND_100_KMH / 1.2), 0.0, 1.0)

    local radialSpeed = 0.0
    local player = sm.localPlayer.getPlayer()
    local listener = player and player.character or nil
    if listener and sm.exists(listener) then
        local sourceToListener = listener.worldPosition - self.shape.worldPosition
        local distance = sourceToListener:length()
        if distance > 0.001 then
            local listenerVelocity = listener.velocity or sm.vec3.new(0.0, 0.0, 0.0)
            radialSpeed = (sourceVelocity - listenerVelocity):dot(sourceToListener / distance)
        end
    end

    local doppler = clamp(radialSpeed / MAX_DOPPLER_SPEED, -1.0, 1.0) * self.clientEffectPower
    local rpm = clamp(0.08 + rotationFraction * 0.72 + throttle * 0.12 + doppler * 0.15, 0.0, 1.0)
    local load = clamp(0.50 + throttle * 0.25 + rotationFraction * 0.10 + math.abs(doppler) * 0.10, 0.0, 1.0)
    self.engineEffect:setParameter("rpm", rpm)
    self.engineEffect:setParameter("load", load)
end

function PlaneConstructDopplerEngine.client_onUpdate(self, dt)
    self:client_updateEffect()
end

function PlaneConstructDopplerEngine.client_getAvailableParentConnectionCount(self, connectionType)
    if bit.band(connectionType, bit.bor(sm.interactable.connectionType.logic, sm.interactable.connectionType.power)) ~= 0 then
        local used = #self.interactable:getParents(bit.bor(sm.interactable.connectionType.logic, sm.interactable.connectionType.power))
        return math.max(0, 2 - used)
    end
    return 0
end

function PlaneConstructDopplerEngine.client_getAvailableChildConnectionCount(self, connectionType)
    if connectionType ~= sm.interactable.connectionType.bearing then return 0 end
    local level = getLevel(self.clientEngineLevel)
    return math.max(0, level.bearings - #self.interactable:getChildren(sm.interactable.connectionType.bearing))
end
