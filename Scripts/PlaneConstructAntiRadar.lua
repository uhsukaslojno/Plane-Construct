dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneConstructAntiRadar = class()
PlaneConstructAntiRadar.maxParentCount = 1
PlaneConstructAntiRadar.maxChildCount = 0
PlaneConstructAntiRadar.connectionInput = sm.interactable.connectionType.logic
PlaneConstructAntiRadar.connectionOutput = sm.interactable.connectionType.none
PlaneConstructAntiRadar.colorNormal = sm.color.new(0x7628b8ff)
PlaneConstructAntiRadar.colorHighlight = sm.color.new(0xb76affff)

local REGISTRY_NAME = "PlaneConstructAntiRadarZones"
local DEFAULT_RADIUS_BLOCKS = 50
local MIN_RADIUS_BLOCKS = 1
local MAX_RADIUS_BLOCKS = 200
local BLOCKS_PER_WORLD_UNIT = 4.0

local function getRegistry()
    if _G[REGISTRY_NAME] == nil then
        _G[REGISTRY_NAME] = {}
    end
    return _G[REGISTRY_NAME]
end

local function registryKey(self)
    return tostring(self.interactable:getId())
end

local function clampInteger(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor((tonumber(value) or minimum) + 0.5)))
end

local function isLogicDisabled(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            return true
        end
    end
    return false
end

function PlaneConstructAntiRadar.server_onCreate(self)
    local stored = self.storage:load()
    self.radiusBlocks = clampInteger(
        type(stored) == "table" and stored.radiusBlocks or DEFAULT_RADIUS_BLOCKS,
        MIN_RADIUS_BLOCKS,
        MAX_RADIUS_BLOCKS
    )
    self.enabled = true
    self:sv_syncClientData()
    self:sv_publish()
end

function PlaneConstructAntiRadar.server_onRefresh(self)
    self:server_onCreate()
end

function PlaneConstructAntiRadar.server_onDestroy(self)
    getRegistry()[registryKey(self)] = nil
end

function PlaneConstructAntiRadar.server_onUnload(self)
    self:server_onDestroy()
end

function PlaneConstructAntiRadar.sv_publish(self)
    local enabled = self.enabled == true
    getRegistry()[registryKey(self)] = {
        sourceShape = self.shape,
        position = self.shape.worldPosition,
        radius = self.radiusBlocks / BLOCKS_PER_WORLD_UNIT,
        enabled = enabled
    }
    self.interactable:setActive(enabled)
    self.interactable:setPublicData({
        radiusBlocks = self.radiusBlocks,
        enabled = enabled
    })
end

function PlaneConstructAntiRadar.sv_syncClientData(self)
    self.network:setClientData({ radiusBlocks = self.radiusBlocks })
end

function PlaneConstructAntiRadar.sv_setRadiusBlocks(self, requestedRadius)
    local radiusBlocks = clampInteger(requestedRadius, MIN_RADIUS_BLOCKS, MAX_RADIUS_BLOCKS)
    if radiusBlocks == self.radiusBlocks then return end
    self.radiusBlocks = radiusBlocks
    self.storage:save({ radiusBlocks = radiusBlocks })
    self:sv_syncClientData()
    self:sv_publish()
end

function PlaneConstructAntiRadar.server_onFixedUpdate(self, _)
    self.enabled = not isLogicDisabled(self)
    self:sv_publish()
end

function PlaneConstructAntiRadar.client_onCreate(self)
    self.cl = { radiusBlocks = DEFAULT_RADIUS_BLOCKS, gui = nil }
end

function PlaneConstructAntiRadar.client_onClientDataUpdate(self, data)
    if self.cl == nil then self:client_onCreate() end
    self.cl.radiusBlocks = clampInteger(data.radiusBlocks, MIN_RADIUS_BLOCKS, MAX_RADIUS_BLOCKS)
    self:cl_refreshGui()
end

function PlaneConstructAntiRadar.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneConstructAntiRadar.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_antiradar"))
    return true
end

function PlaneConstructAntiRadar.client_onInteract(self, _, state)
    if not state then return end
    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end
    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructAntiRadar.layout"),
        false,
        { backgroundAlpha = 0.5, hidesHotbar = true }
    )
    self.cl.gui:createHorizontalSlider(
        "RadiusSlider",
        MAX_RADIUS_BLOCKS - MIN_RADIUS_BLOCKS + 1,
        self.cl.radiusBlocks - MIN_RADIUS_BLOCKS,
        "cl_onRadiusSliderChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneConstructAntiRadar.cl_onRadiusSliderChanged(self, position)
    self.cl.radiusBlocks = clampInteger(position + MIN_RADIUS_BLOCKS, MIN_RADIUS_BLOCKS, MAX_RADIUS_BLOCKS)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setRadiusBlocks", self.cl.radiusBlocks)
end

function PlaneConstructAntiRadar.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText("RadiusValue", PC_L.get("jamming_radius", self.cl.radiusBlocks))
    self.cl.gui:setSliderPosition("RadiusSlider", self.cl.radiusBlocks - MIN_RADIUS_BLOCKS)
end

function PlaneConstructAntiRadar.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
