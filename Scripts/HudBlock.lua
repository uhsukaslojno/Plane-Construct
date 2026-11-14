dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
HudBlock = class()

HudBlock.maxParentCount = -1
HudBlock.maxChildCount = 0
HudBlock.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.logic + sm.interactable.connectionType.power
HudBlock.connectionOutput = sm.interactable.connectionType.none
HudBlock.colorNormal = sm.color.new(0x000000ff)
HudBlock.colorHighlight = sm.color.new(0x303030ff)

local DEFAULT_POSITION_INDEX = 3
local POSITION_COUNT = 3
local HUD_UPDATE_INTERVAL_TICKS = 5
local SPEED_METERS_PER_SECOND_TO_KMH = 3.6

local FUEL_TANK_UUID = "f0a5db28-26f9-4cf9-a3d9-d75d5a0bf8c8"
local FIRE_DETECTOR_UUID = "91c22f4b-cd44-4b2f-9b68-a6b625a3ee8f"
local COUNTERMEASURE_DISPENSER_UUID = "7c31d534-f77c-4006-afe6-47c0573f1af2"
local PLAYER_LOCK_DETECTOR_UUID = "939a5048-b7d9-4c01-96bc-22337f4d9e08"
local FLIGHT_SENSOR_UUID = "c2f4a6d8-7b10-4e53-9c21-5f8a0d3b6e74"
local THRUST_CONTROLLER_UUID = "c81f2a4e-12d9-4ec6-8b33-1e61f230a403"
local FUEL_REGISTRY_PREFIX = "PlaneConstructFuelTank:"
local FIRE_REGISTRY_PREFIX = "PlaneConstructFireDetector:"
local COUNTERMEASURE_REGISTRY_PREFIX = "PlaneConstructCountermeasureDispenser:"
local PLAYER_LOCK_REGISTRY_PREFIX = "PlaneConstructPlayerLockDetector:"
local FLIGHT_SENSOR_REGISTRY_PREFIX = "PlaneConstructFlightSensor:"

local POSITION_SUFFIXES = {
    [1] = "TopLeft",
    [2] = "TopRight",
    [3] = "BottomMiddle"
}

local function clampPositionIndex(value)
    return math.max(1, math.min(POSITION_COUNT, math.floor((tonumber(value) or DEFAULT_POSITION_INDEX) + 0.5)))
end

local function getParentShapeUuid(parent)
    local shape = parent:getShape()
    if shape == nil or not sm.exists(shape) then return nil end
    return tostring(sm.shape.getShapeUuid(shape))
end

local function getCountermeasureModeData()
    return {
        chaff = { count = 0, remaining = 0, capacity = 0, unlimited = false },
        flare = { count = 0, remaining = 0, capacity = 0, unlimited = false }
    }
end

function HudBlock.server_onCreate(self)
    self:sv_initialize()
end

function HudBlock.server_onRefresh(self)
    self:sv_hidePreviousPlayer()
    self:sv_initialize()
end

function HudBlock.server_onDestroy(self)
    self:sv_hidePreviousPlayer()
end

function HudBlock.sv_initialize(self)
    local stored = self.storage:load()
    local positionIndex = DEFAULT_POSITION_INDEX
    if type(stored) == "table" then
        positionIndex = clampPositionIndex(stored.positionIndex)
    end

    self.sv = {
        positionIndex = positionIndex,
        lastPlayer = nil,
        lastPlayerId = nil,
        updateTicks = HUD_UPDATE_INTERVAL_TICKS
    }

    self.storage:save({ positionIndex = positionIndex })
    self:sv_syncClientData()
end

function HudBlock.sv_syncClientData(self)
    self.network:setClientData({ positionIndex = self.sv.positionIndex })
end

function HudBlock.sv_hidePreviousPlayer(self)
    if self.sv ~= nil and self.sv.lastPlayer ~= nil then
        self.network:sendToClient(self.sv.lastPlayer, "cl_hideHud")
    end
    if self.sv ~= nil then
        self.sv.lastPlayer = nil
        self.sv.lastPlayerId = nil
    end
end

function HudBlock.sv_getSeatPlayer(self)
    for _, parent in ipairs(self.interactable:getParents()) do
        if parent:hasOutputType(sm.interactable.connectionType.seated) then
            local character = parent:getSeatCharacter()
            if character ~= nil and sm.exists(character) and character:isPlayer() then
                return character:getPlayer()
            end
        end
    end
    return nil
