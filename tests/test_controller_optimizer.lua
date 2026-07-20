local frame = 0
local actionValuesByController = {}
local buttonStatesByController = {}
local worldFamiliars = {}
local savedData = ""
local nextPlayerSeed = 1000

REPENTANCE_PLUS = true

ModCallbacks = {
    MC_INPUT_ACTION = 13,
    MC_POST_GAME_STARTED = 15,
    MC_POST_NEW_ROOM = 18,
    MC_POST_UPDATE = 1,
    MC_PRE_GAME_EXIT = 31,
    MC_POST_RENDER = 2,
}

InputHook = {
    IS_ACTION_PRESSED = 0,
    IS_ACTION_TRIGGERED = 1,
    GET_ACTION_VALUE = 2,
}

ButtonAction = {
    ACTION_LEFT = 0,
    ACTION_RIGHT = 1,
    ACTION_UP = 2,
    ACTION_DOWN = 3,
    ACTION_SHOOTLEFT = 4,
    ACTION_SHOOTRIGHT = 5,
    ACTION_SHOOTUP = 6,
    ACTION_SHOOTDOWN = 7,
}

CollectibleType = {
    COLLECTIBLE_ANALOG_STICK = 465,
    COLLECTIBLE_EYE_OF_THE_OCCULT = 572,
    COLLECTIBLE_MARS = 609,
    COLLECTIBLE_SCHOOLBAG = 534,
}

FamiliarVariant = {
    LIL_BRIMSTONE = 61,
    LIL_MONSTRO = 108,
}

EntityType = { ENTITY_FAMILIAR = 3 }
WeaponType = { WEAPON_BRIMSTONE = 4 }
PlayerType = { PLAYER_AZAZEL_B = 23 }
ActiveSlot = { SLOT_PRIMARY = 0, SLOT_SECONDARY = 1 }

Input = {
    GetActionValue = function(action, controllerIndex)
        local values = actionValuesByController[controllerIndex] or {}
        return values[action] or 0
    end,
    IsButtonPressed = function(button, controllerIndex)
        local buttons = buttonStatesByController[controllerIndex] or {}
        return buttons[button] == true
    end,
}

Isaac = {
    GetFrameCount = function()
        return frame
    end,
    DebugString = function() end,
    RenderText = function() end,
    FindByType = function(entityType)
        if entityType == EntityType.ENTITY_FAMILIAR then
            return worldFamiliars
        end
        return {}
    end,
}

local player = {
    InitSeed = 1000,
    ControllerIndex = 1,
    collectibles = {},
    brimstone = true,
    playerType = 0,
    activeItems = { [0] = 0, [1] = 0 },
    swapCount = 0,
}

GetPtrHash = function(entity)
    return entity.InitSeed
end

function player:ToPlayer()
    return self
end

function player:GetPlayerType()
    return self.playerType
end

function player:HasWeaponType(weaponType)
    return self.brimstone and weaponType == WeaponType.WEAPON_BRIMSTONE
end

function player:HasCollectible(collectible)
    return self.collectibles[collectible] == true
end

function player:GetActiveItem(slot)
    return self.activeItems[slot] or 0
end

function player:SwapActiveItems()
    self.activeItems[0], self.activeItems[1] = self.activeItems[1], self.activeItems[0]
    self.swapCount = self.swapCount + 1
end

local players = { player }
local game = {
    GetNumPlayers = function()
        return #players
    end,
    GetPlayer = function(_, index)
        return players[index + 1]
    end,
}

Game = function()
    return game
end

local registeredMod = nil
RegisterMod = function()
    registeredMod = {
        callbacks = {},
        AddCallback = function(self, callback, fn, optional)
            table.insert(self.callbacks, { callback, fn, optional })
        end,
        HasData = function()
            return savedData ~= ""
        end,
        LoadData = function()
            return savedData
        end,
        SaveData = function(_, data)
            savedData = data
        end,
    }
    return registeredMod
end

dofile("main.lua")

local function setActionValue(action, value, controllerIndex)
    controllerIndex = controllerIndex or player.ControllerIndex
    local values = actionValuesByController[controllerIndex]
    if values == nil then
        values = {}
        actionValuesByController[controllerIndex] = values
    end
    values[action] = value
end

