local MOD_NAME = "Controller Optimizer"
local VERSION = "1.6.0"
local mod = RegisterMod(MOD_NAME, 1)
local IS_REPENTANCE_PLUS = REPENTANCE_PLUS == true

-- ============================================================
-- 配置区
-- ============================================================
-- 这些值是 mod 的主要行为边界。优先通过这里调参；MCM 只暴露
-- 对普通玩家最安全的开关和数值。
local Config = {
    Enabled = true,

    -- 保持开启可降低兼容风险：普通眼泪射击不会被 Brimstone 保持逻辑接管。
    OnlyBrimstoneTargets = true,
    EyeOfTheOccultPassThrough = true,
    -- Analog Stick 保留完整二维方向；只滤除死区、回中和回弹，不再吸附到四方向。
    AnalogStick360Enabled = true,

    -- 摇杆超过 EnterDeadzone 才选择新方向；低于 ExitDeadzone 后才进入释放保持计时。
    EnterDeadzone = 0.35,
    ExitDeadzone = 0.20,

    -- 只掩盖极短的摇杆采样掉帧；稳定回中后立即把释放交还给游戏。
    -- 不能用长保持窗口，否则 Brimstone 会在玩家松手后继续蓄力。
    ShootReleaseDebounceFrames = 2,
    -- 有跟随宝宝时沿用旧版兼容路径：优先释放输入，玩家本体激光只做短过渡保护。
    ChargeFamiliarCompatibility = true,
    ChargeFamiliarReleaseFrames = 0,
    ChargeFamiliarLaserHoldFrames = 8,
    ChargeFamiliarLaserCaptureFrames = 8,
    ChargeFamiliarCacheIntervalFrames = 5,

    -- 忽略摇杆回弹造成的短暂、较弱反向尖峰。
    ReverseGuardFrames = 5,
    ReverseGuardDot = -0.35,
    AbruptReverseConfirmFrames = 2,

    -- 普通 Brimstone 使用数字方向；Analog Stick 会自动切换为 360° 模拟输出。
    DigitalOutput = true,
    DirectionSwitchMargin = 0.22,

    -- 里阿撒泻勒需要一次干净的 triggered 启动咳血，随后保持同一输入完成蓄力。
    -- 这里只重建输入契约，不直接生成咳血、激光或伤害。
    TaintedAzazelInputFix = true,
    TaintedAzazelConfirmFrames = 1,
    TaintedAzazelConfirmMagnitude = 0.65,
    TaintedAzazelReleaseDebounceFrames = 2,
    TaintedAzazelRearmFrames = 2,

    -- 火星只做左摇杆误触防护，不提供左摇杆主动触发辅助。
    MarsAnalogGuardEnabled = true,
    MarsAnalogMidMin = 0.12,
    MarsAnalogMidMax = 0.92,
    MarsDigitalPressValue = 0.98,
    MarsReleaseValue = 0.08,
    MarsAnalogValueCap = 0.95,
    MarsSuppressAnalogTriggered = true,
    MarsSuppressAnalogPressed = true,
    MarsAnalogTriggerMemoryFrames = 10,

    -- 独立书包切换：默认按下左摇杆，避开部分手柄上与攻击面键冲突的编号。
    ActiveSwapEnabled = true,
    ActiveSwapControllerButton = 10,

    DiagnosticLogging = false,
    DiagnosticLogLimit = 120,
    Debug = false,
}

-- ============================================================
-- 输入动作分组与运行时状态
-- ============================================================
-- MC_INPUT_ACTION 里会同时收到射击、移动、丢弃/切换等动作。
-- 先用表声明本 mod 接管的动作范围，避免误处理炸弹、卡牌等输入。
-- 表初始化必须容忍 ButtonAction 缺失，这样未来 API 变更时还能进入失效提示。
local SHOOT_ACTIONS = {}
local MOVE_ACTIONS = {}

if ButtonAction ~= nil then
    if ButtonAction.ACTION_SHOOTLEFT ~= nil then
        SHOOT_ACTIONS[ButtonAction.ACTION_SHOOTLEFT] = true
    end
    if ButtonAction.ACTION_SHOOTRIGHT ~= nil then
        SHOOT_ACTIONS[ButtonAction.ACTION_SHOOTRIGHT] = true
    end
    if ButtonAction.ACTION_SHOOTUP ~= nil then
        SHOOT_ACTIONS[ButtonAction.ACTION_SHOOTUP] = true
    end
    if ButtonAction.ACTION_SHOOTDOWN ~= nil then
        SHOOT_ACTIONS[ButtonAction.ACTION_SHOOTDOWN] = true
    end

    if ButtonAction.ACTION_LEFT ~= nil then
        MOVE_ACTIONS[ButtonAction.ACTION_LEFT] = true
    end
    if ButtonAction.ACTION_RIGHT ~= nil then
        MOVE_ACTIONS[ButtonAction.ACTION_RIGHT] = true
    end
    if ButtonAction.ACTION_UP ~= nil then
        MOVE_ACTIONS[ButtonAction.ACTION_UP] = true
    end
    if ButtonAction.ACTION_DOWN ~= nil then
        MOVE_ACTIONS[ButtonAction.ACTION_DOWN] = true
    end
end

local stateByController = {}
local activeSwapButtonStateByController = {}
local chargeFamiliarByController = {}
local chargeFamiliarCacheFrame = -9999
local chargeFamiliarLaserHoldByController = {}
local samplingRawInput = false
local lastSkipLogFrameByKey = {}
local modConfigMenuRegistered = false
local FATAL_MESSAGE = "Controller Optimizer disabled: required input API is missing."
local fatalError = false
local diagnosticLog = {}

-- ============================================================
-- 启动兼容性检查与基础工具
-- ============================================================
-- 目标是让未来游戏版本移除关键 API 时给出明确失败提示，而不是
-- 在输入回调中反复报错。
local function detectFatalError()
    fatalError =
        Input == nil or
        Input.GetActionValue == nil or
        Input.IsButtonPressed == nil or
        InputHook == nil or
        InputHook.IS_ACTION_PRESSED == nil or
        InputHook.GET_ACTION_VALUE == nil or
        InputHook.IS_ACTION_TRIGGERED == nil or
        ModCallbacks == nil or
        ModCallbacks.MC_INPUT_ACTION == nil or
        ModCallbacks.MC_POST_UPDATE == nil or
        ButtonAction == nil or
        ButtonAction.ACTION_SHOOTLEFT == nil or
        ButtonAction.ACTION_SHOOTRIGHT == nil or
        ButtonAction.ACTION_SHOOTUP == nil or
        ButtonAction.ACTION_SHOOTDOWN == nil or
        ButtonAction.ACTION_LEFT == nil or
        ButtonAction.ACTION_RIGHT == nil or
        ButtonAction.ACTION_UP == nil or
        ButtonAction.ACTION_DOWN == nil
end

local function encodeBool(value)
    return value and "1" or "0"
end

local function decodeBool(value, defaultValue)
    if value == "1" or value == "true" then
        return true
    end
    if value == "0" or value == "false" then
        return false
    end
    return defaultValue
end

