dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlayerLockDetector = class()

PlayerLockDetector.maxParentCount = 1
PlayerLockDetector.maxChildCount = -1
PlayerLockDetector.connectionInput = sm.interactable.connectionType.logic
PlayerLockDetector.connectionOutput = sm.interactable.connectionType.logic
PlayerLockDetector.colorNormal = sm.color.new(0xeeeeeeff)
PlayerLockDetector.colorHighlight = sm.color.new(0xffffffff)

local DEFAULT_RANGE_BLOCKS = 25
local MIN_RANGE_BLOCKS = 1
local MAX_RANGE_BLOCKS = 50
local BLOCKS_PER_WORLD_UNIT = 4.0

local RADAR_REGISTRY_PREFIX = "PlaneRadarScreen:"
local PLANE_CONTROLLER_LOCK_PREFIX = "PlaneConstructPlaneControllerLock:"
local TURRET_CONTROLLER_LOCK_PREFIX = "PlaneConstructTurretControllerLock:"
local LOCK_REGISTRY_PREFIX = "PlaneConstructPlayerLockDetector:"
local PLANE_CONTROLLER_UUID = "e4ad98f3-f9c7-48f9-bd2a-da16f9da8ee9"

local WHITE_OUTPUT_COLOR = sm.color.new(0xeeeeeeff)
local BLACK_OUTPUT_COLOR = sm.color.new(0x222222ff)
local DEFAULT_DETECTION_MODE = "controller"

local function normalizeDetectionMode(value)
    return DEFAULT_DETECTION_MODE
end

local function clampInteger(value, minimum, maximum)
    local numericValue = tonumber(value) or DEFAULT_RANGE_BLOCKS
    return math.max(minimum, math.min(maximum, math.floor(numericValue + 0.5)))
end

local function getRegistryKey(self)
    return LOCK_REGISTRY_PREFIX .. tostring(self.interactable:getId())
end

