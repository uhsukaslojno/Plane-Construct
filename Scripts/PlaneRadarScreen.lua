dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneRadarScreen = class()

PlaneRadarScreen.maxParentCount = -1
PlaneRadarScreen.maxChildCount = -1
PlaneRadarScreen.connectionInput = sm.interactable.connectionType.logic
PlaneRadarScreen.connectionOutput = sm.interactable.connectionType.logic
PlaneRadarScreen.colorNormal = sm.color.new(0x8bd7e6ff)
PlaneRadarScreen.colorHighlight = sm.color.new(0xd7fbffff)

local MARKER_UUID = sm.uuid.new("fe538133-1a7c-4698-8410-377fdd68824a")
local SELECTED_MARKER_UUID = sm.uuid.new("6bd47f9b-4b9f-4fe0-8f6a-8acb1a54c9a2")
local PRESENCE_REGISTRY_NAME = "PlaneConstructPresenceTargets"

local DEFAULT_FOV_DEGREES = 60
local MIN_FOV_DEGREES = 10
local MAX_FOV_DEGREES = 180
local DEFAULT_MIN_DISTANCE_BLOCKS = 0
local MIN_MIN_DISTANCE_BLOCKS = 0
local MAX_MIN_DISTANCE_BLOCKS = 100
local DEFAULT_MAX_DISTANCE_BLOCKS = 1000
local MIN_MAX_DISTANCE_BLOCKS = 100
local MAX_MAX_DISTANCE_BLOCKS = 5000
local BLOCKS_PER_WORLD_UNIT = 4.0

-- PlaneRadarGlass.mesh occupies +/-0.5 on its local Y/Z axes and +/-0.1
-- on local X. Keep the dots inside that actual pane instead of the larger
-- one-block hull used for collision.
local PANE_HALF_WIDTH = 0.5
local PANE_HALF_HEIGHT = 0.5
-- Leave room for the complete billboard, not only its center point.
local PANE_MARGIN = 0.12
local PANE_DEPTH_OFFSET = 0.106
-- These are the four yellow shades used by the vanilla paint tool.
local YELLOW_LOGIC_COLORS = {
    f5f071ff = true,
    e2db13ff = true,
    ["817c00ff"] = true,
    ["323000ff"] = true
}

local function clampInteger(value, minimum, maximum)
    local numericValue = tonumber(value)
    if numericValue == nil then
        return minimum
    end
    return math.max(minimum, math.min(maximum, math.floor(numericValue + 0.5)))
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

-- MJM's radar converts a normalized world direction into the block's local
-- right/at/up axes before mapping it to the display.
local function toLocal(shape, globalVector)
    if globalVector:length() < 0.000001 then
        return sm.vec3.zero()
    end

    return sm.vec3.new(
        shape:getRight():dot(globalVector),
        shape:getAt():dot(globalVector),
        shape:getUp():dot(globalVector)
    )
end

local function getRegistryKey(self)
    return "PlaneRadarScreen:" .. tostring(self.interactable:getId())
end

local function isTargetInSensorCone(self, targetPosition, fovDegrees, minimumDistanceBlocks, maximumDistanceBlocks)
    local toTarget = targetPosition - self.shape.worldPosition
    local distance = toTarget:length()
    local minimumDistance = minimumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    local maximumDistance = maximumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    if distance <= 0.001 or distance <= minimumDistance or distance > maximumDistance then
        return false
    end

    -- MJM's radar converts the world direction into the block's local axes.
    -- The glass normal is local X (Shape:right), so the FOV is the exact
    -- angle away from that forward axis, not an independent screen clamp.
    local localDirection = toLocal(self.shape, toTarget / distance)
    local radialAngle = math.atan2(
        math.sqrt(
            localDirection.y * localDirection.y
                + localDirection.z * localDirection.z
        ),
        localDirection.x
    )
    return radialAngle <= math.rad(fovDegrees) * 0.5
end