local function clampNumber(value, minimum, maximum, defaultValue)
    local number = tonumber(value)
    if number == nil then
        number = defaultValue
    end
    if number < minimum then
        return minimum
    end
    if number > maximum then
        return maximum
    end
    return number
end

local function clampInteger(value, minimum, maximum, defaultValue)
    return math.floor(clampNumber(value, minimum, maximum, defaultValue) + 0.5)
end

local function sanitizeConfig()
    Config.ShootReleaseDebounceFrames = clampInteger(Config.ShootReleaseDebounceFrames, 0, 5, 2)
    Config.AbruptReverseConfirmFrames = clampInteger(Config.AbruptReverseConfirmFrames, 1, 5, 2)
    Config.TaintedAzazelConfirmFrames = clampInteger(Config.TaintedAzazelConfirmFrames, 0, 5, 1)
    Config.TaintedAzazelConfirmMagnitude = clampNumber(Config.TaintedAzazelConfirmMagnitude, 0.35, 1, 0.65)
    Config.TaintedAzazelReleaseDebounceFrames = clampInteger(Config.TaintedAzazelReleaseDebounceFrames, 0, 5, 2)
    Config.TaintedAzazelRearmFrames = clampInteger(Config.TaintedAzazelRearmFrames, 1, 8, 2)
    Config.ChargeFamiliarReleaseFrames = clampInteger(Config.ChargeFamiliarReleaseFrames, 0, 15, 0)
    Config.ChargeFamiliarLaserHoldFrames = clampInteger(Config.ChargeFamiliarLaserHoldFrames, 0, 30, 8)
    Config.ChargeFamiliarLaserCaptureFrames = clampInteger(Config.ChargeFamiliarLaserCaptureFrames, 0, 30, 8)
    Config.ChargeFamiliarCacheIntervalFrames = clampInteger(Config.ChargeFamiliarCacheIntervalFrames, 1, 30, 5)
    Config.ActiveSwapControllerButton = clampInteger(Config.ActiveSwapControllerButton, 0, 15, 10)
    Config.DiagnosticLogLimit = clampInteger(Config.DiagnosticLogLimit, 20, 300, 120)
end

-- 诊断日志只写入本 mod 的 SaveData，不在正常游戏画面显示。
local function appendDiagnosticLog(message)
    if not Config.DiagnosticLogging then
        return
    end

    table.insert(diagnosticLog, tostring(Isaac.GetFrameCount()) .. ": " .. tostring(message))
    while #diagnosticLog > Config.DiagnosticLogLimit do
        table.remove(diagnosticLog, 1)
    end
end

local function appendDiagnosticState(reason)
    appendDiagnosticLog(
        tostring(reason) ..
        " version=" .. VERSION ..
        " repentancePlus=" .. encodeBool(IS_REPENTANCE_PLUS) ..
        " enabled=" .. encodeBool(Config.Enabled) ..
        " analog360=" .. encodeBool(Config.AnalogStick360Enabled) ..
        " taintedAzazel=" .. encodeBool(Config.TaintedAzazelInputFix) ..
        " mars=" .. encodeBool(Config.MarsAnalogGuardEnabled) ..
        " schoolbag=" .. encodeBool(Config.ActiveSwapEnabled) ..
        " familiarRelease=" .. encodeBool(Config.ChargeFamiliarCompatibility) ..
        " button=" .. tostring(Config.ActiveSwapControllerButton) ..
        " fatal=" .. encodeBool(fatalError)
    )
end

local function encodeDiagnostics()
    local data = ""
    for _, line in ipairs(diagnosticLog) do
        data = data .. "log=" .. line .. "\n"
    end
    return data
end

-- ============================================================
-- 存档数据
-- ============================================================
-- 保存格式故意保持为简单的 key=value 文本，便于用户手动检查，
-- 也便于旧版本字段迁移。
local function saveSettings()
    sanitizeConfig()
    mod:SaveData(
        "version=" .. VERSION .. "\n" ..
        "Enabled=" .. encodeBool(Config.Enabled) .. "\n" ..
        "TaintedAzazelInputFix=" .. encodeBool(Config.TaintedAzazelInputFix) .. "\n" ..
        "MarsAnalogGuardEnabled=" .. encodeBool(Config.MarsAnalogGuardEnabled) .. "\n" ..
        "ActiveSwapEnabled=" .. encodeBool(Config.ActiveSwapEnabled) .. "\n" ..
        "DiagnosticLogging=" .. encodeBool(Config.DiagnosticLogging) .. "\n" ..
        encodeDiagnostics()
    )
end

-- 读取时兼容几个旧字段名，避免升级后玩家菜单设置丢失。
local function loadSettings()
    if not mod:HasData() then
        sanitizeConfig()
        return
    end

    local data = mod:LoadData() or ""
    diagnosticLog = {}
    for line in string.gmatch(data, "[^\r\n]+") do
        local key, value = string.match(line, "^([^=]+)=(.*)$")
        if key == "Enabled" then
            Config.Enabled = decodeBool(value, Config.Enabled)
        elseif key == "TaintedAzazelInputFix" then
            Config.TaintedAzazelInputFix = decodeBool(value, Config.TaintedAzazelInputFix)
        elseif key == "MarsAnalogGuardEnabled" then
            Config.MarsAnalogGuardEnabled = decodeBool(value, Config.MarsAnalogGuardEnabled)
        elseif key == "ActiveSwapEnabled" then
            Config.ActiveSwapEnabled = decodeBool(value, Config.ActiveSwapEnabled)
        elseif key == "DiagnosticLogging" then
            Config.DiagnosticLogging = decodeBool(value, Config.DiagnosticLogging)
        elseif key == "log" then
            table.insert(diagnosticLog, value)
        end
    end

    sanitizeConfig()
    while #diagnosticLog > Config.DiagnosticLogLimit do
        table.remove(diagnosticLog, 1)
    end
end

-- 所有输入状态都是每局/每房间可重建的临时状态，不进入 SaveData。
local function resetInputState()
    stateByController = {}
    activeSwapButtonStateByController = {}
    chargeFamiliarByController = {}
    chargeFamiliarCacheFrame = -9999
    chargeFamiliarLaserHoldByController = {}
    lastSkipLogFrameByKey = {}
end