end

function HudBlock.sv_getConnectedSources(self)
    local fuel = 0
    local fuelCapacity = 0
    local hasFuel = false
    local fuelKnown = false
    local hasFireDetector = false
    local fireDetected = false
    local hasCountermeasureDispenser = false
    local countermeasureKnown = true
    local countermeasureRemaining = 0
    local countermeasureCapacity = 0
    local countermeasureUnlimited = false
    local countermeasureModes = getCountermeasureModeData()
    local hasPlayerLockDetector = false
    local playerLockActive = false
    local playerLockKind = nil
    local flightSensors = {}
    local hasThrustController = false
    local thrustPercent = 0

    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.logic)) do
        local shapeUuid = getParentShapeUuid(parent)
        if shapeUuid == FUEL_TANK_UUID then
            hasFuel = true
            local data = _G[FUEL_REGISTRY_PREFIX .. tostring(parent:getId())]
            if type(data) == "table" then
                fuel = fuel + (tonumber(data.fuel) or 0)
                fuelCapacity = fuelCapacity + (tonumber(data.capacity) or 0)
                fuelKnown = true
            end
        elseif shapeUuid == FIRE_DETECTOR_UUID then
            hasFireDetector = true
            local data = _G[FIRE_REGISTRY_PREFIX .. tostring(parent:getId())]
            if type(data) == "table" and data.isDetectingFire == true then
                fireDetected = true
            elseif parent:isActive() then
                fireDetected = true
            end
        elseif shapeUuid == COUNTERMEASURE_DISPENSER_UUID then
            hasCountermeasureDispenser = true
            local countermeasureMode = "flare"
            local countermeasureData = _G[COUNTERMEASURE_REGISTRY_PREFIX .. tostring(parent:getId())]
            if type(countermeasureData) == "table" and countermeasureData.mode == "chaff" then
                countermeasureMode = "chaff"
            end
            countermeasureModes[countermeasureMode].count = countermeasureModes[countermeasureMode].count + 1
            if type(countermeasureData) == "table" then
                local modeData = countermeasureModes[countermeasureMode]
                if countermeasureData.limitEnabled == true then
                    local remaining = tonumber(countermeasureData.remaining) or 0
                    local capacity = tonumber(countermeasureData.capacity) or 0
                    countermeasureRemaining = countermeasureRemaining + remaining
                    countermeasureCapacity = countermeasureCapacity + capacity
                    modeData.remaining = modeData.remaining + remaining
                    modeData.capacity = modeData.capacity + capacity
                else
                    countermeasureUnlimited = true
                    countermeasureModes[countermeasureMode].unlimited = true
                end
            else
                countermeasureKnown = false
            end
        elseif shapeUuid == PLAYER_LOCK_DETECTOR_UUID then
            hasPlayerLockDetector = true
            local lockData = _G[PLAYER_LOCK_REGISTRY_PREFIX .. tostring(parent:getId())]
            if type(lockData) == "table" and lockData.lockActive == true then
                if lockData.lockKind == "controller" or playerLockKind == nil then
                    playerLockActive = true
                    playerLockKind = lockData.lockKind == "controller" and "controller" or "radar"
                end
            end
        elseif shapeUuid == FLIGHT_SENSOR_UUID then
            local sensorData = _G[FLIGHT_SENSOR_REGISTRY_PREFIX .. tostring(parent:getId())]
            if type(sensorData) == "table" and type(sensorData.metricKey) == "string" then
                -- Keep one entry for each sensor mode.  This makes it possible
                -- to connect all five modes without duplicating HUD rows.
                flightSensors[sensorData.metricKey] = {
                    threshold = tonumber(sensorData.threshold) or 0.0,
                    measuredValue = tonumber(sensorData.measuredValue) or 0.0,
                    active = sensorData.active == true
                }
            end
        end
    end

    -- Power connections are kept separate from the logic-source scan above.
    -- This lets the HUD accept the analog output of the thrust controller.
    for _, parent in ipairs(self.interactable:getParents(sm.interactable.connectionType.power)) do
        if getParentShapeUuid(parent) == THRUST_CONTROLLER_UUID then
            hasThrustController = true
            local thrustData = parent:getPublicData()
            local throttle = type(thrustData) == "table" and tonumber(thrustData.throttle) or nil
            throttle = throttle or tonumber(parent:getPower()) or 0
            thrustPercent = math.max(0, math.min(100, math.floor(throttle * 100 + 0.5)))
        end
    end

    if not hasCountermeasureDispenser then
        countermeasureKnown = false
    end

    return {
        hasFuel = hasFuel,
        fuelKnown = fuelKnown,
        fuel = fuel,
        fuelCapacity = fuelCapacity,
        hasFireDetector = hasFireDetector,
        fireDetected = fireDetected,
        hasCountermeasureDispenser = hasCountermeasureDispenser,
        countermeasureKnown = countermeasureKnown,
        countermeasureRemaining = countermeasureRemaining,
        countermeasureCapacity = countermeasureCapacity,
        countermeasureUnlimited = countermeasureUnlimited,
        countermeasureDispenserCount = countermeasureModes.chaff.count + countermeasureModes.flare.count,
        countermeasureChaffCount = countermeasureModes.chaff.count,
        countermeasureChaffRemaining = countermeasureModes.chaff.remaining,
        countermeasureChaffCapacity = countermeasureModes.chaff.capacity,
        countermeasureChaffUnlimited = countermeasureModes.chaff.unlimited,
        countermeasureFlareCount = countermeasureModes.flare.count,
        countermeasureFlareRemaining = countermeasureModes.flare.remaining,
        countermeasureFlareCapacity = countermeasureModes.flare.capacity,
        countermeasureFlareUnlimited = countermeasureModes.flare.unlimited,
        hasPlayerLockDetector = hasPlayerLockDetector,
        playerLockActive = playerLockActive,
        playerLockKind = playerLockKind,
        flightSensors = flightSensors,
        hasFlightSensor = next(flightSensors) ~= nil,
        hasThrustController = hasThrustController,
        thrustPercent = thrustPercent
    }
