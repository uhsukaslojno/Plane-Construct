PlayerPresence = class()

PlayerPresence.maxParentCount = -1
PlayerPresence.maxChildCount = -1
PlayerPresence.connectionInput = sm.interactable.connectionType.logic
PlayerPresence.connectionOutput = sm.interactable.connectionType.logic
PlayerPresence.colorNormal = sm.color.new(0x2f80edff)
PlayerPresence.colorHighlight = sm.color.new(0x8fc7ffff)

local REGISTRY_NAME = "PlaneConstructPresenceTargets"

local function getVirtualId(self)
    return -self.interactable:getId()
end

local function getRegistry()
    if _G[REGISTRY_NAME] == nil then
        _G[REGISTRY_NAME] = {}
    end
    return _G[REGISTRY_NAME]
end

local function isLogicInputActive(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            return true
        end
    end
    return false
end

function PlayerPresence.server_onCreate(self)
    self:sv_initialize()
end

function PlayerPresence.server_onRefresh(self)
    self:sv_initialize()
end

function PlayerPresence.server_onDestroy(self)
    if self.interactable ~= nil then
        self.interactable:setActive(false)
    end
    getRegistry()[self.sv.virtualId] = nil
end

function PlayerPresence.sv_initialize(self)
    self.sv = {
        virtualId = getVirtualId(self),
        name = "Player Presence [" .. tostring(self.interactable:getId()) .. "]",
        active = true
    }
    self.interactable:setActive(true)
    self:sv_publishRegistry()
    self:sv_syncClientData()
end

function PlayerPresence.sv_publishRegistry(self)
    local registry = getRegistry()
    local target = registry[self.sv.virtualId]
    if target == nil then
        target = {}
        registry[self.sv.virtualId] = target
    end

    target.id = self.sv.virtualId
    target.name = self.sv.name
    target.active = self.sv.active == true
    target.position = self.shape.worldPosition
    target.velocity = self.shape:getVelocity()
end

function PlayerPresence.sv_syncClientData(self)
    self.network:setClientData({
        virtualId = self.sv.virtualId,
        name = self.sv.name,
        active = self.sv.active
    })
end

function PlayerPresence.server_onFixedUpdate(self)
    -- The presence exists by default. Any active logic input disables it.
    local active = not isLogicInputActive(self)
    if active ~= self.sv.active then
        self.sv.active = active
        self.interactable:setActive(active)
        self:sv_syncClientData()
    end
    self:sv_publishRegistry()
end

function PlayerPresence.client_onCreate(self)
    self.cl = {
        virtualId = getVirtualId(self),
        name = "Player Presence [" .. tostring(self.interactable:getId()) .. "]",
        active = true
    }
    self:cl_publishRegistry()
end

function PlayerPresence.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self:client_onCreate()
    end

    self.cl.virtualId = tonumber(data.virtualId) or self.cl.virtualId
    self.cl.name = data.name or self.cl.name
    self.cl.active = data.active == true
    self:cl_publishRegistry()
end

function PlayerPresence.client_onDestroy(self)
    if self.cl ~= nil then
        getRegistry()[self.cl.virtualId] = nil
    end
end

function PlayerPresence.cl_publishRegistry(self)
    local registry = getRegistry()
    local target = registry[self.cl.virtualId]
    if target == nil then
        target = {}
        registry[self.cl.virtualId] = target
    end

    target.id = self.cl.virtualId
    target.name = self.cl.name
    target.active = self.cl.active == true
    target.position = self.shape.worldPosition
    target.velocity = self.shape:getVelocity()
end

function PlayerPresence.client_onFixedUpdate(self)
    if self.cl ~= nil then
        self:cl_publishRegistry()
    end
end