local function setStick(x, y, controllerIndex)
    setActionValue(ButtonAction.ACTION_SHOOTLEFT, math.max(-x, 0), controllerIndex)
    setActionValue(ButtonAction.ACTION_SHOOTRIGHT, math.max(x, 0), controllerIndex)
    setActionValue(ButtonAction.ACTION_SHOOTUP, math.max(-y, 0), controllerIndex)
    setActionValue(ButtonAction.ACTION_SHOOTDOWN, math.max(y, 0), controllerIndex)
end

local function setButton(button, isDown, controllerIndex)
    controllerIndex = controllerIndex or player.ControllerIndex
    local buttons = buttonStatesByController[controllerIndex]
    if buttons == nil then
        buttons = {}
        buttonStatesByController[controllerIndex] = buttons
    end
    buttons[button] = isDown
end

local function pollFor(targetPlayer, hook, action)
    return registeredMod:OnInputAction(targetPlayer, hook, action)
end

local function poll(hook, action)
    return pollFor(player, hook, action)
end

local function reset(atFrame)
    frame = atFrame
    actionValuesByController = {}
    buttonStatesByController = {}
    worldFamiliars = {}
    players = { player }
    player.collectibles = {}
    player.brimstone = true
    player.playerType = 0
    player.ControllerIndex = 1
    player.activeItems = { [0] = 0, [1] = 0 }
    player.swapCount = 0
    registeredMod:OnNewRoom()
end

local function makePlayer(controllerIndex)
    nextPlayerSeed = nextPlayerSeed + 1
    return setmetatable({
        InitSeed = nextPlayerSeed,
        ControllerIndex = controllerIndex,
        collectibles = {},
        brimstone = true,
        playerType = 0,
        activeItems = { [0] = 0, [1] = 0 },
        swapCount = 0,
    }, { __index = player })
end

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertClose(actual, expected, tolerance, label)
    if actual == nil or math.abs(actual - expected) > tolerance then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

-- 普通 Brimstone 只修正方向值；pressed/triggered 保持原生，确保松手立即可见。
reset(1)
setStick(0.8, 0.6)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "cardinal right")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN), 0, "cardinal down")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), nil, "pressed right native")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTDOWN), nil, "pressed down native")

-- Analog Stick 保留归一化后的完整 360° 向量。
reset(10)
player.collectibles[CollectibleType.COLLECTIBLE_ANALOG_STICK] = true
setStick(0.8, 0.6)
assertClose(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 0.8, 0.0001, "analog right")
assertClose(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN), 0.6, 0.0001, "analog down")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), nil, "analog pressed right native")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTDOWN), nil, "analog pressed down native")

-- 绕完整一圈采样，360° 输出角度不能因四方向动作拆分而失真。
for degrees = 0, 355, 5 do
    frame = 11 + degrees / 5
    local radians = math.rad(degrees)
    local expectedX = math.cos(radians)
    local expectedY = math.sin(radians)
    setStick(expectedX * 0.9, expectedY * 0.9)
    local actualX =
        (poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT) or 0) -
        (poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT) or 0)
    local actualY =
        (poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN) or 0) -
        (poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTUP) or 0)
    local dot = actualX * expectedX + actualY * expectedY
    if dot < 0.9999 then
        error("analog angle drift at " .. tostring(degrees) .. " degrees: dot=" .. tostring(dot))
    end
end

-- 进入回中区后的强反向 snapback 也不能覆盖最后意图方向。
reset(20)
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "snapback acquire")
frame = 21
setStick(0, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "center hold")
frame = 22
setStick(-1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "snapback keeps intent")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 0, "snapback blocks reverse")
frame = 23
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 0, "snapback release frame suppressed")
frame = 24
setStick(-1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 1, "sustained reverse accepted")

-- 游戏可能为同一底层角色返回新的 userdata wrapper。稳定实体键必须让方向、
-- 回中防抖和反向保护跨 wrapper 延续，否则实机会退化成近似原生输入。
reset(25)
local wrapperEntity = {
    ToPlayer = function()
        return setmetatable({ InitSeed = player.InitSeed }, { __index = player })
    end,
}
setStick(1, 0)
assertEqual(
    pollFor(wrapperEntity, InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT),
    1,
    "wrapper churn acquires direction"
)
frame = 26
setStick(0, 0)
assertEqual(
    pollFor(wrapperEntity, InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT),
    1,
    "wrapper churn preserves release debounce"
)
frame = 27
setStick(-1, 0)
assertEqual(
    pollFor(wrapperEntity, InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT),
    1,
    "wrapper churn preserves snapback intent"
)
assertEqual(
    pollFor(wrapperEntity, InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT),
    0,
    "wrapper churn blocks reverse output"
)