end

function HudBlock.sv_getHudData(self)
    local velocity = self.shape:getVelocity()
    local position = self.shape.worldPosition
    local sources = self:sv_getConnectedSources()

    return {
        positionIndex = self.sv.positionIndex,
        speedKmh = (velocity ~= nil and velocity:length() or 0) * SPEED_METERS_PER_SECOND_TO_KMH,
        heightMeters = position ~= nil and position.z or 0,
        hasFuel = sources.hasFuel,
        fuelKnown = sources.fuelKnown,
        fuel = sources.fuel,
        fuelCapacity = sources.fuelCapacity,
        hasFireDetector = sources.hasFireDetector,
        fireDetected = sources.fireDetected,
        hasCountermeasureDispenser = sources.hasCountermeasureDispenser,
        countermeasureKnown = sources.countermeasureKnown,
        countermeasureRemaining = sources.countermeasureRemaining,
        countermeasureCapacity = sources.countermeasureCapacity,
        countermeasureUnlimited = sources.countermeasureUnlimited,
        countermeasureDispenserCount = sources.countermeasureDispenserCount,
        countermeasureChaffCount = sources.countermeasureChaffCount,
        countermeasureChaffRemaining = sources.countermeasureChaffRemaining,
        countermeasureChaffCapacity = sources.countermeasureChaffCapacity,
        countermeasureChaffUnlimited = sources.countermeasureChaffUnlimited,
        countermeasureFlareCount = sources.countermeasureFlareCount,
        countermeasureFlareRemaining = sources.countermeasureFlareRemaining,
        countermeasureFlareCapacity = sources.countermeasureFlareCapacity,
        countermeasureFlareUnlimited = sources.countermeasureFlareUnlimited,
        hasPlayerLockDetector = sources.hasPlayerLockDetector,
        playerLockActive = sources.playerLockActive,
        playerLockKind = sources.playerLockKind,
        flightSensors = sources.flightSensors,
        hasFlightSensor = sources.hasFlightSensor,
        hasThrustController = sources.hasThrustController,
        thrustPercent = sources.thrustPercent
    }
end

function HudBlock.sv_sendHudData(self, player)
    if player ~= nil then
        self.network:sendToClient(player, "cl_updateHud", self:sv_getHudData())
    end
end