-- ============================================================
-- Mod Config Menu
-- ============================================================
-- MCM 是可选依赖：没安装时直接跳过，mod 仍按 Config 默认值运行。
local function registerModConfigMenu()
    if modConfigMenuRegistered or ModConfigMenu == nil or
        ModConfigMenu.AddSetting == nil or ModConfigMenu.OptionType == nil then
        return
    end

    if ModConfigMenu.AddTitle ~= nil then
        ModConfigMenu.AddTitle(MOD_NAME, "General", MOD_NAME)
    end
    if ModConfigMenu.AddText ~= nil then
        ModConfigMenu.AddText(MOD_NAME, "General", function()
            return "Version " .. VERSION
        end)
    end
    if ModConfigMenu.AddSpace ~= nil then
        ModConfigMenu.AddSpace(MOD_NAME, "General")
    end

    ModConfigMenu.AddSetting(
        MOD_NAME,
        "General",
        {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
                return Config.Enabled
            end,
            Display = function()
                return "Enable optimizer: " .. (Config.Enabled and "on" or "off")
            end,
            OnChange = function(value)
                Config.Enabled = value
                sanitizeConfig()
                resetInputState()
                saveSettings()
            end,
            Info = {
                "Master switch for all controller stick optimizations.",
            },
        }
    )

    ModConfigMenu.AddSetting(
        MOD_NAME,
        "General",
        {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
                return Config.ActiveSwapEnabled
            end,
            Display = function()
                return "Schoolbag quick swap: " .. (Config.ActiveSwapEnabled and "on" or "off")
            end,
            OnChange = function(value)
                Config.ActiveSwapEnabled = value
                sanitizeConfig()
                resetInputState()
                saveSettings()
            end,
            Info = {
                "Swaps primary and secondary active item slots.",
                "Default button is left-stick press.",
                "Works with any two active items, not only D Infinity.",
            },
        }
    )

    ModConfigMenu.AddSetting(
        MOD_NAME,
        "General",
        {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
                return Config.TaintedAzazelInputFix
            end,
            Display = function()
                return "Tainted Azazel native input (Rep+): " ..
                    (Config.TaintedAzazelInputFix and "on" or "off")
            end,
            OnChange = function(value)
                Config.TaintedAzazelInputFix = value
                sanitizeConfig()
                resetInputState()
                saveSettings()
            end,
            Info = {
                "Only activates when the REPENTANCE_PLUS API flag is present.",
                "Rebuilds one trigger, then follows the live held direction.",
                "The game still creates the sneeze, charge and Brimstone beam.",
            },
        }
    )

    ModConfigMenu.AddSetting(
        MOD_NAME,
        "General",
        {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
                return Config.MarsAnalogGuardEnabled
            end,
            Display = function()
                return "Mars analog guard: " .. (Config.MarsAnalogGuardEnabled and "on" or "off")
            end,
            OnChange = function(value)
                Config.MarsAnalogGuardEnabled = value
                sanitizeConfig()
                resetInputState()
                saveSettings()
            end,
            Info = {
                "Blocks common Mars accidental triggers from analog left-stick movement.",
                "D-pad style movement remains pass-through.",
            },
        }
    )

    ModConfigMenu.AddSetting(
        MOD_NAME,
        "General",
        {
            Type = ModConfigMenu.OptionType.BOOLEAN,
            CurrentSetting = function()
                return Config.DiagnosticLogging
            end,
            Display = function()
                return "Diagnostic logging: " .. (Config.DiagnosticLogging and "on" or "off")
            end,
            OnChange = function(value)
                Config.DiagnosticLogging = value
                sanitizeConfig()
                if value then
                    appendDiagnosticState("diagnostic enabled")
                end
                saveSettings()
            end,
            Info = {
                "Writes recent internal events into this mod's SaveData.",
                "Does not render gameplay text during normal play.",
            },
        }
    )

    modConfigMenuRegistered = true
end

local function setupModConfigMenu()
    local ok, err = pcall(registerModConfigMenu)
    if not ok and Isaac ~= nil and Isaac.DebugString ~= nil then
        Isaac.DebugString("[" .. MOD_NAME .. "] MCM registration failed: " .. tostring(err))
    end
end

-- ============================================================
-- 主动槽与物品工具
-- ============================================================
-- 这些包装函数主要处理 Repentance+ / Lua API 差异和 nil 防御。
local function getPrimarySlot()
    if ActiveSlot ~= nil and ActiveSlot.SLOT_PRIMARY ~= nil then
        return ActiveSlot.SLOT_PRIMARY
    end
    return 0
end

local function getSecondarySlot()
    if ActiveSlot ~= nil and ActiveSlot.SLOT_SECONDARY ~= nil then
        return ActiveSlot.SLOT_SECONDARY
    end
    return 1
end

local function getEyeOfTheOccultId()
    if CollectibleType ~= nil and CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT ~= nil then
        return CollectibleType.COLLECTIBLE_EYE_OF_THE_OCCULT
    end
    return 572
end

local function getAnalogStickId()
    if CollectibleType ~= nil and CollectibleType.COLLECTIBLE_ANALOG_STICK ~= nil then
        return CollectibleType.COLLECTIBLE_ANALOG_STICK
    end
    return 465
end

local function refreshChargeFamiliarCache()
    local frame = Isaac.GetFrameCount()
    if frame - chargeFamiliarCacheFrame < Config.ChargeFamiliarCacheIntervalFrames then
        return
    end

    chargeFamiliarCacheFrame = frame
    chargeFamiliarByController = {}
    if not Config.Enabled or not Config.ChargeFamiliarCompatibility or
        Isaac == nil or Isaac.FindByType == nil or EntityType == nil or
        EntityType.ENTITY_FAMILIAR == nil then
        return
    end

    local familiars = Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -1, -1, false, false)
    for _, entity in ipairs(familiars) do
        local familiar = entity ~= nil and entity.ToFamiliar ~= nil and entity:ToFamiliar() or nil
        if familiar ~= nil then
            local owner = familiar.Player
            local controllerIndex = owner ~= nil and owner.ControllerIndex or nil
            if controllerIndex ~= nil and controllerIndex > 0 then
                chargeFamiliarByController[controllerIndex] = true
            end
        end
    end
end

local function hasChargeReleaseFamiliar(player)
    if not Config.ChargeFamiliarCompatibility or player == nil then
        return false
    end

    local controllerIndex = player.ControllerIndex
    return controllerIndex ~= nil and chargeFamiliarByController[controllerIndex] == true
end

-- ============================================================
-- 书包快速切换
-- ============================================================
-- 短按独立按钮时，只调用原版 SwapActiveItems，不改主动道具形态、
-- 充能或 VarData。
local function canSwapActiveItems(player)
    if player == nil or player.SwapActiveItems == nil or player.GetActiveItem == nil then
        return false
    end

    local primarySlot = getPrimarySlot()
    local secondarySlot = getSecondarySlot()
    local primaryItem = player:GetActiveItem(primarySlot) or 0
    local secondaryItem = player:GetActiveItem(secondarySlot) or 0

    return primaryItem ~= 0 and secondaryItem ~= 0
end

local function quickSwapActiveItems(player, controllerIndex)
    if not Config.Enabled or not Config.ActiveSwapEnabled or not canSwapActiveItems(player) then
        appendDiagnosticLog("active swap skipped controller=" .. tostring(controllerIndex))
        return
    end

    player:SwapActiveItems()
    appendDiagnosticLog("active swap controller=" .. tostring(controllerIndex))
end

-- 每帧轮询物理按钮编号；松开时执行一次普通书包切换。
local function checkActiveSwapInput()
    if not Config.Enabled then
        return
    end

    local game = Game()
    local playerCount = 1
    local seenControllers = {}
    if game.GetNumPlayers ~= nil then
        playerCount = game:GetNumPlayers()
    end

    for index = 0, playerCount - 1 do
        local player = nil
        if game.GetPlayer ~= nil then
            player = game:GetPlayer(index)
        elseif index == 0 then
            player = Isaac.GetPlayer(0)
        end

        local controllerIndex = player ~= nil and player.ControllerIndex or nil
        if controllerIndex ~= nil and controllerIndex > 0 and not seenControllers[controllerIndex] then
            seenControllers[controllerIndex] = true
            local isDown = Input.IsButtonPressed(Config.ActiveSwapControllerButton, controllerIndex)
            local state = activeSwapButtonStateByController[controllerIndex]
            if state == nil then
                state = {
                    down = false,
                }
                activeSwapButtonStateByController[controllerIndex] = state
            end

            if isDown and not state.down then
                state.down = true
                appendDiagnosticLog("swap button down controller=" .. tostring(controllerIndex))
            elseif not isDown and state.down then
                if Config.ActiveSwapEnabled then
                    quickSwapActiveItems(player, controllerIndex)
                end
                state.down = false
            end
        end
    end