-- 没有采样到中心的单帧反向跳变也必须视为回弹，不能覆盖发射方向。
reset(30)
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "direct snapback acquire")
frame = 31
setStick(-1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "direct snapback keeps direction")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 0, "direct snapback reverse hidden")
frame = 32
setStick(0, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "direct snapback releases original direction")
frame = 34
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), nil, "direct snapback returns control")

-- 回中只允许两帧采样防抖；pressed 始终交还原版，不能制造 45 帧发射延迟。
reset(40)
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "hold acquire")
frame = 41
setStick(0, 0)
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), nil, "release pressed stays native")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "release debounce frame zero")
frame = 42
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "release debounce frame one")
frame = 43
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), nil, "release returns control")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), nil, "released pressed stays native")
frame = 44
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "next attack is not guarded")

-- Eye of the Occult 仍完全放行，非 Brimstone 玩家也不接管。
reset(100)
player.collectibles[CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT] = true
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), nil, "occult pass-through")
reset(101)
player.brimstone = false
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), nil, "non-brimstone pass-through")

-- 普通或 modded 跟班必须完全放行，不能改变玩家本体的释放窗口。
reset(110)
worldFamiliars = {
    { ToFamiliar = function(self) return self end, Variant = 1, Player = player },
}
registeredMod:OnPostUpdate()
frame = 111
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "generic familiar acquire")
frame = 112
setStick(0, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "generic familiar keeps normal debounce")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), nil, "generic familiar pressed native")

-- 真正的蓄力宝宝仍使用专用释放路径。
reset(120)
worldFamiliars = {
    { ToFamiliar = function(self) return self end, Variant = FamiliarVariant.LIL_BRIMSTONE, Player = player },
}
registeredMod:OnPostUpdate()
frame = 121
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "charge familiar acquire")
frame = 122
setStick(0, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 0, "charge familiar releases")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), false, "charge familiar release edge")

-- Mars 只拦截模拟轨迹产生的 triggered；持续 pressed 必须留给原版和其他 mod。
reset(140)
player.collectibles[CollectibleType.COLLECTIBLE_MARS] = true
setActionValue(ButtonAction.ACTION_RIGHT, 0.5)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_RIGHT), nil, "mars observes analog mid")
frame = 141
setActionValue(ButtonAction.ACTION_RIGHT, 0.99)
assertClose(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_RIGHT), 0.95, 0.0001, "mars caps analog peak")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_RIGHT), false, "mars suppresses analog trigger")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_RIGHT), nil, "mars pressed remains native")

-- 书包快捷交换默认开启，但仍必须持有 Schoolbag 且目标角色唯一。
reset(150)
player.activeItems = { [0] = 100, [1] = 200 }
setButton(13, true)
registeredMod:OnPostUpdate()
frame = 151
setButton(13, false)
registeredMod:OnPostUpdate()
assertEqual(player.swapCount, 0, "active swap requires schoolbag")

reset(160)
player.collectibles[CollectibleType.COLLECTIBLE_SCHOOLBAG] = true
player.activeItems = { [0] = 100, [1] = 200 }
-- Isaac 的编号 11 是 RB，不得把它误认成右摇杆按下。
setButton(11, true)
registeredMod:OnPostUpdate()
frame = 161
setButton(11, false)
registeredMod:OnPostUpdate()
assertEqual(player.swapCount, 0, "right bumper does not trigger schoolbag swap")

frame = 162
setButton(13, true)
registeredMod:OnPostUpdate()
frame = 163
setButton(13, false)
registeredMod:OnPostUpdate()
assertEqual(player.swapCount, 1, "schoolbag swaps once on release")
assertEqual(player.activeItems[0], 200, "schoolbag primary swapped")
assertEqual(player.activeItems[1], 100, "schoolbag secondary swapped")

reset(170)
local sharedPlayer = makePlayer(1)
player.collectibles[CollectibleType.COLLECTIBLE_SCHOOLBAG] = true
sharedPlayer.collectibles[CollectibleType.COLLECTIBLE_SCHOOLBAG] = true
player.activeItems = { [0] = 100, [1] = 200 }
sharedPlayer.activeItems = { [0] = 300, [1] = 400 }
players = { player, sharedPlayer }
setButton(13, true)
registeredMod:OnPostUpdate()
frame = 171
setButton(13, false)
registeredMod:OnPostUpdate()
assertEqual(player.swapCount, 0, "shared controller does not guess first player")
assertEqual(sharedPlayer.swapCount, 0, "shared controller does not guess second player")