function HudBlock.server_onFixedUpdate(self, _)
    if self.sv == nil then return end

    local player = self:sv_getSeatPlayer()
    local playerId = player ~= nil and player:getId() or nil

    if playerId ~= self.sv.lastPlayerId then
        if self.sv.lastPlayer ~= nil then
            self.network:sendToClient(self.sv.lastPlayer, "cl_hideHud")
        end

        self.sv.lastPlayer = player
        self.sv.lastPlayerId = playerId
        self.sv.updateTicks = 0

        if player ~= nil then
            self:sv_sendHudData(player)
        end
        return
    end

    if player ~= nil then
        self.sv.updateTicks = self.sv.updateTicks + 1
        if self.sv.updateTicks >= HUD_UPDATE_INTERVAL_TICKS then
            self.sv.updateTicks = 0
            self:sv_sendHudData(player)
        end
    end
end

function HudBlock.sv_setPosition(self, requestedPosition)
    local positionIndex = clampPositionIndex(requestedPosition)
    if positionIndex == self.sv.positionIndex then return end

    self.sv.positionIndex = positionIndex
    self.storage:save({ positionIndex = positionIndex })
    self:sv_syncClientData()
end

function HudBlock.client_onCreate(self)
    self.cl = {
        positionIndex = DEFAULT_POSITION_INDEX,
        hud = nil,
        hudLayout = nil,
        hudData = nil,
        menu = nil,
        firePulseTime = 0.0,
        firePulseVisible = true
    }
end

function HudBlock.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self:client_onCreate()
    end

    self.cl.positionIndex = clampPositionIndex(data.positionIndex)
    self:cl_refreshMenu()
    self:cl_refreshHud()
end

function HudBlock.client_onDestroy(self)
    self:cl_destroyMenu()
    self:cl_destroyHud()
end

function HudBlock.client_onFixedUpdate(self, timeStep)
    if self.cl == nil or self.cl.hud == nil or self.cl.hudData == nil then return end
    if self.cl.hudData.hasFireDetector ~= true or self.cl.hudData.fireDetected ~= true then
        self.cl.firePulseTime = 0.0
        self.cl.firePulseVisible = true
        return
    end

    self.cl.firePulseTime = (self.cl.firePulseTime + (timeStep or 0.025)) % (1.0 / 3.0)
    self.cl.firePulseVisible = self.cl.firePulseTime < (1.0 / 6.0)
    self:cl_refreshFireIcon()
end

function HudBlock.cl_refreshFireIcon(self)
    if self.cl == nil or self.cl.hud == nil or self.cl.hudData == nil then return end
    local active = self.cl.hudData.hasFireDetector == true and self.cl.hudData.fireDetected == true
    for _, suffix in ipairs(POSITION_SUFFIXES) do
        self.cl.hud:setVisible("FireIconOff" .. suffix, false)
        self.cl.hud:setVisible("FireIconOn" .. suffix, active and self.cl.firePulseVisible and self.cl.positionIndex == ({TopLeft=1, TopRight=2, BottomMiddle=3})[suffix])
    end
end

function HudBlock.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_hud"))
    return true
end

