dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
PlaneConstructDragReducer = class(nil)

PlaneConstructDragReducer.maxParentCount = 1
PlaneConstructDragReducer.maxChildCount = 0
PlaneConstructDragReducer.connectionInput = sm.interactable.connectionType.logic
PlaneConstructDragReducer.connectionOutput = sm.interactable.connectionType.none

local BASE_GAME_DAMPING = 0.025
local MIN_DRAG_PERCENT = -1.0
local MAX_DRAG_PERCENT = 100.0
local SLIDER_STEP = 0.01
local DEFAULT_DRAG_PERCENT = 0.01

local activeBodies = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function sliderToPercent(position)
    return MIN_DRAG_PERCENT + position * SLIDER_STEP
end

local function percentToSlider(percent)
    return math.floor((percent - MIN_DRAG_PERCENT) / SLIDER_STEP + 0.5)
end

local function clampPercent(value)
    return clamp(tonumber(value) or DEFAULT_DRAG_PERCENT, MIN_DRAG_PERCENT, MAX_DRAG_PERCENT)
end

-- Convert the requested final velocity change into the impulse that must
-- compensate the game's built-in damping before the next physics update.
local function getCompensation(requestedPercent)
    local targetDamping = clampPercent(requestedPercent) / 100.0
    if targetDamping >= 1.0 then
        return 1.0
    end
    return 1.0 - (1.0 - BASE_GAME_DAMPING) / (1.0 - targetDamping)
end

local function isDisabledBySignal(self)
    local parent = self.interactable:getSingleParent()
    return parent ~= nil and parent:isActive()
end

local function isShapeInCreation(shape, creationBodies)
    if shape == nil or not sm.exists(shape) then return false end

    local shapeBody = shape:getBody()
    if shapeBody == nil or not sm.exists(shapeBody) then return false end

    local shapeBodyId = shapeBody:getId()
    for _, creationBody in ipairs(creationBodies) do
        if creationBody:getId() == shapeBodyId then
            return true
        end
    end
    return false
end

local function updateActiveState(self)
    self.active = false

    -- An active logic signal disables this reducer. With no active signal it
    -- remains eligible for selection.
    if isDisabledBySignal(self) then
        for id, selected in pairs(activeBodies) do
            if selected.shapeId == self.shape:getId() then
                activeBodies[id] = nil
            end
        end
        return
    end

    local creationBodies = self.shape:getBody():getCreationBodies()
    for _, body in ipairs(creationBodies) do
        local bodyId = body:getId()
        local selected = activeBodies[bodyId]

        -- A catapult/ejection can split a creation without changing every
        -- body id. Discard a selection that belongs to the old creation.
        if selected ~= nil and not isShapeInCreation(selected.shape, creationBodies) then
            selected = nil
            activeBodies[bodyId] = nil
        end

        local shouldSelect = selected == nil

        if selected ~= nil then
            shouldSelect = selected.shapeId == self.shape:getId()
                or self.sv.dragPercent < selected.dragPercent
                or (self.sv.dragPercent == selected.dragPercent
                    and self.shape:getId() < selected.shapeId)
        end

        if shouldSelect then
            selected = {
                shape = self.shape,
                shapeId = self.shape:getId(),
                dragPercent = self.sv.dragPercent
            }
            activeBodies[bodyId] = selected
        end

        if selected.shapeId == self.shape:getId() then
            self.active = true
        end
    end
end

function PlaneConstructDragReducer.server_onCreate(self)
    local stored = self.storage:load()
    local storedPercent = type(stored) == "table" and stored.dragPercent or nil
    self.sv = { dragPercent = clampPercent(storedPercent) }
    self.active = false
    self.myBodyId = 0
    self.myShapeId = 0
    self.storage:save({ dragPercent = self.sv.dragPercent })
    self.network:setClientData({ dragPercent = self.sv.dragPercent })
end

function PlaneConstructDragReducer.sv_setDragPercent(self, value)
    local dragPercent = clampPercent(value)
    if dragPercent == self.sv.dragPercent then return end
    self.sv.dragPercent = dragPercent
    self.storage:save({ dragPercent = dragPercent })
    self.network:setClientData({ dragPercent = dragPercent })
end

function PlaneConstructDragReducer.server_onFixedUpdate(self, dt)
    local body = self.shape:getBody()
    if self.myBodyId ~= body:getId() then
        self.active = false
        for id, selected in pairs(activeBodies) do
            if selected.shapeId == self.myShapeId then activeBodies[id] = nil end
        end
        self.myBodyId = body:getId()
    end
    self.myShapeId = self.shape:getId()

    updateActiveState(self)
    if not self.active then return end

    -- Проверяем переключатель: если сигнал идет (true), то инвертируем логику и отключаем работу блока
    local compensation = getCompensation(self.sv.dragPercent)
    for _, creationBody in pairs(body:getCreationBodies()) do
        local velocity = creationBody:getVelocity()
        if compensation >= 1.0 then
            sm.physics.applyImpulse(creationBody, -velocity * creationBody:getMass(), true)
        else
            local multiplier = 1.0 / (1.0 - compensation) - 1.0
            sm.physics.applyImpulse(
                creationBody,
                velocity * multiplier * creationBody:getMass() * dt * 10.0,
                true
            )
        end
    end
end

function PlaneConstructDragReducer.server_onDestroy(self)
    for id, selected in pairs(activeBodies) do
        if selected.shapeId == self.myShapeId then activeBodies[id] = nil end
    end
end

function PlaneConstructDragReducer.client_onCreate(self)
    self.cl = { dragPercent = DEFAULT_DRAG_PERCENT, gui = nil }
end

function PlaneConstructDragReducer.client_onClientDataUpdate(self, data)
    self.cl.dragPercent = clampPercent(data.dragPercent)
    self:cl_refreshGui()
end

function PlaneConstructDragReducer.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_drag_reducer"))
    return true
end

function PlaneConstructDragReducer.client_onInteract(self, _, state)
    if not state then return end
    if self.cl.gui then self.cl.gui:close(); self.cl.gui:destroy() end

    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("PlaneConstructDragReducer.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    local sliderCount = math.floor((MAX_DRAG_PERCENT - MIN_DRAG_PERCENT) / SLIDER_STEP + 1.5)
    self.cl.gui:createHorizontalSlider(
        "DragSlider",
        sliderCount,
        percentToSlider(self.cl.dragPercent),
        "cl_onDragSliderChanged"
    )
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
    self.cl.gui:open()
end

function PlaneConstructDragReducer.cl_onDragSliderChanged(self, position)
    self.cl.dragPercent = clampPercent(sliderToPercent(position))
    self:cl_refreshGui()
    self.network:sendToServer("sv_setDragPercent", self.cl.dragPercent)
end

function PlaneConstructDragReducer.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end
    self.cl.gui:setText("DragValue", PC_L.get("velocity_change", self.cl.dragPercent))
end

function PlaneConstructDragReducer.cl_onGuiClosed(self)
    if self.cl.gui then self.cl.gui:destroy(); self.cl.gui = nil end
end
