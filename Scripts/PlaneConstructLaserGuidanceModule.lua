dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
-- Plane Construct laser receiver.
-- This block never raycasts and never calculates an angle. It reads the point
-- published by a matching emitter and exposes that point to a controller.

if PlaneConstructLaserBus == nil then PlaneConstructLaserBus = {} end
if PlaneConstructLaserGuidanceTargets == nil then PlaneConstructLaserGuidanceTargets = {} end

PlaneConstructLaserGuidanceModule = class()
PlaneConstructLaserGuidanceModule.maxParentCount = 4
PlaneConstructLaserGuidanceModule.maxChildCount = -1
PlaneConstructLaserGuidanceModule.connectionInput = sm.interactable.connectionType.logic
PlaneConstructLaserGuidanceModule.connectionOutput = sm.interactable.connectionType.logic
PlaneConstructLaserGuidanceModule.colorNormal = sm.color.new(0x79d9ffff)
PlaneConstructLaserGuidanceModule.colorHighlight = sm.color.new(0xb8efffff)

local DEFAULT_CODE = "0"
local DEFAULT_PASSWORD = "0"
local MAX_CODE_LENGTH = 24
local MAX_PASSWORD_LENGTH = 32
local TURRET_CONTROLLER_UUID = "de73f113-3f2c-4c35-9c7f-cb5efe394b17"
local PLANE_CONTROLLER_UUID = "e4ad98f3-f9c7-48f9-bd2a-da16f9da8ee9"

local function cleanValue(value, fallback, maximumLength)
    value = tostring(value or ""):gsub("[^%w%-%_]", "")
    if value == "" then value = fallback end
    return string.sub(value, 1, maximumLength)
end

local function laserKey(code, password)
    return tostring(code) .. "\031" .. tostring(password)
end

local function isController(parent)
    local shape = parent:getShape()
    if shape == nil then return false end
    local uuid = tostring(sm.shape.getShapeUuid(shape))
    return uuid == TURRET_CONTROLLER_UUID or uuid == PLANE_CONTROLLER_UUID
end

local function clearTarget(self)
    PlaneConstructLaserGuidanceTargets[self.interactable:getId()] = nil
    self.interactable:setActive(false)
end

function PlaneConstructLaserGuidanceModule.sv_load(self)
    local stored = self.storage:load()
    self.sv = {
        code = cleanValue(type(stored) == "table" and stored.code or nil, DEFAULT_CODE, MAX_CODE_LENGTH),
        password = cleanValue(type(stored) == "table" and stored.password or nil, DEFAULT_PASSWORD, MAX_PASSWORD_LENGTH)
    }
    self.storage:save(self.sv)
    self.network:setClientData(self.sv)
end

function PlaneConstructLaserGuidanceModule.server_onCreate(self)
    self:sv_load()
end

function PlaneConstructLaserGuidanceModule.server_onRefresh(self)
    self:sv_load()
end

function PlaneConstructLaserGuidanceModule.server_onDestroy(self)
    clearTarget(self)
end

function PlaneConstructLaserGuidanceModule.sv_setCredentials(self, data)
    if type(data) ~= "table" then return end
    self.sv.code = cleanValue(data.code, DEFAULT_CODE, MAX_CODE_LENGTH)
    self.sv.password = cleanValue(data.password, DEFAULT_PASSWORD, MAX_PASSWORD_LENGTH)
    self.storage:save(self.sv)
    self.network:setClientData(self.sv)
end

function PlaneConstructLaserGuidanceModule.server_onFixedUpdate(self)
    local enabled = false
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        -- The controller connection carries the target output; it is not an
        -- activation signal. A separate switch/button must enable the module.
        if not isController(parent) and parent:isActive() then
            enabled = true
            break
        end
    end

    local spot = enabled and PlaneConstructLaserBus[laserKey(self.sv.code, self.sv.password)] or nil
    local point = spot ~= nil and spot.point or nil
    local active = point ~= nil

    PlaneConstructLaserGuidanceTargets[self.interactable:getId()] = {
        active = active,
        enabled = enabled,
        point = point,
        receiverPosition = self.shape:getWorldPosition(),
        -- The module is mounted at the front of the moving turret assembly.
        -- Its local Z axis is the optical/forward axis in Scrap Mechanic.
        receiverDirection = self.shape:getUp(),
        emitterId = spot and spot.emitterId or nil,
        tick = spot and spot.tick or nil
    }
    self.interactable:setActive(active)
end

function PlaneConstructLaserGuidanceModule.client_onCreate(self)
    self.cl = { code = DEFAULT_CODE, password = DEFAULT_PASSWORD, gui = nil }
end

function PlaneConstructLaserGuidanceModule.client_onClientDataUpdate(self, data)
    if type(data) ~= "table" then return end
    self.cl.code = tostring(data.code or DEFAULT_CODE)
    self.cl.password = tostring(data.password or DEFAULT_PASSWORD)
    self:cl_refreshGui()
end

function PlaneConstructLaserGuidanceModule.client_canInteract(self)
    sm.gui.setInteractionText(
        "",
        sm.gui.getKeyBinding("Use", true),
        PC_L.get("configure_laser_guidance") .. " (" .. self.cl.code .. "/" .. self.cl.password .. ")"
    )
    return true
end

function PlaneConstructLaserGuidanceModule.client_onInteract(self, _, state)
    if not state then return end
    if self.cl.gui ~= nil then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end
    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructLaserGuidanceModule.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:setButtonCallback("SaveButton", "cl_save")
    self.cl.gui:setTextChangedCallback("CodeInput", "cl_codeChanged")
    self.cl.gui:setTextChangedCallback("PasswordInput", "cl_passwordChanged")
    self.cl.gui:setOnCloseCallback("cl_closed")
    self.cl.gui:open()
    self:cl_refreshGui()
end

function PlaneConstructLaserGuidanceModule.cl_codeChanged(self, _, text)
    self.cl.code = text
end

function PlaneConstructLaserGuidanceModule.cl_passwordChanged(self, _, text)
    self.cl.password = text
end

function PlaneConstructLaserGuidanceModule.cl_save(self)
    self.network:sendToServer("sv_setCredentials", {
        code = self.cl.code,
        password = self.cl.password
    })
    self:cl_closed()
end

function PlaneConstructLaserGuidanceModule.cl_refreshGui(self)
    if self.cl.gui == nil then return end
    self.cl.gui:setText("CodeInput", self.cl.code)
    self.cl.gui:setText("PasswordInput", self.cl.password)
end

function PlaneConstructLaserGuidanceModule.cl_closed(self)
    if self.cl.gui ~= nil then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