function HudBlock.client_onInteract(self, _, state)
    if not state then return end

    self:cl_destroyMenu()
    self.cl.menu = sm.gui.createGuiFromLayout(
        PC_L.layout("HudBlockMenu.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.menu:setButtonCallback("TopLeftButton", "cl_onTopLeftPressed")
    self.cl.menu:setButtonCallback("TopRightButton", "cl_onTopRightPressed")
    self.cl.menu:setButtonCallback("BottomMiddleButton", "cl_onBottomMiddlePressed")
    self.cl.menu:setOnCloseCallback("cl_onMenuClosed")
    self:cl_refreshMenu()
    self.cl.menu:open()
end

function HudBlock.cl_setPosition(self, positionIndex)
    self.cl.positionIndex = clampPositionIndex(positionIndex)
    self:cl_refreshMenu()
    self:cl_refreshHud()
    self.network:sendToServer("sv_setPosition", self.cl.positionIndex)
end

function HudBlock.cl_onTopLeftPressed(self)
    self:cl_setPosition(1)
end

function HudBlock.cl_onTopRightPressed(self)
    self:cl_setPosition(2)
end

function HudBlock.cl_onBottomMiddlePressed(self)
    self:cl_setPosition(3)
end

function HudBlock.cl_refreshMenu(self)
    if self.cl == nil or self.cl.menu == nil then return end
    self.cl.menu:setButtonState("TopLeftButton", self.cl.positionIndex == 1)
    self.cl.menu:setButtonState("TopRightButton", self.cl.positionIndex == 2)
    self.cl.menu:setButtonState("BottomMiddleButton", self.cl.positionIndex == 3)
end

function HudBlock.cl_shouldUseCompactHud(self)
    local data = self.cl.hudData or {}
    local sensors = type(data.flightSensors) == "table" and data.flightSensors or {}
    local hasDetailedSensor = sensors.roll ~= nil or sensors.pitch ~= nil or sensors.gforce ~= nil
    return not data.hasFuel
        and not data.hasFireDetector
        and not data.hasCountermeasureDispenser
        and not data.hasPlayerLockDetector
        and not hasDetailedSensor
end

function HudBlock.cl_ensureHud(self)
    local hasFireDetector = self.cl.hudData ~= nil and self.cl.hudData.hasFireDetector == true
    local data = self.cl.hudData or {}
    local hasShortNoFireHud = not hasFireDetector
        and not (data.hasFuel == true)
        and not (data.hasCountermeasureDispenser == true)
        and not (data.hasPlayerLockDetector == true)
    local isBottomPosition = self.cl.positionIndex == 3
    local desiredLayout = isBottomPosition
        and (hasFireDetector and "full" or (hasShortNoFireHud and "nofire-short" or "nofire"))
        or "top-vertical"
    if self.cl.hud ~= nil and self.cl.hudLayout == desiredLayout then return end

    if self.cl.hud ~= nil then
        self.cl.hud:close()
        self.cl.hud:destroy()
        self.cl.hud = nil
    end

    local layoutName = isBottomPosition
        and (hasFireDetector and "HudBlockHud.layout" or (hasShortNoFireHud and "HudBlockHudNoFireShort.layout" or "HudBlockHudNoFire.layout"))
        or "HudBlockHudTop.layout"
    self.cl.hud = sm.gui.createGuiFromLayout(
        PC_L.layout(layoutName),
        false,
        { isHud = true, isInteractive = false, needsCursor = false }
    )
    self.cl.hudLayout = desiredLayout
end

function HudBlock.cl_updateHud(self, data)
    if self.cl == nil then
        self:client_onCreate()
    end

    self.cl.hudData = data or {}
    self.cl.positionIndex = clampPositionIndex(self.cl.hudData.positionIndex)
    self:cl_ensureHud()
    self:cl_refreshHud()
    if not self.cl.hud:isActive() then
        self.cl.hud:open()
    end
end

function HudBlock.cl_hideHud(self)
    if self.cl ~= nil and self.cl.hud ~= nil and self.cl.hud:isActive() then
        self.cl.hud:close()
    end
    if self.cl ~= nil then
        self.cl.hudData = nil
    end
end

function HudBlock.cl_refreshHud(self)
    if self.cl == nil or self.cl.hud == nil or self.cl.hudData == nil then return end

    local data = self.cl.hudData
    local positionIndex = clampPositionIndex(self.cl.positionIndex)
    local speed = tonumber(data.speedKmh) or 0
    local height = tonumber(data.heightMeters) or 0
    local fuel = tonumber(data.fuel) or 0
    local fuelCapacity = tonumber(data.fuelCapacity) or 0
    local hasFuel = data.hasFuel == true
    local fuelKnown = data.fuelKnown == true
    local hasFireDetector = data.hasFireDetector == true
    local fireDetected = data.fireDetected == true
    local hasCountermeasureDispenser = data.hasCountermeasureDispenser == true
    local countermeasureKnown = data.countermeasureKnown == true
    local countermeasureRemaining = tonumber(data.countermeasureRemaining) or 0
    local countermeasureCapacity = tonumber(data.countermeasureCapacity) or 0
    local countermeasureUnlimited = data.countermeasureUnlimited == true
    local countermeasureDispenserCount = tonumber(data.countermeasureDispenserCount) or 0
    local countermeasureChaffCount = tonumber(data.countermeasureChaffCount) or 0
    local countermeasureChaffRemaining = tonumber(data.countermeasureChaffRemaining) or 0
    local countermeasureChaffCapacity = tonumber(data.countermeasureChaffCapacity) or 0
    local countermeasureChaffUnlimited = data.countermeasureChaffUnlimited == true
    local countermeasureFlareCount = tonumber(data.countermeasureFlareCount) or 0
    local countermeasureFlareRemaining = tonumber(data.countermeasureFlareRemaining) or 0
    local countermeasureFlareCapacity = tonumber(data.countermeasureFlareCapacity) or 0
    local countermeasureFlareUnlimited = data.countermeasureFlareUnlimited == true
    local hasPlayerLockDetector = data.hasPlayerLockDetector == true
    local playerLockActive = data.playerLockActive == true
    local playerLockKind = data.playerLockKind
    local flightSensors = type(data.flightSensors) == "table" and data.flightSensors or {}
    local speedSensor = flightSensors.speed
    local altitudeSensor = flightSensors.altitude
    local rollSensor = flightSensors.roll
    local pitchSensor = flightSensors.pitch
    local gforceSensor = flightSensors.gforce
    local hasFlightSensor = data.hasFlightSensor == true
    local hasDetailedFlightSensor = rollSensor ~= nil or pitchSensor ~= nil or gforceSensor ~= nil
    local hasConnectedSource = hasFuel or hasFireDetector or hasCountermeasureDispenser or hasPlayerLockDetector or hasDetailedFlightSensor

    for index, suffix in ipairs(POSITION_SUFFIXES) do
        local isActivePosition = index == positionIndex
        self.cl.hud:setVisible("HudPanelSmall" .. suffix, isActivePosition and not hasConnectedSource)
        self.cl.hud:setVisible("HudPanelFull" .. suffix, isActivePosition and hasConnectedSource)
        local smallSpeedText = speedSensor
            and PC_L.get("speed", speedSensor.measuredValue)
            or PC_L.get("speed", speed)
        local smallHeightText = altitudeSensor
            and PC_L.get("height", altitudeSensor.measuredValue)
            or PC_L.get("height", height)
        self.cl.hud:setText("SpeedValueSmall" .. suffix, smallSpeedText)
        self.cl.hud:setText("HeightValueSmall" .. suffix, smallHeightText)
        local speedText = speedSensor
            and PC_L.get("speed", speedSensor.measuredValue)
            or PC_L.get("speed", speed)
        local heightText = altitudeSensor
            and PC_L.get("height", altitudeSensor.measuredValue)
            or PC_L.get("height", height)
        local fuelText = hasFuel and (fuelKnown
            and PC_L.get("fuel", fuel, fuelCapacity)
            or PC_L.get("fuel_empty")) or nil
        self.cl.hud:setText("SpeedValueFull" .. suffix, speedText)
        self.cl.hud:setText("HeightValueFull" .. suffix, heightText)
        self.cl.hud:setVisible("HeightValueFull" .. suffix, true)
        self.cl.hud:setVisible("FuelValueFull" .. suffix, hasFuel)
        self.cl.hud:setVisible("FireIconOff" .. suffix, hasFireDetector and not fireDetected)
        self.cl.hud:setVisible("FireIconOn" .. suffix, hasFireDetector and fireDetected and self.cl.firePulseVisible)

        local sensorText = {}
        if rollSensor then
            sensorText[#sensorText + 1] = PC_L.get("roll", rollSensor.measuredValue)
        end
        if pitchSensor then
            sensorText[#sensorText + 1] = PC_L.get("pitch", pitchSensor.measuredValue)
        end
        if gforceSensor then
            sensorText[#sensorText + 1] = PC_L.get("g_force", gforceSensor.measuredValue)
        end
        if hasCountermeasureDispenser then
            sensorText[#sensorText + 1] = "CM: " .. (countermeasureKnown and "OK" or "--")
        end
        if hasPlayerLockDetector then
            sensorText[#sensorText + 1] = playerLockActive and "Lock: Active" or "Lock: Clear"
        end
        self.cl.hud:setText("RollValueFull" .. suffix, rollSensor and PC_L.get("roll", rollSensor.measuredValue) or "")
        self.cl.hud:setText("PitchValueFull" .. suffix, pitchSensor and PC_L.get("pitch", pitchSensor.measuredValue) or "")
        self.cl.hud:setText("GValueFull" .. suffix, gforceSensor and PC_L.get("g_force", gforceSensor.measuredValue) or "")
        self.cl.hud:setVisible("RollValueFull" .. suffix, rollSensor ~= nil)
        self.cl.hud:setVisible("PitchValueFull" .. suffix, pitchSensor ~= nil)
        self.cl.hud:setVisible("GValueFull" .. suffix, gforceSensor ~= nil)
        self.cl.hud:setText("FlightSensorValueFull" .. suffix, table.concat(sensorText, "     "))
        self.cl.hud:setVisible("FlightSensorValueFull" .. suffix, false)

        if hasFuel and fuelKnown then
            self.cl.hud:setText("FuelValueFull" .. suffix, PC_L.get("fuel", fuel, fuelCapacity))
        else
            self.cl.hud:setText("FuelValueFull" .. suffix, PC_L.get("fuel_empty"))
        end

        if hasCountermeasureDispenser and countermeasureKnown then
            if countermeasureDispenserCount > 1 and countermeasureChaffCount > 0 and countermeasureFlareCount > 0 then
                local chaffValue = "--"
                local flareValue = "--"
                if countermeasureChaffCount > 0 then
                    chaffValue = countermeasureChaffUnlimited and "Unlimited" or string.format("%.0f", countermeasureChaffRemaining)
                end
                if countermeasureFlareCount > 0 then
                    flareValue = countermeasureFlareUnlimited and "Unlimited" or string.format("%.0f", countermeasureFlareRemaining)
                end
                self.cl.hud:setText(
                    "CountermeasureValueFull" .. suffix,
                    "Chaff: " .. chaffValue .. "   Flare: " .. flareValue
                )
            elseif countermeasureChaffCount > 0 then
                if countermeasureChaffUnlimited then
                    self.cl.hud:setText("CountermeasureValueFull" .. suffix, "Chaff: Unlimited")
                else
                    self.cl.hud:setText(
                        "CountermeasureValueFull" .. suffix,
                        string.format("Chaff: %.0f / %.0f", countermeasureChaffRemaining, countermeasureChaffCapacity)
                    )
                end
            elseif countermeasureFlareCount > 0 then
                if countermeasureFlareUnlimited then
                    self.cl.hud:setText("CountermeasureValueFull" .. suffix, "Flare: Unlimited")
                else
                    self.cl.hud:setText(
                        "CountermeasureValueFull" .. suffix,
                        string.format("Flare: %.0f / %.0f", countermeasureFlareRemaining, countermeasureFlareCapacity)
                    )
                end
            elseif countermeasureUnlimited then
                self.cl.hud:setText("CountermeasureValueFull" .. suffix, "Countermeasures: Unlimited")
            else
                self.cl.hud:setText(
                    "CountermeasureValueFull" .. suffix,
                    string.format(
                        "Countermeasures: %.0f / %.0f",
                        countermeasureRemaining,
                        countermeasureCapacity
                    )
                )
            end
        else
            self.cl.hud:setText("CountermeasureValueFull" .. suffix, "Countermeasures: --")
        end

        if hasPlayerLockDetector then
            local lockText = "Lock: Clear"
            if playerLockActive then
                lockText = playerLockKind == "controller" and "Lock: Controller" or "Lock: Radar"
            end
            self.cl.hud:setText("LockValueFull" .. suffix, lockText)
        else
            self.cl.hud:setText("LockValueFull" .. suffix, "Lock: --")
        end

        self.cl.hud:setVisible("CountermeasureValueFull" .. suffix, false)
        self.cl.hud:setVisible("LockValueFull" .. suffix, false)
    end
end

function HudBlock.cl_destroyMenu(self)
    if self.cl ~= nil and self.cl.menu ~= nil then
        self.cl.menu:close()
        self.cl.menu:destroy()
        self.cl.menu = nil
    end
end

function HudBlock.cl_destroyHud(self)
    if self.cl ~= nil and self.cl.hud ~= nil then
        self.cl.hud:close()
        self.cl.hud:destroy()
        self.cl.hud = nil
        self.cl.hudLayout = nil
    end
end

function HudBlock.cl_onMenuClosed(self)
    self:cl_destroyMenu()
end
