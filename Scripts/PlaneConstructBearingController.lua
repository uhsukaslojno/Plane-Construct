dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneConstructBearingController = class()

PlaneConstructBearingController.maxParentCount = 1
PlaneConstructBearingController.maxChildCount = -1
PlaneConstructBearingController.connectionInput = sm.interactable.connectionType.logic
PlaneConstructBearingController.connectionOutput = sm.interactable.connectionType.bearing
PlaneConstructBearingController.colorNormal = sm.color.new(0x2aa876ff)
PlaneConstructBearingController.colorHighlight = sm.color.new(0x5de0adff)

local DEFAULT_SPEED_RPM = 1000
local MIN_SPEED_RPM = 0
local MAX_SPEED_RPM = 5000
local DEFAULT_FORCE = 1000
local MIN_FORCE = 0
local MAX_FORCE = 5000
local RPM_TO_RADIANS_PER_SECOND = (2.0 * math.pi) / 60.0

local function clampInteger(value, minimum, maximum, defaultValue)
    local numericValue = tonumber(value)
    if numericValue == nil then numericValue = defaultValue end
    return math.max(minimum, math.min(maximum, math.floor(numericValue + 0.5)))
end

local function isLogicActive(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic) or {}) do
        if parent:isActive() then
            return true
        end
    end
    return false
end

function PlaneConstructBearingController.server_onCreate(self)
    local stored = self.storage:load()
    self.speedRpm = clampInteger(
        type(stored) == "table" and stored.speedRpm or DEFAULT_SPEED_RPM,
        MIN_SPEED_RPM,
        MAX_SPEED_RPM,
        DEFAULT_SPEED_RPM
    )
    self.force = clampInteger(
        type(stored) == "table" and stored.force or DEFAULT_FORCE,
        MIN_FORCE,
        MAX_FORCE,
        DEFAULT_FORCE
    )
    self:sv_syncClientData()
end

function PlaneConstructBearingController.sv_save(self)
    self.storage:save({ speedRpm = self.speedRpm, force = self.force })
    self:sv_syncClientData()
end

function PlaneConstructBearingController.sv_setSpeedRpm(self, value)
    self.speedRpm = clampInteger(value, MIN_SPEED_RPM, MAX_SPEED_RPM, DEFAULT_SPEED_RPM)
    self:sv_save()
end

function PlaneConstructBearingController.sv_setForce(self, value)
    self.force = clampInteger(value, MIN_FORCE, MAX_FORCE, DEFAULT_FORCE)
    self:sv_save()
end

function PlaneConstructBearingController.sv_syncClientData(self)
    self.network:setClientData({ speedRpm = self.speedRpm, force = self.force })
end

function PlaneConstructBearingController.server_onFixedUpdate(self, _timeStep)
    local active = isLogicActive(self)
    local velocity = active and self.speedRpm * RPM_TO_RADIANS_PER_SECOND or 0.0
    local impulse = active and self.force or 0.0

    for _, bearing in ipairs(self.interactable:getBearings() or {}) do
        bearing:setMotorVelocity(velocity, impulse)
    end

    self.interactable:setActive(active)
end

function PlaneConstructBearingController.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("bearing_motor_controller"))
    return true
end

function PlaneConstructBearingController.client_onCreate(self)
    self.cl = {
        speedRpm = DEFAULT_SPEED_RPM,
        force = DEFAULT_FORCE,
        gui = nil
    }
end

function PlaneConstructBearingController.client_onClientDataUpdate(self, data)
    if self.cl == nil then self:client_onCreate() end
    self.cl.speedRpm = clampInteger(data.speedRpm, MIN_SPEED_RPM, MAX_SPEED_RPM, DEFAULT_SPEED_RPM)
    self.cl.force = clampInteger(data.force, MIN_FORCE, MAX_FORCE, DEFAULT_FORCE)
    self:cl_refreshGui()
end

function PlaneConstructBearingController.client_onInteract(self, _, state)
    if not state then return end
    if self.cl == nil then self:client_onCreate() end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructBearingController.layout"),
        false,
        { backgroundAlpha = 0.5, hidesHotbar = true }
    )
    self.cl.gui:createHorizontalSlider(
        "SpeedSlider",
        MAX_SPEED_RPM - MIN_SPEED_RPM + 1,
        self.cl.speedRpm - MIN_SPEED_RPM,
        "cl_onSpeedSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "ForceSlider",
        MAX_FORCE - MIN_FORCE + 1,
        self.cl.force - MIN_FORCE,
        "cl_onForceSliderChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneConstructBearingController.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText("SpeedValue", PC_L.get("bearing_speed", self.cl.speedRpm))
    self.cl.gui:setText("ForceValue", PC_L.get("bearing_force", self.cl.force))
    self.cl.gui:setSliderPosition("SpeedSlider", self.cl.speedRpm - MIN_SPEED_RPM)
    self.cl.gui:setSliderPosition("ForceSlider", self.cl.force - MIN_FORCE)
end

function PlaneConstructBearingController.cl_onSpeedSliderChanged(self, position)
    self.cl.speedRpm = clampInteger(position, MIN_SPEED_RPM, MAX_SPEED_RPM, DEFAULT_SPEED_RPM)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setSpeedRpm", self.cl.speedRpm)
end

function PlaneConstructBearingController.cl_onForceSliderChanged(self, position)
    self.cl.force = clampInteger(position, MIN_FORCE, MAX_FORCE, DEFAULT_FORCE)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setForce", self.cl.force)
end

function PlaneConstructBearingController.cl_onGuiClosed(self)
    if self.cl and self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneConstructBearingController.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
