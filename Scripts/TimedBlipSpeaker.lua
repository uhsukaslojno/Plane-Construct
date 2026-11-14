dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
TimedBlipSpeaker = class()

TimedBlipSpeaker.maxParentCount = 1
TimedBlipSpeaker.maxChildCount = -1
TimedBlipSpeaker.connectionInput = sm.interactable.connectionType.logic
TimedBlipSpeaker.connectionOutput = sm.interactable.connectionType.logic
TimedBlipSpeaker.colorNormal = sm.color.new(0x0a5ebcff)
TimedBlipSpeaker.colorHighlight = sm.color.new(0x2d8de8ff)

local TICKS_PER_SECOND = 40
local MIN_DURATION_TICKS = 2
local MAX_DURATION_TICKS = 800
local DURATION_STEP_TICKS = 2
local DEFAULT_TIMING_TICKS = 40
local DEFAULT_ACTIVATION_TICKS = 10

local function clampInteger(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
end

local function clampDurationTicks(value)
    local clamped = clampInteger(value, MIN_DURATION_TICKS, MAX_DURATION_TICKS)
    return MIN_DURATION_TICKS + math.floor((clamped - MIN_DURATION_TICKS) / DURATION_STEP_TICKS) * DURATION_STEP_TICKS
end

local function isLogicInputActive(interactable)
    for _, parent in ipairs(interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:isActive() then return true end
    end
    return false
end

function TimedBlipSpeaker.server_onCreate(self)
    self:sv_initialize()
end

function TimedBlipSpeaker.server_onRefresh(self)
    self:sv_initialize()
end

function TimedBlipSpeaker.server_onDestroy(self)
    if self.sv and sm.exists(self.interactable) then
        self.interactable:setActive(false)
    end
end

function TimedBlipSpeaker.sv_initialize(self)
    local stored = self.storage:load()
    stored = type(stored) == "table" and stored or {}

    self.sv = {
        timingTicks = clampDurationTicks(tonumber(stored.timingTicks) or DEFAULT_TIMING_TICKS),
        activationTicks = clampDurationTicks(tonumber(stored.activationTicks) or DEFAULT_ACTIVATION_TICKS),
        cycleTicks = 0,
        activeTicks = 0,
        isActive = false
    }
    if self.sv.activationTicks > self.sv.timingTicks then
        self.sv.activationTicks = self.sv.timingTicks
    end

    self.interactable:setActive(false)
    self:sv_saveAndSync()
end

function TimedBlipSpeaker.sv_saveAndSync(self)
    self.storage:save({
        timingTicks = self.sv.timingTicks,
        activationTicks = self.sv.activationTicks
    })
    self.network:setClientData({
        timingTicks = self.sv.timingTicks,
        activationTicks = self.sv.activationTicks
    })
end

function TimedBlipSpeaker.sv_setActive(self, active)
    if self.sv.isActive == active then return end
    self.sv.isActive = active
    self.interactable:setActive(active)
end

function TimedBlipSpeaker.sv_setSetting(self, request)
    if type(request) ~= "table" or type(request.setting) ~= "string" then return end
    local value = tonumber(request.value)
    if value == nil then return end

    if request.setting == "timingTicks" then
        self.sv.timingTicks = clampDurationTicks(value)
        if self.sv.activationTicks > self.sv.timingTicks then
            self.sv.activationTicks = self.sv.timingTicks
        end
    elseif request.setting == "activationTicks" then
        self.sv.activationTicks = math.min(clampDurationTicks(value), self.sv.timingTicks)
    else
        return
    end

    self.sv.cycleTicks = 0
    self.sv.activeTicks = 0
    self:sv_setActive(false)
    self:sv_saveAndSync()
end

function TimedBlipSpeaker.server_onFixedUpdate(self, _)
    if not isLogicInputActive(self.interactable) then
        self.sv.cycleTicks = 0
        self.sv.activeTicks = 0
        self:sv_setActive(false)
        return
    end

    self.sv.cycleTicks = self.sv.cycleTicks + 1
    if self.sv.isActive then
        self.sv.activeTicks = self.sv.activeTicks + 1
        if self.sv.activeTicks >= self.sv.activationTicks then
            self:sv_setActive(false)
        end
    elseif self.sv.cycleTicks >= self.sv.timingTicks then
        self.sv.cycleTicks = 0
        self.sv.activeTicks = 0
        self:sv_setActive(true)
    end
end

function TimedBlipSpeaker.client_onCreate(self)
    self.cl = {
        timingTicks = DEFAULT_TIMING_TICKS,
        activationTicks = DEFAULT_ACTIVATION_TICKS,
        gui = nil
    }
end

function TimedBlipSpeaker.client_onClientDataUpdate(self, data)
    if self.cl == nil then return end
    self.cl.timingTicks = clampDurationTicks(tonumber(data.timingTicks) or DEFAULT_TIMING_TICKS)
    self.cl.activationTicks = math.min(clampDurationTicks(tonumber(data.activationTicks) or DEFAULT_ACTIVATION_TICKS), self.cl.timingTicks)
    self:cl_refreshGui()
end

function TimedBlipSpeaker.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end
end

function TimedBlipSpeaker.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_timed_gate"))
    return true
end

function TimedBlipSpeaker.client_onInteract(self, _, state)
    if not state then return end
    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("TimedBlipSpeaker.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider("TimingSlider", (MAX_DURATION_TICKS - MIN_DURATION_TICKS) / DURATION_STEP_TICKS + 1, (self.cl.timingTicks - MIN_DURATION_TICKS) / DURATION_STEP_TICKS, "cl_onTimingChanged")
    self.cl.gui:createHorizontalSlider("ActivationSlider", (MAX_DURATION_TICKS - MIN_DURATION_TICKS) / DURATION_STEP_TICKS + 1, (self.cl.activationTicks - MIN_DURATION_TICKS) / DURATION_STEP_TICKS, "cl_onActivationChanged")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function TimedBlipSpeaker.cl_sendSetting(self, setting, value)
    self.network:sendToServer("sv_setSetting", { setting = setting, value = value })
end

function TimedBlipSpeaker.cl_onTimingChanged(self, position)
    self.cl.timingTicks = clampDurationTicks(MIN_DURATION_TICKS + position * DURATION_STEP_TICKS)
    if self.cl.activationTicks > self.cl.timingTicks then
        self.cl.activationTicks = self.cl.timingTicks
    end
    self:cl_refreshGui()
    self:cl_sendSetting("timingTicks", self.cl.timingTicks)
end

function TimedBlipSpeaker.cl_onActivationChanged(self, position)
    self.cl.activationTicks = math.min(clampDurationTicks(MIN_DURATION_TICKS + position * DURATION_STEP_TICKS), self.cl.timingTicks)
    self:cl_refreshGui()
    self:cl_sendSetting("activationTicks", self.cl.activationTicks)
end

function TimedBlipSpeaker.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText("TimingValue", PC_L.get("timer_timing", self.cl.timingTicks / TICKS_PER_SECOND))
    self.cl.gui:setText("ActivationValue", PC_L.get("timer_activation", self.cl.activationTicks / TICKS_PER_SECOND))
end

function TimedBlipSpeaker.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
