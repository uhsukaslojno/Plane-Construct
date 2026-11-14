dofile("ModPaths.lua")
local PC_L = PlaneConstructLocalization
ConnectedWeaponSelector = class()

-- A driver seat is accepted so this controller can live with the other
-- seat-operated aircraft controls. Only a white logic input can fire it.
ConnectedWeaponSelector.maxParentCount = -1
ConnectedWeaponSelector.maxChildCount = -1
ConnectedWeaponSelector.connectionInput = sm.interactable.connectionType.seated + sm.interactable.connectionType.logic
ConnectedWeaponSelector.connectionOutput = sm.interactable.connectionType.logic
ConnectedWeaponSelector.colorNormal = sm.color.new(0xae79f0ff)
ConnectedWeaponSelector.colorHighlight = sm.color.new(0xd4b5ffff)

local WHITE_LOGIC_COLOR = "eeeeeeff"
local ROWS_PER_PAGE = 8

local function isWhiteLogicInputActive(interactable)
    for _, parent in ipairs(interactable:getParents(sm.interactable.connectionType.logic)) do
        if parent:isActive()
            and string.lower(tostring(parent:getShape():getColor())) == WHITE_LOGIC_COLOR then
            return true
        end
    end

    return false
end

local function getChildId(child)
    local shape = child:getShape()
    return shape ~= nil and sm.exists(shape) and shape.id or nil
end

function ConnectedWeaponSelector.server_onCreate(self)
    self:sv_initialize()
end

function ConnectedWeaponSelector.server_onRefresh(self)
    self:sv_restoreWiring()
    self:sv_initialize()
end

function ConnectedWeaponSelector.server_onDestroy(self)
    self:sv_restoreWiring()
end

function ConnectedWeaponSelector.sv_initialize(self)
    local stored = self.storage:load()
    self.sv = {
        selectedChildId = type(stored) == "table" and tonumber(stored.selectedChildId) or nil,
        disconnectedChildren = nil,
        routedChildId = nil,
        outputSignature = nil
    }

    self.interactable:setActive(false)
    self:sv_updateOutputData(true)
end

