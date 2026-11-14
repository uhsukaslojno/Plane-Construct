-- Small vanilla pipe fittings that are removed by an active logic input.

PlaneConstructDisappearPipe = class(nil)
PlaneConstructDisappearPipe.maxParentCount = 1
PlaneConstructDisappearPipe.maxChildCount = 0
PlaneConstructDisappearPipe.connectionInput = sm.interactable.connectionType.logic
PlaneConstructDisappearPipe.connectionOutput = sm.interactable.connectionType.none
PlaneConstructDisappearPipe.colorNormal = sm.color.new(0x7a7a7aff)
PlaneConstructDisappearPipe.colorHighlight = sm.color.new(0xa0a0a0ff)

function PlaneConstructDisappearPipe.server_onFixedUpdate(self, timeStep)
    local input = self.interactable:getSingleParent()
    if input and input:isActive() then
        sm.shape.destroyPart(self.shape)
    end
end