-- 同一手柄控制多个角色时，每个 player 保持独立射击状态，不能互相重置配置。
reset(180)
local taintedSharedPlayer = makePlayer(1)
taintedSharedPlayer.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(1, 0)
assertEqual(
    pollFor(taintedSharedPlayer, InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT),
    true,
    "shared controller tainted initial trigger"
)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "shared controller generic output")
frame = 181
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "shared generic remains active")
assertEqual(
    pollFor(taintedSharedPlayer, InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT),
    false,
    "shared profiles do not retrigger tainted attack"
)

-- 里阿撒泻勒：一次摇杆动作只产生一帧 triggered，后续只维持 pressed/value。
reset(200)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted sneeze trigger")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted charge pressed")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "tainted charge value")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT), false, "tainted blocks other trigger")
frame = 201
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), false, "tainted trigger is one frame")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted hold continues")

-- 单帧采样掉到中心后，同方向恢复应继续原生蓄力，不再次触发咳血。
frame = 202
setStick(0, 0)
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted dropout guarded")
frame = 203
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted dropout recovered")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), false, "tainted recovery no sneeze")

-- 真正回中只防抖 2 帧，随后自然释放；稳定回中后才允许下一次咳血。
frame = 204
setStick(0, 0)
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted release debounce")
frame = 205
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted release debounce one")
frame = 206
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), false, "tainted released pressed")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 0, "tainted released value")
frame = 207
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), nil, "tainted rearmed at center")
frame = 208
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted second sneeze")

-- 弱幅输入需要一帧确认方向，避免摇杆刚越过死区时向错误轴咳血。
reset(220)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(0, 0.4)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTDOWN), false, "tainted aim confirming")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN), 0, "tainted hides unconfirmed value")
frame = 221
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTDOWN), true, "tainted confirmed sneeze")

-- 未确认的死区内残余值必须被隐藏，不能绕过状态机让游戏自行咳血。
reset(230)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(0, 0.3)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTDOWN), false, "tainted sub-deadzone trigger hidden")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTDOWN), false, "tainted sub-deadzone press hidden")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN), 0, "tainted sub-deadzone value hidden")

-- 长时间持续推动只维持一次原生攻击手势，不能周期性重复咳血。
reset(240)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted long hold initial trigger")
for heldFrame = 241, 360 do
    frame = heldFrame
    assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), false, "tainted long hold no retrigger")
    assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted long hold remains pressed")
end

-- 回中后的反向 snapback 不能变成第二次攻击；释放后必须重新回中才可武装。
reset(300)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted snapback acquire")
frame = 301
setStick(0, 0)
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted snapback center")
frame = 302
setStick(-1, 0)
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted snapback keeps direction")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT), false, "tainted snapback no trigger")
frame = 303
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTRIGHT), false, "tainted snapback releases")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 0, "tainted snapback suppressed")
frame = 304
setStick(0, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 0, "tainted snapback center rearm starts")
frame = 306
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), nil, "tainted snapback rearms at center")

-- 不带 Analog Stick 时，蓄力仍可在四个原生射击动作之间转向，且不重复咳血。
reset(380)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted cardinal initial trigger")
frame = 381
setStick(0, 1)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 0, "tainted cardinal old direction released")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN), 1, "tainted cardinal turns while charging")
assertEqual(poll(InputHook.IS_ACTION_PRESSED, ButtonAction.ACTION_SHOOTDOWN), true, "tainted cardinal new direction pressed")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTDOWN), false, "tainted cardinal turn has no sneeze")

-- Analog Stick 与里阿撒泻勒组合保留 360° 向量，同时仍只生成一次启动沿。
reset(400)
player.playerType = PlayerType.PLAYER_AZAZEL_B
player.collectibles[CollectibleType.COLLECTIBLE_ANALOG_STICK] = true
setStick(0.8, 0.6)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted analog trigger x")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTDOWN), true, "tainted analog trigger y")
assertClose(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 0.8, 0.0001, "tainted analog x")
assertClose(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN), 0.6, 0.0001, "tainted analog y")
frame = 401
setStick(-0.6, 0.8)
assertClose(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 0.6, 0.0001, "tainted analog turns x")
assertClose(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN), 0.8, 0.0001, "tainted analog turns y")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 0, "tainted analog clears old x")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT), false, "tainted analog turn has no sneeze")