local function isTargetInSensorRange(self, targetPosition, minimumDistanceBlocks, maximumDistanceBlocks)
    local offset = targetPosition - self.shape.worldPosition
    local distance = offset:length()
    local minimumDistance = minimumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    local maximumDistance = maximumDistanceBlocks / BLOCKS_PER_WORLD_UNIT
    return distance > 0.001 and distance > minimumDistance and distance <= maximumDistance
end

local function isLogicColorActive(self, colorSet)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            local parentShape = parent:getShape()
            if parentShape ~= nil then
                local parentColor = string.lower(tostring(parentShape:getColor()))
                if colorSet[parentColor] then return true end
            end
        end
    end

    return false
end

local function isBasicLogicInputActive(self)
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:hasOutputType(sm.interactable.connectionType.logic) and parent:isActive() then
            local parentShape = parent:getShape()
            local parentColor = parentShape ~= nil and string.lower(tostring(parentShape:getColor())) or ""
            if not YELLOW_LOGIC_COLORS[parentColor] then
                return true
            end
        end
    end

    return false
end

local function getPresenceRegistry()
    return _G[PRESENCE_REGISTRY_NAME] or {}
end

function PlaneRadarScreen.server_onCreate(self)
    self:sv_initialize()
end

function PlaneRadarScreen.server_onRefresh(self)
    self:sv_initialize()
end

function PlaneRadarScreen.server_onDestroy(self)
    if self.interactable ~= nil then
        self.interactable:setActive(false)
    end
    _G[getRegistryKey(self)] = nil
end

function PlaneRadarScreen.sv_save(self)
    self.storage:save({
        fovDegrees = self.sv.fovDegrees,
        minimumDistanceBlocks = self.sv.minimumDistanceBlocks,
        maximumDistanceBlocks = self.sv.maximumDistanceBlocks,
        selectedPlayerId = self.sv.selectedPlayerId
    })
end