end

-- ============================================================
-- 输入回调基础工具
-- ============================================================
-- logSkip 只服务内部调试，默认关闭，避免玩家日志被高频输入刷屏。
local function logSkip(reason, controllerIndex)
    if not Config.Debug then
        return
    end

    local frame = Isaac.GetFrameCount()
    local key = reason .. ":" .. tostring(controllerIndex or "none")
    local lastFrame = lastSkipLogFrameByKey[key] or -9999
    if frame - lastFrame < 30 then
        return
    end

    lastSkipLogFrameByKey[key] = frame
    Isaac.DebugString(
        string.format(
            "[%s] skip: %s controller=%s",
            MOD_NAME,
            reason,
            tostring(controllerIndex)
        )
    )
end

local function isActionPressedHook(inputHook)
    return InputHook.IS_ACTION_PRESSED ~= nil and inputHook == InputHook.IS_ACTION_PRESSED
end

local function isSupportedInputHook(inputHook)
    return inputHook == InputHook.GET_ACTION_VALUE or
        inputHook == InputHook.IS_ACTION_TRIGGERED or
        isActionPressedHook(inputHook)
end

local function addInputActionCallback(inputHook)
    if inputHook ~= nil then
        mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, mod.OnInputAction, inputHook)
    end
end

-- ============================================================
-- 右摇杆射击方向滤波状态
-- ============================================================
-- 每个 controllerIndex 独立维护状态，避免多手柄或 Steam Deck +
-- 外接手柄时互相污染。
local function clamp01(value)
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

local function getControllerState(controllerIndex)
    local state = stateByController[controllerIndex]
    if state == nil then
        state = {
            frame = -1,
            active = false,
            lastActiveFrame = -9999,
            rawMagnitude = 0,
            x = 0,
            y = 0,
            outLeft = 0,
            outRight = 0,
            outUp = 0,
            outDown = 0,
            outputDir = nil,
            analogAim = false,
            taintedMode = nil,
            taintedArmed = true,
            taintedCandidateFrame = nil,
            taintedCandidateX = 0,
            taintedCandidateY = 0,
            taintedCenterStartFrame = nil,
            triggerFrame = -9999,
            suppressRawShootInput = false,
            releaseStartFrame = nil,
            reverseCandidateFrame = nil,
            reverseCandidateX = 0,
            reverseCandidateY = 0,
            lastSnapbackLogFrame = -9999,
            releaseReason = "none",
            mars = {
                frame = -1,
                outLeft = nil,
                outRight = nil,
                outUp = nil,
                outDown = nil,
                dirs = {
                    left = {
                        active = false,
                        sawAnalogMid = false,
                        analogPress = false,
                        lastAnalogFrame = -9999,
                    },
                    right = {
                        active = false,
                        sawAnalogMid = false,
                        analogPress = false,
                        lastAnalogFrame = -9999,
                    },
                    up = {
                        active = false,
                        sawAnalogMid = false,
                        analogPress = false,
                        lastAnalogFrame = -9999,
                    },
                    down = {
                        active = false,
                        sawAnalogMid = false,
                        analogPress = false,
                        lastAnalogFrame = -9999,
                    },
                },
            },
        }
        stateByController[controllerIndex] = state
    end
    return state
end

local function resetShootState(state)
    state.frame = -1
    state.active = false
    state.lastActiveFrame = -9999
    state.rawMagnitude = 0
    state.x = 0
    state.y = 0
    state.outLeft = 0
    state.outRight = 0
    state.outUp = 0
    state.outDown = 0
    state.outputDir = nil
    state.analogAim = false
    state.taintedArmed = true
    state.taintedCandidateFrame = nil
    state.taintedCandidateX = 0
    state.taintedCandidateY = 0
    state.taintedCenterStartFrame = nil
    state.triggerFrame = -9999
    state.suppressRawShootInput = false
    state.releaseStartFrame = nil
    state.reverseCandidateFrame = nil
    state.reverseCandidateX = 0
    state.reverseCandidateY = 0
    state.lastSnapbackLogFrame = -9999
    state.releaseReason = "none"
end

-- 读取原始输入时会触发同一个 MC_INPUT_ACTION 链路；samplingRawInput
-- 是递归保护，确保内部采样不会再次进入本 mod 的接管逻辑。
local function rawActionValue(action, controllerIndex)
    samplingRawInput = true
    local ok, value = pcall(Input.GetActionValue, action, controllerIndex)
    samplingRawInput = false
    if not ok then
        Isaac.DebugString("[" .. MOD_NAME .. "] Input.GetActionValue failed: " .. tostring(value))
        return 0
    end
    return value or 0
end

-- 把归一化后的摇杆方向转换成输出动作值。默认使用数字方向，
-- 因为 Brimstone 对 0/1 式输入更稳定。
local function updateOutputs(state)
    local x = state.x
    local y = state.y

    if Config.DigitalOutput and not state.analogAim then
        local ax = math.abs(x)
        local ay = math.abs(y)
        local candidateDir = nil
        local candidateStrength = 0
        local currentStrength = 0

        state.outLeft = 0
        state.outRight = 0
        state.outUp = 0
        state.outDown = 0

        if ax >= ay then
            if x < 0 then
                candidateDir = "left"
                candidateStrength = ax
            elseif x > 0 then
                candidateDir = "right"
                candidateStrength = ax
            end
        else
            if y < 0 then
                candidateDir = "up"
                candidateStrength = ay
            elseif y > 0 then
                candidateDir = "down"
                candidateStrength = ay
            end
        end

        if state.outputDir == "left" then
            currentStrength = clamp01(-x)
        elseif state.outputDir == "right" then
            currentStrength = clamp01(x)
        elseif state.outputDir == "up" then
            currentStrength = clamp01(-y)
        elseif state.outputDir == "down" then
            currentStrength = clamp01(y)
        end

        if state.outputDir ~= nil and
            candidateDir ~= nil and
            candidateDir ~= state.outputDir and
            candidateStrength < currentStrength + Config.DirectionSwitchMargin then
            candidateDir = state.outputDir
        end

        state.outputDir = candidateDir

        if candidateDir == "left" then
            state.outLeft = 1
        elseif candidateDir == "right" then
            state.outRight = 1
        elseif candidateDir == "up" then
            state.outUp = 1
        elseif candidateDir == "down" then
            state.outDown = 1
        end
        return
    end

    state.outputDir = nil
    state.outLeft = clamp01(-x)
    state.outRight = clamp01(x)
    state.outUp = clamp01(-y)
    state.outDown = clamp01(y)
