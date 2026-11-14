-- Ported from an original aerodynamic propeller implementation.
-- Original algorithm copyright (c) 2022 David Sirius.

local airDensity = 1.3
local maxAcceleration = 300
local maxVelocity = 1000
local maxAngularVelocity = 150
local takeEffectTime = 2

local function sign(value)
    if value < 0 then
        return -1
    elseif value > 0 then
        return 1
    end
    return 0
end

local function applyThreeBladeLift(self, timeStep)
    local objectVelocity = self.shape.velocity
    local objectSpeed = objectVelocity:length()
    local angularVelocity = self.shape:getBody():getAngularVelocity()
    local angularSpeed = angularVelocity:length()

    if angularSpeed > 0.1 then
        self.spinTimer = (self.spinTimer or 0) + 1
    else
        self.spinTimer = 0
    end

    if self.spinTimer > takeEffectTime then
        local acceleration = objectSpeed
        if self.lastSpeed then
            acceleration = (objectSpeed - self.lastSpeed) / timeStep
        end
        self.lastSpeed = objectSpeed

        local propellerAxis = self.shape.up
        local axialAngularSpeed = angularVelocity:dot(propellerAxis)

        if objectSpeed < maxVelocity
            and math.abs(acceleration) < maxAcceleration
            and angularSpeed < maxAngularVelocity then
            local pressureLift = 0.5
                * airDensity
                * self.liftCoefficient
                * (axialAngularSpeed * axialAngularSpeed * sign(axialAngularSpeed))
                * self.effectiveArea

            local impulse = sm.vec3.new(0, 0, self.rotationDirection * pressureLift)
            sm.physics.applyImpulse(self.shape, impulse * timeStep)
        end
    end
end

local function updateThreeBladePropeller(self, timeStep)
    local input = self.interactable:getSingleParent()
    if input and not input:isActive() then
        self.interactable:setActive(false)
        return
    end

    self.interactable:setActive(true)
    applyThreeBladeLift(self, timeStep)
end

local function configureThreeBladeClass(classObject, effectiveArea)
    classObject.effectiveArea = effectiveArea
    classObject.liftCoefficient = 0.5
    classObject.rotationDirection = 1
    classObject.maxParentCount = 1
    classObject.maxChildCount = -1
    classObject.connectionInput = sm.interactable.connectionType.logic
    classObject.connectionOutput = sm.interactable.connectionType.logic
    classObject.colorNormal = sm.color.new(0x999999ff)
    classObject.colorHighlight = sm.color.new(0xbbbbbbff)
end

PlaneConstructThreeBladeSmall = class(nil)
configureThreeBladeClass(PlaneConstructThreeBladeSmall, 6)

function PlaneConstructThreeBladeSmall.server_onFixedUpdate(self, timeStep)
    updateThreeBladePropeller(self, timeStep)
end

PlaneConstructThreeBladeMedium = class(nil)
configureThreeBladeClass(PlaneConstructThreeBladeMedium, 9)

function PlaneConstructThreeBladeMedium.server_onFixedUpdate(self, timeStep)
    updateThreeBladePropeller(self, timeStep)
end

PlaneConstructThreeBladeLarge = class(nil)
configureThreeBladeClass(PlaneConstructThreeBladeLarge, 15)

function PlaneConstructThreeBladeLarge.server_onFixedUpdate(self, timeStep)
    updateThreeBladePropeller(self, timeStep)
end
