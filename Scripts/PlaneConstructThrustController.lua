dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneConstructThrustController = class()

-- The controller owns one normalized throttle value in the range 0..1.
-- It is published through publicData so connected scripted blocks can read
-- it directly on the server without relying on setPower replication.
PlaneConstructThrustController.maxParentCount = 3
PlaneConstructThrustController.maxChildCount = -1
PlaneConstructThrustController.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.logic
PlaneConstructThrustController.connectionOutput = sm.interactable.connectionType.power
PlaneConstructThrustController.colorNormal = sm.color.new(0x2878d0ff)
PlaneConstructThrustController.colorHighlight = sm.color.new(0x55aaffff)

local THROTTLE_KEY = "plane_construct_throttle"
local THROTTLE_TIME = 1.5
local DEFAULT_DOUBLE_TAP_WINDOW = 0.35
local AFTERBODY_THRUSTER_UUIDS = {
    ["c81f2a4e-12d9-4ec6-8b33-1e61f230a401"] = true,
    ["c81f2a4e-12d9-4ec6-8b33-1e61f230a402"] = true
}

local WHITE_LOGIC_COLORS = {
    ["eeeeeeff"] = true, ["eeeeee"] = true,
    ["ffffffff"] = true, ["ddddddff"] = true,
    ["dddddd"] = true, ["ffffff"] = true
}

local BLACK_LOGIC_COLORS = {
    ["222222ff"] = true, ["222222"] = true,
    ["111111ff"] = true, ["111111"] = true,
    ["000000ff"] = true, ["000000"] = true
}

local function clamp(value, minimum, maximum)
    return math.min(math.max(value, minimum), maximum)
end

local function loadDoubleTapWindow(self)
    local stored = self.storage:load()
    if type(stored) ~= "table" then return DEFAULT_DOUBLE_TAP_WINDOW end
    return clamp(tonumber(stored.doubleTapWindow) or DEFAULT_DOUBLE_TAP_WINDOW, 0.0, 1.0)
end

local function normalizedColor(shape)
    if shape == nil then return "" end
    return string.gsub(string.lower(tostring(shape:getColor())), "^0x", "")
end

local function getLogicDirection(self)
    local direction = 0
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:isActive() then
            local color = normalizedColor(parent:getShape())
            if WHITE_LOGIC_COLORS[color] then
                direction = math.max(direction, 1)
            elseif BLACK_LOGIC_COLORS[color] then
                direction = math.min(direction, -1)
            end
        end
    end
    return direction
end

