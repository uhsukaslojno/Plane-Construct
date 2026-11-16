dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneConstructFlightSensor = class()

PlaneConstructFlightSensor.maxParentCount = 0
PlaneConstructFlightSensor.maxChildCount = -1
PlaneConstructFlightSensor.connectionInput = sm.interactable.connectionType.none
PlaneConstructFlightSensor.connectionOutput = sm.interactable.connectionType.logic
PlaneConstructFlightSensor.colorNormal = sm.color.new(0x11a7c7ff)
PlaneConstructFlightSensor.colorHighlight = sm.color.new(0x63e5ffff)

local TICKS_PER_SECOND = 40.0
-- Scrap Mechanic physics uses metres, while the sensor UI uses game blocks.
-- One building block is 0.25 m, so one physics metre equals four blocks.
local PHYSICS_METERS_PER_BLOCK = 0.25
local PHYSICS_METERS_TO_KMH = 3.6
local MAX_SPEED_KMH = 3000.0
local DEFAULT_METRIC = "speed"
local DEFAULT_THRESHOLD = 100.0
local DEFAULT_DELAY_TICKS = 0
local MIN_DELAY_TICKS = 0
local MAX_DELAY_TICKS = 2400
local GRAVITY_ACCELERATION = 10.0
local ALTITUDE_RAY_LENGTH = 1000.0
local ALTITUDE_SAMPLE_INTERVAL_TICKS = 8
local THRESHOLD_SLIDER_STEPS = 1000
local CLOSE_INPUT_GUARD_TICKS = 5
local BREAKABLE_WING_UUID = "f1a2b3c4-d5e6-4789-9012-3456789abcde"
local SENSOR_REGISTRY_PREFIX = "PlaneConstructFlightSensor:"

