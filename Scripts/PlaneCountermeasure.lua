dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneCountermeasure = class()

PlaneCountermeasure.maxParentCount = 1
PlaneCountermeasure.maxChildCount = -1
PlaneCountermeasure.connectionInput = sm.interactable.connectionType.logic
PlaneCountermeasure.connectionOutput = sm.interactable.connectionType.logic
PlaneCountermeasure.colorNormal = sm.color.new(0xff7a00ff)
PlaneCountermeasure.colorHighlight = sm.color.new(0xffc14dff)

local MODE_FLARE = "flare"
local MODE_CHAFF = "chaff"
local DEFAULT_MODE = MODE_FLARE
local DEFAULT_INTERVAL_TICKS = 60
local MIN_INTERVAL_TICKS = 10
local MAX_INTERVAL_TICKS = 200
local DEFAULT_LIMIT_ENABLED = false
local DEFAULT_CAPACITY = 100
local MIN_CAPACITY = 1
local MAX_CAPACITY = 1000
local PARTICLE_LIFETIME_TICKS = 320
local COUNTERMEASURE_EFFECT_REPEAT_TICKS = 2
local COUNTERMEASURE_EFFECT_KEEP_TICKS = 80
local DEPLOY_EJECTION_SPEED = 20.0
local VELOCITY_DAMPING = 0.95
local GRAVITY = sm.vec3.new(0, 0, -9.81)
local MAX_ID_SERIAL = 9999
local REGISTRY_NAME = "PlaneConstructPresenceTargets"
local DISPENSER_REGISTRY_PREFIX = "PlaneConstructCountermeasureDispenser:"
local EFFECT_NAMES = {
    [MODE_FLARE] = "PlaneCountermeasureFlareSilent",
    [MODE_CHAFF] = "PlaneCountermeasureChaff"
}
local DEPLOY_SOUND_EFFECT_NAME = "PlaneCountermeasureDeploySound"
local DEBRIS_EFFECT_NAME = "PlaneCountermeasureFlareSilent"

local function clampInteger(value, minimum, maximum)
    local numericValue = tonumber(value) or minimum
    return math.max(minimum, math.min(maximum, math.floor(numericValue + 0.5)))
end

local function getRegistry()
    if _G[REGISTRY_NAME] == nil then
        _G[REGISTRY_NAME] = {}
    end
    return _G[REGISTRY_NAME]
end

local function getDispenserRegistryKey(interactable)
    return DISPENSER_REGISTRY_PREFIX .. tostring(interactable:getId())
end