function ConnectedWeaponSelector.sv_getOutputData(self)
    local outputsById = {}
    local children = self.interactable:getChildren(sm.interactable.connectionType.logic)

    -- Routed outputs are deliberately disconnected while the trigger is on.
    -- Keep them in the menu/snapshot so that temporary routing never looks
    -- like the player removed their wires.
    if self.sv.disconnectedChildren ~= nil then
        for _, child in ipairs(self.sv.disconnectedChildren) do
            if sm.exists(child) then
                children[#children + 1] = child
            end
        end
    end

    for _, child in ipairs(children) do
        local shape = child:getShape()
        if shape ~= nil and sm.exists(shape) then
            local childId = shape.id
            if outputsById[childId] == nil then
                local shapeUuid = shape.uuid
                outputsById[childId] = {
                    id = childId,
                    title = sm.shape.getShapeTitle(shapeUuid) or tostring(shapeUuid),
                    uuid = tostring(shapeUuid)
                }
            end
        end
    end

    local outputs = {}
    for _, output in pairs(outputsById) do
        outputs[#outputs + 1] = output
    end
    table.sort(outputs, function(a, b) return a.id < b.id end)

    local signatureParts = {}
    for index, output in ipairs(outputs) do
        -- Keep list captions ASCII-only. The default ListBox font is more
        -- restrictive than ordinary text widgets and silently drops several
        -- extended glyphs, including the previous arrow character.
        output.label = string.format("OUTPUT %d - %s", index, output.title)
        signatureParts[#signatureParts + 1] = tostring(output.id)
    end
    return outputs, table.concat(signatureParts, ",")
end

function ConnectedWeaponSelector.sv_hasChildId(self, childId)
    local children = self.interactable:getChildren(sm.interactable.connectionType.logic)
    if self.sv.disconnectedChildren ~= nil then
        for _, child in ipairs(self.sv.disconnectedChildren) do
            if sm.exists(child) then children[#children + 1] = child end
        end
    end
    for _, child in ipairs(children) do
        if getChildId(child) == childId then
            return true
        end
    end

    return false
end

function ConnectedWeaponSelector.sv_syncClientData(self, outputs)
    self.network:setClientData({
        outputs = outputs,
        selectedChildId = self.sv.selectedChildId
    })
end

function ConnectedWeaponSelector.sv_updateOutputData(self, force)
    local outputs, signature = self:sv_getOutputData()
    if not force and signature == self.sv.outputSignature then return false end

    -- If the target was removed, do not silently redirect the trigger to a
    -- different output which happened to move into its old list position.
    if self.sv.selectedChildId ~= nil and not self:sv_hasChildId(self.sv.selectedChildId) then
        self.sv.selectedChildId = nil
        self.storage:save({ selectedChildId = nil })
    end

    self.sv.outputSignature = signature
    self:sv_syncClientData(outputs)
    return true
end

function ConnectedWeaponSelector.sv_getSelectedChild(self)
    if self.sv.selectedChildId == nil then return nil end

    local children = self.interactable:getChildren(sm.interactable.connectionType.logic)
    if self.sv.disconnectedChildren ~= nil then
        for _, child in ipairs(self.sv.disconnectedChildren) do
            if sm.exists(child) then children[#children + 1] = child end
        end
    end
    for _, child in ipairs(children) do
        if getChildId(child) == self.sv.selectedChildId then
            return child
        end
    end

    return nil
end

function ConnectedWeaponSelector.sv_selectOutput(self, requestedChildId)
    local childId = tonumber(requestedChildId)
    if childId == nil or not self:sv_hasChildId(childId) then return end
    if childId == self.sv.selectedChildId then return end

    -- Change targets cleanly even when the white trigger is currently held.
    self:sv_restoreWiring()
    self.sv.selectedChildId = childId
    self.storage:save({ selectedChildId = childId })
    self:sv_updateOutputData(true)
end

function ConnectedWeaponSelector.sv_restoreWiring(self)
    if self.sv == nil then return end

    if sm.exists(self.interactable) then
        self.interactable:setActive(false)
    end
    if self.sv.disconnectedChildren ~= nil then
        for _, child in ipairs(self.sv.disconnectedChildren) do
            if sm.exists(child) then
                self.interactable:connect(child)
            end
        end
    end

    self.sv.disconnectedChildren = nil
    self.sv.routedChildId = nil
end

function ConnectedWeaponSelector.sv_routeToSelectedChild(self, selectedChild)
    local selectedChildId = getChildId(selectedChild)
    if selectedChildId == nil then return end
    if self.sv.routedChildId == selectedChildId then return end

    self:sv_restoreWiring()

    local disconnected = {}
    for _, child in ipairs(self.interactable:getChildren(sm.interactable.connectionType.logic)) do
        if child ~= selectedChild then
            if not self.interactable:disconnect(child) then
                for _, disconnectedChild in ipairs(disconnected) do
                    if sm.exists(disconnectedChild) then
                        self.interactable:connect(disconnectedChild)
                    end
                end
                return
            end
            disconnected[#disconnected + 1] = child
        end
    end

    self.sv.disconnectedChildren = disconnected
    self.sv.routedChildId = selectedChildId
    self.interactable:setActive(true)
end

function ConnectedWeaponSelector.server_onFixedUpdate(self, _)
    -- Rebuild the routed wire set when a player adds or removes an output.
    if self:sv_updateOutputData(false) and self.sv.routedChildId ~= nil then
        self:sv_restoreWiring()
    end

    local selectedChild = self:sv_getSelectedChild()
    if isWhiteLogicInputActive(self.interactable) and selectedChild ~= nil then
        self:sv_routeToSelectedChild(selectedChild)
    else
        self:sv_restoreWiring()
    end
end

function ConnectedWeaponSelector.client_onCreate(self)
    self.cl = {
        outputs = {},
        selectedChildId = nil,
        scrollOffset = 0,
        gui = nil
    }
end

function ConnectedWeaponSelector.client_onClientDataUpdate(self, data)
    self.cl.outputs = type(data.outputs) == "table" and data.outputs or {}
    self.cl.selectedChildId = data.selectedChildId
    self:cl_refreshGui()
end

function ConnectedWeaponSelector.client_onDestroy(self)
    self:cl_destroyGui()
end

function ConnectedWeaponSelector.client_canInteract(self)
    sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), PC_L.get("configure_connected_weapons"))
    return true
end

function ConnectedWeaponSelector.client_onInteract(self, _, state)
    if not state then return end

    self:cl_destroyGui()
    self.cl.gui = sm.gui.createGuiFromLayout(
        PC_L.layout("ConnectedWeaponSelector.layout"),
        false,
        { backgroundAlpha = 0.5 }
    )
    self:cl_refreshGui()
    self.cl.gui:open()

    -- Bind interactive callbacks after opening, matching the vanilla
    -- interactable GUI lifecycle.
    for row = 1, ROWS_PER_PAGE do
        self.cl.gui:setButtonCallback("OutputButton" .. row, "cl_onOutputButtonPressed")
    end
    self.cl.gui:setButtonCallback("OutputPrevButton", "cl_onOutputPrevButtonPressed")
    self.cl.gui:setButtonCallback("OutputNextButton", "cl_onOutputNextButtonPressed")
    self.cl.gui:setOnCloseCallback("cl_onGuiClosed")
    self:cl_refreshGui()
end

function ConnectedWeaponSelector.cl_refreshGui(self)
    if self.cl == nil or self.cl.gui == nil then return end

    local hasOutputs = #self.cl.outputs > 0
    self.cl.gui:setVisible("ConnectedWeaponsTitle", hasOutputs)
    self.cl.gui:setVisible("NoConnectionsTitle", not hasOutputs)
    self.cl.gui:setVisible("OutputListPanel", hasOutputs)
    self.cl.gui:setVisible("OutputPrevButton", hasOutputs and #self.cl.outputs > ROWS_PER_PAGE)
    self.cl.gui:setVisible("OutputNextButton", hasOutputs and #self.cl.outputs > ROWS_PER_PAGE)

    if not hasOutputs then return end

    local maximum = math.max(0, #self.cl.outputs - ROWS_PER_PAGE)
    self.cl.scrollOffset = math.max(0, math.min(self.cl.scrollOffset or 0, maximum))

    for row = 1, ROWS_PER_PAGE do
        local output = self.cl.outputs[self.cl.scrollOffset + row]
        local buttonName = "OutputButton" .. row
        local visible = output ~= nil

        self.cl.gui:setVisible(buttonName, visible)
        if visible then
            self.cl.gui:setText("OutputLabel" .. row, output.label)
            self.cl.gui:setButtonState(buttonName, output.id == self.cl.selectedChildId)
        end
    end
end

function ConnectedWeaponSelector.cl_onOutputPrevButtonPressed(self)
    self.cl.scrollOffset = math.max(0, (self.cl.scrollOffset or 0) - 1)
    self:cl_refreshGui()
end

function ConnectedWeaponSelector.cl_onOutputNextButtonPressed(self)
    local maximum = math.max(0, #self.cl.outputs - ROWS_PER_PAGE)
    self.cl.scrollOffset = math.min(maximum, (self.cl.scrollOffset or 0) + 1)
    self:cl_refreshGui()
end

function ConnectedWeaponSelector.cl_onOutputButtonPressed(self, buttonName)
    local row = tonumber(string.match(buttonName or "", "(%d+)$"))
    local output = row ~= nil and self.cl.outputs[(self.cl.scrollOffset or 0) + row] or nil
    if output ~= nil then
        self.network:sendToServer("sv_selectOutput", output.id)
    end
end

function ConnectedWeaponSelector.cl_destroyGui(self)
    if self.cl and self.cl.gui then
        self.cl.gui:close()
        self.cl.gui:destroy()
        self.cl.gui = nil
    end
end

function ConnectedWeaponSelector.cl_onGuiClosed(self)
    self:cl_destroyGui()
end
