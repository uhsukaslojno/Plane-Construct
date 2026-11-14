dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneConstructAfterbodyThruster = class()

-- The thrust controller writes throttle directly into this interactable's
-- public data on the server. This shape never reads parent power values.
PlaneConstructAfterbodyThruster.maxParentCount = -1
PlaneConstructAfterbodyThruster.maxChildCount = 0
PlaneConstructAfterbodyThruster.connectionInput = sm.interactable.connectionType.power + sm.interactable.connectionType.logic
PlaneConstructAfterbodyThruster.connectionOutput = sm.interactable.connectionType.none
PlaneConstructAfterbodyThruster.poseWeightCount = 2
PlaneConstructAfterbodyThruster.colorNormal = sm.color.new(0x909090ff)
PlaneConstructAfterbodyThruster.colorHighlight = sm.color.new(0xc0c0c0ff)

local DEFAULT_MAX_POWER = 1.0
local BASE_THRUST = 3500.0
local THRUST_DIRECTION = -1.0
local ACTIVE_THRESHOLD = 0.01
local LINK_TIMEOUT = 0.20
local FUEL_RATE_AT_FULL_AFTERBURNER = 5000.0 / 300.0

local function clamp(value, minimum, maximum)
    return math.min(math.max(value, minimum), maximum)
end

local function hasActiveLogicParent(self)
    local parents = self.interactable:getParents(sm.interactable.connectionType.logic) or {}
    for _, parent in ipairs(parents) do
        if parent:isActive() then return true end
    end
    return false
end

function PlaneConstructAfterbodyThruster.server_onCreate(self)
    local stored = self.storage:load()
    self.maxPower = clamp(
        type(stored) == "table" and tonumber(stored.maxPower) or DEFAULT_MAX_POWER,
        0.0,
        1.0
    )
    self.effectLevel = clamp(
        type(stored) == "table" and tonumber(stored.effectLevel) or 1,
        1,
        5
    )
    self.noAfterburner = type(stored) == "table" and stored.noAfterburner == true or false
    self.throttle = 0.0
    self.logicActive = false
    self.lastPulse = nil
    self.linkAge = LINK_TIMEOUT
    self.lastClientState = nil
    self:sv_sendState(true)
end

function PlaneConstructAfterbodyThruster.server_onRefresh(self)
    self:server_onCreate()
end

function PlaneConstructAfterbodyThruster.sv_setMaxPower(self, requestedPower)
    self.maxPower = clamp(tonumber(requestedPower) or self.maxPower, 0.0, 1.0)
    self.storage:save({
        maxPower = self.maxPower,
        effectLevel = self.effectLevel,
        noAfterburner = self.noAfterburner
    })
    self:sv_sendState(true)
end

function PlaneConstructAfterbodyThruster.sv_setEffectLevel(self, requestedLevel)
    self.effectLevel = math.floor(clamp(tonumber(requestedLevel) or self.effectLevel, 1, 5) + 0.5)
    self.storage:save({
        maxPower = self.maxPower,
        effectLevel = self.effectLevel,
        noAfterburner = self.noAfterburner
    })
    self:sv_sendState(true)
end

function PlaneConstructAfterbodyThruster.sv_setNoAfterburner(self, enabled)
    self.noAfterburner = enabled == true
    self.storage:save({
        maxPower = self.maxPower,
        effectLevel = self.effectLevel,
        noAfterburner = self.noAfterburner
    })
    self:sv_sendState(true)
end

function PlaneConstructAfterbodyThruster.sv_sendState(self, force)
    local active = self.logicActive
        and self.throttle > ACTIVE_THRESHOLD
        and self.maxPower > 0.0
    local state = {
        maxPower = self.maxPower,
        effectLevel = self.effectLevel,
        noAfterburner = self.noAfterburner,
        throttle = self.throttle,
        active = active,
        logicActive = self.logicActive == true
    }

    if force or self.lastClientState == nil
        or math.abs((self.lastClientState.maxPower or 0) - state.maxPower) >= 0.001
        or self.lastClientState.effectLevel ~= state.effectLevel
        or self.lastClientState.noAfterburner ~= state.noAfterburner
        or math.abs((self.lastClientState.throttle or 0) - state.throttle) >= 0.001
        or self.lastClientState.active ~= state.active
        or self.lastClientState.logicActive ~= state.logicActive then
        self.lastClientState = state
        self.network:setClientData(state)
    end
end