local function isLogicInputActive(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            return true
        end
    end
    return false
end

local function getTargetId(self, serial)
    return -(100000000 + self.interactable:getId() * 10000 + serial)
end

local function createEffectAtPosition(effectName, position)
    local effect = sm.effect.createEffect(effectName)
    effect:setPosition(position)
    effect:start()
    return effect
end

local function destroyEffect(effect)
    if effect == nil then return end
    if effect:isPlaying() then effect:stop() end
    effect:destroy()
end

local function destroyParticleEffects(particle)
    if particle == nil then return end
    if particle.effects ~= nil then
        for _, effectData in ipairs(particle.effects) do
            destroyEffect(effectData.effect)
        end
    else
        destroyEffect(particle.effect)
    end
end

function PlaneCountermeasure.server_onCreate(self)
    self:sv_initialize()
end

function PlaneCountermeasure.server_onRefresh(self)
    self:sv_removeAllParticles()
    self:sv_initialize()
end

function PlaneCountermeasure.server_onDestroy(self)
    self:sv_removeAllParticles()
    _G[getDispenserRegistryKey(self.interactable)] = nil
end

function PlaneCountermeasure.sv_initialize(self)
    local stored = self.storage:load()
    local mode = type(stored) == "table" and stored.mode or DEFAULT_MODE
    if mode ~= MODE_FLARE and mode ~= MODE_CHAFF then
        mode = DEFAULT_MODE
    end

    local storedInterval = type(stored) == "table" and tonumber(stored.intervalTicks) or nil
    local intervalTicks = clampInteger(
        storedInterval or DEFAULT_INTERVAL_TICKS,
        MIN_INTERVAL_TICKS,
        MAX_INTERVAL_TICKS
    )
    local limitEnabled = type(stored) == "table" and stored.limitEnabled == true or DEFAULT_LIMIT_ENABLED
    local capacity = clampInteger(
        type(stored) == "table" and tonumber(stored.capacity) or DEFAULT_CAPACITY,
        MIN_CAPACITY,
        MAX_CAPACITY
    )
    local remaining = clampInteger(
        type(stored) == "table" and tonumber(stored.remaining) or capacity,
        0,
        capacity
    )

    self.sv = {
        mode = mode,
        intervalTicks = intervalTicks,
        limitEnabled = limitEnabled,
        capacity = capacity,
        remaining = remaining,
        wasInputActive = false,
        intervalCounter = 0,
        nextSerial = 0,
        nextSequence = 0,
        particles = {}
    }

    self:sv_saveState()
    self:sv_syncClientData()
end

function PlaneCountermeasure.sv_saveState(self)
    self.storage:save({
        mode = self.sv.mode,
        intervalTicks = self.sv.intervalTicks,
        limitEnabled = self.sv.limitEnabled,
        capacity = self.sv.capacity,
        remaining = self.sv.remaining
    })
end

function PlaneCountermeasure.sv_syncClientData(self)
    self.network:setClientData({
        mode = self.sv.mode,
        intervalTicks = self.sv.intervalTicks,
        limitEnabled = self.sv.limitEnabled,
        capacity = self.sv.capacity,
        remaining = self.sv.remaining
    })
    self:sv_publishDispenserRegistry()
end

function PlaneCountermeasure.sv_setMode(self, requestedMode)
    if requestedMode ~= MODE_FLARE and requestedMode ~= MODE_CHAFF then return end
    if requestedMode == self.sv.mode then return end

    self.sv.mode = requestedMode
    self:sv_saveState()
    self:sv_syncClientData()
end

function PlaneCountermeasure.sv_setIntervalTicks(self, requestedInterval)
    local intervalTicks = clampInteger(requestedInterval, MIN_INTERVAL_TICKS, MAX_INTERVAL_TICKS)
    if intervalTicks == self.sv.intervalTicks then return end

    self.sv.intervalTicks = intervalTicks
    self.sv.intervalCounter = 0
    self:sv_saveState()
    self:sv_syncClientData()
end

function PlaneCountermeasure.sv_setLimitEnabled(self, requestedLimitEnabled)
    local limitEnabled = requestedLimitEnabled == true
    if limitEnabled == self.sv.limitEnabled then return end

    self.sv.limitEnabled = limitEnabled
    self.sv.remaining = self.sv.capacity
    self:sv_saveState()
    self:sv_syncClientData()
end

function PlaneCountermeasure.sv_setCapacity(self, requestedCapacity)
    local capacity = clampInteger(requestedCapacity, MIN_CAPACITY, MAX_CAPACITY)
    if capacity == self.sv.capacity and self.sv.remaining == capacity then return end

    self.sv.capacity = capacity
    self.sv.remaining = capacity
    self:sv_saveState()
    self:sv_syncClientData()
end

function PlaneCountermeasure.sv_reload(self)
    self.sv.remaining = self.sv.capacity
    self:sv_saveState()
    self:sv_syncClientData()
end

function PlaneCountermeasure.sv_removeParticle(self, targetId)
    self.sv.particles[targetId] = nil
    getRegistry()[targetId] = nil
end

function PlaneCountermeasure.sv_removeAllParticles(self)
    if self.sv == nil then return end
    local registry = getRegistry()
    for targetId in pairs(self.sv.particles or {}) do
        registry[targetId] = nil
    end
    self.sv.particles = {}
end

function PlaneCountermeasure.sv_publishDispenserRegistry(self)
    if self.sv == nil then return end

    _G[getDispenserRegistryKey(self.interactable)] = {
        mode = self.sv.mode,
        limitEnabled = self.sv.limitEnabled,
        capacity = self.sv.capacity,
        remaining = self.sv.remaining
    }
end

function PlaneCountermeasure.sv_publishRegistry(self)
    local registry = getRegistry()
    for targetId, particle in pairs(self.sv.particles) do
        registry[targetId] = {
            id = targetId,
            name = particle.mode == MODE_CHAFF and "Chaff" or "Flare",
            kind = particle.mode,
            countermeasure = true,
            active = true,
            position = particle.position,
            velocity = particle.velocity,
            spawnSequence = particle.spawnSequence
        }
    end
end

function PlaneCountermeasure.sv_deploy(self)
    if self.sv.limitEnabled and self.sv.remaining <= 0 then
        return false
    end

    self.sv.nextSerial = self.sv.nextSerial + 1
    if self.sv.nextSerial > MAX_ID_SERIAL then
        self.sv.nextSerial = 1
    end

    self.sv.nextSequence = self.sv.nextSequence + 1
    local targetId = getTargetId(self, self.sv.nextSerial)
    local direction = self.shape:getUp()
    local position = self.shape.worldPosition + direction * 0.65
    local velocity = self.shape:getVelocity() + direction * DEPLOY_EJECTION_SPEED
    local particle = {
        mode = self.sv.mode,
        position = position,
        velocity = velocity,
        ageTicks = 0,
        spawnSequence = self.sv.nextSequence
    }
    self.sv.particles[targetId] = particle
    if self.sv.limitEnabled then
        self.sv.remaining = math.max(self.sv.remaining - 1, 0)
        self:sv_saveState()
        self:sv_syncClientData()
    end
    self:sv_publishRegistry()
    self.network:sendToClients("client_spawnParticle", {
        id = targetId,
        mode = particle.mode,
        position = particle.position,
        velocity = particle.velocity,
        spawnSequence = particle.spawnSequence
    })
end

function PlaneCountermeasure.server_onFixedUpdate(self)
    for targetId, particle in pairs(self.sv.particles) do
        particle.ageTicks = particle.ageTicks + 1
        if particle.ageTicks > PARTICLE_LIFETIME_TICKS then
            self:sv_removeParticle(targetId)
        else
            particle.position = particle.position + particle.velocity * 0.025
            particle.velocity = (particle.velocity + GRAVITY * 0.025) * VELOCITY_DAMPING
        end
    end

    local inputActive = isLogicInputActive(self)
    if inputActive then
        if not self.sv.wasInputActive then
            self.sv.intervalCounter = 0
            self:sv_deploy()
        else
            self.sv.intervalCounter = self.sv.intervalCounter + 1
            if self.sv.intervalCounter >= self.sv.intervalTicks then
                self.sv.intervalCounter = 0
                self:sv_deploy()
            end
        end
    else
        self.sv.intervalCounter = 0
    end
    self.sv.wasInputActive = inputActive
    self:sv_publishRegistry()
end

function PlaneCountermeasure.client_onCreate(self)
    self.cl = {
        mode = DEFAULT_MODE,
        intervalTicks = DEFAULT_INTERVAL_TICKS,
        limitEnabled = DEFAULT_LIMIT_ENABLED,
        capacity = DEFAULT_CAPACITY,
        remaining = DEFAULT_CAPACITY,
        particles = {},
        deploymentSounds = {},
        gui = nil
    }
end

function PlaneCountermeasure.client_onClientDataUpdate(self, data)
    if self.cl == nil then self:client_onCreate() end
    self.cl.mode = data.mode == MODE_CHAFF and MODE_CHAFF or MODE_FLARE
    self.cl.intervalTicks = clampInteger(
        data.intervalTicks,
        MIN_INTERVAL_TICKS,
        MAX_INTERVAL_TICKS
    )
    self.cl.limitEnabled = data.limitEnabled == true
    self.cl.capacity = clampInteger(
        tonumber(data.capacity) or DEFAULT_CAPACITY,
        MIN_CAPACITY,
        MAX_CAPACITY
    )
    self.cl.remaining = clampInteger(
        tonumber(data.remaining) or self.cl.capacity,
        0,
        self.cl.capacity
    )
    self:cl_refreshGui()
end

function PlaneCountermeasure.client_spawnParticle(self, data)
    if self.cl == nil then self:client_onCreate() end
    local targetId = tonumber(data.id)
    if targetId == nil or data.position == nil then return end

    local existing = self.cl.particles[targetId]
    if existing ~= nil then
        destroyParticleEffects(existing)
    end

    local mode = data.mode == MODE_CHAFF and MODE_CHAFF or MODE_FLARE
    table.insert(self.cl.deploymentSounds, {
        effect = createEffectAtPosition(DEPLOY_SOUND_EFFECT_NAME, data.position),
        ageTicks = 0
    })
    local effects = {
        {
            effect = createEffectAtPosition(EFFECT_NAMES[mode], data.position),
            ageTicks = 0
        }
    }
    self.cl.particles[targetId] = {
        mode = mode,
        position = data.position,
        velocity = data.velocity or sm.vec3.zero(),
        ageTicks = 0,
        spawnSequence = tonumber(data.spawnSequence) or 0,
        effectCounter = 0,
        effects = effects
    }
end

function PlaneCountermeasure.cl_removeParticle(self, targetId)
    local particle = self.cl.particles[targetId]
    if particle == nil then return end
    destroyParticleEffects(particle)
    self.cl.particles[targetId] = nil
    getRegistry()[targetId] = nil
end

function PlaneCountermeasure.cl_publishRegistry(self)
    local registry = getRegistry()
    for targetId, particle in pairs(self.cl.particles) do
        registry[targetId] = {
            id = targetId,
            name = particle.mode == MODE_CHAFF and "Chaff" or "Flare",
            kind = particle.mode,
            countermeasure = true,
            active = true,
            position = particle.position,
            velocity = particle.velocity,
            spawnSequence = particle.spawnSequence
        }
    end
end

function PlaneCountermeasure.client_onFixedUpdate(self)
    if self.cl == nil then return end

    for index = #self.cl.deploymentSounds, 1, -1 do
        local soundData = self.cl.deploymentSounds[index]
        soundData.ageTicks = soundData.ageTicks + 1
        if soundData.ageTicks > COUNTERMEASURE_EFFECT_KEEP_TICKS then
            destroyEffect(soundData.effect)
            table.remove(self.cl.deploymentSounds, index)
        end
    end

    for targetId, particle in pairs(self.cl.particles) do
        particle.ageTicks = particle.ageTicks + 1
        if particle.ageTicks > PARTICLE_LIFETIME_TICKS then
            self:cl_removeParticle(targetId)
        else
            particle.position = particle.position + particle.velocity * 0.025
            particle.velocity = (particle.velocity + GRAVITY * 0.025) * VELOCITY_DAMPING

            for index = #particle.effects, 1, -1 do
                local effectData = particle.effects[index]
                effectData.ageTicks = effectData.ageTicks + 1
                if effectData.ageTicks > COUNTERMEASURE_EFFECT_KEEP_TICKS then
                    destroyEffect(effectData.effect)
                    table.remove(particle.effects, index)
                end
            end

            if particle.mode == MODE_FLARE or particle.mode == MODE_CHAFF then
                particle.effectCounter = particle.effectCounter + 1
                if particle.effectCounter >= COUNTERMEASURE_EFFECT_REPEAT_TICKS then
                    particle.effectCounter = 0
                    table.insert(particle.effects, {
                        effect = createEffectAtPosition(EFFECT_NAMES[particle.mode], particle.position),
                        ageTicks = 0
                    })
                end
            end
        end
    end
    self:cl_publishRegistry()
end

function PlaneCountermeasure.client_onDestroy(self)
    if self.cl == nil then return end
    local gui = self.cl.gui
    self.cl.gui = nil
    if gui then
        gui:close()
        gui:destroy()
    end
    for targetId, particle in pairs(self.cl.particles) do
        destroyParticleEffects(particle)
        getRegistry()[targetId] = nil
    end
    self.cl.particles = {}
    for _, soundData in ipairs(self.cl.deploymentSounds) do
        destroyEffect(soundData.effect)
    end
    self.cl.deploymentSounds = {}
end

function PlaneCountermeasure.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_countermeasures"))
    return true
end

function PlaneCountermeasure.cl_openGui(self)
    local oldGui = self.cl.gui
    self.cl.gui = nil
    if oldGui then
        oldGui:close()
        oldGui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneCountermeasure.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "IntervalSlider",
        MAX_INTERVAL_TICKS - MIN_INTERVAL_TICKS + 1,
        self.cl.intervalTicks - MIN_INTERVAL_TICKS,
        "cl_onIntervalSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "IntervalSliderUpper",
        MAX_INTERVAL_TICKS - MIN_INTERVAL_TICKS + 1,
        self.cl.intervalTicks - MIN_INTERVAL_TICKS,
        "cl_onIntervalSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "CapacitySlider",
        MAX_CAPACITY,
        self.cl.capacity - MIN_CAPACITY,
        "cl_onCapacitySliderChanged"
    )
    self.cl.gui:setButtonCallback("FlareButton", "cl_onFlarePressed")
    self.cl.gui:setButtonCallback("ChaffButton", "cl_onChaffPressed")
    self.cl.gui:setButtonCallback("LimitButton", "cl_onLimitPressed")
    self.cl.gui:setButtonCallback("ReloadButton", "cl_onReloadPressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneCountermeasure.client_onInteract(self, _, state)
    if not state then return end
    self:cl_openGui()
end

function PlaneCountermeasure.cl_onFlarePressed(self)
    self.cl.mode = MODE_FLARE
    self:cl_refreshGui()
    self.network:sendToServer("sv_setMode", MODE_FLARE)
end

function PlaneCountermeasure.cl_onChaffPressed(self)
    self.cl.mode = MODE_CHAFF
    self:cl_refreshGui()
    self.network:sendToServer("sv_setMode", MODE_CHAFF)
end

function PlaneCountermeasure.cl_onIntervalSliderChanged(self, sliderPosition)
    self.cl.intervalTicks = clampInteger(
        sliderPosition + MIN_INTERVAL_TICKS,
        MIN_INTERVAL_TICKS,
        MAX_INTERVAL_TICKS
    )
    self:cl_refreshGui()
    self.network:sendToServer("sv_setIntervalTicks", self.cl.intervalTicks)
end

function PlaneCountermeasure.cl_onLimitPressed(self)
    self.cl.limitEnabled = not self.cl.limitEnabled
    self.cl.remaining = self.cl.capacity
    self:cl_refreshGui()
    self.network:sendToServer("sv_setLimitEnabled", self.cl.limitEnabled)
end

function PlaneCountermeasure.cl_onCapacitySliderChanged(self, sliderPosition)
    self.cl.capacity = clampInteger(sliderPosition + MIN_CAPACITY, MIN_CAPACITY, MAX_CAPACITY)
    self.cl.remaining = self.cl.capacity
    self:cl_refreshGui()
    self.network:sendToServer("sv_setCapacity", self.cl.capacity)
end

function PlaneCountermeasure.cl_onReloadPressed(self)
    self.cl.remaining = self.cl.capacity
    self:cl_refreshGui()
    self.network:sendToServer("sv_reload")
end

function PlaneCountermeasure.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    local modeName = self.cl.mode == MODE_CHAFF and "Chaff" or "Flare"
    self.cl.gui:setText("ModeValue", PC_L.get("dispensing", modeName))
    local intervalText = PC_L.get("dispensing_interval", self.cl.intervalTicks, self.cl.intervalTicks / 40.0)
    self.cl.gui:setText("IntervalValue", intervalText)
    self.cl.gui:setText("IntervalValueUpper", intervalText)
    self.cl.gui:setSliderPosition(
        "IntervalSlider",
        self.cl.intervalTicks - MIN_INTERVAL_TICKS
    )
    self.cl.gui:setSliderPosition(
        "IntervalSliderUpper",
        self.cl.intervalTicks - MIN_INTERVAL_TICKS
    )
    self.cl.gui:setText(
        "CapacityValue",
        PC_L.get("countermeasures_left", self.cl.remaining, self.cl.capacity)
    )
    self.cl.gui:setSliderPosition(
        "CapacitySlider",
        self.cl.capacity - MIN_CAPACITY
    )
    self.cl.gui:setVisible("UnlimitedBackground", not self.cl.limitEnabled)
    self.cl.gui:setVisible("LimitedBackground", self.cl.limitEnabled)
    self.cl.gui:setVisible("IntervalBackgroundUpper", not self.cl.limitEnabled)
    self.cl.gui:setVisible("IntervalSliderUpper", not self.cl.limitEnabled)
    self.cl.gui:setVisible("IntervalValueUpper", not self.cl.limitEnabled)
    self.cl.gui:setVisible("IntervalBackground", self.cl.limitEnabled)
    self.cl.gui:setVisible("IntervalSlider", self.cl.limitEnabled)
    self.cl.gui:setVisible("IntervalValue", self.cl.limitEnabled)
    self.cl.gui:setVisible("CapacityBackground", self.cl.limitEnabled)
    self.cl.gui:setVisible("CapacitySlider", self.cl.limitEnabled)
    self.cl.gui:setVisible("HelpTextUpper", not self.cl.limitEnabled)
    self.cl.gui:setVisible("HelpText", self.cl.limitEnabled)
    self.cl.gui:setVisible("ReloadButton", self.cl.limitEnabled)
    self.cl.gui:setButtonState("FlareButton", self.cl.mode == MODE_FLARE)
    self.cl.gui:setButtonState("ChaffButton", self.cl.mode == MODE_CHAFF)
    self.cl.gui:setButtonState("LimitButton", self.cl.limitEnabled)
end

function PlaneCountermeasure.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
