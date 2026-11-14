dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
-- Plane Construct laser emitter.
-- The emitter is the only object that performs the raycast. It publishes one
-- world-space point to the server-wide laser bus.

if PlaneConstructLaserBus == nil then PlaneConstructLaserBus = {} end

PlaneConstructLaserEmitter = class()
PlaneConstructLaserEmitter.maxParentCount = 1
PlaneConstructLaserEmitter.maxChildCount = 0
PlaneConstructLaserEmitter.connectionInput = sm.interactable.connectionType.logic
PlaneConstructLaserEmitter.connectionOutput = sm.interactable.connectionType.none
PlaneConstructLaserEmitter.colorNormal = sm.color.new(0xd00000ff)
PlaneConstructLaserEmitter.colorHighlight = sm.color.new(0xff6060ff)

local DEFAULT_CODE = "0"
local DEFAULT_PASSWORD = "0"
local MAX_CODE_LENGTH = 24
local MAX_PASSWORD_LENGTH = 32
local LASER_RANGE = 10000

local function cleanValue(value, fallback, maximumLength)
    value = tostring(value or ""):gsub("[^%w%-%_]", "")
    if value == "" then value = fallback end
    return string.sub(value, 1, maximumLength)
end

local function laserKey(code, password)
    return tostring(code) .. "\031" .. tostring(password)
end

local function clearOwnSpot(self)
    if self.sv == nil then return end
    local key = laserKey(self.sv.code, self.sv.password)
    local spot = PlaneConstructLaserBus[key]
    if spot ~= nil and spot.emitterId == self.interactable:getId() then
        PlaneConstructLaserBus[key] = nil
    end
end

function PlaneConstructLaserEmitter.sv_load(self)
    local stored = self.storage:load()
    self.sv = {
        code = cleanValue(type(stored) == "table" and stored.code or nil, DEFAULT_CODE, MAX_CODE_LENGTH),
        password = cleanValue(type(stored) == "table" and stored.password or nil, DEFAULT_PASSWORD, MAX_PASSWORD_LENGTH)
    }
    self.storage:save(self.sv)
    self.network:setClientData(self.sv)
end

function PlaneConstructLaserEmitter.server_onCreate(self)
    self:sv_load()
end

function PlaneConstructLaserEmitter.server_onRefresh(self)
    self:sv_load()
end

function PlaneConstructLaserEmitter.server_onDestroy(self)
    clearOwnSpot(self)
end

function PlaneConstructLaserEmitter.sv_setCredentials(self, data)
    if type(data) ~= "table" then return end
    clearOwnSpot(self)
    self.sv.code = cleanValue(data.code, DEFAULT_CODE, MAX_CODE_LENGTH)
    self.sv.password = cleanValue(data.password, DEFAULT_PASSWORD, MAX_PASSWORD_LENGTH)
    self.storage:save(self.sv)
    self.network:setClientData(self.sv)
end

function PlaneConstructLaserEmitter.server_onFixedUpdate(self)
    clearOwnSpot(self)

    local parents = self.interactable:getParents(sm.interactable.connectionType.logic)
    local parent = parents[1]
    if parent == nil or not parent:isActive() then
        self.interactable:setActive(false)
        return
    end

    -- New Legend's working laser uses the shape's local `at` axis. The emitter
    -- never uses the receiver's orientation and never sends an angle.
    local direction = self.shape.at
    if direction == nil or direction:length() <= 0.001 then
        self.interactable:setActive(false)
        return
    end
    direction = direction / direction:length()

    local origin = self.shape:getWorldPosition()
    local from = origin + direction * 0.1
    local to = origin + direction * LASER_RANGE
    local hit, result = sm.physics.raycast(from, to, self.shape)
    local point = hit and result ~= nil and result.pointWorld or nil
    if point == nil then
        self.interactable:setActive(false)
        return
    end

    PlaneConstructLaserBus[laserKey(self.sv.code, self.sv.password)] = {
        point = point,
        emitterId = self.interactable:getId(),
        tick = sm.game.getCurrentTick()
    }
    self.interactable:setActive(true)
end

function PlaneConstructLaserEmitter.client_onCreate(self)
    self.cl = { code = DEFAULT_CODE, password = DEFAULT_PASSWORD, gui = nil }
end

function PlaneConstructLaserEmitter.client_onClientDataUpdate(self, data)
    if type(data) ~= "table" then return end
    self.cl.code = tostring(data.code or DEFAULT_CODE)
    self.cl.password = tostring(data.password or DEFAULT_PASSWORD)
    self:cl_refreshGui()
end

function PlaneConstructLaserEmitter.client_canInteract(self)
    sm.gui.setInteractionText(
        "",
        sm.gui.getKeyBinding("Use", true),
        PC_L.get("configure_laser_emitter") .. " (" .. self.cl.code .. "/" .. self.cl.password .. ")"
    )
    return true
end

function PlaneConstructLaserEmitter.client_onInteract(self, _, state)
    if not state then return end
    if self.cl.gui ~= nil then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end
    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructLaserEmitter.layout"),
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

function PlaneConstructLaserEmitter.cl_codeChanged(self, _, text)
    self.cl.code = text
end

function PlaneConstructLaserEmitter.cl_passwordChanged(self, _, text)
    self.cl.password = text
end

function PlaneConstructLaserEmitter.cl_save(self)
    self.network:sendToServer("sv_setCredentials", {
        code = self.cl.code,
        password = self.cl.password
    })
    self:cl_closed()
end

function PlaneConstructLaserEmitter.cl_refreshGui(self)
    if self.cl.gui == nil then return end
    self.cl.gui:setText("CodeInput", self.cl.code)
    self.cl.gui:setText("PasswordInput", self.cl.password)
end

function PlaneConstructLaserEmitter.cl_closed(self)
    if self.cl.gui ~= nil then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
