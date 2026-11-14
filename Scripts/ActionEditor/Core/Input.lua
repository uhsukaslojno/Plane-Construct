----------------------------------------------------
-- 操作编辑器：输入分类与渲染顺序
-- Copyright (c) 2026 APxiaosong & Nyako. All rights reserved.
-- 将座椅能够响应的控制器动作统一归入三条通道，作为录制、回放和座椅写回时共同依据的数据来源。
-- 增加可录制动作时只需要改动这里；轨道在界面中的固定渲染顺序也由这里确定。
----------------------------------------------------

local M = {}

-- 三条通道对应座椅最终的三种输出：方向、快捷栏、座椅逻辑键。
M.STEERING = "steering"
M.ITEM = "item"
M.LOGIC = "logic"

M.STEERING_KEYS = { "forward", "backward", "left", "right" }
M.LOGIC_KEYS = { "space", "leftClick", "rightClick" }

-- classified 同时兼作“是否已经构建”的标志；ordered 和 orderIndex 预先置为空表，是为了让静态类型能够确定，
-- 真正的内容会在 build() 里一次性填好。
local classified = nil   -- action（int）→ { channel, key, colorKey, nameKey }
local ordered = {}       -- 固定顺序的 action 列表（方向 → 逻辑 → 快捷栏）
local orderIndex = {}    -- action → 在 ordered 中的下标，供并列时确定先后
local reverse = {}       -- channel → key → action：classify 的逆映射，供从通道状态反推动作编号

local function build()
    -- sm.interactable.actions 在脚本加载期不一定就绪，首次使用时再建表。
    local a = sm.interactable.actions
    local map, list, rev = {}, {}, {}

    local function add( action, channel, key, colorKey, nameKey )
        map[action] = { channel = channel, key = key, colorKey = colorKey, nameKey = nameKey }
        list[#list + 1] = action
        local keys = rev[channel]
        if not keys then keys = {}; rev[channel] = keys end
        keys[key] = action
    end

    add( a.forward,  M.STEERING, "forward",  "forward",  "action_forward" )
    add( a.backward, M.STEERING, "backward", "backward", "action_backward" )
    add( a.left,     M.STEERING, "left",     "left",     "action_left" )
    add( a.right,    M.STEERING, "right",    "right",    "action_right" )
    add( a.jump,     M.LOGIC,    "space",      "space",      "action_jump" )
    add( a.create,   M.LOGIC,    "leftClick",  "leftClick",  "action_create" )
    add( a.attack,   M.LOGIC,    "rightClick", "rightClick", "action_attack" )
    for i = 0, 9 do
        add( a["item" .. i], M.ITEM, i, "item" .. i, nil )
    end

    local index = {}
    for pos, action in ipairs( list ) do
        index[action] = pos
    end

    classified, ordered, orderIndex, reverse = map, list, index, rev
end

local function ensureBuilt()
    if not classified then build() end
end

function M.classify( action )
    ensureBuilt()
    return classified[action]
end

function M.isSupported( action )
    return M.classify( action ) ~= nil
end

-- classify 的逆映射：由通道和键名反查动作编号。座椅输入镜像按通道和键名保存，
-- 服务端替异常离座的乘员合成松键时，要以此还原信箱记录所需的动作编号。
function M.actionOf( channel, key )
    ensureBuilt()
    local keys = reverse[channel]
    return keys and keys[key] or nil
end

-- 这里给出受支持动作（方向 4 个、逻辑 3 个、快捷栏 item0 至 item9）的固定渲染顺序，数量由 build() 构建的集合决定。
-- 界面按它铺排轨道；Projection 在为同一格里并列的片段确定先后时也依靠它，从而保证主色每帧都确定，不会闪烁。
-- 返回内部表，调用方只读，不应修改。
function M.orderedActions()
    ensureBuilt()
    return ordered
end

-- 顺序下标越小，排得越靠前；不受支持的动作排到最后，避免它在并列片段中被选为主色。
function M.orderIndex( action )
    ensureBuilt()
    return orderIndex[action] or math.huge
end

function M.steeringFlag( key )
    return sm.interactable.steering[key]
end

function M.actionName( action )
    local info = M.classify( action )
    local t = AEI18N.t
    if not info then
        return string.format( t( "action_unknown" ), action or 0 )
    end
    if info.channel == M.ITEM then
        return string.format( t( "action_item" ), info.key )
    end
    return t( info.nameKey )
end

AEInput = M