function PlaneConstructAfterbodyThruster.server_onFixedUpdate(self, timeStep)
    local data = self.interactable:getPublicData()
    local pulse = type(data) == "table" and tonumber(data.plane_construct_throttle_pulse) or nil

    if pulse ~= nil and pulse ~= self.lastPulse then
        self.lastPulse = pulse
        self.linkAge = 0.0
        self.throttle = clamp(tonumber(data.plane_construct_throttle) or 0.0, 0.0, 1.0)
    else
        self.linkAge = self.linkAge + (tonumber(timeStep) or 0.025)
        if self.linkAge >= LINK_TIMEOUT then
            self.throttle = 0.0
        end
    end

    self.logicActive = hasActiveLogicParent(self)
    local active = self.logicActive
        and self.throttle > ACTIVE_THRESHOLD
        and self.maxPower > 0.0
    local force = active and self.throttle * self.maxPower * BASE_THRUST * THRUST_DIRECTION or 0.0

    if force ~= 0.0 then
        sm.physics.applyImpulse(self.shape, sm.vec3.new(0, 0, force), false, nil)
    end

    local afterburnerActive = active
        and self.throttle > 0.90
        and not self.noAfterburner
    local fuelRate = 0.0
    if active then
        -- Normal full-throttle consumption is half of the five-minute rate;
        -- afterburner restores the full rate with its 2x multiplier.
        local normalRate = FUEL_RATE_AT_FULL_AFTERBURNER / 2.0
        fuelRate = self.maxPower * self.throttle * normalRate
        if afterburnerActive then fuelRate = fuelRate * 2.0 end
    end
    self.interactable:setPublicData({
        plane_construct_throttle = self.throttle,
        plane_construct_max_power = self.maxPower,
        plane_construct_fuel_demand = fuelRate,
        plane_construct_afterburner = afterburnerActive,
        plane_construct_logic_active = self.logicActive == true
    })

    self.interactable:setActive(active)
    self:sv_sendState(false)
end

function PlaneConstructAfterbodyThruster.client_onCreate(self)
    self.cl = {
        maxPower = DEFAULT_MAX_POWER,
        effectLevel = 1,
        throttle = 0.0,
        active = false,
        logicActive = false,
        noAfterburner = false,
        gui = nil,
        thrusterEffect = nil,
        thrusterSoundEffect = nil,
        thrusterSoundEffectName = nil
    }
    self:cl_createEffect()
end

function PlaneConstructAfterbodyThruster.client_onClientDataUpdate(self, data)
    if self.cl == nil then self:client_onCreate() end
    self.cl.maxPower = clamp(tonumber(data.maxPower) or DEFAULT_MAX_POWER, 0.0, 1.0)
    self.cl.effectLevel = math.floor(clamp(tonumber(data.effectLevel) or 1, 1, 5) + 0.5)
    self.cl.noAfterburner = data.noAfterburner == true
    self.cl.throttle = clamp(tonumber(data.throttle) or 0.0, 0.0, 1.0)
    self.cl.active = data.active == true
    self.cl.logicActive = data.logicActive == true
    self:cl_createEffect()
    self:cl_refreshGui()
end

function PlaneConstructAfterbodyThruster.client_onFixedUpdate(self, _)
    if self.cl == nil then return end
    self.interactable:setPoseWeight(0, self.cl.active and self.cl.throttle or 0.0)
    self.interactable:setPoseWeight(1, 0.0)

    local soundActive = self.cl.logicActive
    local flameActive = self.cl.active
        and self.cl.throttle > 0.90
        and not self.cl.noAfterburner
    local sourceVelocity = self.shape:getVelocity()
    if sourceVelocity == nil then
        sourceVelocity = self.shape.velocity
    end
    sourceVelocity = sourceVelocity or sm.vec3.new(0.0, 0.0, 0.0)
    local speed = math.min(sourceVelocity:length(), 200.0)

    if self.cl.thrusterEffect then
        self.cl.thrusterEffect:setVelocity(sourceVelocity)
        self.cl.thrusterEffect:setParameter("power", self.cl.throttle)
        self.cl.thrusterEffect:setParameter("velocity", speed)
        if flameActive then
            if not self.cl.thrusterEffect:isPlaying() then
                self.cl.thrusterEffect:start()
            end
        elseif self.cl.thrusterEffect:isPlaying() then
            self.cl.thrusterEffect:stop()
        end
    end

    if self.cl.thrusterSoundEffect then
        self.cl.thrusterSoundEffect:setVelocity(sourceVelocity)
        -- Both throttle and movement contribute to the rumble. Throttle is
        -- the primary source, while speed fills the remaining range so the
        -- sound also grows while the creation accelerates.
        local speedPower = clamp(speed / 200.0, 0.0, 1.0)
        local combinedPower = self.cl.throttle
            + speedPower * (1.0 - self.cl.throttle)
        -- Keep a quiet idle tone while the logic signal is on, even at 0%
        -- throttle and zero speed.
        local soundPower = math.max(clamp(combinedPower, 0.0, 1.0), 0.05)
        self.cl.thrusterSoundEffect:setParameter("power", soundPower)
        self.cl.thrusterSoundEffect:setParameter("velocity", speed)
        if soundActive then
            if not self.cl.thrusterSoundEffect:isPlaying() then
                self.cl.thrusterSoundEffect:start()
            end
        elseif self.cl.thrusterSoundEffect:isPlaying() then
            self.cl.thrusterSoundEffect:stop()
        end
    end
