NapalmBomb = class()

NapalmBomb.maxParentCount = 1
NapalmBomb.maxChildCount = 0
NapalmBomb.connectionInput = sm.interactable.connectionType.logic
NapalmBomb.connectionOutput = sm.interactable.connectionType.none
NapalmBomb.colorNormal = sm.color.new(0xd9480fff)
NapalmBomb.colorHighlight = sm.color.new(0xff6b22ff)
NapalmBomb.poseWeightCount = 1

local FUSE_TICKS = 80
local ARM_TICKS = 10
local IMPACT_SPEED = 0.75
local FIRE_RADIUS = 1.0

function NapalmBomb.server_onCreate(self)
    self:sv_reset()
end

function NapalmBomb.server_onRefresh(self)
    self:sv_reset()
end

function NapalmBomb.sv_reset(self)
    self.sv = {
        alive = true,
        counting = false,
        fuse = 0,
        age = 0,
        pendingDetonation = false
    }
end

function NapalmBomb.server_onFixedUpdate(self, _)
    if not self.sv.alive then
        return
    end

    if self.sv.pendingDetonation then
        self:sv_detonate()
        return
    end

    self.sv.age = self.sv.age + 1

    local parent = self.interactable:getSingleParent()
    if parent and parent:isActive() then
        self:sv_detonate()
        return
    end

    if self.sv.counting then
        self.sv.fuse = self.sv.fuse + 1
        if self.sv.fuse >= FUSE_TICKS then
            self:sv_detonate()
        end
    end
end

function NapalmBomb.server_onCollision(self, other, collisionPosition, selfPointVelocity, otherPointVelocity, collisionNormal)
    if not self.sv.alive or self.sv.age < ARM_TICKS then
        return
    end

    if sm.exists(other) and type(other) == "Character" and other:isPlayer() then
        return
    end

    local relativeVelocity = selfPointVelocity - otherPointVelocity
    local speed = relativeVelocity:length()
    if speed <= 0 then
        return
    end

    local impactSpeed = math.abs((relativeVelocity / speed):dot(collisionNormal)) * speed
    if impactSpeed >= IMPACT_SPEED then
        self.sv.pendingDetonation = true
    end
end

function NapalmBomb.server_onMelee(self, _, _, _, _, _)
    if self.sv.alive then
        self.sv.pendingDetonation = true
    end
end

function NapalmBomb.server_onExplosion(self, _, _)
    if self.sv.alive then
        self.sv.counting = true
        self.sv.fuse = math.max(self.sv.fuse, FUSE_TICKS - 5)
        self.network:sendToClients("cl_startFuse")
    end
end

function NapalmBomb.sv_startFuse(self, hitPosition)
    if not self.sv.counting then
        self.sv.counting = true
        self.network:sendToClients("cl_startFuse", hitPosition)
    end
end

function NapalmBomb.sv_detonate(self)
    if not self.sv.alive or not self.shape.body.destructable then
        return
    end

    self.sv.alive = false
    local position = self.shape.worldPosition

    sm.fire.igniteSphere(position, FIRE_RADIUS, true)
    sm.effect.playEffect("PropaneTank - ExplosionSmall", position)
    sm.shape.destroyPart(self.shape)
end

function NapalmBomb.client_onCreate(self)
    self.cl = {
        fuseEffect = sm.effect.createEffect("PropaneTank - ActivateSmall", self.interactable)
    }
end

function NapalmBomb.client_onDestroy(self)
    if self.cl and self.cl.fuseEffect then
        self.cl.fuseEffect:destroy()
    end
end

function NapalmBomb.cl_startFuse(self)
    if not self.cl.fuseEffect:isPlaying() then
        self.cl.fuseEffect:start()
    end
end
