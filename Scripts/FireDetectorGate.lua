dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
FireDetectorGate = class()

FireDetectorGate.maxParentCount = 0
FireDetectorGate.maxChildCount = -1
FireDetectorGate.connectionInput = sm.interactable.connectionType.none
FireDetectorGate.connectionOutput = sm.interactable.connectionType.logic
FireDetectorGate.colorNormal = sm.color.new(0xd00000ff)
FireDetectorGate.colorHighlight = sm.color.new(0xff3a3aff)

local DEFAULT_RANGE_BLOCKS = 10
local MIN_RANGE_BLOCKS = 1
local MAX_RANGE_BLOCKS = 50
local BLOCK_SIZE = 0.25
local SCAN_INTERVAL_TICKS = 5
local REGISTRY_PREFIX = "PlaneConstructFireDetector:"

local function registryKey(interactable)
    return REGISTRY_PREFIX .. tostring(interactable:getId())
end

local function clampInteger(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
end

function FireDetectorGate.server_onCreate(self)
    self:sv_initialize()
end

function FireDetectorGate.server_onRefresh(self)
    self:sv_initialize()
end

function FireDetectorGate.server_onDestroy(self)
    if sm.exists(self.interactable) then
        self.interactable:setActive(false)
    end
    _G[registryKey(self.interactable)] = nil
end

function FireDetectorGate.sv_initialize(self)
    local stored = self.storage:load()
    local storedRange = type(stored) == "table" and tonumber(stored.rangeBlocks) or nil
    local rangeBlocks = clampInteger(storedRange or DEFAULT_RANGE_BLOCKS, MIN_RANGE_BLOCKS, MAX_RANGE_BLOCKS)

    self.sv = {
        rangeBlocks = rangeBlocks,
        scanTicks = 0,
        isDetectingFire = false
    }

    self.interactable:setActive(false)
    self.storage:save({ rangeBlocks = rangeBlocks })
    self:sv_publishState()
    self:sv_syncClientData()
end

function FireDetectorGate.sv_publishState(self)
    _G[registryKey(self.interactable)] = {
        isDetectingFire = self.sv.isDetectingFire
    }
end

function FireDetectorGate.sv_syncClientData(self)
    self.network:setClientData({ rangeBlocks = self.sv.rangeBlocks })
end

function FireDetectorGate.sv_setRangeBlocks(self, requestedRange)
    local numericRange = tonumber(requestedRange)
    if numericRange == nil then return end

    local rangeBlocks = clampInteger(numericRange, MIN_RANGE_BLOCKS, MAX_RANGE_BLOCKS)
    if rangeBlocks == self.sv.rangeBlocks then return end

    self.sv.rangeBlocks = rangeBlocks
    self.sv.scanTicks = SCAN_INTERVAL_TICKS
    self.storage:save({ rangeBlocks = rangeBlocks })
    self:sv_syncClientData()
end

function FireDetectorGate.sv_isFireInRange(self)
    local radius = self.sv.rangeBlocks * BLOCK_SIZE
    local nearbyShapes = sm.shape.shapesInSphere(self.shape.worldPosition, radius)

    for _, shape in ipairs(nearbyShapes) do
        if sm.exists(shape) and shape:getBurning() then
            return true
        end
    end

    return false
end

function FireDetectorGate.server_onFixedUpdate(self, _)
    self.sv.scanTicks = self.sv.scanTicks + 1
    if self.sv.scanTicks < SCAN_INTERVAL_TICKS then return end
    self.sv.scanTicks = 0

    local isDetectingFire = self:sv_isFireInRange()
    if isDetectingFire ~= self.sv.isDetectingFire then
        self.sv.isDetectingFire = isDetectingFire
        self.interactable:setActive(isDetectingFire)
        self:sv_publishState()
    end
end

function FireDetectorGate.client_onCreate(self)
    self.cl = {
        rangeBlocks = DEFAULT_RANGE_BLOCKS,
        gui = nil
    }
end

function FireDetectorGate.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self.cl = { rangeBlocks = DEFAULT_RANGE_BLOCKS, gui = nil }
    end
    self.cl.rangeBlocks = clampInteger(tonumber(data.rangeBlocks) or DEFAULT_RANGE_BLOCKS, MIN_RANGE_BLOCKS, MAX_RANGE_BLOCKS)
    self:cl_refreshGui()
end

function FireDetectorGate.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function FireDetectorGate.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_fire_detector"))
    return true
end

function FireDetectorGate.client_onInteract(self, _, state)
    if not state then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("FireDetectorGate.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "RangeSlider",
        MAX_RANGE_BLOCKS - MIN_RANGE_BLOCKS + 1,
        self.cl.rangeBlocks - MIN_RANGE_BLOCKS,
        "cl_onRangeSliderChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function FireDetectorGate.cl_onRangeSliderChanged(self, sliderPosition)
    self.cl.rangeBlocks = clampInteger(sliderPosition + MIN_RANGE_BLOCKS, MIN_RANGE_BLOCKS, MAX_RANGE_BLOCKS)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setRangeBlocks", self.cl.rangeBlocks)
end

function FireDetectorGate.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText("RangeValue", PC_L.get("detection_radius", self.cl.rangeBlocks))
end

function FireDetectorGate.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