function PlaneRadarScreen.sv_initialize(self)
    local stored = self.storage:load()
    local fovDegrees = DEFAULT_FOV_DEGREES
    local minimumDistanceBlocks = DEFAULT_MIN_DISTANCE_BLOCKS
    local maximumDistanceBlocks = DEFAULT_MAX_DISTANCE_BLOCKS
    local selectedPlayerId = nil

    if type(stored) == "table" then
        fovDegrees = clampInteger(stored.fovDegrees, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
        minimumDistanceBlocks = clampInteger(
            stored.minimumDistanceBlocks,
            MIN_MIN_DISTANCE_BLOCKS,
            MAX_MIN_DISTANCE_BLOCKS
        )
        maximumDistanceBlocks = clampInteger(
            stored.maximumDistanceBlocks or stored.distanceBlocks,
            MIN_MAX_DISTANCE_BLOCKS,
            MAX_MAX_DISTANCE_BLOCKS
        )
        selectedPlayerId = tonumber(stored.selectedPlayerId)
    end

    self.sv = {
        fovDegrees = fovDegrees,
        minimumDistanceBlocks = minimumDistanceBlocks,
        maximumDistanceBlocks = maximumDistanceBlocks,
        selectedPlayerId = selectedPlayerId,
        previousYellowActive = false,
        yellowCycleTimer = 0.0,
        outputActive = false,
        inRangeTargets = {}
    }

    self.interactable:setActive(false)
    self:sv_save()
    self:sv_syncClientData()
    self:sv_publishRegistry()
end

function PlaneRadarScreen.sv_syncClientData(self)
    self.network:setClientData({
        fovDegrees = self.sv.fovDegrees,
        minimumDistanceBlocks = self.sv.minimumDistanceBlocks,
        maximumDistanceBlocks = self.sv.maximumDistanceBlocks,
        selectedPlayerId = self.sv.selectedPlayerId
    })
end

function PlaneRadarScreen.sv_setFovDegrees(self, requestedFov)
    local fovDegrees = clampInteger(requestedFov, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
    if fovDegrees == self.sv.fovDegrees then return end

    self.sv.fovDegrees = fovDegrees
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setMinimumDistanceBlocks(self, requestedDistance)
    local minimumDistanceBlocks = clampInteger(
        requestedDistance,
        MIN_MIN_DISTANCE_BLOCKS,
        MAX_MIN_DISTANCE_BLOCKS
    )
    if minimumDistanceBlocks == self.sv.minimumDistanceBlocks then return end

    self.sv.minimumDistanceBlocks = minimumDistanceBlocks
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_setMaximumDistanceBlocks(self, requestedDistance)
    local maximumDistanceBlocks = clampInteger(
        requestedDistance,
        MIN_MAX_DISTANCE_BLOCKS,
        MAX_MAX_DISTANCE_BLOCKS
    )
    if maximumDistanceBlocks == self.sv.maximumDistanceBlocks then return end

    self.sv.maximumDistanceBlocks = maximumDistanceBlocks
    self:sv_save()
    self:sv_syncClientData()
end

function PlaneRadarScreen.sv_publishRegistry(self)
    _G[getRegistryKey(self)] = {
        selectedPlayerId = self.sv.selectedPlayerId,
        outputActive = self.sv.outputActive == true,
        fovDegrees = self.sv.fovDegrees,
        maximumDistanceBlocks = self.sv.maximumDistanceBlocks,
        sensorPosition = self.shape.worldPosition,
        sensorRight = self.shape:getRight(),
        sensorAt = self.shape:getAt(),
        sensorUp = self.shape:getUp(),
        visibleTargets = self.sv.visibleTargets or {},
        inRangeTargets = self.sv.inRangeTargets or {}
    }
end

function PlaneRadarScreen.sv_getTargetPositionById(self, targetId)
    for _, player in ipairs(sm.player.getAllPlayers()) do
        if player:getId() == targetId then
            local character = player:getCharacter()
            return character ~= nil and sm.exists(character) and character.worldPosition or nil
        end
    end

    local target = getPresenceRegistry()[targetId]
    return type(target) == "table" and target.active == true and target.position or nil
end

function PlaneRadarScreen.sv_getInRangeTargets(self)
    local inRangeTargets = {}
    local function addTarget(targetId, targetPosition)
        if targetId ~= nil and targetPosition ~= nil
            and isTargetInSensorRange(
                self,
                targetPosition,
                self.sv.minimumDistanceBlocks,
                self.sv.maximumDistanceBlocks
            ) then
            inRangeTargets[targetId] = true
        end
    end

    for _, player in ipairs(sm.player.getAllPlayers()) do
        local character = player:getCharacter()
        if character ~= nil and sm.exists(character) then
            addTarget(player:getId(), character.worldPosition)
        end
    end

    for targetId, target in pairs(getPresenceRegistry()) do
        local numericTargetId = tonumber(targetId)
            or (type(target) == "table" and tonumber(target.id) or nil)
        if numericTargetId ~= nil and type(target) == "table"
            and target.active == true and target.position ~= nil then
            addTarget(numericTargetId, target.position)
        end
    end

    return inRangeTargets
end

function PlaneRadarScreen.sv_getEligiblePlayers(self)
    local eligiblePlayers = {}
    for _, player in ipairs(sm.player.getAllPlayers()) do
        local character = player:getCharacter()
        if character ~= nil and sm.exists(character)
            and isTargetInSensorCone(
                self,
                character.worldPosition,
                self.sv.fovDegrees,
                self.sv.minimumDistanceBlocks,
                self.sv.maximumDistanceBlocks
            ) then
            local offset = character.worldPosition - self.shape.worldPosition
            table.insert(eligiblePlayers, {
                id = player:getId(),
                distanceSquared = offset:dot(offset)
            })
        end
    end

    for targetId, target in pairs(getPresenceRegistry()) do
        local numericTargetId = tonumber(targetId) or tonumber(target.id)
        if numericTargetId ~= nil and target.active == true and target.position ~= nil
            and isTargetInSensorCone(
                self,
                target.position,
                self.sv.fovDegrees,
                self.sv.minimumDistanceBlocks,
                self.sv.maximumDistanceBlocks
            ) then
            local offset = target.position - self.shape.worldPosition
            table.insert(eligiblePlayers, {
                id = numericTargetId,
                distanceSquared = offset:dot(offset)
            })
        end
    end

    -- Closest first gives a useful default and a stable, intuitive cycle order.
    table.sort(eligiblePlayers, function(left, right)
        if left.distanceSquared == right.distanceSquared then
            return left.id < right.id
        end
        return left.distanceSquared < right.distanceSquared
    end)
    return eligiblePlayers
end

function PlaneRadarScreen.sv_setSelectedPlayer(self, playerId)
    if self.sv.selectedPlayerId == playerId then return end

    self.sv.selectedPlayerId = playerId
    self:sv_save()
    self:sv_syncClientData()
    self:sv_publishRegistry()
end

function PlaneRadarScreen.sv_ensureSelectedPlayer(self, eligiblePlayers)
    if #eligiblePlayers == 0 then
        self:sv_setSelectedPlayer(nil)
        return
    end

    for _, eligiblePlayer in ipairs(eligiblePlayers) do
        if eligiblePlayer.id == self.sv.selectedPlayerId then
            return
        end
    end

    -- The closest eligible player gets the yellow marker by default.
    self:sv_setSelectedPlayer(eligiblePlayers[1].id)
end

function PlaneRadarScreen.sv_cycleSelectedPlayer(self, eligiblePlayers)
    if #eligiblePlayers <= 1 then return end

    local currentIndex = 0
    for index, eligiblePlayer in ipairs(eligiblePlayers) do
        if eligiblePlayer.id == self.sv.selectedPlayerId then
            currentIndex = index
            break
        end
    end

    local nextIndex = currentIndex + 1
    if nextIndex > #eligiblePlayers then
        nextIndex = 1
    end
    self:sv_setSelectedPlayer(eligiblePlayers[nextIndex].id)
end

function PlaneRadarScreen.server_onFixedUpdate(self, timeStep)
    self.sv.inRangeTargets = self:sv_getInRangeTargets()
    local eligiblePlayers = self:sv_getEligiblePlayers()
    self.sv.visibleTargets = {}
    for _, eligiblePlayer in ipairs(eligiblePlayers) do
        local position = self:sv_getTargetPositionById(eligiblePlayer.id)
        if position ~= nil then
            self.sv.visibleTargets[eligiblePlayer.id] = position
        end
    end
    self:sv_ensureSelectedPlayer(eligiblePlayers)

    local yellowActive = isLogicColorActive(self, YELLOW_LOGIC_COLORS)
    if yellowActive then
        if not self.sv.previousYellowActive then
            -- Rising edge: one immediate cycle.
            self:sv_cycleSelectedPlayer(eligiblePlayers)
            self.sv.yellowCycleTimer = 0.0
        else
            self.sv.yellowCycleTimer = self.sv.yellowCycleTimer + (tonumber(timeStep) or 0.025)
            while self.sv.yellowCycleTimer >= 1.0 do
                self.sv.yellowCycleTimer = self.sv.yellowCycleTimer - 1.0
                self:sv_cycleSelectedPlayer(eligiblePlayers)
            end
        end
    else
        self.sv.yellowCycleTimer = 0.0
    end
    self.sv.previousYellowActive = yellowActive

    -- Basic logic is the radar's tracking-enable output. Yellow only changes
    -- the selected target and never starts the Plane Controller by itself.
    local basicActive = isBasicLogicInputActive(self)
    if basicActive ~= self.sv.outputActive then
        self.sv.outputActive = basicActive
        self.interactable:setActive(basicActive)
    end
    self:sv_publishRegistry()
end

function PlaneRadarScreen.client_onCreate(self)
    self.cl = {
        fovDegrees = DEFAULT_FOV_DEGREES,
        minimumDistanceBlocks = DEFAULT_MIN_DISTANCE_BLOCKS,
        maximumDistanceBlocks = DEFAULT_MAX_DISTANCE_BLOCKS,
        selectedPlayerId = nil,
        gui = nil,
        markers = {},
        markerUuids = {}
    }
end

function PlaneRadarScreen.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self:client_onCreate()
    end

    self.cl.fovDegrees = clampInteger(data.fovDegrees, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
    self.cl.minimumDistanceBlocks = clampInteger(
        data.minimumDistanceBlocks,
        MIN_MIN_DISTANCE_BLOCKS,
        MAX_MIN_DISTANCE_BLOCKS
    )
    self.cl.maximumDistanceBlocks = clampInteger(
        data.maximumDistanceBlocks or data.distanceBlocks,
        MIN_MAX_DISTANCE_BLOCKS,
        MAX_MAX_DISTANCE_BLOCKS
    )
    self.cl.selectedPlayerId = tonumber(data.selectedPlayerId)
    self:cl_refreshGui()
end

function PlaneRadarScreen.client_onDestroy(self)
    if self.cl == nil then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end

    for _, marker in pairs(self.cl.markers) do
        if marker:isPlaying() then marker:stop() end
        marker:destroy()
    end
    self.cl.markers = {}
    self.cl.markerUuids = {}
end

function PlaneRadarScreen.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_radar_screen"))
    return true
end

function PlaneRadarScreen.client_onInteract(self, _, state)
    if not state then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneRadarScreen.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "FovSlider",
        MAX_FOV_DEGREES - MIN_FOV_DEGREES + 1,
        self.cl.fovDegrees - MIN_FOV_DEGREES,
        "cl_onFovSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "MinimumDistanceSlider",
        MAX_MIN_DISTANCE_BLOCKS - MIN_MIN_DISTANCE_BLOCKS + 1,
        self.cl.minimumDistanceBlocks - MIN_MIN_DISTANCE_BLOCKS,
        "cl_onMinimumDistanceSliderChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "DistanceSlider",
        MAX_MAX_DISTANCE_BLOCKS - MIN_MAX_DISTANCE_BLOCKS + 1,
        self.cl.maximumDistanceBlocks - MIN_MAX_DISTANCE_BLOCKS,
        "cl_onMaximumDistanceSliderChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneRadarScreen.cl_onFovSliderChanged(self, sliderPosition)
    self.cl.fovDegrees = clampInteger(sliderPosition + MIN_FOV_DEGREES, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setFovDegrees", self.cl.fovDegrees)
end

function PlaneRadarScreen.cl_onMinimumDistanceSliderChanged(self, sliderPosition)
    self.cl.minimumDistanceBlocks = clampInteger(
        sliderPosition + MIN_MIN_DISTANCE_BLOCKS,
        MIN_MIN_DISTANCE_BLOCKS,
        MAX_MIN_DISTANCE_BLOCKS
    )
    self:cl_refreshGui()
    self.network:sendToServer("sv_setMinimumDistanceBlocks", self.cl.minimumDistanceBlocks)
end

function PlaneRadarScreen.cl_onMaximumDistanceSliderChanged(self, sliderPosition)
    self.cl.maximumDistanceBlocks = clampInteger(
        sliderPosition + MIN_MAX_DISTANCE_BLOCKS,
        MIN_MAX_DISTANCE_BLOCKS,
        MAX_MAX_DISTANCE_BLOCKS
    )
    self:cl_refreshGui()
    self.network:sendToServer("sv_setMaximumDistanceBlocks", self.cl.maximumDistanceBlocks)
end

function PlaneRadarScreen.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end

    self.cl.gui:setText("FovValue", PC_L.get("field_of_view", self.cl.fovDegrees))
    self.cl.gui:setText(
        "MinimumDistanceValue",
        PC_L.get("minimum_distance", self.cl.minimumDistanceBlocks)
    )
    self.cl.gui:setText(
        "DistanceValue",
        PC_L.get("maximum_distance", self.cl.maximumDistanceBlocks)
    )
end

function PlaneRadarScreen.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function PlaneRadarScreen.cl_updateMarker(self, targetId, targetPosition, activeMarkers)
    local localPosition = self:cl_getScreenLocalPosition(targetPosition)
    if localPosition == nil then return end

    local isSelected = targetId == self.cl.selectedPlayerId
    local markerUuid = isSelected and SELECTED_MARKER_UUID or MARKER_UUID
    local marker = self.cl.markers[targetId]
    if marker == nil or self.cl.markerUuids[targetId] ~= markerUuid then
        if marker ~= nil then
            marker:stop()
            marker:destroy()
        end
        marker = sm.effect.createEffect("ShapeRenderable", self.shape)
        marker:setParameter("uuid", markerUuid)
        self.cl.markers[targetId] = marker
        self.cl.markerUuids[targetId] = markerUuid
    end

    marker:setOffsetPosition(localPosition)
    marker:setOffsetRotation(
        sm.vec3.getRotation(sm.vec3.new(0, 1, 0), sm.vec3.new(1, 0, 0))
    )
    -- Selected targets use a dedicated yellow mesh as well as a larger dot.
    local markerScale = isSelected and 0.19 or 0.15
    marker:setScale(sm.vec3.new(markerScale, 1, markerScale))
    if not marker:isPlaying() then marker:start() end
    activeMarkers[targetId] = true
end

function PlaneRadarScreen.cl_updateMarkers(self)
    if self.cl == nil then return end

    local activeMarkers = {}
    local players = sm.player.getAllPlayers()
    for _, player in ipairs(players) do
        local character = player:getCharacter()
        if character ~= nil and sm.exists(character) then
            self:cl_updateMarker(player:getId(), character.worldPosition, activeMarkers)
        end
    end

    for targetId, target in pairs(getPresenceRegistry()) do
        local numericTargetId = tonumber(targetId) or tonumber(target.id)
        if numericTargetId ~= nil and target.active == true and target.position ~= nil then
            self:cl_updateMarker(numericTargetId, target.position, activeMarkers)
        end
    end

    for playerId, marker in pairs(self.cl.markers) do
        if not activeMarkers[playerId] and marker:isPlaying() then
            marker:stop()
        end
    end
end

-- Keep the MJM-style fixed-tick update, while also refreshing during render
-- frames so a moving physics target does not visibly outrun the marker.
function PlaneRadarScreen.client_onFixedUpdate(self, _)
    self:cl_updateMarkers()
end

function PlaneRadarScreen.client_onUpdate(self, _)
    self:cl_updateMarkers()
end

function PlaneRadarScreen.cl_getScreenLocalPosition(self, targetPosition)
    if not isTargetInSensorCone(
        self,
        targetPosition,
        self.cl.fovDegrees,
        self.cl.minimumDistanceBlocks,
        self.cl.maximumDistanceBlocks
    ) then
        return nil
    end

    local toTarget = targetPosition - self.shape.worldPosition
    local distance = toTarget:length()
    if distance <= 0.001 then return nil end

    -- Follow MJM's method: normalize first, then map the local direction
    -- directly to the display. This keeps marker movement proportional to
    -- target direction and tied to the same fixed tick as target updates.
    local targetLocal = toLocal(self.shape, toTarget / distance)
    local paneHalfWidth = math.max(PANE_HALF_WIDTH - PANE_MARGIN, 0.01)
    local paneHalfHeight = math.max(PANE_HALF_HEIGHT - PANE_MARGIN, 0.01)
    -- Each component of targetLocal is already in [-1, 1], so this is the
    -- same normalized screen mapping used by MJM's radar and inherently
    -- keeps the dot inside the physical glass bounds.
    local paneX = clamp(targetLocal.y * paneHalfWidth, -paneHalfWidth, paneHalfWidth)
    local paneZ = clamp(targetLocal.z * paneHalfHeight, -paneHalfHeight, paneHalfHeight)
    return sm.vec3.new(PANE_DEPTH_OFFSET, paneX, paneZ)
end
