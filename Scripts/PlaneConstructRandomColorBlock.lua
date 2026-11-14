dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneConstructRandomColorBlock = class(nil)

PlaneConstructRandomColorBlock.maxParentCount = -1
PlaneConstructRandomColorBlock.maxChildCount = 0
PlaneConstructRandomColorBlock.connectionInput = sm.interactable.connectionType.logic
PlaneConstructRandomColorBlock.connectionOutput = sm.interactable.connectionType.none
PlaneConstructRandomColorBlock.colorNormal = sm.color.new(0x6b4fd6ff)
PlaneConstructRandomColorBlock.colorHighlight = sm.color.new(0x9d83ffff)

local TICKS_PER_SECOND = 40
local MIN_INTERVAL_TICKS = 0
local MAX_INTERVAL_TICKS = 10 * TICKS_PER_SECOND
local DEFAULT_INTERVAL_TICKS = TICKS_PER_SECOND
local SLIDER_POSITIONS = MAX_INTERVAL_TICKS - MIN_INTERVAL_TICKS + 1

local function clampInteger(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor((tonumber(value) or minimum) + 0.5)))
end

local function getRandomColor()
    -- Keep the colors bright enough to remain visible on the block.
    local red = math.random(40, 255)
    local green = math.random(40, 255)
    local blue = math.random(40, 255)
    return sm.color.new(red * 0x1000000 + green * 0x10000 + blue * 0x100 + 0xff)
end

local function isLogicInputActive(interactable)
    for _, parent in ipairs(interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:isActive() then
            return true
        end
    end
    return false
end

function PlaneConstructRandomColorBlock.server_onCreate(self)
    self:sv_initialize()
end

function PlaneConstructRandomColorBlock.server_onRefresh(self)
    self:sv_initialize()
end

function PlaneConstructRandomColorBlock.sv_initialize(self)
    local stored = self.storage:load()
    local storedInterval = type(stored) == "table" and stored.intervalTicks or nil
    local intervalTicks = clampInteger(
        storedInterval or DEFAULT_INTERVAL_TICKS,
        MIN_INTERVAL_TICKS,
        MAX_INTERVAL_TICKS
    )

    self.sv = {
        intervalTicks = intervalTicks,
        timerTicks = 0,
        wasInputActive = false
    }

    self.storage:save({ intervalTicks = intervalTicks })
    self.network:setClientData({ intervalTicks = intervalTicks })
end

function PlaneConstructRandomColorBlock.sv_setIntervalTicks(self, requestedInterval)
    if self.sv == nil then return end

    local intervalTicks = clampInteger(
        requestedInterval,
        MIN_INTERVAL_TICKS,
        MAX_INTERVAL_TICKS
    )
    if intervalTicks == self.sv.intervalTicks then return end

    self.sv.intervalTicks = intervalTicks
    self.sv.timerTicks = 0
    self.storage:save({ intervalTicks = intervalTicks })
    self.network:setClientData({ intervalTicks = intervalTicks })
end

function PlaneConstructRandomColorBlock.sv_changeColor(self)
    self.shape:setColor(getRandomColor())
end

function PlaneConstructRandomColorBlock.server_onFixedUpdate(self, _)
    local inputActive = isLogicInputActive(self.interactable)
    if not inputActive then
        self.sv.timerTicks = 0
        self.sv.wasInputActive = false
        return
    end

    if not self.sv.wasInputActive then
        self:sv_changeColor()
        self.sv.timerTicks = 0
    elseif self.sv.intervalTicks == 0 then
        self:sv_changeColor()
    else
        self.sv.timerTicks = self.sv.timerTicks + 1
        if self.sv.timerTicks >= self.sv.intervalTicks then
            self:sv_changeColor()
            self.sv.timerTicks = 0
        end
    end

    self.sv.wasInputActive = true
end

function PlaneConstructRandomColorBlock.client_onCreate(self)
    self.cl = {
        intervalTicks = DEFAULT_INTERVAL_TICKS,
        gui = nil
    }
end

function PlaneConstructRandomColorBlock.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self:client_onCreate()
    end
    self.cl.intervalTicks = clampInteger(
        data.intervalTicks,
        MIN_INTERVAL_TICKS,
        MAX_INTERVAL_TICKS
    )
    self:cl_refreshGui()
end

function PlaneConstructRandomColorBlock.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneConstructRandomColorBlock.client_canInteract(self)
    sm.gui.setInteractionText(
        "",
        sm.gui.getKeyBinding("Use", true),
        PC_L.get("configure_random_color")
    )
    return true
end

function PlaneConstructRandomColorBlock.client_onInteract(self, _, state)
    if not state then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructRandomColorBlock.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "IntervalSlider",
        SLIDER_POSITIONS,
        self.cl.intervalTicks - MIN_INTERVAL_TICKS,
        "cl_onIntervalSliderChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneConstructRandomColorBlock.cl_onIntervalSliderChanged(self, position)
    self.cl.intervalTicks = clampInteger(
        position + MIN_INTERVAL_TICKS,
        MIN_INTERVAL_TICKS,
        MAX_INTERVAL_TICKS
    )
    self:cl_refreshGui()
    self.network:sendToServer("sv_setIntervalTicks", self.cl.intervalTicks)
end

function PlaneConstructRandomColorBlock.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end

    if self.cl.intervalTicks == 0 then
        self.cl.gui:setText("IntervalValue", PC_L.get("random_color_fast"))
    else
        self.cl.gui:setText(
            "IntervalValue",
            PC_L.get("random_color_interval", string.format("%.2f s", self.cl.intervalTicks / TICKS_PER_SECOND))
        )
    end
end

function PlaneConstructRandomColorBlock.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
