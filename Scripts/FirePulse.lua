FirePulse = class()

FirePulse.maxParentCount = 1
FirePulse.maxChildCount = 0
FirePulse.connectionInput = sm.interactable.connectionType.logic
FirePulse.connectionOutput = sm.interactable.connectionType.none
FirePulse.colorNormal = sm.color.new(0xff6b22ff)
FirePulse.colorHighlight = sm.color.new(0xffffb347ff)

local FIRE_RADIUS = 5 * 0.25
local COOLDOWN_TICKS = 20

function FirePulse.server_onCreate(self)
    self:sv_reset()
end

function FirePulse.server_onRefresh(self)
    self:sv_reset()
end

function FirePulse.sv_reset(self)
    self.sv = { cooldown = 0, parentActive = false }
end

function FirePulse.server_onFixedUpdate(self, _)
    self.sv.cooldown = math.max(self.sv.cooldown - 1, 0)

    local parent = self.interactable:getSingleParent()
    local active = parent ~= nil and parent:isActive()
    if active and not self.sv.parentActive then
        self:sv_ignite()
    end
    self.sv.parentActive = active
end

function FirePulse.sv_ignite(self)
    if self.sv.cooldown > 0 then
        return
    end
    self.sv.cooldown = COOLDOWN_TICKS
    sm.fire.igniteSphere(self.shape.worldPosition, FIRE_RADIUS, false)
end