local function hasPrefix(value, prefix)
    return type(value) == "string" and string.sub(value, 1, #prefix) == prefix
end

local function isRegistrySourceAlive(data)
    if type(data) ~= "table" or data.sourceShape == nil then
        return true
    end

    local ok, exists = pcall(sm.exists, data.sourceShape)
    return ok and exists == true
end

local function getPlayerAndCharacter(playerId)
    local numericPlayerId = tonumber(playerId)
    if numericPlayerId == nil then return nil, nil end

    for _, player in ipairs(sm.player.getAllPlayers()) do
        if player:getId() == numericPlayerId then
            local character = player:getCharacter()
            if character ~= nil and sm.exists(character) then
                return player, character
            end
            return player, nil
        end
    end

    return nil, nil
end

local function isCharacterInRange(self, character)
    if character == nil or character.worldPosition == nil then return false end

    local offset = character.worldPosition - self.shape.worldPosition
    local distance = offset:length()
    return distance > 0.001 and distance <= self.sv.rangeBlocks / BLOCKS_PER_WORLD_UNIT
end

local function getConnectedPlaneController(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        local shape = parent:getShape()
        if shape ~= nil and tostring(sm.shape.getShapeUuid(shape)) == PLANE_CONTROLLER_UUID then
            return parent
        end
    end
    return nil
end

local function findPlayerLock(self)
    local parent = getConnectedPlaneController(self)
    if parent == nil then return nil end

    local data = _G[PLANE_CONTROLLER_LOCK_PREFIX .. tostring(parent:getId())]
    if type(data) ~= "table"
        or data.lockActive ~= true
        or data.targetKind ~= "plane_controller"
        or data.targetPosition == nil then
        return nil
    end

    local offset = data.targetPosition - self.shape.worldPosition
    local distance = offset:length()
    if distance <= 0.001 or distance > self.sv.rangeBlocks / BLOCKS_PER_WORLD_UNIT then
        return nil
    end

    return {
        kind = "controller",
        playerId = tonumber(data.targetPlayerId),
        playerName = data.targetPlayerName or "Plane Controller"
    }
end

function PlayerLockDetector.server_onCreate(self)
    self:sv_initialize()
end

function PlayerLockDetector.server_onRefresh(self)
    self:sv_initialize()
end

function PlayerLockDetector.server_onDestroy(self)
    self.interactable:setActive(false)
    _G[getRegistryKey(self)] = nil
end

function PlayerLockDetector.sv_initialize(self)
    local stored = self.storage:load()
    local rangeBlocks = type(stored) == "table" and stored.rangeBlocks or DEFAULT_RANGE_BLOCKS
    local detectionMode = type(stored) == "table"
        and normalizeDetectionMode(stored.detectionMode)
        or DEFAULT_DETECTION_MODE

    self.sv = {
        rangeBlocks = clampInteger(rangeBlocks, MIN_RANGE_BLOCKS, MAX_RANGE_BLOCKS),
        detectionMode = detectionMode,
        lockActive = false,
        lockKind = nil,
        targetPlayerId = nil,
        targetPlayerName = nil,
        outputColor = "white"
    }

    self.storage:save({
        rangeBlocks = self.sv.rangeBlocks,
        detectionMode = self.sv.detectionMode
    })
    self.shape:setColor(WHITE_OUTPUT_COLOR)
    self.interactable:setActive(false)
    self:sv_publishRegistry()
    self:sv_syncClientData()
end

function PlayerLockDetector.sv_syncClientData(self)
    self.network:setClientData({
        rangeBlocks = self.sv.rangeBlocks,
        detectionMode = self.sv.detectionMode
    })
end

function PlayerLockDetector.sv_setRangeBlocks(self, requestedRange)
    local rangeBlocks = clampInteger(requestedRange, MIN_RANGE_BLOCKS, MAX_RANGE_BLOCKS)
    if rangeBlocks == self.sv.rangeBlocks then return end

    self.sv.rangeBlocks = rangeBlocks
    self.storage:save({
        rangeBlocks = rangeBlocks,
        detectionMode = self.sv.detectionMode
    })
    self:sv_syncClientData()
end

function PlayerLockDetector.sv_setDetectionMode(self, requestedMode)
    local detectionMode = normalizeDetectionMode(requestedMode)
    if detectionMode == self.sv.detectionMode then return end

    self.sv.detectionMode = detectionMode
    self.sv.lockActive = false
    self.sv.lockKind = nil
    self.sv.targetPlayerId = nil
    self.sv.targetPlayerName = nil
    self.sv.outputColor = "white"
    self.storage:save({
        rangeBlocks = self.sv.rangeBlocks,
        detectionMode = self.sv.detectionMode
    })
    self.shape:setColor(WHITE_OUTPUT_COLOR)
    self.interactable:setActive(false)
    self:sv_syncClientData()
    self:sv_publishRegistry()
end

function PlayerLockDetector.sv_publishRegistry(self)
    _G[getRegistryKey(self)] = {
        lockActive = self.sv.lockActive == true,
        lockKind = self.sv.lockKind,
        targetPlayerId = self.sv.targetPlayerId,
        targetPlayerName = self.sv.targetPlayerName,
        outputColor = self.sv.outputColor,
        detectionMode = self.sv.detectionMode,
        rangeBlocks = self.sv.rangeBlocks,
        detectorPosition = self.shape.worldPosition
    }
end

function PlayerLockDetector.server_onFixedUpdate(self)
    local lock = findPlayerLock(self)
    local lockActive = lock ~= nil
    local lockKind = lock ~= nil and lock.kind or nil
    local outputColor = lockKind == "controller" and "black" or "white"

    if self.sv.lockActive ~= lockActive
        or self.sv.lockKind ~= lockKind
        or self.sv.targetPlayerId ~= (lock ~= nil and lock.playerId or nil) then
        self.sv.lockActive = lockActive
        self.sv.lockKind = lockKind
        self.sv.targetPlayerId = lock ~= nil and lock.playerId or nil
        self.sv.targetPlayerName = lock ~= nil and lock.playerName or nil
    end

    if self.sv.outputColor ~= outputColor then
        self.sv.outputColor = outputColor
    end

    self.interactable:setActive(lockActive)
    self:sv_publishRegistry()
end

function PlayerLockDetector.client_onCreate(self)
    self.cl = {
        rangeBlocks = DEFAULT_RANGE_BLOCKS,
        detectionMode = DEFAULT_DETECTION_MODE,
        gui = nil
    }
end

function PlayerLockDetector.client_onClientDataUpdate(self, data)
    if self.cl == nil then self:client_onCreate() end
    self.cl.rangeBlocks = clampInteger(data.rangeBlocks, MIN_RANGE_BLOCKS, MAX_RANGE_BLOCKS)
    self.cl.detectionMode = normalizeDetectionMode(data.detectionMode)
    self:cl_refreshGui()
end

function PlayerLockDetector.client_onDestroy(self)
    if self.cl == nil then return end
    local gui = self.cl.gui
    self.cl.gui = nil
    if gui then
        gui:close()
        gui:destroy()
    end
end

function PlayerLockDetector.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_player_lock"))
    return true
end

function PlayerLockDetector.client_onInteract(self, _, state)
    if not state then return end
    self:cl_openGui()
end

function PlayerLockDetector.cl_openGui(self)
    if self.cl.gui then
        local oldGui = self.cl.gui
        self.cl.gui = nil
        oldGui:close()
        oldGui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlayerLockDetector.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "RangeSlider",
        MAX_RANGE_BLOCKS,
        self.cl.rangeBlocks - MIN_RANGE_BLOCKS,
        "cl_onRangeSliderChanged"
    )
    self.cl.gui:setButtonCallback("DetectionModeButton", "cl_onDetectionModePressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlayerLockDetector.cl_onRangeSliderChanged(self, sliderPosition)
    self.cl.rangeBlocks = clampInteger(
        sliderPosition + MIN_RANGE_BLOCKS,
        MIN_RANGE_BLOCKS,
        MAX_RANGE_BLOCKS
    )
    self:cl_refreshGui()
    self.network:sendToServer("sv_setRangeBlocks", self.cl.rangeBlocks)
end

function PlayerLockDetector.cl_onDetectionModePressed(self)
    self.cl.detectionMode = "controller"
    self:cl_refreshGui()
end

function PlayerLockDetector.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText("RangeValue", PC_L.get("lock_detection_range", self.cl.rangeBlocks))
    self.cl.gui:setSliderPosition("RangeSlider", self.cl.rangeBlocks - MIN_RANGE_BLOCKS)
    self.cl.gui:setText("DetectionModeValue", PC_L.get("detecting_plane_locks"))
end

function PlayerLockDetector.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