end

local function clearReverseCandidate(state)
    state.reverseCandidateFrame = nil
    state.reverseCandidateX = 0
    state.reverseCandidateY = 0
end

-- 平滑转向每帧与上一方向夹角很小，立即接受。只有没有中心采样的突发
-- 大角度反转需要连续存在数帧；这样既过滤回弹，也不锁住正常绕圈转向。
local function shouldAcceptLiveDirection(state, x, y, frame)
    local dot = (x * state.x) + (y * state.y)
    if dot > Config.ReverseGuardDot then
        clearReverseCandidate(state)
        return true
    end

    local candidateDot =
        (x * state.reverseCandidateX) + (y * state.reverseCandidateY)
    if state.reverseCandidateFrame == nil or candidateDot < 0.80 then
        state.reverseCandidateFrame = frame
    end
    state.reverseCandidateX = x
    state.reverseCandidateY = y

    if frame - state.reverseCandidateFrame >= Config.AbruptReverseConfirmFrames then
        clearReverseCandidate(state)
        return true
    end
    return false
end

-- ============================================================
-- 激光武器与角色判定
-- ============================================================
-- 默认只接管 Brimstone 类武器，避免普通眼泪射击被方向保持逻辑影响。
local function isBrimstoneFilterTarget(player)
    if not Config.OnlyBrimstoneTargets then
        return true
    end

    if player == nil then
        return false
    end

    if PlayerType ~= nil and
        PlayerType.PLAYER_AZAZEL_B ~= nil and
        player:GetPlayerType() == PlayerType.PLAYER_AZAZEL_B then
        return true
    end

    if WeaponType and WeaponType.WEAPON_BRIMSTONE and player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE) then
        return true
    end

    return false
end

local function isTaintedAzazel(player)
    return PlayerType ~= nil and
        PlayerType.PLAYER_AZAZEL_B ~= nil and
        player:GetPlayerType() == PlayerType.PLAYER_AZAZEL_B
end

local function playerHasCollectible(player, collectible)
    return player ~= nil and
        collectible ~= nil and
        player.HasCollectible ~= nil and
        player:HasCollectible(collectible)
end

local function hasEyeOfTheOccultPassThrough(player)
    return Config.EyeOfTheOccultPassThrough and
        playerHasCollectible(player, getEyeOfTheOccultId())
end

local function hasAnalogStickAim(player)
    return Config.AnalogStick360Enabled and
        playerHasCollectible(player, getAnalogStickId())
end

local function shouldFilterShootInput(player)
    if hasEyeOfTheOccultPassThrough(player) then
        return false
    end
    return isBrimstoneFilterTarget(player)
end

local function clearShootFilterState(controllerIndex)
    local state = stateByController[controllerIndex]
    if state == nil then
        return
    end

    resetShootState(state)
    state.releaseReason = "passThrough"
end

local function shouldUseChargeFamiliarReleasePath(player)
    return player ~= nil and
        not isTaintedAzazel(player) and
        hasChargeReleaseFamiliar(player) and
        shouldFilterShootInput(player)
end

local extendLaserTimeout

local function startChargeFamiliarLaserHold(controllerIndex, player, state, frame, laser)
    if Config.ChargeFamiliarLaserHoldFrames <= 0 or
        controllerIndex == nil or player == nil or state == nil or
        not shouldUseChargeFamiliarReleasePath(player) then
        return
    end

    if state.x == 0 and state.y == 0 then
        return
    end

    chargeFamiliarLaserHoldByController[controllerIndex] = {
        player = player,
        laser = laser,
        endFrame = frame + Config.ChargeFamiliarLaserHoldFrames,
        captureUntilFrame = frame + Config.ChargeFamiliarLaserCaptureFrames,
    }

    appendDiagnosticLog(
        "charge familiar laser hold controller=" .. tostring(controllerIndex) ..
        " laser=" .. tostring(laser ~= nil) ..
        " holdFrames=" .. tostring(Config.ChargeFamiliarLaserHoldFrames)
    )

    if laser ~= nil and extendLaserTimeout ~= nil then
        extendLaserTimeout(laser, Config.ChargeFamiliarLaserHoldFrames)
    end
end

local function getActivePlayerLaser(player)
    if player == nil then
        return nil
    end

    if player.GetActiveWeaponEntity ~= nil then
        local weapon = player:GetActiveWeaponEntity()
        if weapon ~= nil and weapon.ToLaser ~= nil then
            local laser = weapon:ToLaser()
            if laser ~= nil then
                return laser
            end
        end
    end

    return nil
end

extendLaserTimeout = function(laser, remainingFrames)
    if laser == nil or remainingFrames <= 0 then
        return false
    end

    local currentTimeout = laser.Timeout or 0
    local targetTimeout = math.max(currentTimeout, remainingFrames)
    if laser.Shrink ~= nil then
        laser.Shrink = false
    end
    if laser.SetTimeout ~= nil then
        laser:SetTimeout(targetTimeout)
    else
        laser.Timeout = targetTimeout
    end
    return true
end

local function updateChargeFamiliarLaserHolds()
    if not Config.Enabled or not Config.ChargeFamiliarCompatibility then
        chargeFamiliarLaserHoldByController = {}
        return
    end

    local frame = Isaac.GetFrameCount()
    for controllerIndex, hold in pairs(chargeFamiliarLaserHoldByController) do
        if hold == nil or hold.endFrame == nil or frame > hold.endFrame then
            chargeFamiliarLaserHoldByController[controllerIndex] = nil
        else
            local laser = hold.laser
            if laser == nil or laser.Exists == nil or not laser:Exists() then
                laser = getActivePlayerLaser(hold.player)
                if laser ~= nil then
                    hold.laser = laser
                elseif hold.captureUntilFrame ~= nil and frame > hold.captureUntilFrame then
                    chargeFamiliarLaserHoldByController[controllerIndex] = nil
                end
            end
            if laser ~= nil then
                extendLaserTimeout(laser, hold.endFrame - frame + 1)
            end
        end
    end
end

-- ============================================================
-- Mars 左摇杆误触防护
-- ============================================================
-- Mars 的双击移动触发会受到左摇杆线性行程影响。这里尝试识别
-- 模拟摇杆的中间值轨迹，并对对应方向的 triggered/pressed 做保护。
local function hasMarsAnalogGuard(player)
    if not Config.MarsAnalogGuardEnabled or CollectibleType == nil then
        return false
    end
    return playerHasCollectible(player, CollectibleType.COLLECTIBLE_MARS)
end

local function readStickVector(controllerIndex)
    local left = rawActionValue(ButtonAction.ACTION_SHOOTLEFT, controllerIndex)
    local right = rawActionValue(ButtonAction.ACTION_SHOOTRIGHT, controllerIndex)
    local up = rawActionValue(ButtonAction.ACTION_SHOOTUP, controllerIndex)
    local down = rawActionValue(ButtonAction.ACTION_SHOOTDOWN, controllerIndex)

    return right - left, down - up
end