end

function PlaneConstructAfterbodyThruster.cl_createEffect(self)
    if self.cl == nil then return end
    local level = self.cl.effectLevel or 1
    local name = "Thruster - Level " .. tostring(level)
    local soundName = "PlaneConstruct - Thruster Sound " .. tostring(level)
    if self.cl.effectName == name
        and self.cl.thrusterEffect ~= nil
        and self.cl.thrusterSoundEffectName == soundName
        and self.cl.thrusterSoundEffect ~= nil then
        return
    end

    if self.cl.thrusterEffect then
        if self.cl.thrusterEffect:isPlaying() then self.cl.thrusterEffect:stop() end
        self.cl.thrusterEffect:destroy()
    end
    if self.cl.thrusterSoundEffect then
        if self.cl.thrusterSoundEffect:isPlaying() then self.cl.thrusterSoundEffect:stop() end
        self.cl.thrusterSoundEffect:destroy()
    end

    self.cl.effectName = name
    self.cl.thrusterEffect = sm.effect.createEffect(name, self.interactable)
    -- Vanilla thruster effects are authored half a metre from the host. The
    -- 2x2 afterbody already places its nozzle one block from the centre, so
    -- pull the effect back by one construction block onto the nozzle.
    self.cl.thrusterEffect:setOffsetPosition(sm.vec3.new(0.0, 0.0, -0.25))

    self.cl.thrusterSoundEffectName = soundName
    self.cl.thrusterSoundEffect = sm.effect.createEffect(soundName, self.interactable)
    self.cl.thrusterSoundEffect:setOffsetPosition(sm.vec3.new(0.0, 0.0, -0.25))
end

function PlaneConstructAfterbodyThruster.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_afterbody_thruster"))
    return true
end

function PlaneConstructAfterbodyThruster.client_onInteract(self, _, state)
    if not state then return end
    if self.cl == nil then self:client_onCreate() end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructAfterbodyThruster.layout"),
        false,
        { backgroundAlpha = 0.5, hidesHotbar = true }
    )
    self.cl.gui:createHorizontalSlider(
        "MaxPowerSlider",
        101,
        math.floor(self.cl.maxPower * 100 + 0.5),
        "cl_onMaxPowerSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "EffectLevelSlider",
        5,
        self.cl.effectLevel - 1,
        "cl_onEffectLevelSliderChanged"
    )
    self.cl.gui:setButtonCallback("NoAfterburnerButton", "cl_onNoAfterburnerPressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneConstructAfterbodyThruster.cl_onEffectLevelSliderChanged(self, position)
    self.cl.effectLevel = math.floor(clamp(tonumber(position) or 0, 0, 4) + 0.5) + 1
    self:cl_createEffect()
    self:cl_refreshGui()
    self.network:sendToServer("sv_setEffectLevel", self.cl.effectLevel)
end

function PlaneConstructAfterbodyThruster.cl_onMaxPowerSliderChanged(self, position)
    self.cl.maxPower = clamp(position / 100.0, 0.0, 1.0)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setMaxPower", self.cl.maxPower)
end

function PlaneConstructAfterbodyThruster.cl_onNoAfterburnerPressed(self)
    self.cl.noAfterburner = not self.cl.noAfterburner
    self:cl_refreshGui()
    self.network:sendToServer("sv_setNoAfterburner", self.cl.noAfterburner)
end

function PlaneConstructAfterbodyThruster.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    local position = math.floor(self.cl.maxPower * 100 + 0.5)
    self.cl.gui:setText("MaxPowerValue", PC_L.get("maximum_power", position))
    self.cl.gui:setSliderPosition("MaxPowerSlider", position)
    self.cl.gui:setText("EffectLevelValue", PC_L.get("effect_sound_level", self.cl.effectLevel))
    self.cl.gui:setSliderPosition("EffectLevelSlider", self.cl.effectLevel - 1)
    self.cl.gui:setButtonState("NoAfterburnerButton", self.cl.noAfterburner)
end

function PlaneConstructAfterbodyThruster.cl_onGuiClosed(self)
    if self.cl and self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneConstructAfterbodyThruster.client_onDestroy(self)
    if self.cl and self.cl.thrusterEffect then
        if self.cl.thrusterEffect:isPlaying() then self.cl.thrusterEffect:stop() end
        self.cl.thrusterEffect:destroy()
        self.cl.thrusterEffect = nil
    end
    if self.cl and self.cl.thrusterSoundEffect then
        if self.cl.thrusterSoundEffect:isPlaying() then self.cl.thrusterSoundEffect:stop() end
        self.cl.thrusterSoundEffect:destroy()
        self.cl.thrusterSoundEffect = nil
    end
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
