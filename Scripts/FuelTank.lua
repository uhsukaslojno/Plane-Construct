dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
FuelTank = class()

FuelTank.maxParentCount = -1
FuelTank.maxChildCount = -1
FuelTank.connectionInput = sm.interactable.connectionType.logic
FuelTank.connectionOutput = sm.interactable.connectionType.logic
FuelTank.colorNormal = sm.color.new(0xf2c40eff)
FuelTank.colorHighlight = sm.color.new(0xffed75ff)

local DEFAULT_CAPACITY = 100
local MIN_CAPACITY = 1
local MAX_CAPACITY = 5000
local CONSUMPTION_TICKS = 40
local REGISTRY_PREFIX = "PlaneConstructFuelTank:"
local AFTERBODY_THRUSTER_UUIDS = {
    ["c81f2a4e-12d9-4ec6-8b33-1e61f230a401"] = true,
    ["c81f2a4e-12d9-4ec6-8b33-1e61f230a402"] = true
}

local function registryKey(interactable)
    return REGISTRY_PREFIX .. tostring(interactable:getId())
end

local function clampInteger(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
end

local function isLogicInputActive(interactable)
    for _, parent in ipairs(interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:isActive() then
            return true
        end
    end
    return false
end

local function getConnectedThrusterDemand(self)
    local totalDemand = 0.0
    local hasThruster = false
    local children = self.interactable:getChildren(sm.interactable.connectionType.logic) or {}
    for _, child in ipairs(children) do
        local shape = child:getShape()
        local uuid = shape and string.lower(tostring(shape.shapeUuid)) or ""
        if AFTERBODY_THRUSTER_UUIDS[uuid] then
            hasThruster = true
            local data = child:getPublicData()
            if type(data) == "table" then
                totalDemand = totalDemand
                    + math.max(0.0, tonumber(data.plane_construct_fuel_demand) or 0.0)
            end
        end
    end
    return totalDemand, hasThruster
end

function FuelTank.server_onCreate(self)
    self:sv_initialize()
end

function FuelTank.server_onRefresh(self)
    self:sv_initialize()
end

function FuelTank.server_onDestroy(self)
    if sm.exists(self.interactable) then
        self.interactable:setActive(false)
    end
    _G[registryKey(self.interactable)] = nil
end

function FuelTank.sv_initialize(self)
    local stored = self.storage:load()
    local capacity = DEFAULT_CAPACITY
    local fuel = DEFAULT_CAPACITY

    if type(stored) == "table" then
        capacity = clampInteger(tonumber(stored.capacity) or DEFAULT_CAPACITY, MIN_CAPACITY, MAX_CAPACITY)
        fuel = clampInteger(tonumber(stored.fuel) or capacity, 0, capacity)
    end

    self.sv = {
        capacity = capacity,
        fuel = fuel,
        fuelAccumulator = 0.0,
        outputActive = false
    }

    self.interactable:setActive(false)
    self.storage:save({ capacity = capacity, fuel = fuel })
    self:sv_syncClientData()
end

function FuelTank.sv_syncClientData(self)
    self.network:setClientData({
        capacity = self.sv.capacity,
        fuel = self.sv.fuel
    })
    _G[registryKey(self.interactable)] = {
        capacity = self.sv.capacity,
        fuel = self.sv.fuel
    }
end

function FuelTank.sv_setCapacity(self, requestedCapacity)
    local numericCapacity = tonumber(requestedCapacity)
    if numericCapacity == nil then return end

    local capacity = clampInteger(numericCapacity, MIN_CAPACITY, MAX_CAPACITY)
    local fuel = math.min(self.sv.fuel, capacity)
    if capacity == self.sv.capacity and fuel == self.sv.fuel then return end

    self.sv.capacity = capacity
    self.sv.fuel = fuel
    self.sv.fuelAccumulator = 0.0
    self.storage:save({ capacity = capacity, fuel = fuel })
    self:sv_syncClientData()
end

function FuelTank.sv_refill(self)
    self.sv.fuel = self.sv.capacity
    self.sv.fuelAccumulator = 0.0
    self.storage:save({ capacity = self.sv.capacity, fuel = self.sv.fuel })
    self:sv_syncClientData()
end

function FuelTank.server_onFixedUpdate(self, timeStep)
    local inputActive = isLogicInputActive(self.interactable)
    local thrusterDemand, hasThruster = getConnectedThrusterDemand(self)

    if inputActive and self.sv.fuel > 0 then
        local normalRate = 40.0 / CONSUMPTION_TICKS
        local consumptionRate = hasThruster and thrusterDemand or normalRate
        self.sv.fuelAccumulator = self.sv.fuelAccumulator
            + consumptionRate * (tonumber(timeStep) or 0.025)
        local wholeFuel = math.floor(self.sv.fuelAccumulator)
        if wholeFuel > 0 then
            self.sv.fuel = math.max(self.sv.fuel - wholeFuel, 0)
            self.sv.fuelAccumulator = self.sv.fuelAccumulator - wholeFuel
            self.storage:save({ capacity = self.sv.capacity, fuel = self.sv.fuel })
            self:sv_syncClientData()
        end
    else
        self.sv.fuelAccumulator = 0.0
    end

    local shouldOutput = inputActive and self.sv.fuel > 0
    if shouldOutput ~= self.sv.outputActive then
        self.interactable:setActive(shouldOutput)
        self.sv.outputActive = shouldOutput
    end
end

function FuelTank.client_onCreate(self)
    self.cl = {
        capacity = DEFAULT_CAPACITY,
        fuel = DEFAULT_CAPACITY,
        gui = nil
    }
end

function FuelTank.client_onClientDataUpdate(self, data)
    if self.cl == nil then
        self.cl = { capacity = DEFAULT_CAPACITY, fuel = DEFAULT_CAPACITY, gui = nil }
    end

    self.cl.capacity = clampInteger(tonumber(data.capacity) or DEFAULT_CAPACITY, MIN_CAPACITY, MAX_CAPACITY)
    self.cl.fuel = clampInteger(tonumber(data.fuel) or self.cl.capacity, 0, self.cl.capacity)
    self:cl_refreshGui()
end

function FuelTank.client_onDestroy(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function FuelTank.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_fuel_tank"))
    return true
end

function FuelTank.client_onInteract(self, _, state)
    if not state then return end

    if self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
    end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("FuelTank.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self.cl.gui:createHorizontalSlider(
        "CapacitySlider",
        MAX_CAPACITY,
        self.cl.capacity - MIN_CAPACITY,
        "cl_onCapacitySliderChanged"
    )
    self.cl.gui:setButtonCallback("RefillButton", "cl_onRefillPressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function FuelTank.cl_onCapacitySliderChanged(self, sliderPosition)
    self.cl.capacity = clampInteger(sliderPosition + MIN_CAPACITY, MIN_CAPACITY, MAX_CAPACITY)
    self:cl_refreshGui()
    self.network:sendToServer("sv_setCapacity", self.cl.capacity)
end

function FuelTank.cl_onRefillPressed(self)
    self.network:sendToServer("sv_refill")
end

function FuelTank.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end

    self.cl.gui:setText(
        "FuelValue",
        PC_L.get("fuel", self.cl.fuel, self.cl.capacity)
    )
end

function FuelTank.cl_onGuiClosed(self)
    if self.cl.gui then
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end