-- 持续蓄力绕完整一圈时保持实时向量，任何新方向都不能生成第二个 triggered。
for degrees = 130, 480, 10 do
    frame = 402 + (degrees - 130) / 10
    local radians = math.rad(degrees)
    local expectedX = math.cos(radians)
    local expectedY = math.sin(radians)
    setStick(expectedX * 0.9, expectedY * 0.9)
    local actualX =
        (poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT) or 0) -
        (poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT) or 0)
    local actualY =
        (poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTDOWN) or 0) -
        (poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTUP) or 0)
    local dot = actualX * expectedX + actualY * expectedY
    if dot < 0.9999 then
        error("tainted analog charge angle drift at " .. tostring(degrees) .. " degrees: dot=" .. tostring(dot))
    end
    assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT), false, "tainted analog loop no left trigger")
    assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), false, "tainted analog loop no right trigger")
    assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTUP), false, "tainted analog loop no up trigger")
    assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTDOWN), false, "tainted analog loop no down trigger")
end

-- 里阿撒泻勒直接出现单帧反向回弹时保持玩家原意；持续反向才接受为主动转向。
reset(450)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted direct snapback acquire")
frame = 451
setStick(-1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "tainted direct snapback keeps intent")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 0, "tainted direct snapback hides reverse")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT), false, "tainted direct snapback no sneeze")
frame = 452
setStick(0, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "tainted direct snapback releases intended direction")

reset(460)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), true, "tainted abrupt turn acquire")
for confirmingFrame = 461, 462 do
    frame = confirmingFrame
    setStick(-1, 0)
    assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "tainted abrupt turn confirming")
    assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT), false, "tainted abrupt turn no sneeze")
end
frame = 463
setStick(-1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTLEFT), 1, "tainted sustained abrupt turn accepted")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 0, "tainted sustained abrupt turn clears old direction")
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT), false, "tainted accepted turn no sneeze")

-- 非玩家、无效手柄和无关动作一律返回 nil，不抢占其他输入处理器。
assertEqual(registeredMod:OnInputAction(nil, InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), nil, "nil entity pass-through")
player.ControllerIndex = 0
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), nil, "keyboard controller pass-through")
player.ControllerIndex = 1
assertEqual(registeredMod:OnInputAction(player, InputHook.GET_ACTION_VALUE, 999), nil, "unrelated action pass-through")

-- 静态边界：运行时代码不得调用生成攻击或修改激光实体的 API。
local sourceFile = assert(io.open("main.lua", "rb"))
local source = sourceFile:read("*a")
sourceFile:close()
for _, forbidden in ipairs({
    "FireBrimstone",
    "FireDelayedBrimstone",
    "GetActiveWeaponEntity",
    "SetTimeout",
    "AddBrimstoneBall",
    "Isaac.Spawn",
}) do
    if string.find(source, forbidden, 1, true) ~= nil then
        error("input-only boundary violated by API: " .. forbidden)
    end
end

-- 普通 Repentance 不启用专用咳血触发重建，避免破坏原本正常的手柄行为。
REPENTANCE_PLUS = false
dofile("main.lua")
reset(500)
player.playerType = PlayerType.PLAYER_AZAZEL_B
setStick(1, 0)
assertEqual(poll(InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTRIGHT), nil, "repentance keeps native trigger")
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "repentance keeps generic filter")

-- 可选的移动、轮询和生命周期 API 缺失时，核心射击滤波仍应正常加载。
REPENTANCE_PLUS = true
Input.IsButtonPressed = nil
Isaac.FindByType = nil
ModCallbacks.MC_POST_UPDATE = nil
ButtonAction.ACTION_LEFT = nil
ButtonAction.ACTION_RIGHT = nil
ButtonAction.ACTION_UP = nil
ButtonAction.ACTION_DOWN = nil
dofile("main.lua")
reset(520)
setStick(1, 0)
assertEqual(poll(InputHook.GET_ACTION_VALUE, ButtonAction.ACTION_SHOOTRIGHT), 1, "optional APIs do not disable core")

print("controller optimizer tests: ok")