local METRICS = {
    {
        key = "speed",
        label = "Speed",
        unit = "km/h",
        minimum = 0.0,
        maximum = MAX_SPEED_KMH,
        step = 1.0
    },
    {
        key = "altitude",
        label = "Altitude above tile",
        unit = "blocks",
        minimum = 0.0,
        maximum = 1000.0,
        step = 1.0
    },
    {
        key = "roll",
        label = "Roll angle",
        unit = "degrees",
        minimum = 0.0,
        maximum = 180.0,
        step = 1.0
    },
    {
        key = "pitch",
        label = "Pitch angle",
        unit = "degrees",
        minimum = 0.0,
        maximum = 180.0,
        step = 1.0
    },
    {
        key = "gforce",
        label = "G-force",
        unit = "G",
        minimum = 0.0,
        maximum = 20.0,
        step = 0.1
    },
    {
        key = "turnRate",
        label = PC_L.get("flight_sensor_turn_rate"),
        unit = "degrees/s",
        minimum = -1000.0,
        maximum = 1000.0,
        step = 1.0
    }
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function clampInteger(value, minimum, maximum)
    return math.floor(clamp(tonumber(value) or minimum, minimum, maximum) + 0.5)
end

local function getMetric(metricKey)
    for _, metric in ipairs(METRICS) do
        if metric.key == metricKey then
            return metric
        end
    end
    return METRICS[1]
end

local function getMetricIndex(metricKey)
    for index, metric in ipairs(METRICS) do
        if metric.key == metricKey then
            return index
        end
    end
    return 1
end

local function clampThreshold(metricKey, value)
    local metric = getMetric(metricKey)
    if metric.step == 0.1 then
        return math.floor(clamp(tonumber(value) or metric.minimum, metric.minimum, metric.maximum) * 10.0 + 0.5) / 10.0
    end
    return clampInteger(value, metric.minimum, metric.maximum)
end

local function thresholdToSliderPosition(metricKey, value)
    local metric = getMetric(metricKey)
    local span = metric.maximum - metric.minimum
    if span <= 0.0 then return 0 end
    local threshold = clampThreshold(metricKey, value)
    return clampInteger(
        (threshold - metric.minimum) / span * THRESHOLD_SLIDER_STEPS,
        0,
        THRESHOLD_SLIDER_STEPS
    )
end

local function sliderPositionToThreshold(metricKey, sliderPosition)
    local metric = getMetric(metricKey)
    local normalized = clamp(
        (tonumber(sliderPosition) or 0.0) / THRESHOLD_SLIDER_STEPS,
        0.0,
        1.0
    )
    return clampThreshold(
        metricKey,
        metric.minimum + normalized * (metric.maximum - metric.minimum)
    )
end

local function getShapeVelocity(shape)
    -- On the server, getVelocity() is the authoritative rigid-body velocity.
    -- The .velocity property can be stale for a shape attached to a vehicle.
    local velocity = shape:getVelocity()
    if velocity == nil then
        velocity = shape.velocity
    end
    return velocity or sm.vec3.new(0.0, 0.0, 0.0)
end

local function getSpeed(shape)
    return clamp(
        getShapeVelocity(shape):length() * PHYSICS_METERS_TO_KMH,
        0.0,
        MAX_SPEED_KMH
    )
end

local function getAltitudeAboveTile(shape)
    local position = shape.worldPosition
    local rayStart = position
    local rayEnd = rayStart - sm.vec3.new(0.0, 0.0, ALTITUDE_RAY_LENGTH)
    local hit, result = sm.physics.raycast(
        rayStart,
        rayEnd,
        shape:getBody(),
        sm.physics.filter.terrainSurface
    )
    if hit and result and result.pointWorld then
        return clamp(rayStart.z - result.pointWorld.z, 0.0, ALTITUDE_RAY_LENGTH)
    end
    return ALTITUDE_RAY_LENGTH
end

local function getRollAngle(shape)
    -- Signed bank angle: 0 is level, +90 is right bank, -90 is left bank,
    -- and 180 is inverted.  This is independent of pitch.
    local rightZ = shape:getRight().z
    local upZ = shape:getAt().z
    return clamp(math.abs(math.deg(math.atan2(rightZ, upZ))), 0.0, 180.0)
end

local function getPitchAngle(shape)
    -- Build a horizontal forward axis from the body's horizontal right axis.
    -- This keeps pitch independent of yaw and roll and preserves the
    -- backwards-facing half of the circle.
    local forward = shape:getUp()
    local right = shape:getRight()
    local worldUp = sm.vec3.new(0.0, 0.0, 1.0)
    local horizontalRight = right - worldUp * right.z
    local horizontalRightLength = horizontalRight:length()
    if horizontalRightLength <= 0.0001 then return 0.0 end
    horizontalRight = horizontalRight / horizontalRightLength
    local levelForward = horizontalRight:cross(worldUp)
    local levelForwardLength = levelForward:length()
    if levelForwardLength <= 0.0001 then return 0.0 end
    levelForward = levelForward / levelForwardLength
    local angle = math.deg(math.atan2(forward:dot(worldUp), forward:dot(levelForward)))
    return clamp(math.abs(angle), 0.0, 180.0)
end

local function getHorizontalTurnRate(shape)
    local body = shape:getBody()
    if body == nil then return 0.0 end

    local angularVelocity = body:getAngularVelocity()
    if angularVelocity == nil then return 0.0 end

    -- Project angular velocity onto the world's vertical axis. This leaves
    -- only the horizontal/yaw component and reports signed degrees per second.
    local worldUp = sm.vec3.new(0.0, 0.0, 1.0)
    -- The engine's positive yaw direction is opposite to the direction used
    -- by the sensor controls, so invert the projection for intuitive signs.
    return clamp(-math.deg(angularVelocity:dot(worldUp)), -1000.0, 1000.0)
end

local function isTurnRateThresholdReached(measuredValue, threshold)
    if threshold > 0.0 then
        -- Positive threshold selects positive rotation and acts as an upper
        -- limit: keep the signal while the rate has not exceeded it.
        return measuredValue >= 0.0 and measuredValue <= threshold
    elseif threshold < 0.0 then
        -- Negative threshold selects negative rotation and mirrors the same
        -- upper-limit behavior by magnitude.
        return measuredValue <= 0.0 and measuredValue >= threshold
    end
    -- A zero threshold means any actual horizontal rotation.
    return math.abs(measuredValue) > 0.001
end

function PlaneConstructFlightSensor.sv_setActive(self, active)
    if self.sv.outputActive == active then return end
    self.sv.outputActive = active
    self.interactable:setActive(active)
end

function PlaneConstructFlightSensor.sv_syncRegistry(self, measuredValue)
    if self.sv == nil or self.interactable == nil then return end
    _G[SENSOR_REGISTRY_PREFIX .. tostring(self.interactable:getId())] = {
        metricKey = self.sv.metricKey,
        threshold = self.sv.threshold,
        measuredValue = tonumber(measuredValue) or 0.0,
        active = self.sv.outputActive == true
    }
end

function PlaneConstructFlightSensor.sv_resetCycle(self)
    self.sv.cycleTicks = 0
    self:sv_setActive(false)
end

function PlaneConstructFlightSensor.sv_measureGForce(self, timeStep)
    local velocity = getShapeVelocity(self.shape)
    local previousVelocity = self.sv.previousVelocity or velocity
    local deltaTime = math.max(tonumber(timeStep) or (1.0 / TICKS_PER_SECOND), 0.001)
    local acceleration = (velocity - previousVelocity) / deltaTime
    local gravity = sm.vec3.new(0.0, 0.0, -GRAVITY_ACCELERATION)
    local properAcceleration = acceleration - gravity
    self.sv.previousVelocity = velocity
    return clamp(properAcceleration:length() / GRAVITY_ACCELERATION, 0.0, 20.0)
end

function PlaneConstructFlightSensor.sv_measure(self, timeStep)
    local metricKey = self.sv.metricKey
    if metricKey == "speed" then
        return getSpeed(self.shape)
    elseif metricKey == "altitude" then
        -- A 1000-block physics ray every fixed tick is unnecessarily expensive
        -- and can destabilize the native physics thread.  Keep the last value
        -- between samples; eight ticks is still five altitude checks per second.
        if self.sv.altitudeSampleTicks > 0 then
            self.sv.altitudeSampleTicks = self.sv.altitudeSampleTicks - 1
            return self.sv.altitudeValue
        end
        self.sv.altitudeValue = getAltitudeAboveTile(self.shape)
        self.sv.altitudeSampleTicks = ALTITUDE_SAMPLE_INTERVAL_TICKS - 1
        return self.sv.altitudeValue
    elseif metricKey == "roll" then
        return getPitchAngle(self.shape)
    elseif metricKey == "pitch" then
        return getRollAngle(self.shape)
    elseif metricKey == "gforce" then
        return self:sv_measureGForce(timeStep)
    elseif metricKey == "turnRate" then
        return getHorizontalTurnRate(self.shape)
    end
    return 0.0
end

function PlaneConstructFlightSensor.sv_hasBreakableWing(self)
    for _, child in ipairs(self.interactable:getChildren(sm.interactable.connectionType.logic)) do
        local childShape = child:getShape()
        if childShape and tostring(sm.shape.getShapeUuid(childShape)) == BREAKABLE_WING_UUID then
            return true
        end
    end
    return false
end

function PlaneConstructFlightSensor.sv_updateBreakableWingConnection(self)
    local connected = self:sv_hasBreakableWing()
    if connected == self.sv.breakableWingConnected then return end

    self.sv.breakableWingConnected = connected
    self.sv.cycleTicks = 0
    self:sv_setActive(false)

    if connected then
        self.sv.metricKey = "gforce"
        self.sv.threshold = clampThreshold("gforce", self.sv.threshold)
    end

    self:sv_saveAndSync()
end

function PlaneConstructFlightSensor.sv_saveAndSync(self)
    self.storage:save({
        metricKey = self.sv.metricKey,
        threshold = self.sv.threshold,
        delayTicks = self.sv.delayTicks
    })
    self.network:setClientData({
        metricKey = self.sv.metricKey,
        threshold = self.sv.threshold,
        delayTicks = self.sv.delayTicks,
        breakableWingConnected = self.sv.breakableWingConnected == true
    })
end

function PlaneConstructFlightSensor.sv_initialize(self)
    local stored = self.storage:load()
    stored = type(stored) == "table" and stored or {}

    local metricKey = getMetric(stored.metricKey).key
    local threshold = clampThreshold(metricKey, stored.threshold or DEFAULT_THRESHOLD)
    local delayTicks = clampInteger(stored.delayTicks or DEFAULT_DELAY_TICKS, MIN_DELAY_TICKS, MAX_DELAY_TICKS)

    self.sv = {
        metricKey = metricKey,
        threshold = threshold,
        delayTicks = delayTicks,
        cycleTicks = 0,
        outputActive = false,
        previousVelocity = getShapeVelocity(self.shape),
        altitudeSampleTicks = 0,
        altitudeValue = ALTITUDE_RAY_LENGTH,
        breakableWingConnected = false
    }

    self.interactable:setActive(false)
    self:sv_syncRegistry(0.0)
    self:sv_saveAndSync()
end

function PlaneConstructFlightSensor.server_onCreate(self)
    self:sv_initialize()
end

function PlaneConstructFlightSensor.server_onRefresh(self)
    self:sv_initialize()
end

function PlaneConstructFlightSensor.server_onDestroy(self)
    if self.interactable ~= nil then
        _G[SENSOR_REGISTRY_PREFIX .. tostring(self.interactable:getId())] = nil
    end
    if self.sv and sm.exists(self.interactable) then
        self.interactable:setActive(false)
    end
end

function PlaneConstructFlightSensor.sv_setMetric(self, requestedMetric)
    if type(requestedMetric) ~= "string" or getMetric(requestedMetric).key ~= requestedMetric then return end
    if self.sv.breakableWingConnected then return end
    if self.sv.metricKey == requestedMetric then return end

    self.sv.metricKey = requestedMetric
    self.sv.threshold = clampThreshold(requestedMetric, self.sv.threshold)
    self.sv.previousVelocity = getShapeVelocity(self.shape)
    self.sv.altitudeSampleTicks = 0
    self.sv.altitudeValue = ALTITUDE_RAY_LENGTH
    self:sv_resetCycle()
    self:sv_saveAndSync()
end

function PlaneConstructFlightSensor.sv_setThreshold(self, requestedThreshold)
    local threshold = clampThreshold(self.sv.metricKey, requestedThreshold)
    if threshold == self.sv.threshold then return end

    self.sv.threshold = threshold
    self:sv_resetCycle()
    self:sv_saveAndSync()
end

function PlaneConstructFlightSensor.sv_setDelayTicks(self, requestedDelay)
    local delayTicks = clampInteger(requestedDelay, MIN_DELAY_TICKS, MAX_DELAY_TICKS)
    if delayTicks == self.sv.delayTicks then return end

    self.sv.delayTicks = delayTicks
    self:sv_resetCycle()
    self:sv_saveAndSync()
end

function PlaneConstructFlightSensor.server_onFixedUpdate(self, timeStep)
    self:sv_updateBreakableWingConnection()
    local measuredValue = self:sv_measure(timeStep)
    self:sv_syncRegistry(measuredValue)
    local detected
    if self.sv.breakableWingConnected then
        -- When connected to the breakable wing, delay is the continuous
        -- overload time before the wing is destroyed. The output stays off
        -- until that time has elapsed, then remains active.
        detected = measuredValue >= self.sv.threshold
        if not detected then
            self:sv_resetCycle()
            return
        end
        if self.sv.delayTicks == 0 then
            self:sv_setActive(true)
            return
        end
        self.sv.cycleTicks = self.sv.cycleTicks + 1
        if self.sv.cycleTicks >= self.sv.delayTicks then
            self.sv.cycleTicks = 0
            self:sv_setActive(true)
        end
        return
    elseif self.sv.metricKey == "altitude" then
        -- For altitude, the sensor is active when the ground is closer than
        -- the configured threshold.
        detected = measuredValue <= self.sv.threshold
    elseif self.sv.metricKey == "turnRate" then
        -- Positive and negative thresholds select opposite rotation directions.
        detected = isTurnRateThresholdReached(measuredValue, self.sv.threshold)
    else
        detected = measuredValue >= self.sv.threshold
    end

    if not detected then
        self:sv_resetCycle()
        return
    end

    if self.sv.delayTicks == 0 then
        self.sv.cycleTicks = 0
        self:sv_setActive(true)
        return
    end

    self.sv.cycleTicks = self.sv.cycleTicks + 1
    if self.sv.cycleTicks >= self.sv.delayTicks then
        self.sv.cycleTicks = 0
        if self.sv.metricKey == "turnRate" then
            -- For turn rate, delay is only an activation delay. Once the
            -- threshold is reached, keep the output active until it drops.
            self:sv_setActive(true)
        else
            self:sv_setActive(not self.sv.outputActive)
        end
    end
end

function PlaneConstructFlightSensor.client_onCreate(self)
    self.cl = {
        metricKey = DEFAULT_METRIC,
        threshold = DEFAULT_THRESHOLD,
        delayTicks = DEFAULT_DELAY_TICKS,
        gui = nil,
        interactionHeld = false,
        closeInputGuardTicks = 0,
        breakableWingConnected = false
    }
end

function PlaneConstructFlightSensor.client_onFixedUpdate(self)
    if self.cl == nil then return end
    if self.cl.closeInputGuardTicks > 0 then
        self.cl.closeInputGuardTicks = self.cl.closeInputGuardTicks - 1
    end
end

function PlaneConstructFlightSensor.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self:client_onCreate()
    end

    self.cl.breakableWingConnected = data.breakableWingConnected == true
    self.cl.metricKey = getMetric(data.metricKey).key
    if self.cl.breakableWingConnected then
        self.cl.metricKey = "gforce"
    end
    self.cl.threshold = clampThreshold(self.cl.metricKey, data.threshold)
    self.cl.delayTicks = clampInteger(data.delayTicks or DEFAULT_DELAY_TICKS, MIN_DELAY_TICKS, MAX_DELAY_TICKS)
    self:cl_refreshGui()
end

function PlaneConstructFlightSensor.client_onDestroy(self)
    if self.cl then
        local gui = self.cl.gui
        self.cl.gui = nil
        if gui then
            gui:close()
            gui:destroy()
        end
    end
end

function PlaneConstructFlightSensor.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_flight_sensor"))
    return true
end

function PlaneConstructFlightSensor.cl_metricOptions(self)
    local options = {}
    if self.cl.breakableWingConnected then
        return { "G-force (locked)" }
    end
    for _, metric in ipairs(METRICS) do
        options[#options + 1] = metric.label
    end
    return options
end

function PlaneConstructFlightSensor.cl_openGui(self)
    if self.cl.gui then return end

    local metric = getMetric(self.cl.metricKey)
    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructFlightSensor.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createDropDown("MetricDropDown", "cl_onMetricSelected", self:cl_metricOptions())
    self.cl.gui:createHorizontalSlider(
        "ThresholdSlider",
        THRESHOLD_SLIDER_STEPS + 1,
        thresholdToSliderPosition(self.cl.metricKey, self.cl.threshold),
        "cl_onThresholdChanged"
    )
    self.cl.gui:createHorizontalSlider(
        "DelaySlider",
        MAX_DELAY_TICKS - MIN_DELAY_TICKS + 1,
        self.cl.delayTicks - MIN_DELAY_TICKS,
        "cl_onDelayChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneConstructFlightSensor.client_onInteract(self, _, state)
    if self.cl == nil then self:client_onCreate() end
    if not state then
        self.cl.interactionHeld = false
        return
    end
    if self.cl.interactionHeld then return end
    self.cl.interactionHeld = true
    if self.cl.closeInputGuardTicks > 0 or self.cl.gui then return end
    self:cl_openGui()
end

function PlaneConstructFlightSensor.cl_onMetricSelected(self, selectedOption)
    -- Scrap Mechanic can pass either the numeric item index or the selected
    -- caption, depending on the UI build.  Handle both forms; otherwise every
    -- caption is converted to nil and the sensor silently stays on Speed.
    if type(selectedOption) == "table" then
        selectedOption = selectedOption.value or selectedOption.label or selectedOption.name or selectedOption[1]
    end

    if self.cl.breakableWingConnected then
        self.cl.metricKey = "gforce"
        self.cl.threshold = clampThreshold("gforce", self.cl.threshold)
        self:cl_refreshGui()
        return
    end

    local metric = nil
    local numericOption = tonumber(selectedOption)
    if numericOption ~= nil then
        metric = METRICS[clampInteger(numericOption, 1, #METRICS)]
    else
        for _, candidate in ipairs(METRICS) do
            if selectedOption == candidate.label or selectedOption == candidate.key then
                metric = candidate
                break
            end
        end
    end

    if metric == nil then return end

    self.cl.metricKey = metric.key
    self.cl.threshold = clampThreshold(metric.key, self.cl.threshold)
    self.network:sendToServer("sv_setMetric", self.cl.metricKey)
    self.network:sendToServer("sv_setThreshold", self.cl.threshold)
    -- Do not destroy/recreate the GUI from inside the dropdown callback.  The
    -- old implementation caused invalid scriptRef errors when the callback
    -- queue still contained events for the closing GUI.
    self:cl_refreshGui()
end

function PlaneConstructFlightSensor.cl_onThresholdChanged(self, sliderPosition)
    local metric = getMetric(self.cl.metricKey)
    self.cl.threshold = sliderPositionToThreshold(self.cl.metricKey, sliderPosition)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setThreshold", self.cl.threshold)
end

function PlaneConstructFlightSensor.cl_onDelayChanged(self, sliderPosition)
    self.cl.delayTicks = clampInteger(sliderPosition + MIN_DELAY_TICKS, MIN_DELAY_TICKS, MAX_DELAY_TICKS)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDelayTicks", self.cl.delayTicks)
end

function PlaneConstructFlightSensor.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end

    local metric = getMetric(self.cl.metricKey)
    local thresholdFormat = metric.step == 0.1 and "%.1f" or "%d"
    local metricLabel = self.cl.breakableWingConnected and "G-force (locked)" or metric.label
    self.cl.gui:setSelectedDropDownItem("MetricDropDown", metricLabel)
    self.cl.gui:setText("ThresholdLabel", PC_L.get("threshold", string.format(thresholdFormat, self.cl.threshold) .. " " .. metric.unit))
    local delayCaption = self.cl.breakableWingConnected and "wing_break_delay" or "interval_on_duration"
    self.cl.gui:setText("DelayLabel", PC_L.get(delayCaption, self.cl.delayTicks, self.cl.delayTicks / TICKS_PER_SECOND))
    self.cl.gui:setSliderPosition(
        "ThresholdSlider",
        thresholdToSliderPosition(self.cl.metricKey, self.cl.threshold)
    )
    self.cl.gui:setSliderPosition("DelaySlider", self.cl.delayTicks - MIN_DELAY_TICKS)
end

function PlaneConstructFlightSensor.cl_onGuiClosed(self)
    if self.cl then
        self.cl.closeInputGuardTicks = CLOSE_INPUT_GUARD_TICKS
        self.cl.interactionHeld = false
        local gui = self.cl.gui
        self.cl.gui = nil
        if gui then
            gui:destroy()
        end
    end
end
