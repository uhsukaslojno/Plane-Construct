dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
RandomOutputGate = class()

RandomOutputGate.maxParentCount = -1
RandomOutputGate.maxChildCount = -1
RandomOutputGate.connectionInput = sm.interactable.connectionType.logic
RandomOutputGate.connectionOutput = sm.interactable.connectionType.logic
RandomOutputGate.colorNormal = sm.color.new(0x19e753ff)
RandomOutputGate.colorHighlight = sm.color.new(0x68ff88ff)

local DEFAULT_RATE_TICKS = 40
local MIN_RATE_TICKS = 0
local MAX_RATE_TICKS = 2400

local function clampInteger(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
end

local function isLogicInputActive(interactable)
    for _, parent in ipairs(interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:isActive() then
            return true
        end
    end
    return false
end

function RandomOutputGate.server_onCreate(self)
    self:sv_initialize()
end

function RandomOutputGate.server_onRefresh(self)
    -- A refresh can happen during a routed pulse. Restore its wiring before
    -- rebuilding transient state so no connection is left hidden.
    self:sv_finishPulse()
    self:sv_initialize()
end

function RandomOutputGate.server_onDestroy(self)
    self:sv_finishPulse()
end

function RandomOutputGate.sv_initialize(self)
    local stored = self.storage:load()
    local storedRate = type(stored) == "table" and tonumber(stored.rateTicks) or nil
    local rateTicks = clampInteger(storedRate or DEFAULT_RATE_TICKS, MIN_RATE_TICKS, MAX_RATE_TICKS)

    self.sv = {
        rateTicks = rateTicks,
        wasInputActive = false,
        heldTicks = 0,
        pulseActive = false,
        disconnectedChildren = nil
    }

    self.interactable:setActive(false)
    self.storage:save({ rateTicks = rateTicks })
    self:sv_syncClientData()
end

function RandomOutputGate.sv_syncClientData(self)
    self.network:setClientData({ rateTicks = self.sv.rateTicks })
end

function RandomOutputGate.sv_setRateTicks(self, requestedRate)
    local numericRate = tonumber(requestedRate)
    if numericRate == nil then return end

    local rateTicks = clampInteger(numericRate, MIN_RATE_TICKS, MAX_RATE_TICKS)
    if rateTicks == self.sv.rateTicks then return end

    self.sv.rateTicks = rateTicks
    self.sv.heldTicks = 0
    self.storage:save({ rateTicks = rateTicks })
    self:sv_syncClientData()
end

function RandomOutputGate.sv_finishPulse(self)
    if self.sv == nil then return end

    if self.sv.pulseActive then
        self.interactable:setActive(false)
        self.sv.pulseActive = false
    end

    if self.sv.disconnectedChildren ~= nil then
        for _, child in ipairs(self.sv.disconnectedChildren) do
            if sm.exists(child) then
                self.interactable:connect(child)
            end
        end
        self.sv.disconnectedChildren = nil
    end
end

function RandomOutputGate.sv_fireRandomOutput(self)
    local children = self.interactable:getChildren(sm.interactable.connectionType.logic)
    if #children == 0 then return end

    local selectedIndex = math.random(1, #children)
    local disconnected = {}

    -- A scripted interactable has one shared logic signal. Temporarily isolate
    -- the selected wire for the pulse, then restore every connection next tick.
    for index, child in ipairs(children) do
        if index ~= selectedIndex then
            if not self.interactable:disconnect(child) then
                for _, disconnectedChild in ipairs(disconnected) do
                    if sm.exists(disconnectedChild) then
                        self.interactable:connect(disconnectedChild)
                    end
                end
                return
            end
            disconnected[#disconnected + 1] = child
        end
    end

    self.sv.disconnectedChildren = disconnected
    self.interactable:setActive(true)
    self.sv.pulseActive = true
end

function RandomOutputGate.server_onFixedUpdate(self, _)
    self:sv_finishPulse()

    local inputActive = isLogicInputActive(self.interactable)
    local shouldFire = false

    if inputActive then
        if not self.sv.wasInputActive then
            -- Rising edges always fire immediately, independent of the slider.
            shouldFire = true
            self.sv.heldTicks = 0
        else
            self.sv.heldTicks = self.sv.heldTicks + 1
            if self.sv.rateTicks == 0 or self.sv.heldTicks >= self.sv.rateTicks then
                shouldFire = true
                self.sv.heldTicks = 0
            end
        end
    else
        self.sv.heldTicks = 0
    end

    self.sv.wasInputActive = inputActive

    if shouldFire then
        self:sv_fireRandomOutput()
    end
end

function RandomOutputGate.client_onCreate(self)
    self.cl = {
        rateTicks = DEFAULT_RATE_TICKS,
        gui = nil
    }
end

function RandomOutputGate.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self.cl = { rateTicks = DEFAULT_RATE_TICKS, gui = nil }
    end
    self.cl.rateTicks = clampInteger(tonumber(data.rateTicks) or DEFAULT_RATE_TICKS, MIN_RATE_TICKS, MAX_RATE_TICKS)
    self:cl_refreshGui()
end

function RandomOutputGate.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function RandomOutputGate.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_random_output"))
    return true
end

function RandomOutputGate.client_onInteract(self, _, state)
    if not state then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("RandomOutputGate.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "RateSlider",
        MAX_RATE_TICKS - MIN_RATE_TICKS + 1,
        self.cl.rateTicks - MIN_RATE_TICKS,
        "cl_onRateSliderChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function RandomOutputGate.cl_onRateSliderChanged(self, sliderPosition)
    self.cl.rateTicks = clampInteger(sliderPosition + MIN_RATE_TICKS, MIN_RATE_TICKS, MAX_RATE_TICKS)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setRateTicks", self.cl.rateTicks)
end

function RandomOutputGate.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end

    local seconds = self.cl.rateTicks / 40.0
    self.cl.gui:setText(
        "RateValue",
        PC_L.get("output_interval_full", self.cl.rateTicks, seconds)
    )
end

function RandomOutputGate.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