local function getSeatParent(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        local hasSeatOutput = parent:hasOutputType(sm.interactable.connectionType.seated)
        local hasRider = false
        pcall(function()
            hasRider = parent:getSeatCharacter() ~= nil
        end)
        if hasSeatOutput or hasRider then return parent end
    end
    return nil
end

local function getSeatDirection(seat)
    if seat == nil then return nil end
    local seatId = tostring(seat.id or seat:getId())
    local increase = _G[seatId .. "thrustIncrease"] == true
    local decrease = _G[seatId .. "thrustDecrease"] == true
    if increase == decrease then return 0 end
    return increase and 1 or -1
end

local function getSeatInputState(seat)
    if seat == nil then
        return { increase = false, decrease = false, id = nil }
    end
    local seatId = tostring(seat.id or seat:getId())
    return {
        increase = _G[seatId .. "thrustIncrease"] == true,
        decrease = _G[seatId .. "thrustDecrease"] == true,
        id = seatId
    }
end

local function getShapeUuid(interactable)
    local shape = interactable and interactable:getShape() or nil
    return shape and string.lower(tostring(shape.shapeUuid)) or ""
end

local function sendThrottleToThrusters(self, value)
    self.throttlePulse = (self.throttlePulse or 0) + 1
    local controllerId = tostring(self.interactable.id or self.interactable:getId())

    for _, child in ipairs(self.interactable:getChildren()) do
        if AFTERBODY_THRUSTER_UUIDS[getShapeUuid(child)] then
            -- Direct server-to-server data path. It deliberately bypasses
            -- analog wires, client replication and parent lookups.
            local data = child:getPublicData()
            if type(data) ~= "table" then data = {} end
            data.plane_construct_throttle = value
            data.plane_construct_controller_id = controllerId
            data.plane_construct_throttle_pulse = self.throttlePulse
            child:setPublicData(data)
        end
    end
end

local function publishThrottle(self)
    local value = clamp(tonumber(self.throttle) or 0.0, 0.0, 1.0)
    self.interactable:setPublicData({
        [THROTTLE_KEY] = value,
        throttle = value,
        power = value
    })
    self.interactable:setPower(value)
    self.interactable:setActive(value > 0.001)
    sendThrottleToThrusters(self, value)
end

function PlaneConstructThrustController.server_onCreate(self)
    self.throttle = 0.0
    self.doubleTapWindow = loadDoubleTapWindow(self)
    self.inputClock = 0.0
    self.previousSeatId = nil
    self.previousIncrease = false
    self.previousDecrease = false
    self.lastIncreaseTap = nil
    self.lastDecreaseTap = nil
    self.lastSentThrottle = nil
    publishThrottle(self)
    self:sv_sendState(true)
end

function PlaneConstructThrustController.server_onRefresh(self)
    self:server_onCreate()
end

function PlaneConstructThrustController.sv_sendState(self, force)
    if force or self.lastSentThrottle == nil
        or math.abs(self.lastSentThrottle - self.throttle) >= 0.001 then
        self.lastSentThrottle = self.throttle
        self.network:setClientData({
            throttle = self.throttle,
            doubleTapWindow = self.doubleTapWindow
        })
    end
end

function PlaneConstructThrustController.sv_setDoubleTapWindow(self, requestedWindow)
    self.doubleTapWindow = clamp(tonumber(requestedWindow) or self.doubleTapWindow, 0.0, 1.0)
    self.storage:save({ doubleTapWindow = self.doubleTapWindow })
    self:sv_sendState(true)
end

function PlaneConstructThrustController.server_onFixedUpdate(self, timeStep)
    local deltaTime = tonumber(timeStep) or 0.025
    self.inputClock = self.inputClock + deltaTime

    local seat = getSeatParent(self)
    local input = getSeatInputState(seat)
    if input.id ~= self.previousSeatId then
        self.previousSeatId = input.id
        self.previousIncrease = false
        self.previousDecrease = false
        self.lastIncreaseTap = nil
        self.lastDecreaseTap = nil
    end

    if input.increase and not self.previousIncrease then
        if self.lastIncreaseTap ~= nil
            and self.inputClock - self.lastIncreaseTap <= self.doubleTapWindow then
            self.throttle = 1.0
            self.lastIncreaseTap = nil
        else
            self.lastIncreaseTap = self.inputClock
        end
    end
    if input.decrease and not self.previousDecrease then
        if self.lastDecreaseTap ~= nil
            and self.inputClock - self.lastDecreaseTap <= self.doubleTapWindow then
            self.throttle = 0.0
            self.lastDecreaseTap = nil
        else
            self.lastDecreaseTap = self.inputClock
        end
    end

    self.previousIncrease = input.increase
    self.previousDecrease = input.decrease

    local direction = getSeatDirection(seat)
    if direction == nil or direction == 0 then
        direction = getLogicDirection(self)
    end

    self.throttle = clamp(
        self.throttle + direction * deltaTime / THROTTLE_TIME,
        0.0,
        1.0
    )
    publishThrottle(self)
    self:sv_sendState(false)
end

function PlaneConstructThrustController.server_onDestroy(self)
    -- The interactable is already being destroyed; do not call setPower on it.
end

function PlaneConstructThrustController.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("thrust_controller"))
    return true
end

function PlaneConstructThrustController.client_onCreate(self)
    self.cl = { throttle = 0.0, doubleTapWindow = DEFAULT_DOUBLE_TAP_WINDOW, gui = nil }
end

function PlaneConstructThrustController.client_onClientDataUpdate(self, data)
    if self.cl == nil then self:client_onCreate() end
    self.cl.throttle = clamp(tonumber(data.throttle) or 0.0, 0.0, 1.0)
    self.cl.doubleTapWindow = clamp(tonumber(data.doubleTapWindow) or DEFAULT_DOUBLE_TAP_WINDOW, 0.0, 1.0)
    self:cl_refreshGui()
end

function PlaneConstructThrustController.client_onInteract(self, _, state)
    if not state then return end
    if self.cl == nil then self:client_onCreate() end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructThrustController.layout"),
        false,
        { backgroundAlpha = 0.5, hidesHotbar = true }
    )
    self.cl.gui:createHorizontalSlider(
        "DoubleTapSlider",
        101,
        math.floor(self.cl.doubleTapWindow * 100.0 + 0.5),
        "cl_onDoubleTapSliderChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneConstructThrustController.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText(
        "ThrottleValue",
        PC_L.get("current_thrust", math.floor(self.cl.throttle * 100 + 0.5))
    )
    self.cl.gui:setText(
        "DoubleTapValue",
        PC_L.get("double_tap_window", self.cl.doubleTapWindow)
    )
    self.cl.gui:setSliderPosition(
        "DoubleTapSlider",
        math.floor(self.cl.doubleTapWindow * 100.0 + 0.5)
    )
end

function PlaneConstructThrustController.cl_onDoubleTapSliderChanged(self, position)
    self.cl.doubleTapWindow = clamp((tonumber(position) or 0) / 100.0, 0.0, 1.0)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDoubleTapWindow", self.cl.doubleTapWindow)
end

function PlaneConstructThrustController.cl_onGuiClosed(self)
    if self.cl and self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneConstructThrustController.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