local function refreshMarsAnalogGuard(state, controllerIndex)
    local mars = state.mars
    local frame = Isaac.GetFrameCount()
    if mars.frame == frame then
        return
    end

    mars.frame = frame
    mars.outLeft = nil
    mars.outRight = nil
    mars.outUp = nil
    mars.outDown = nil

    local leftValue = rawActionValue(ButtonAction.ACTION_LEFT, controllerIndex)
    local rightValue = rawActionValue(ButtonAction.ACTION_RIGHT, controllerIndex)
    local upValue = rawActionValue(ButtonAction.ACTION_UP, controllerIndex)
    local downValue = rawActionValue(ButtonAction.ACTION_DOWN, controllerIndex)
    local directions = mars.dirs
    local function updateDirection(dirState, value, action)
        if value >= Config.MarsAnalogMidMin and value <= Config.MarsAnalogMidMax then
            dirState.sawAnalogMid = true
            dirState.lastAnalogFrame = frame
        end

        if not dirState.active and value >= Config.MarsDigitalPressValue then
            dirState.active = true
            dirState.analogPress = dirState.sawAnalogMid
            dirState.sawAnalogMid = false
        elseif dirState.active and value <= Config.MarsReleaseValue then
            dirState.active = false
            dirState.analogPress = false
            dirState.sawAnalogMid = false
        elseif not dirState.active and value <= Config.MarsReleaseValue then
            dirState.analogPress = false
            dirState.sawAnalogMid = false
        end

        if (dirState.analogPress or dirState.sawAnalogMid) and value > Config.MarsAnalogValueCap then
            if action == ButtonAction.ACTION_LEFT then
                mars.outLeft = Config.MarsAnalogValueCap
            elseif action == ButtonAction.ACTION_RIGHT then
                mars.outRight = Config.MarsAnalogValueCap
            elseif action == ButtonAction.ACTION_UP then
                mars.outUp = Config.MarsAnalogValueCap
            elseif action == ButtonAction.ACTION_DOWN then
                mars.outDown = Config.MarsAnalogValueCap
            end
        end
    end

    updateDirection(directions.left, leftValue, ButtonAction.ACTION_LEFT)
    updateDirection(directions.right, rightValue, ButtonAction.ACTION_RIGHT)
    updateDirection(directions.up, upValue, ButtonAction.ACTION_UP)
    updateDirection(directions.down, downValue, ButtonAction.ACTION_DOWN)
end

local function getMarsAnalogGuardValue(state, controllerIndex, buttonAction)
    refreshMarsAnalogGuard(state, controllerIndex)

    if buttonAction == ButtonAction.ACTION_LEFT then
        return state.mars.outLeft
    elseif buttonAction == ButtonAction.ACTION_RIGHT then
        return state.mars.outRight
    elseif buttonAction == ButtonAction.ACTION_UP then
        return state.mars.outUp
    elseif buttonAction == ButtonAction.ACTION_DOWN then
        return state.mars.outDown
    end

    return nil
end

local function getMoveDirectionName(buttonAction)
    if buttonAction == ButtonAction.ACTION_LEFT then
        return "left"
    elseif buttonAction == ButtonAction.ACTION_RIGHT then
        return "right"
    elseif buttonAction == ButtonAction.ACTION_UP then
        return "up"
    elseif buttonAction == ButtonAction.ACTION_DOWN then
        return "down"
    end

    return nil
end

local function shouldSuppressMarsAnalogInput(state, controllerIndex, buttonAction)
    refreshMarsAnalogGuard(state, controllerIndex)

    local direction = getMoveDirectionName(buttonAction)
    if direction == nil then
        return false
    end

    local dirState = state.mars.dirs[direction]
    local frame = Isaac.GetFrameCount()
    return dirState ~= nil and
        (dirState.analogPress or dirState.sawAnalogMid or
            frame - dirState.lastAnalogFrame <= Config.MarsAnalogTriggerMemoryFrames)
end

-- ============================================================
-- 右摇杆滤波主状态机
-- ============================================================
local function updateAnalogAimMode(state, controllerIndex, player)
    local analogAim = hasAnalogStickAim(player)
    if state.analogAim == analogAim then
        return
    end

    state.analogAim = analogAim
    updateOutputs(state)
    appendDiagnosticLog(
        "aim mode controller=" .. tostring(controllerIndex) ..
        " mode=" .. (analogAim and "analog360" or "cardinal")
    )
end

local function finishShootRelease(state, reason, suppressRaw)
    state.active = false
    state.x = 0
    state.y = 0
    state.releaseStartFrame = nil
    clearReverseCandidate(state)
    state.triggerFrame = -9999
    state.suppressRawShootInput = suppressRaw == true
    state.releaseReason = reason
    updateOutputs(state)
end

-- 普通 Brimstone/Azazel 只稳定方向值。triggered/pressed 仍由原版处理，
-- 避免 Mod 把已经回中的摇杆继续伪装成“按住”而延迟发射。
local function refreshGenericBrimstoneState(state, controllerIndex, player)
    local frame = Isaac.GetFrameCount()
    if state.frame == frame then
        return
    end

    state.frame = frame

    state.suppressRawShootInput = false
    updateAnalogAimMode(state, controllerIndex, player)

    local rawX, rawY = readStickVector(controllerIndex)
    local magnitude = math.sqrt(rawX * rawX + rawY * rawY)
    state.rawMagnitude = magnitude

    if magnitude >= Config.EnterDeadzone then
        local x = rawX / magnitude
        local y = rawY / magnitude
        local dot = (x * state.x) + (y * state.y)
        local releaseAge = state.releaseStartFrame ~= nil and
            frame - state.releaseStartFrame or nil
        local springBackSpike =
            state.active and
            releaseAge ~= nil and
            releaseAge <= Config.ReverseGuardFrames and
            dot <= Config.ReverseGuardDot

        if springBackSpike then
            -- 只有已经经过中心的短反向尖峰才作为 snapback。保持该帧为
            -- 释放态；若反向输入持续，下一帧会作为新的原生攻击交还游戏。
            if releaseAge >= Config.ShootReleaseDebounceFrames then
                finishShootRelease(state, "snapbackReleased", true)
            elseif frame - state.lastSnapbackLogFrame > Config.ReverseGuardFrames then
                state.lastSnapbackLogFrame = frame
                appendDiagnosticLog(
                    "snapback rejected controller=" .. tostring(controllerIndex) ..
                    " raw=" .. string.format("%.3f,%.3f", rawX, rawY) ..
                    " dot=" .. string.format("%.3f", dot)
                )
            end
        elseif shouldAcceptLiveDirection(state, x, y, frame) then
            local previousOutputDir = state.outputDir
            state.x = x
            state.y = y
            state.active = true
            state.lastActiveFrame = frame
            state.releaseStartFrame = nil
            state.releaseReason = "active"
            updateOutputs(state)
            if previousOutputDir ~= state.outputDir then
                appendDiagnosticLog(
                    "direction controller=" .. tostring(controllerIndex) ..
                    " mode=" .. (state.analogAim and "analog360" or "cardinal") ..
                    " raw=" .. string.format("%.3f,%.3f", rawX, rawY) ..
                    " out=" .. string.format("%.3f,%.3f", state.x, state.y)
                )
            end
        else
            state.lastActiveFrame = frame
            state.releaseReason = "abruptReverseConfirming"
        end
    elseif state.active and
        (magnitude < Config.ExitDeadzone or state.releaseStartFrame ~= nil) then
        if state.releaseStartFrame == nil then
            state.releaseStartFrame = frame
            clearReverseCandidate(state)
            appendDiagnosticLog(
                "release pending controller=" .. tostring(controllerIndex) ..
                " rawMagnitude=" .. string.format("%.3f", magnitude) ..
                " direction=" .. string.format("%.3f,%.3f", state.x, state.y)
            )
        end

        if shouldUseChargeFamiliarReleasePath(player) and
            frame - state.lastActiveFrame > Config.ChargeFamiliarReleaseFrames then
            local chargeFamiliarLaser = getActivePlayerLaser(player)
            startChargeFamiliarLaserHold(controllerIndex, player, state, frame, chargeFamiliarLaser)
            finishShootRelease(state, "chargeFamiliarReleased", false)
            return
        end

        if frame - state.releaseStartFrame >= Config.ShootReleaseDebounceFrames then
            finishShootRelease(state, "releasedAtCenter", false)
            appendDiagnosticLog(
                "released controller=" .. tostring(controllerIndex) ..
                " reason=" .. tostring(state.releaseReason) ..
                " rawMagnitude=" .. string.format("%.3f", magnitude)
            )
        end
    end

    if Config.Debug and frame % 15 == 0 then
        Isaac.DebugString(
            string.format(
                "[%s] c=%d raw=(%.2f, %.2f) active=%s analog=%s last=%d age=%d out=(%.2f %.2f %.2f %.2f) reason=%s",
                MOD_NAME,
                controllerIndex,
                rawX,
                rawY,
                tostring(state.active),
                tostring(state.analogAim),
                state.lastActiveFrame,
                frame - state.lastActiveFrame,
                state.outLeft,
                state.outRight,
                state.outUp,
                state.outDown,
                tostring(state.releaseReason)
            )
        )
    end
end

-- 里阿撒泻勒的原生攻击依赖一次 triggered 启动咳血，随后由持续的
-- pressed/value 继续蓄力。启动沿只生成一次，但蓄力方向必须实时跟随摇杆。
-- 状态机只修复输入序列，游戏仍负责咳血、蓄力和 Brimstone 实体。
local function refreshTaintedAzazelState(state, controllerIndex, player)
    local frame = Isaac.GetFrameCount()
    if state.frame == frame then
        return
    end

    state.frame = frame
    updateAnalogAimMode(state, controllerIndex, player)

    local rawX, rawY = readStickVector(controllerIndex)
    local magnitude = math.sqrt(rawX * rawX + rawY * rawY)
    state.rawMagnitude = magnitude

    if state.active then
        state.suppressRawShootInput = true

        if magnitude >= Config.EnterDeadzone then
            local x = rawX / magnitude
            local y = rawY / magnitude
            local releaseAge = state.releaseStartFrame ~= nil and
                frame - state.releaseStartFrame or nil
            local dot = (x * state.x) + (y * state.y)
            local springBackSpike = releaseAge ~= nil and
                releaseAge <= Config.ReverseGuardFrames and
                dot <= Config.ReverseGuardDot

            if springBackSpike then
                if releaseAge >= Config.TaintedAzazelReleaseDebounceFrames then
                    state.taintedCenterStartFrame = nil
                    finishShootRelease(state, "taintedReleasedAfterSnapback", true)
                end
            elseif shouldAcceptLiveDirection(state, x, y, frame) then
                -- 持续推动期间每帧更新方向。这里只改变 value/pressed 的方向，
                -- triggerFrame 不变，因此转向不会再次咳血。
                state.x = x
                state.y = y
                state.releaseStartFrame = nil
                state.lastActiveFrame = frame
                state.releaseReason = "taintedCharging"
                updateOutputs(state)
            else
                state.lastActiveFrame = frame
                state.releaseReason = "taintedAbruptReverseConfirming"
            end
        elseif magnitude < Config.ExitDeadzone or state.releaseStartFrame ~= nil then
            if state.releaseStartFrame == nil then
                state.releaseStartFrame = frame
                clearReverseCandidate(state)
                state.releaseReason = "taintedReleasePending"
                appendDiagnosticLog(
                    "tainted release pending controller=" .. tostring(controllerIndex) ..
                    " direction=" .. string.format("%.3f,%.3f", state.x, state.y)
                )
            end

            if frame - state.releaseStartFrame >= Config.TaintedAzazelReleaseDebounceFrames then
                state.taintedCenterStartFrame = state.releaseStartFrame
                finishShootRelease(state, "taintedReleased", true)
            end
        else
            -- 尚未真正回中的滞回带只保持当前方向，不自行制造释放。
            state.lastActiveFrame = frame
        end

        return
    end

    if not state.taintedArmed then
        state.taintedCandidateFrame = nil
        state.suppressRawShootInput = true

        if magnitude < Config.ExitDeadzone then
            if state.taintedCenterStartFrame == nil then
                state.taintedCenterStartFrame = frame
            end
            if frame - state.taintedCenterStartFrame >= Config.TaintedAzazelRearmFrames then
                state.taintedArmed = true
                state.taintedCenterStartFrame = nil
                state.suppressRawShootInput = false
                state.releaseReason = "taintedArmed"
                appendDiagnosticLog("tainted rearmed controller=" .. tostring(controllerIndex))
            end
        else
            state.taintedCenterStartFrame = nil
        end
        return
    end

    state.suppressRawShootInput = false
    if magnitude < Config.EnterDeadzone then
        state.taintedCandidateFrame = nil
        -- 小于进入死区但仍非零的轴值不能漏回原版输入，否则游戏可能在
        -- 状态机确认方向前自行产生一次不稳定的 triggered。
        state.suppressRawShootInput = magnitude > 0.01
        return
    end

    local x = rawX / magnitude
    local y = rawY / magnitude
    if state.taintedCandidateFrame == nil then
        state.taintedCandidateFrame = frame
    end
    state.taintedCandidateX = x
    state.taintedCandidateY = y
    state.suppressRawShootInput = true

    local candidateAge = frame - state.taintedCandidateFrame
    if magnitude < Config.TaintedAzazelConfirmMagnitude and
        candidateAge < Config.TaintedAzazelConfirmFrames then
        state.releaseReason = "taintedAimConfirming"
        return
    end

    state.x = state.taintedCandidateX
    state.y = state.taintedCandidateY
    state.active = true
    state.lastActiveFrame = frame
    state.taintedArmed = false
    state.taintedCandidateFrame = nil
    state.taintedCenterStartFrame = nil
    state.releaseStartFrame = nil
    state.triggerFrame = frame
    state.releaseReason = "taintedTriggered"
    updateOutputs(state)
    appendDiagnosticLog(
        "tainted triggered controller=" .. tostring(controllerIndex) ..
        " mode=" .. (state.analogAim and "analog360" or "cardinal") ..
        " raw=" .. string.format("%.3f,%.3f", rawX, rawY) ..
        " direction=" .. string.format("%.3f,%.3f", state.x, state.y)
    )
end

local function refreshControllerState(state, controllerIndex, player)
    -- 普通 Repentance 的手柄路径本来正常；专用触发重建只在 Repentance+ 启用。
    local taintedMode = IS_REPENTANCE_PLUS and
        Config.TaintedAzazelInputFix and isTaintedAzazel(player)
    if state.taintedMode ~= taintedMode then
        resetShootState(state)
        state.taintedMode = taintedMode
        appendDiagnosticLog(
            "shoot profile controller=" .. tostring(controllerIndex) ..
            " profile=" .. (taintedMode and "taintedAzazel" or "brimstone")
        )
    end

    if taintedMode then
        refreshTaintedAzazelState(state, controllerIndex, player)
    else
        refreshGenericBrimstoneState(state, controllerIndex, player)
    end
end

-- ============================================================
-- 输入回调入口
-- ============================================================
-- 这是所有输入接管的唯一入口。处理顺序有意保持为：
-- 1. 快速放行不相关输入；
-- 2. 处理 Mars 移动保护；
-- 3. 处理通用激光方向滤波。
local function getPlayerFromEntity(entity)
    if entity == nil or entity.ToPlayer == nil then
        return nil
    end
    return entity:ToPlayer()
end

local function getShootOutput(state, buttonAction)
    if buttonAction == ButtonAction.ACTION_SHOOTLEFT then
        return state.outLeft
    elseif buttonAction == ButtonAction.ACTION_SHOOTRIGHT then
        return state.outRight
    elseif buttonAction == ButtonAction.ACTION_SHOOTUP then
        return state.outUp
    elseif buttonAction == ButtonAction.ACTION_SHOOTDOWN then
        return state.outDown
    end
    return nil
end

local function handleTaintedAzazelShootInput(state, inputHook, buttonAction)
    local output = getShootOutput(state, buttonAction) or 0
    -- 里阿撒泻勒由“稳定回中后重新武装”自行界定手势边界；重新武装后
    -- 立即归还输入，不再叠加普通 Brimstone 的释放保护窗口。
    local suppressInactive = state.suppressRawShootInput

    if inputHook == InputHook.IS_ACTION_TRIGGERED then
        if state.active then
            return Isaac.GetFrameCount() == state.triggerFrame and output > 0.001
        end
        if suppressInactive then
            return false
        end
        return nil
    end

    if isActionPressedHook(inputHook) then
        if state.active then
            return output > 0.001
        end
        if suppressInactive then
            return false
        end
        return nil
    end

    if state.active then
        return output
    end
    return suppressInactive and 0 or nil
end

local function handleGenericShootInput(state, inputHook, buttonAction)
    if inputHook == InputHook.IS_ACTION_TRIGGERED or isActionPressedHook(inputHook) then
        if state.releaseReason == "chargeFamiliarReleased" and
            state.rawMagnitude < Config.EnterDeadzone then
            return false
        end
        if state.suppressRawShootInput then
            return false
        end
        -- 普通 Brimstone/Azazel 的按下沿与松开沿完全交还原版。
        return nil
    end

    if state.suppressRawShootInput then
        return 0
    end
    if state.active then
        return getShootOutput(state, buttonAction)
    end
    if state.releaseReason == "chargeFamiliarReleased" and
        state.rawMagnitude < Config.EnterDeadzone then
        return 0
    end
    return nil
end

function mod:OnInputAction(entity, inputHook, buttonAction)
    if samplingRawInput then
        return nil
    end

    if not Config.Enabled then
        logSkip("disabled")
        return nil
    end

    if not isSupportedInputHook(inputHook) then
        logSkip("non-supported input hook")
        return nil
    end

    if not SHOOT_ACTIONS[buttonAction] and not MOVE_ACTIONS[buttonAction] then
        logSkip("non-supported action")
        return nil
    end

    local player = getPlayerFromEntity(entity)
    if player == nil then
        logSkip("entity is not player")
        return nil
    end

    local controllerIndex = player.ControllerIndex
    if controllerIndex == nil or controllerIndex <= 0 then
        logSkip("invalid controllerIndex", controllerIndex)
        return nil
    end

    local state = getControllerState(controllerIndex)

    if MOVE_ACTIONS[buttonAction] then
        if inputHook == InputHook.IS_ACTION_TRIGGERED or isActionPressedHook(inputHook) then
            local suppressMarsAnalog =
                inputHook == InputHook.IS_ACTION_TRIGGERED and Config.MarsSuppressAnalogTriggered
            if isActionPressedHook(inputHook) then
                suppressMarsAnalog = Config.MarsSuppressAnalogPressed
            end

            if suppressMarsAnalog and hasMarsAnalogGuard(player) and
                shouldSuppressMarsAnalogInput(state, controllerIndex, buttonAction) then
                appendDiagnosticLog(
                    "mars analog suppressed controller=" .. tostring(controllerIndex) ..
                    " action=" .. tostring(buttonAction) ..
                    " hook=" .. tostring(inputHook)
                )
                return false
            end
            return nil
        end
        if hasMarsAnalogGuard(player) then
            return getMarsAnalogGuardValue(state, controllerIndex, buttonAction)
        end
        return nil
    end

    if hasEyeOfTheOccultPassThrough(player) then
        clearShootFilterState(controllerIndex)
        return nil
    end

    if not shouldFilterShootInput(player) then
        logSkip("no Brimstone filter target", player.ControllerIndex)
        return nil
    end

    refreshControllerState(state, controllerIndex, player)
    if state.taintedMode then
        return handleTaintedAzazelShootInput(state, inputHook, buttonAction)
    end
    return handleGenericShootInput(state, inputHook, buttonAction)
end

-- ============================================================
-- 游戏生命周期回调
-- ============================================================
-- 房间/新局重置临时输入状态，避免上一房间的保持方向污染当前房间。
function mod:OnNewRun()
    resetInputState()
    setupModConfigMenu()
    appendDiagnosticState("new run")
end

function mod:OnNewRoom()
    resetInputState()
    appendDiagnosticLog("new room")
end

function mod:OnPostUpdate()
    refreshChargeFamiliarCache()
    updateChargeFamiliarLaserHolds()
    checkActiveSwapInput()
end

function mod:OnPostRender()
    if fatalError and Isaac.RenderText ~= nil then
        Isaac.RenderText(FATAL_MESSAGE, 42, 42, 1, 1, 1, 1)
    end
end

function mod:OnPreGameExit()
    appendDiagnosticState("game exit")
    saveSettings()
end

-- ============================================================
-- 回调注册
-- ============================================================
-- MC_POST_RENDER 即使 fatalError 也注册，用于显示失效提示。
-- 其他功能回调只有在关键输入 API 存在时才注册。
detectFatalError()
loadSettings()
appendDiagnosticState("loaded")
setupModConfigMenu()

if ModCallbacks ~= nil and ModCallbacks.MC_POST_RENDER ~= nil then
    mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.OnPostRender)
end

if not fatalError then
    addInputActionCallback(InputHook.GET_ACTION_VALUE)
    addInputActionCallback(InputHook.IS_ACTION_TRIGGERED)
    addInputActionCallback(InputHook.IS_ACTION_PRESSED)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnNewRun)
    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom)
    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnPostUpdate)
    if ModCallbacks.MC_PRE_GAME_EXIT ~= nil then
        mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.OnPreGameExit)
    end
end



