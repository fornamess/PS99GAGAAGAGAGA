--[[
    ================================================================
       SOCCER EVENT AUTO  v5.15  —  Pet Sim 99 / Soccer Event
    ================================================================
    Полностью исследовано вживую через Roblox MCP (placeId 8737899170,
    executor Volt 1.2.24.3). Все механики подтверждены на реальной игре.

    ВОЗМОЖНОСТИ
      • Авто-кик (футбол): InfiniteShoot с идеальной точностью на макс.
        серверной частоте. БЕЗ анимации (прямой Invoke) и НЕ привязан к
        позиции — можно стоять на яйце и одновременно бить. (проверено)
      • Авто-сбор орбов: без лагов, реестр через upvalue, getgc один раз.
      • Авто-открытие яиц: использует встроенный авто-хэтч игры
        (server-side, не конфликтует с киком). Стой на яйце — скрипт держит
        авто-хэтч включённым.
      • Умные апгрейды: тратит SoccerOrbs по приоритету (доход / 100% крит).
      • Авто-экип: PetCmds.EquipBest (LD_BestFit — как кнопка Equip Best в игре).
      • Анти-АФК: VirtualUser + Players.Idled (проверено).
      • Оптимизация игры (обратимая): FPS-cap, отключение пост-эффектов,
        понижение качества рендера.

    ОПТИМИЗАЦИЯ САМОГО СКРИПТА
      • Чистый перезапуск: повторный запуск гасит прошлый экземпляр
        (нет утечки потоков/коннектов).
      • Кик вынесен в отдельный поток (Invoke yield не стопорит сбор орбов).
      • Горячие пути без аллокаций замыканий (pcall(fn, args)).
      • Централизованная обработка ошибок с rate-limit (нет спама).
      • Все коннекты и изменения настроек хранятся и откатываются в Stop().

    УПРАВЛЕНИЕ
      Стоп:    getgenv().__SoccerAuto.Stop()
      Статус:  getgenv().__SoccerAuto.Status()
    ================================================================
]]

--======================== НАСТРОЙКИ ========================--
local CONFIG = {
    -- Модули (вкл/выкл)
    COLLECT_ORBS = true,
    AUTO_KICK    = true,   -- кастомный быстрый кик (InfiniteShoot)
    AUTO_HATCH   = true,   -- авто-открытие кастом-яйца (CustomEggs_Hatch)
    AUTO_UPGRADE = true,
    AUTO_EQUIP_PETS = true,  -- PetCmds.EquipBest (LD_BestFit)
    ANTI_AFK     = true,
    OPTIMIZE_GAME = true,  -- обратимая оптимизация графики

    -- Кик
    KICK_ACCURACY = 1.0,   -- InfiniteShoot (endgame)
    GATE_KICK_ACCURACY = 0.99, -- Shoot по воротам — игра шлёт 0.98–0.99 (хук)
    KICK_RATE     = 3.05,  -- пауза между киками InfiniteShoot (сек). Guard = 3с.
    GATE_KICK_RATE = 2.5,  -- пауза между ударами по воротам (Shoot)
    KICK_BACKOFF  = 0.6,   -- пауза, если кик отклонён сервером

    -- Орбы
    CLAIM_INTERVAL      = 0.15, -- быстрый проход, когда орбы есть
    CLAIM_INTERVAL_IDLE = 0.65, -- медленный проход, когда реестр пуст
    DESTROY_MODEL  = true, -- убирать модель орба после сбора

    -- Апгрейды
    UPGRADE_INTERVAL = 2.0,
    ORB_RESERVE      = 0,

    -- Экип: EquipBest / LD_BestFit (как кнопка Equip Best в инвентаре)
    EQUIP_BEST_INTERVAL = 30,
    EQUIP_BEST_COOLDOWN = 8,
    EQUIP_ENSURE_AUTO   = true,
    EQUIP_DISABLE_FAVORITE = true,
    PRIORITIZE_100_PERCENT = false, -- сперва Critical+Trickshot до 100%
    UPGRADE_PRIORITY = {
        "SoccerYeetOrbStrength", "SoccerYeetOrbsReach", "SoccerBetterYeetEgg",
        "SoccerCriticalThrowChance", "SoccerTrickshotThrowChance",
    },
    UPGRADE_PRIORITY_100 = {
        "SoccerCriticalThrowChance", "SoccerTrickshotThrowChance",
        "SoccerYeetOrbStrength", "SoccerYeetOrbsReach", "SoccerBetterYeetEgg",
    },

    -- Хэтч (кастом-яйцо на будке CustomEggs — проверено через хуки)
    -- Анимация "Click to open!" обходится: шлём CustomEggs_Hatch напрямую без
    -- AttemptHatch (это и есть анимация). Темп держит сам сервер (debounce ~1.6с).
    HATCH_RANGE       = 25,    -- радиус поиска будки (studs)
    HATCH_BEST_EGG    = true,  -- лучший Soccer Egg в ивенте (Egg N * 100 + Tier)
    HATCH_INSTANCE_ONLY = true, -- в SoccerEvent только будки внутри инстанса
    HATCH_BOOTH_UID   = nil,   -- nil = авто; или GUID вручную
    HATCH_EGG_ID      = nil,   -- nil = авто через CustomEggsCmds.Get
    HATCH_SKIP_ANIM   = true,  -- НЕ запускать AttemptHatch (обход "Click to open!")
    HATCH_SKIP_SETUP  = true,  -- НЕ SetupCustomEgg/AutoHatch_Enable (анимация + Walk away + скрытие Main)
    HATCH_HIDE_GUI    = true,  -- скрыть VFX хэтча (Camera + оверлеи), Main/инвентарь не трогаем
    HATCH_RETRY       = 0.15,  -- пауза при отклонённом хэтче (сек)
    HATCH_WAIT_BEST   = 0.4,   -- пауза, пока Egg 5 не прогрузится (streaming)
    HATCH_SUPPRESS_SEC = 4,    -- окно очистки Camera VFX после хэтча
    HATCH_DEFAULT_COUNT = 27,  -- запасной count, если не удалось определить max
    EGG_ZONE_TP_COOLDOWN = 8.0, -- не чаще телепорта к зоне яиц (сек)
    EGG_ZONE_NEAR_DIST  = 180,  -- уже в Area N — не телепортировать повторно
    EGG_STREAM_WAIT   = 0.35,  -- пауза после телепорта для streaming CustomEggs

    -- Апгрейды: "priority" | "smart" (самый дешёвый из приоритетных) | "cheapest" (глобально дешёвый)
    UPGRADE_MODE = "smart",

    -- Авто-вход / телепорты
    AUTO_ENTER          = true,  -- InstancingCmds.Enter("SoccerEvent")
    AUTO_TELEPORT_EGG   = true,  -- телепорт к лучшему яйцу (кик без телепорта)
    TELEPORT_EGG_DIST   = 12,    -- телепорт к будке, если дальше N studs
    EGG_BOOTH_TP_COOLDOWN = 2.0, -- не чаще привязки к будке (сек)
    AUTO_ZONE_PROGRESS  = true,  -- авто-прогрессия зон 1→5 (Shoot + покупка зон)
    MAX_SOCCER_ZONE     = 5,

    -- Кик: recovery при серверных ошибках
    KICK_FAIL_HOP_AFTER = 8,     -- после N fail — Move Server (hop)

    -- Доп. клеймы / бусты (проверено через MCP)
    AUTO_FREE_GIFTS    = true,  -- Redeem Free Gift 1..12 по Save.FreeGiftsRedeemed
    AUTO_KICK_REWARDS  = true,  -- GenerateReward когда Soccer*Credits >= 10
    AUTO_CONSUMABLES   = true,  -- авто-юз Cleats / Golden Cleats / Soccer Orb Frenzy
    SOCCER_CONSUMABLES = { "Golden Cleats", "Cleats", "Soccer Orb Frenzy" },
    AUTO_FOREVER_FREE  = true,  -- ForeverPacks: Claim Free (если доступно)

    -- Оптимизация
    FPS_CAP            = 60,    -- 0 = не трогать
    DISABLE_POSTFX     = true,  -- выключить Bloom/Blur/DOF/SunRays
    LOWER_QUALITY      = true,  -- понизить уровень качества рендера
    POTATO_MODE        = true,  -- PlayerGraphicsSetting_Set PotatoMode (игровой режим)
    STRIP_SOCCER_VFX   = true,  -- particles/shadows в SoccerEvent (~74 эмиттера)
    EGG_POTATO_MODE    = true,  -- меньше частиц при хэтче (EggPotatoMode)
    STRIP_VFX_INTERVAL = 45,    -- повторная чистка VFX (сек)

    -- Intermission: ускоренные клеймы/апгрейды между раундами
    INTERMISSION_BURST = true,

    -- Пауза кика на Intermission (сервер всё равно отклоняет кики в паузе)
    PAUSE_ON_INTERMISSION = true,

    -- Авто-клеймы (проверено: Login Streak по CanClaim, Mailbox Claim All)
    AUTO_CLAIM         = true,
    CLAIM_CHECK_INTERVAL = 60, -- как часто проверять клеймы (сек)

    -- Авто-перезапуск
    AUTO_REJOIN       = true,  -- реджойн при вылете/дисконнекте
    QUEUE_ON_TELEPORT = true,  -- авто-перезапуск скрипта после телепорта/реджойна
    GITHUB_BASE       = "https://raw.githubusercontent.com/fornamess/PS99GAGAAGAGAGA/main",
    GITHUB_RAW_URL    = "https://raw.githubusercontent.com/fornamess/PS99GAGAAGAGAGA/main/soccer_auto.lua",
    SCRIPT_PATH       = "soccer_auto.lua", -- запасной локальный путь, если GITHUB_RAW_URL пуст

    -- Обход зависания BIG GAMES без фокуса окна (Intro + PreloadAsync).
    -- Luau не может дать OS-фокус — параллельно запусти focus_helper.ps1 на Windows.
    BYPASS_LOAD_STALL = true,
}
--===========================================================--

-- Ранний bootstrap (Intro/PreloadAsync) — до инициализации скрипта
if CONFIG.BYPASS_LOAD_STALL then
    pcall(function()
        local base = CONFIG.GITHUB_BASE or ""
        local loaded = false
        if type(readfile) == "function" and type(isfile) == "function" and isfile("bootstrap.lua") then
            local src = readfile("bootstrap.lua")
            if type(src) == "string" and src ~= "" then
                loadstring(src)()
                loaded = true
            end
        end
        if not loaded and base ~= "" and game.HttpGet then
            loadstring(game:HttpGet(base .. "/bootstrap.lua"))()
        elseif not loaded then
            -- inline fallback, если HttpGet недоступен
            local G = (getgenv and getgenv()) or _G
            if not G.__PS99BootstrapDone then
                G.__PS99BootstrapDone = true
                pcall(function()
                    local RF = game:GetService("ReplicatedFirst")
                    RF:RemoveDefaultLoadingScreen()
                    local intro = RF:FindFirstChild("Intro")
                    if intro then intro.Disabled = true end
                end)
            end
        end
    end)
end

----------------------------------------------------------------
-- окружение / утилиты executor (UNC/sUNC)
----------------------------------------------------------------
local ENV = (getgenv and getgenv()) or _G

-- Чистый перезапуск: гасим прошлый экземпляр (защита от утечек).
if type(ENV.__SoccerAuto) == "table" and type(ENV.__SoccerAuto.Stop) == "function" then
    pcall(ENV.__SoccerAuto.Stop)
    task.wait(0.2)
end

local U = {
    getgc        = (getgc),
    getupvalue   = (getupvalue)   or (debug and rawget(debug, "getupvalue")),
    getupvalues  = (getupvalues)  or (debug and rawget(debug, "getupvalues")),
    setfpscap    = (setfpscap),
    cloneref     = (cloneref) or function(x) return x end,
    identify     = (identifyexecutor) or function() return "unknown" end,
}

local function svc(name)
    return U.cloneref(game:GetService(name))
end

local Players          = svc("Players")
local ReplicatedStorage = svc("ReplicatedStorage")
local Lighting         = svc("Lighting")
local LocalPlayer      = Players.LocalPlayer

----------------------------------------------------------------
-- рантайм-состояние (для чистой остановки)
----------------------------------------------------------------
local App = {}
local Runtime = {
    running = true,
    connections = {},
    restore = {},          -- что откатить при Stop
    stats = { kicks = 0, orbs = 0, upgrades = 0, hatches = 0, claims = 0, errors = 0 },
}
ENV.__SoccerAuto = App

local function track(conn) Runtime.connections[#Runtime.connections + 1] = conn return conn end

-- rate-limited обработчик ошибок (без спама в консоль)
local _errLog = {}
local function safe(tag, fn)
    local ok, err = pcall(fn)
    if not ok then
        Runtime.stats.errors += 1
        local now = os.clock()
        if not _errLog[tag] or (now - _errLog[tag]) > 5 then
            _errLog[tag] = now
            warn(("[SoccerAuto] %s: %s"):format(tag, tostring(err)))
        end
    end
    return ok
end

local function spawnLoop(name, body)
    task.spawn(function()
        while Runtime.running do
            body()
        end
    end)
end

local function safeRequire(inst)
    if not inst then return nil end
    local ok, m = pcall(require, inst)
    return ok and m or nil
end

----------------------------------------------------------------
-- ссылки на игру
----------------------------------------------------------------
local Library = ReplicatedStorage:WaitForChild("Library", 10)
local Network = ReplicatedStorage:WaitForChild("Network", 10)
if not Library or not Network then
    warn("[SoccerAuto] Не найден Library/Network — не та игра?")
    return
end

local FireCustom   = Network:WaitForChild("Instancing_FireCustomFromClient", 10)
local InvokeCustom = Network:WaitForChild("Instancing_InvokeCustomFromClient", 10)
local CustomEggsHatch = Network:WaitForChild("CustomEggs_Hatch", 10)
local AutoHatchEnable = Network:FindFirstChild("AutoHatch_Enable")

local Client = Library:WaitForChild("Client", 10)
local InstancingCmds   = safeRequire(Client:FindFirstChild("InstancingCmds"))
local InstanceZoneCmds = safeRequire(Client:FindFirstChild("InstanceZoneCmds"))
local EventUpgradeCmds = safeRequire(Client:FindFirstChild("EventUpgradeCmds"))
local CurrencyCmds     = safeRequire(Client:FindFirstChild("CurrencyCmds"))
local Hatching         = safeRequire(Client:FindFirstChild("HatchingCmds"))
local EggCmds          = safeRequire(Client:FindFirstChild("EggCmds"))
local CustomEggsCmds   = safeRequire(Client:FindFirstChild("CustomEggsCmds"))
local PetCmds          = safeRequire(Client:FindFirstChild("PetCmds"))
local LoginStreakCmds  = safeRequire(Client:FindFirstChild("LoginStreakCmds"))
local ConsumableCmds   = safeRequire(Client:FindFirstChild("ConsumableCmds"))
local SaveCmds         = safeRequire(Client:FindFirstChild("Save"))
local SoccerType       = safeRequire(Library.Types and Library.Types:FindFirstChild("Soccer"))
local ConsumableItem   = safeRequire(Library.Items and Library.Items:FindFirstChild("ConsumableItem"))

-- клейм-ремоуты (RemoteFunction)
local Rf_LoginClaim = Network:FindFirstChild("Login Streaks: Claim")
local Rf_MailboxAll = Network:FindFirstChild("Mailbox: Claim All")
local Rf_FreeGift   = Network:FindFirstChild("Redeem Free Gift")
local Rf_ForeverFree = Network:FindFirstChild("ForeverPacks: Claim Free")
local Rf_ZonePurchase = Network:FindFirstChild("InstanceZones_RequestPurchase")
local Ev_MoveServer  = Network:FindFirstChild("Move Server")
local Ev_GraphicsSet = Network:FindFirstChild("PlayerGraphicsSetting_Set")
local Ev_EquipBest   = Network:FindFirstChild("Pets_EquipBest")

local UpgradeDefsFolder
do
    local dir = ReplicatedStorage:FindFirstChild("__DIRECTORY")
    dir = dir and dir:FindFirstChild("EventUpgrades")
    dir = dir and dir:FindFirstChild("Event")
    UpgradeDefsFolder = dir and dir:FindFirstChild("SoccerUpgrades")
end

local function inSoccer()
    if not InstancingCmds then return false end
    local ok, res = pcall(InstancingCmds.IsInInstance, "SoccerEvent")
    return ok and res == true
end

-- Идёт ли активный раунд (не intermission). Если не знаем — считаем что да.
local function isPlaying()
    if not SoccerType or type(SoccerType.IsPlaying) ~= "function" then return true end
    local ok, res = pcall(SoccerType.IsPlaying)
    if not ok then return true end
    return res ~= false
end

local function getSave()
    if not SaveCmds or type(SaveCmds.Get) ~= "function" then return nil end
    local ok, s = pcall(SaveCmds.Get)
    return ok and s or nil
end

local function ensureInSoccer()
    if not CONFIG.AUTO_ENTER or not InstancingCmds then return end
    if inSoccer() then return end
    local ok = pcall(InstancingCmds.Enter, "SoccerEvent")
    if ok then
        print("[SoccerAuto] Авто-вход в SoccerEvent.")
        task.defer(function()
            if InvokeCustom then
                pcall(InvokeCustom.InvokeServer, InvokeCustom, "SoccerEvent", "RequestAllBalls")
            end
        end)
    end
end

----------------------------------------------------------------
-- телепорт / инстанс
----------------------------------------------------------------
local function getSoccerInstance()
    local things = workspace:FindFirstChild("__THINGS")
    local cont = things and things:FindFirstChild("__INSTANCE_CONTAINER")
    local active = cont and cont:FindFirstChild("Active")
    return active and active:FindFirstChild("SoccerEvent")
end

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function teleportTo(pos)
    local hrp = getHRP()
    if not hrp or typeof(pos) ~= "Vector3" then return false end
    pcall(function() hrp.CFrame = CFrame.new(pos) end)
    return true
end

local function teleportToCFrame(cf)
    local hrp = getHRP()
    if not hrp or typeof(cf) ~= "CFrame" then return false end
    pcall(function() hrp.CFrame = cf end)
    return true
end

local function teleportToPart(part)
    if not part or not part:IsA("BasePart") then return false end
    return teleportTo(part.Position + Vector3.new(0, 3, 0))
end

----------------------------------------------------------------
-- авто-прогрессия зон (ворота → Shoot → монеты → покупка зоны)
----------------------------------------------------------------
local ZoneProgress = {}
do
    local function maxZone()
        return CONFIG.MAX_SOCCER_ZONE or 5
    end

    function ZoneProgress.isComplete()
        if not CONFIG.AUTO_ZONE_PROGRESS or not InstanceZoneCmds then return true end
        local mz = maxZone()
        local ok, unlocked = pcall(InstanceZoneCmds.IsUnlocked, mz)
        if ok and unlocked == true then return true end
        local ok2, owned = pcall(InstanceZoneCmds.GetMaximumOwnedZoneNumber)
        return ok2 and type(owned) == "number" and owned >= mz
    end

    function ZoneProgress.getKickCommand()
        return ZoneProgress.isComplete() and "InfiniteShoot" or "Shoot"
    end

    function ZoneProgress.getOwnedZone()
        local owned = 1
        if InstanceZoneCmds then
            local ok, n = pcall(InstanceZoneCmds.GetMaximumOwnedZoneNumber)
            if ok and type(n) == "number" and n >= 1 then owned = n end
        end
        return owned
    end

    local function findAreaFolder(zoneNum)
        local inst = getSoccerInstance()
        if not inst then return nil end
        for _, ch in ipairs(inst:GetChildren()) do
            if ch.Name:find("Area " .. zoneNum) then return ch end
        end
        return inst:FindFirstChild("Common")
            or inst:FindFirstChild("1 | Area 1")
    end

    function ZoneProgress.teleportToZone(zoneNum)
        local inst = getSoccerInstance()
        if not inst then return false end
        local teleports = inst:FindFirstChild("Teleports")
        if teleports then
            local names = {
                tostring(zoneNum),
                "Zone" .. zoneNum,
                "Zone " .. zoneNum,
                "Area" .. zoneNum,
            }
            for _, n in ipairs(names) do
                local t = teleports:FindFirstChild(n)
                if t then
                    local p = t:IsA("BasePart") and t or t:FindFirstChildWhichIsA("BasePart", true)
                    if p and teleportToPart(p) then return true end
                end
            end
        end
        local area = findAreaFolder(zoneNum)
        if area then
            local p = area:FindFirstChild("Center", true)
                or area:FindFirstChild("MainHoop", true)
                or area:FindFirstChild("ThrowZone", true)
                or area:FindFirstChildWhichIsA("BasePart", true)
            if p and teleportToPart(p) then return true end
        end
        local gates = inst:FindFirstChild("Gates")
        if gates then
            local p = gates:FindFirstChildWhichIsA("BasePart", true)
            if p and teleportToPart(p) then return true end
        end
        return false
    end

    function ZoneProgress.requestBalls()
        if InvokeCustom then
            pcall(InvokeCustom.InvokeServer, InvokeCustom, "SoccerEvent", "RequestAllBalls")
        end
    end

    function ZoneProgress.getKickCFrame(zoneNum)
        local inst = getSoccerInstance()
        if not inst then return nil end
        local gates = inst:FindFirstChild("Gates")
        local gate = gates and gates:GetChildren()[zoneNum]
        local gp = gate and (gate:IsA("BasePart") and gate or gate:FindFirstChildWhichIsA("BasePart", true))
        if not gp then return nil end

        local stand
        local teleports = inst:FindFirstChild("Teleports")
        local tp = teleports and teleports:FindFirstChild(tostring(zoneNum))
        if tp then
            stand = tp:IsA("BasePart") and tp or tp:FindFirstChildWhichIsA("BasePart", true)
        end
        if not stand then
            local area = findAreaFolder(zoneNum)
            local throw = area and area:FindFirstChild("ThrowZone", true)
            if throw then
                stand = throw:IsA("BasePart") and throw or throw:FindFirstChildWhichIsA("BasePart", true)
            end
        end
        if stand then
            local dir = (gp.Position - stand.Position).Unit
            return CFrame.new(stand.Position + dir * 4 + Vector3.new(0, 2, 0), gp.Position)
        end
        return nil
    end

    function ZoneProgress.needReposition(zoneNum)
        local cf = ZoneProgress.getKickCFrame(zoneNum)
        local hrp = getHRP()
        if not cf or not hrp then return true end
        return (hrp.Position - cf.Position).Magnitude > 8
    end

    function ZoneProgress.teleportToKickSpot(zoneNum)
        ZoneProgress.requestBalls()
        local cf = ZoneProgress.getKickCFrame(zoneNum)
        if cf and teleportToCFrame(cf) then return true end
        return ZoneProgress.teleportToZone(zoneNum)
    end

    function ZoneProgress.tryPurchaseNext()
        if not InstanceZoneCmds or not Rf_ZonePurchase then return false end
        local owned = 0
        local okO, n = pcall(InstanceZoneCmds.GetMaximumOwnedZoneNumber)
        if okO and type(n) == "number" then owned = n end
        local nextZone = owned + 1
        if nextZone > maxZone() then return false end
        local okU, unlocked = pcall(InstanceZoneCmds.IsUnlocked, nextZone)
        if okU and unlocked == true then return false end
        local ok, res = pcall(Rf_ZonePurchase.InvokeServer, Rf_ZonePurchase, "SoccerEvent", nextZone)
        if ok and res == true then
            print(("[SoccerAuto] Зона %d куплена."):format(nextZone))
            return true
        end
        return false
    end

    function ZoneProgress.tick(force)
        if ZoneProgress.isComplete() or not InstanceZoneCmds then return end
        local owned = ZoneProgress.getOwnedZone()
        ZoneProgress.tryPurchaseNext()
        if force or ZoneProgress.needReposition(owned) then
            ZoneProgress.teleportToKickSpot(owned)
        end
    end
end

----------------------------------------------------------------
-- 1) СБОР ОРБОВ  (реестр через upvalue, без лагов)
----------------------------------------------------------------
local OrbCollector = {}
do
    local accFn, accIdx

    local function isOrbEntry(t)
        if type(t) ~= "table" then return false end
        local ok, uid = pcall(rawget, t, "UID")
        if not ok then return false end
        local tu = type(uid)
        if tu ~= "number" and tu ~= "string" then return false end
        return rawget(t, "Amount") ~= nil and rawget(t, "Model") ~= nil
    end

    local function tableHasOrbs(t)
        for _, v in pairs(t) do
            if isOrbEntry(v) then return true end
        end
        return false
    end

    local function findAccessor()
        if type(U.getgc) ~= "function" or type(U.getupvalues) ~= "function" then return end
        local ok, objects = pcall(U.getgc, false)
        if not ok or type(objects) ~= "table" then return end
        for i = 1, #objects do
            local f = objects[i]
            if type(f) == "function" then
                local okv, ups = pcall(U.getupvalues, f)
                if okv and type(ups) == "table" then
                    for idx, v in pairs(ups) do
                        if type(idx) == "number" and type(v) == "table" and tableHasOrbs(v) then
                            accFn, accIdx = f, idx
                            return true
                        end
                    end
                end
            end
        end
    end

    local function getRegistry()
        if not accFn then return nil end
        local ok, reg = pcall(U.getupvalue, accFn, accIdx)
        if ok and type(reg) == "table" then return reg end
        return nil
    end

    OrbCollector.isOrbEntry = isOrbEntry

    function OrbCollector.reset()
        accFn, accIdx = nil, nil
    end

    function OrbCollector.setupListeners()
        if not InstancingCmds then return end
        if type(InstancingCmds.AddLeaveListener) == "function" then
            track(InstancingCmds.AddLeaveListener(function()
                OrbCollector.reset()
            end))
        end
        if type(InstancingCmds.AddEnterListener) == "function" then
            track(InstancingCmds.AddEnterListener(function(id)
                if id == "SoccerEvent" then
                    OrbCollector.reset()
                    findAccessor()
                    if InvokeCustom then
                        pcall(InvokeCustom.InvokeServer, InvokeCustom, "SoccerEvent", "RequestAllBalls")
                    end
                end
            end))
        end
    end

    function OrbCollector.tick()
        local reg = getRegistry()
        if not reg then
            findAccessor()
            return 0
        end
        local n = 0
        for key, orb in pairs(reg) do
            if isOrbEntry(orb) then
                local uid = rawget(orb, "UID")
                pcall(FireCustom.FireServer, FireCustom, "SoccerEvent", "ClaimOrb", uid)
                if CONFIG.DESTROY_MODEL then
                    local model = rawget(orb, "Model")
                    if typeof(model) == "Instance" then
                        pcall(model.Destroy, model)
                    end
                end
                rawset(reg, key, nil)
                Runtime.stats.orbs += 1
                n += 1
            end
        end
        return n
    end
end

----------------------------------------------------------------
-- 2) КИК  (отдельный поток: Invoke yield не блокирует орбы)
----------------------------------------------------------------
local Kicker = {}
do
    local failStreak = 0

    local function kickAccuracy(cmd)
        if cmd == "Shoot" then
            return math.clamp(tonumber(CONFIG.GATE_KICK_ACCURACY) or 0.99, 0, 1)
        end
        return math.clamp(tonumber(CONFIG.KICK_ACCURACY) or 1, 0, 1)
    end

    local function isKickSuccess(res, cmd)
        if type(res) ~= "table" then return false end
        if cmd == "Shoot" then
            if res.Success == true then return true end
            return type(res.Coins) == "number" and res.Coins > 0
        end
        return true
    end

    local function disableGameAutoKick()
        -- На фазе ворот (Shoot) встроенный авто не мешает — не трогаем
        if not InstancingCmds or not ZoneProgress.isComplete() then return end
        pcall(InstancingCmds.FireCustom, "Auto", false)
        pcall(InstancingCmds.FireCustom, "AutoThrow", false)
        pcall(InstancingCmds.FireCustom, "SoccerEventAuto", false)
    end

    function Kicker.run()
        for _ = 1, 12 do
            if not Runtime.running then return end
            if inSoccer() then break end
            ensureInSoccer()
            task.wait(0.5)
        end
        disableGameAutoKick()

        while Runtime.running do
            if not inSoccer() then
                ensureInSoccer()
                task.wait(1.0)
            elseif CONFIG.PAUSE_ON_INTERMISSION and not isPlaying() then
                task.wait(1.0)
            else
                disableGameAutoKick()
                local gatePhase = not ZoneProgress.isComplete()
                if gatePhase then
                    if failStreak >= 2 or ZoneProgress.needReposition(ZoneProgress.getOwnedZone()) then
                        ZoneProgress.tick(true)
                    end
                elseif not ZoneProgress.isComplete() then
                    ZoneProgress.tick()
                end
                local cmd = ZoneProgress.getKickCommand()
                if cmd == "Shoot" then
                    ZoneProgress.requestBalls()
                end
                local ok, res = pcall(InvokeCustom.InvokeServer, InvokeCustom,
                    "SoccerEvent", cmd, kickAccuracy(cmd))
                if ok and isKickSuccess(res, cmd) then
                    failStreak = 0
                    Runtime.stats.kicks += 1
                    if gatePhase then
                        ZoneProgress.tryPurchaseNext()
                    end
                    task.wait(gatePhase and (CONFIG.GATE_KICK_RATE or 1.1) or CONFIG.KICK_RATE)
                else
                    failStreak += 1
                    if failStreak >= (CONFIG.KICK_FAIL_HOP_AFTER or 8) and Ev_MoveServer then
                        failStreak = 0
                        print("[SoccerAuto] Кик fail — hop на другой сервер…")
                        pcall(Ev_MoveServer.FireServer, Ev_MoveServer)
                        task.wait(5.0)
                        ensureInSoccer()
                    end
                    task.wait(CONFIG.KICK_BACKOFF)
                end
            end
        end
    end
end

----------------------------------------------------------------
-- 3) АВТО-ХЭТЧ  (CustomEggs_Hatch — проверено через хуки)
-- Цепочка: SetupCustomEgg(uid, eggDir, count) -> CustomEggs_Hatch(uid, count)
-- uid = имя папки в workspace.__THINGS.CustomEggs (GUID будки)
----------------------------------------------------------------
local EggHatcher = {}
do
    local cache = {}
    local eggPotatoOn = false
    local lastPrintEggId = nil

    -- Soccer Egg 5 Tier 6 => 506, Soccer Egg 4 => 400 (НЕ Tier-first!)
    local function eggScore(info)
        if not info or not info._id then return -1 end
        local id = info._id
        if not string.find(id, "Soccer", 1, true) then return -1 end
        local eggNum = tonumber(id:match("Egg (%d+)")) or 0
        local tierNum = tonumber(id:match("Tier (%d+)")) or 0
        return eggNum * 100 + tierNum
    end

    local function getEggInfo(uid, retry)
        if not CustomEggsCmds then return nil end
        local tries = retry or 1
        for i = 1, tries do
            local ok, info = pcall(CustomEggsCmds.Get, uid)
            if ok and type(info) == "table" and info._id then return info end
            if i < tries then task.wait(0.15) end
        end
        return nil
    end

    local function isSoccerEgg(info)
        return info and info._id and string.find(info._id, "Soccer", 1, true) ~= nil
    end

    local function isBoothInSoccerEvent(center)
        if not center or not inSoccer() then return false end
        local inst = getSoccerInstance()
        if not inst then return false end
        for _, ch in ipairs(inst:GetChildren()) do
            if ch.Name:find("Area ") then
                local p = ch:FindFirstChildWhichIsA("BasePart", true)
                if p and (center.Position - p.Position).Magnitude < 220 then
                    return true
                end
            end
        end
        local teleports = inst:FindFirstChild("Teleports")
        if teleports then
            for _, tp in ipairs(teleports:GetChildren()) do
                local p = tp:IsA("BasePart") and tp or tp:FindFirstChildWhichIsA("BasePart", true)
                if p and (center.Position - p.Position).Magnitude < 500 then
                    return true
                end
            end
        end
        return false
    end

    local function isEggHatchable(booth, info)
        if not booth:FindFirstChild("Egg") then return false end
        if not info or not isSoccerEgg(info) then return false end
        if inSoccer() and CONFIG.HATCH_INSTANCE_ONLY ~= false then
            if not isBoothInSoccerEvent(booth:FindFirstChild("Center")) then
                return false
            end
        end
        if ZoneProgress.isComplete() then return true end
        if info._dir and EggCmds then
            local ok, ul = pcall(EggCmds.IsUnlocked, info._dir)
            if ok and ul == true then return true end
        end
        if info._id and EggCmds then
            local ok, ul = pcall(EggCmds.IsUnlocked, info._id)
            if ok and ul == true then return true end
        end
        return false
    end

    -- Лучшая будка: максимальный eggScore среди soccer-яиц в инстансе.
    local function findBestBooth()
        if CONFIG.AUTO_ZONE_PROGRESS and not ZoneProgress.isComplete() then
            return nil
        end
        if CONFIG.HATCH_BOOTH_UID then
            local folder = workspace:FindFirstChild("__THINGS")
            folder = folder and folder:FindFirstChild("CustomEggs")
            local booth = folder and folder:FindFirstChild(CONFIG.HATCH_BOOTH_UID)
            return CONFIG.HATCH_BOOTH_UID, booth and booth:FindFirstChild("Center")
        end
        local folder = workspace:FindFirstChild("__THINGS")
        folder = folder and folder:FindFirstChild("CustomEggs")
        if not folder then return nil end

        local hrp = getHRP()
        local bestUID, bestCenter
        local bestScore, bestDist = -1, math.huge
        local wantMinScore = (ZoneProgress.getOwnedZone() or 0) >= 5 and 501 or 0

        local function consider(booth, center, info, dist)
            if not isEggHatchable(booth, info) then return end
            local score = eggScore(info)
            if score < 0 then return end
            local pick
            if CONFIG.HATCH_BEST_EGG then
                pick = score > bestScore
                    or (score == bestScore and dist < bestDist)
            else
                pick = dist < bestDist
            end
            if pick then
                bestUID = booth.Name
                bestScore = score
                bestDist = dist
                bestCenter = center
            end
        end

        local function scanOnce()
            for _, booth in ipairs(folder:GetChildren()) do
                local center = booth:FindFirstChild("Center")
                if booth:FindFirstChild("Egg") and center then
                    local dist = hrp and (center.Position - hrp.Position).Magnitude or 0
                    local inRange = CONFIG.AUTO_TELEPORT_EGG or dist <= CONFIG.HATCH_RANGE
                    if inRange then
                        consider(booth, center, getEggInfo(booth.Name, 1), dist)
                    end
                end
            end
        end

        scanOnce()

        if wantMinScore > 0 and bestScore > 0 and bestScore < wantMinScore then
            if not Runtime._eggWaitLogged then
                Runtime._eggWaitLogged = true
                print("[SoccerAuto] Жду Egg 5 Tier 3+ (streaming)…")
            end
            return nil
        end
        Runtime._eggWaitLogged = false

        return bestUID, bestCenter, bestScore
    end

    local function getEggTargetZone()
        local owned = ZoneProgress.getOwnedZone() or 1
        local maxZ = CONFIG.MAX_SOCCER_ZONE or 5
        if owned >= maxZ and (ZoneProgress.isComplete() or CONFIG.HATCH_BEST_EGG) then
            return maxZ
        end
        return math.min(math.max(owned, 1), maxZ)
    end

    local function isNearEggZone(maxDist)
        local inst = getSoccerInstance()
        if not inst then return false end
        local hrp = getHRP()
        if not hrp then return false end
        local zone = getEggTargetZone()
        local area
        for _, ch in ipairs(inst:GetChildren()) do
            if ch.Name:find("Area " .. zone) then area = ch break end
        end
        area = area or inst:FindFirstChild("5 | Area 5") or inst:FindFirstChild("Common")
        if not area then return false end
        local p = area:FindFirstChild("Center", true)
            or area:FindFirstChild("MainHoop", true)
            or area:FindFirstChildWhichIsA("BasePart", true)
        if not p then return false end
        return (hrp.Position - p.Position).Magnitude <= (maxDist or CONFIG.EGG_ZONE_NEAR_DIST or 180)
    end

    -- Телепорт к Area 5 только пока будок нет / игрок далеко. Не при каждом fail хэтча.
    local function needEggZoneTeleport(uid, score)
        if not CONFIG.AUTO_TELEPORT_EGG or not inSoccer() then return false end
        local wantMin = (ZoneProgress.getOwnedZone() or 0) >= 5 and 501 or 0
        if uid and (wantMin <= 0 or (score or 0) >= wantMin) then
            return false
        end
        if isNearEggZone() then return false end
        return true
    end

    local function teleportToEggZone(uid, score)
        if not needEggZoneTeleport(uid, score) then return false end
        local now = os.clock()
        local cd = CONFIG.EGG_ZONE_TP_COOLDOWN or 8.0
        if Runtime._lastEggZoneTp and (now - Runtime._lastEggZoneTp) < cd then
            return false
        end
        local target = getEggTargetZone()
        local ok = ZoneProgress.teleportToZone(target)
        if not ok then return false end

        Runtime._lastEggZoneTp = now
        if not Runtime._eggZoneTpLogged then
            Runtime._eggZoneTpLogged = true
            print(("[SoccerAuto] Телепорт к Area %d (прогрузка CustomEggs)…"):format(target))
        end

        local hrp = getHRP()
        if hrp and workspace.StreamingEnabled and type(LocalPlayer.RequestStreamAroundAsync) == "function" then
            pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, hrp.Position)
        end
        task.wait(CONFIG.EGG_STREAM_WAIT or 0.35)
        return true
    end

    function EggHatcher.teleportToEggZone(uid, score)
        return teleportToEggZone(uid, score)
    end

    local function teleportToBestEgg(uid, center, force)
        if not CONFIG.AUTO_TELEPORT_EGG then return end
        local hrp = getHRP()
        if not hrp or not center or not uid then return end
        local dist = (center.Position - hrp.Position).Magnitude
        local snapDist = CONFIG.TELEPORT_EGG_DIST or 12
        local hatchRange = CONFIG.HATCH_RANGE or 25

        -- Уже на будке: успешный хэтч + в радиусе сервера — не дёргать CFrame каждый раз
        if not force and Runtime._latchedBooth == uid and Runtime._latchedHatchOk and dist <= hatchRange then
            return
        end
        if not force and dist <= snapDist then
            Runtime._latchedBooth = uid
            return
        end

        local now = os.clock()
        local cd = CONFIG.EGG_BOOTH_TP_COOLDOWN or 2.0
        if not force and Runtime._lastBoothTp and (now - Runtime._lastBoothTp) < cd then
            return
        end

        if teleportToPart(center) then
            Runtime._lastBoothTp = now
            Runtime._latchedBooth = uid
            Runtime._latchedHatchOk = false
        end
    end

    local function setEggPotatoMode(on)
        if not CONFIG.EGG_POTATO_MODE or not Ev_GraphicsSet then return end
        if eggPotatoOn == on then return end
        eggPotatoOn = on
        pcall(Ev_GraphicsSet.FireServer, Ev_GraphicsSet, "EggPotatoMode", on)
    end

    -- Определяем count (max hatch). Best-effort, с запасным значением.
    local function resolveCount(info)
        if info and info._dir and EggCmds then
            local ok, c = pcall(EggCmds.GetMaxHatch, info._dir)
            if ok and type(c) == "number" and c > 0 then return c end
        end
        return CONFIG.HATCH_DEFAULT_COUNT or 27
    end

    -- Настройка (best-effort). По умолчанию пропускаем — SetupCustomEgg включает
    -- "Walk away to stop!" и прячет Main; CustomEggs_Hatch работает без setup.
    local function ensureSetup(uid, info, count)
        local c = cache[uid]
        if c and c.setupDone then return end
        if not CONFIG.HATCH_SKIP_SETUP then
            if Hatching and info and info._dir then
                pcall(Hatching.SetupCustomEgg, uid, info._dir, count)
                if AutoHatchEnable and info._id then
                    pcall(AutoHatchEnable.FireServer, AutoHatchEnable, info._id, count)
                end
            end
        end
        cache[uid] = { count = count, setupDone = true }
        local eggId = info and info._id
        if eggId and eggId ~= lastPrintEggId then
            lastPrintEggId = eggId
            print(("[SoccerAuto] Хэтч-цель: %s x%d (score=%d, будка %s)")
                :format(eggId, count, eggScore(info), uid:sub(1, 8)))
        end
    end

    local HATCH_OVERLAY_NAMES = {
        TapToOpen = true, Reveal = true, CustomEggOpen = true,
        EggReveal = true, PetReveal = true, Overlay = true,
        WalkAway = true, Blackout = true, Blur = true,
    }

    local SOCCER_UI_GUIS = { "YeetMain", "GoalsSide", "ProgressBars" }
    local HUB_UI_GUIS    = { "Main", "MainLeft" }

    local function getGuardGuis()
        if inSoccer() then return SOCCER_UI_GUIS end
        local t = {}
        for _, n in ipairs(HUB_UI_GUIS) do t[#t + 1] = n end
        for _, n in ipairs(SOCCER_UI_GUIS) do t[#t + 1] = n end
        return t
    end

    local function ensureMainUiVisible()
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return end
        for _, name in ipairs(getGuardGuis()) do
            local g = pg:FindFirstChild(name)
            if g and g:IsA("ScreenGui") and not g.Enabled then
                pcall(function() g.Enabled = true end)
            end
        end
    end

    local function clearCameraHatchVfx()
        if not CONFIG.HATCH_HIDE_GUI then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        for _, name in ipairs({ "Eggs", "Pets", "EggOpenLight" }) do
            local c = cam:FindFirstChild(name)
            if c then pcall(c.Destroy, c) end
        end
    end

    local function cameraHasHatchVfx()
        local cam = workspace.CurrentCamera
        if not cam then return false end
        return cam:FindFirstChild("Eggs")
            or cam:FindFirstChild("Pets")
            or cam:FindFirstChild("EggOpenLight")
    end

    local function suppressHatchOverlays()
        if not CONFIG.HATCH_HIDE_GUI then return end
        ensureMainUiVisible()

        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return end

        local eoa = pg:FindFirstChild("EggOpenAnimation")
        if eoa and eoa.Enabled then
            Runtime._eoaDisabledByUs = true
            pcall(function() eoa.Enabled = false end)
        end
        if eoa then
            for _, ch in ipairs(eoa:GetChildren()) do
                if ch:IsA("GuiObject") and HATCH_OVERLAY_NAMES[ch.Name] then
                    pcall(function() ch.Visible = false end)
                end
            end
        end
    end

    local function startHatchSuppress(sec)
        Runtime._hatchSuppressUntil = os.clock() + (sec or CONFIG.HATCH_SUPPRESS_SEC or 4)
    end

    local function finishHatchVisuals()
        if not CONFIG.HATCH_HIDE_GUI then return end
        startHatchSuppress(CONFIG.HATCH_SUPPRESS_SEC or 4)
        clearCameraHatchVfx()
        suppressHatchOverlays()
        if Hatching and type(Hatching.StopHatching) == "function" then
            pcall(Hatching.StopHatching)
        end
    end

    function EggHatcher.setupAnimBlocker()
        if Runtime._animBlockSetup then return end
        Runtime._animBlockSetup = true
        local net = Network:FindFirstChild("Eggs_PlayOpenAnimation")
        if not net then return end
        local function blockHandlers()
            if type(getconnections) ~= "function" then return end
            local ok, list = pcall(getconnections, net.OnClientEvent)
            if not ok or type(list) ~= "table" then return end
            for _, c in ipairs(list) do
                if c and type(c.Disable) == "function" then
                    pcall(c.Disable, c)
                end
            end
        end
        blockHandlers()
        spawnLoop("animBlock", function()
            if Runtime.running and CONFIG.HATCH_HIDE_GUI and inSoccer() then
                blockHandlers()
            end
            task.wait(8)
        end)
    end

    function EggHatcher.setupMainUiGuard()
        if Runtime._hatchUiConn or not CONFIG.HATCH_HIDE_GUI then return end
        EggHatcher.setupAnimBlocker()
        local RS = game:GetService("RunService")
        Runtime._hatchUiConn = track(RS.RenderStepped:Connect(function()
            if not Runtime.running or not CONFIG.HATCH_HIDE_GUI then return end
            if not inSoccer() then return end

            ensureMainUiVisible()

            local untilT = Runtime._hatchSuppressUntil
            local vfx = cameraHasHatchVfx()
            if vfx then
                Runtime._hatchSuppressUntil = math.max(untilT or 0, os.clock() + 1)
            end
            if (untilT and os.clock() < untilT) or vfx then
                clearCameraHatchVfx()
                suppressHatchOverlays()
            elseif Runtime._eoaDisabledByUs then
                local pg = LocalPlayer:FindFirstChild("PlayerGui")
                local eoa = pg and pg:FindFirstChild("EggOpenAnimation")
                if eoa then pcall(function() eoa.Enabled = true end) end
                Runtime._eoaDisabledByUs = false
            end
        end))
        Runtime._mainUiGuard = true
    end

    function EggHatcher.prestreamEggs()
        if not inSoccer() then return end
        teleportToEggZone(nil, nil)
        if not workspace.StreamingEnabled then return end
        local inst = getSoccerInstance()
        if not inst then return end
        local zone = getEggTargetZone()
        local area = inst:FindFirstChild(tostring(zone) .. " | Area " .. zone)
            or inst:FindFirstChild("5 | Area 5")
            or inst:FindFirstChild("Common")
        local p = area and area:FindFirstChildWhichIsA("BasePart", true)
        if p and type(LocalPlayer.RequestStreamAroundAsync) == "function" then
            pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, p.Position)
        end
    end

    function EggHatcher.setupVfxBlocker()
        if not CONFIG.HATCH_HIDE_GUI or Runtime._hatchCamConn then return end
        local cam = workspace.CurrentCamera
        if not cam then return end
        Runtime._hatchCamConn = track(cam.ChildAdded:Connect(function(ch)
            if not Runtime.running or not CONFIG.HATCH_HIDE_GUI then return end
            if ch.Name == "Eggs" or ch.Name == "Pets" or ch.Name == "EggOpenLight" then
                task.defer(function()
                    if ch.Parent then pcall(ch.Destroy, ch) end
                end)
            end
        end))
    end

    local function hatchOnce(uid, center)
        if not CustomEggsHatch or not uid then return false end

        teleportToBestEgg(uid, center)
        setEggPotatoMode(true)

        local info = getEggInfo(uid, 2)
        local count = (cache[uid] and cache[uid].count) or resolveCount(info)

        if not (cache[uid] and cache[uid].setupDone) then
            ensureSetup(uid, info, count)
        end

        if not CONFIG.HATCH_SKIP_ANIM and Hatching then
            pcall(Hatching.AttemptHatch)
        end

        local ok, res = pcall(CustomEggsHatch.InvokeServer, CustomEggsHatch, uid, count)
        if CONFIG.HATCH_HIDE_GUI then
            finishHatchVisuals()
        end
        if ok and res ~= false and res ~= nil then
            Runtime.stats.hatches += 1
            Runtime._eggWaitLogged = false
            Runtime._latchedBooth = uid
            Runtime._latchedHatchOk = true
            if CONFIG.AUTO_EQUIP_PETS then
                PetEquip.afterHatch()
            end
            return true
        end
        if center and getHRP() then
            local dist = (center.Position - getHRP().Position).Magnitude
            if dist > (CONFIG.HATCH_RANGE or 25) then
                Runtime._latchedHatchOk = false
            end
        end
        return false
    end

    -- "ok" | "no_booth" | "hatch_fail" | "idle" | "zones"
    local function hatchTick()
        if not inSoccer() then return "idle" end
        if CONFIG.AUTO_ZONE_PROGRESS and not ZoneProgress.isComplete() then return "zones" end

        local uid, center, score = findBestBooth()
        if uid and uid ~= Runtime._latchedBooth then
            Runtime._latchedHatchOk = false
        end
        if not uid and needEggZoneTeleport(nil, nil) then
            if teleportToEggZone(nil, nil) then
                uid, center, score = findBestBooth()
            end
        end
        if not uid then return "no_booth" end

        if hatchOnce(uid, center) then return "ok" end
        return "hatch_fail"
    end

    -- отдельный поток: InvokeServer сам держит темп (~серверный debounce 1.6с)
    function EggHatcher.run()
        EggHatcher.setupVfxBlocker()
        EggHatcher.setupMainUiGuard()
        if needEggZoneTeleport(nil, nil) then
            EggHatcher.prestreamEggs()
        end
        local missStream = 0
        while Runtime.running do
            if inSoccer() then
                if CONFIG.AUTO_ZONE_PROGRESS and not ZoneProgress.isComplete() then
                    task.wait(CONFIG.HATCH_RETRY)
                else
                    local status = hatchTick()
                    if status == "ok" then
                        missStream = 0
                    elseif status == "no_booth" then
                        missStream += 1
                        if missStream == 1 or missStream == 12 then
                            EggHatcher.prestreamEggs()
                        end
                        local wantMin = (ZoneProgress.getOwnedZone() or 0) >= 5 and 501 or 0
                        local waitT = (wantMin > 0 and missStream <= 12)
                            and (CONFIG.HATCH_WAIT_BEST or 0.4) or CONFIG.HATCH_RETRY
                        task.wait(waitT)
                    elseif status == "hatch_fail" then
                        task.wait(CONFIG.HATCH_RETRY)
                    else
                        task.wait(CONFIG.HATCH_RETRY)
                    end
                end
            else
                missStream = 0
                Runtime._eggZoneTpLogged = false
                task.wait(1.0)
            end
        end
    end

    function EggHatcher.reset()
        table.clear(cache)
        lastPrintEggId = nil
        Runtime._latchedBooth = nil
        Runtime._latchedHatchOk = false
    end
end

----------------------------------------------------------------
-- 4) УМНЫЕ АПГРЕЙДЫ
----------------------------------------------------------------
local Upgrades = {}
do
    local defCache = {}

    local function defFor(id)
        if defCache[id] ~= nil then return defCache[id] or nil end
        local found = false
        if UpgradeDefsFolder then
            for _, m in ipairs(UpgradeDefsFolder:GetChildren()) do
                local def = safeRequire(m)
                if def and def._id == id then found = def break end
            end
        end
        defCache[id] = found
        return found or nil
    end

    local function nextCost(id)
        if not EventUpgradeCmds then return nil end
        local okT, tier = pcall(EventUpgradeCmds.GetTier, id)
        if not okT or type(tier) ~= "number" then return nil end
        local def = defFor(id)
        if not def or type(def.TierCosts) ~= "table" then return nil end
        if tier + 1 > #def.TierCosts then return nil, true end
        local costObj = def.TierCosts[tier + 1]
        if type(costObj) == "table" and type(costObj.GetAmount) == "function" then
            local okA, a = pcall(costObj.GetAmount, costObj)
            if okA then return a, false end
        end
        return nil
    end

    local function orbs()
        if not CurrencyCmds then return 0 end
        local ok, v = pcall(CurrencyCmds.Get, "SoccerOrbs")
        return (ok and type(v) == "number") and v or 0
    end

    function Upgrades.tick()
        if not EventUpgradeCmds or not inSoccer() then return end
        local budget = orbs() - CONFIG.ORB_RESERVE
        local priority = CONFIG.PRIORITIZE_100_PERCENT
            and CONFIG.UPGRADE_PRIORITY_100 or CONFIG.UPGRADE_PRIORITY
        local mode = CONFIG.UPGRADE_MODE or "priority"

        local candidates = {}
        local scan = (mode == "cheapest") and (function()
            local all = {}
            for _, id in ipairs(priority) do all[id] = true end
            if UpgradeDefsFolder then
                for _, m in ipairs(UpgradeDefsFolder:GetChildren()) do
                    local def = safeRequire(m)
                    if def and def._id then all[def._id] = true end
                end
            end
            local list = {}
            for id in pairs(all) do list[#list + 1] = id end
            return list
        end)() or priority

        for _, id in ipairs(scan) do
            local cost, maxed = nextCost(id)
            if not maxed and type(cost) == "number" and cost <= budget then
                candidates[#candidates + 1] = { id = id, cost = cost }
            end
        end
        if #candidates == 0 then return end

        if mode == "smart" or mode == "cheapest" then
            table.sort(candidates, function(a, b) return a.cost < b.cost end)
        end

        local pick = candidates[1]
        if pcall(EventUpgradeCmds.Purchase, pick.id) then
            Runtime.stats.upgrades += 1
            print(("[SoccerAuto] Апгрейд %s куплен за %d орбов (%s).")
                :format(pick.id, pick.cost, mode))
        end
    end
end

----------------------------------------------------------------
-- 4b) АВТО-ЭКИП  (PetCmds.EquipBest → LD_BestFit)
----------------------------------------------------------------
local PetEquip = {}
do
    local lastEquipAt = 0
    local lastEquippedN = -1

    local function countEquipped()
        if not PetCmds then return 0 end
        local ok, items = pcall(PetCmds.GetEquippedItems)
        if ok and type(items) == "table" then return #items end
        return 0
    end

    local function maxSlots()
        if not PetCmds then return 0 end
        local ok, n = pcall(PetCmds.GetMaxEquipped)
        return (ok and type(n) == "number") and n or 0
    end

    local function ensureGameAutoEquip()
        if not CONFIG.EQUIP_ENSURE_AUTO or not PetCmds then return end
        local ok, on = pcall(PetCmds.IsAutoEquipEnabled)
        if ok and on == false and type(PetCmds.ToggleAutoEquip) == "function" then
            pcall(PetCmds.ToggleAutoEquip)
        end
    end

    local function disableFavoriteOnly()
        if not CONFIG.EQUIP_DISABLE_FAVORITE or not PetCmds then return end
        if type(PetCmds.IsFavoriteModeEnabled) ~= "function" then return end
        if type(PetCmds.ToggleFavoriteMode) ~= "function" then return end
        local ok, on = pcall(PetCmds.IsFavoriteModeEnabled)
        if ok and on == true then
            pcall(PetCmds.ToggleFavoriteMode)
        end
    end

    local function fireEquipBest()
        if PetCmds and type(PetCmds.EquipBest) == "function" then
            local ok = pcall(PetCmds.EquipBest)
            if ok then return true end
        end
        if Ev_EquipBest then
            return pcall(Ev_EquipBest.FireServer, Ev_EquipBest, "LD_BestFit")
        end
        return false
    end

    function PetEquip.tick(force)
        if not CONFIG.AUTO_EQUIP_PETS or not PetCmds then return end
        local now = os.clock()
        local cd = CONFIG.EQUIP_BEST_COOLDOWN or 8
        if not force and (now - lastEquipAt) < cd then return end

        if not force then
            local ok, maxed = pcall(PetCmds.IsMaxEquipped)
            if ok and maxed == true then return end
        end

        disableFavoriteOnly()
        ensureGameAutoEquip()

        local before = countEquipped()
        if not fireEquipBest() then return end
        lastEquipAt = now

        task.defer(function()
            task.wait(0.4)
            local after = countEquipped()
            local max = maxSlots()
            if after ~= lastEquippedN or (force and after ~= before) then
                lastEquippedN = after
                print(("[SoccerAuto] Equip Best: %d/%d"):format(after, max))
            end
        end)
    end

    function PetEquip.afterHatch()
        PetEquip.tick(true)
    end
end
----------------------------------------------------------------
-- 5) АНТИ-АФК
----------------------------------------------------------------
local function setupAntiAFK()
    local ok, vu = pcall(svc, "VirtualUser")
    if not ok or not vu then return end
    track(LocalPlayer.Idled:Connect(function()
        pcall(function()
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end)
    end))
    print("[SoccerAuto] Анти-АФК активен.")
end

----------------------------------------------------------------
-- 5b) АВТО-КЛЕЙМЫ
-- Login Streak, Mailbox, Free Gifts, Kick Rewards, Consumables, ForeverPack
----------------------------------------------------------------
local function claimFreeGifts()
    if not CONFIG.AUTO_FREE_GIFTS or not Rf_FreeGift then return end
    local save = getSave()
    if not save then return end
    local redeemed = {}
    for _, id in ipairs(save.FreeGiftsRedeemed or {}) do
        redeemed[id] = true
    end
    for i = 1, 12 do
        if not redeemed[i] then
            local ok, res = pcall(Rf_FreeGift.InvokeServer, Rf_FreeGift, i)
            if ok and res == true then
                Runtime.stats.claims += 1
                redeemed[i] = true
                print(("[SoccerAuto] Free Gift #%d забран."):format(i))
            end
        end
    end
end

local function redeemKickRewards()
    if not CONFIG.AUTO_KICK_REWARDS or not SoccerType or not InvokeCustom then return end
    if type(SoccerType.GenerateRewardDirectory) ~= "function" then return end
    local save = getSave()
    if not save then return end
    local ok, dir = pcall(SoccerType.GenerateRewardDirectory)
    if not ok or type(dir) ~= "table" then return end
    for id, def in pairs(dir) do
        if type(def) == "table" and def.SaveKey and def.CreditsRequired then
            local have = save[def.SaveKey] or 0
            if have >= def.CreditsRequired then
                local ok2, res = pcall(InvokeCustom.InvokeServer, InvokeCustom,
                    "SoccerEvent", "GenerateReward", id)
                if ok2 and res ~= false then
                    Runtime.stats.claims += 1
                    print(("[SoccerAuto] Kick-награда %s (%s)."):format(tostring(id), def.DisplayName or id))
                end
            end
        end
    end
end

local function useSoccerConsumables()
    if not CONFIG.AUTO_CONSUMABLES or not ConsumableCmds then return end
    if not inSoccer() then return end
    for _, id in ipairs(CONFIG.SOCCER_CONSUMABLES or {}) do
        local amount = 0
        if ConsumableItem and ConsumableItem.FromId then
            local ok, item = pcall(ConsumableItem.FromId, id)
            if ok and item and item.GetAmount then
                local ok2, amt = pcall(item.GetAmount, item)
                if ok2 and type(amt) == "number" then amount = amt end
            end
        end
        if amount > 0 then
            local ok3, res = pcall(ConsumableCmds.Consume, id)
            if ok3 and res ~= false then
                Runtime.stats.claims += 1
                print(("[SoccerAuto] Буст использован: %s"):format(id))
            end
        end
    end
end

local function claimForeverFree()
    if not CONFIG.AUTO_FOREVER_FREE or not Rf_ForeverFree then return end
    local ok, res = pcall(Rf_ForeverFree.InvokeServer, Rf_ForeverFree)
    if ok and res and res ~= false then
        Runtime.stats.claims += 1
        print("[SoccerAuto] ForeverPack free забран.")
    end
end

local function claimsTick()
    if CONFIG.AUTO_CLAIM then
        if LoginStreakCmds and Rf_LoginClaim then
            local ok, can = pcall(LoginStreakCmds.CanClaim)
            if ok and can == true then
                if pcall(Rf_LoginClaim.InvokeServer, Rf_LoginClaim) then
                    Runtime.stats.claims += 1
                    print("[SoccerAuto] Login Streak забран.")
                end
            end
        end
        if Rf_MailboxAll then
            local ok, res = pcall(Rf_MailboxAll.InvokeServer, Rf_MailboxAll)
            if ok and res and res ~= false then
                Runtime.stats.claims += 1
                print("[SoccerAuto] Mailbox забран.")
            end
        end
    end
    claimFreeGifts()
    if inSoccer() then
        redeemKickRewards()
        useSoccerConsumables()
    end
    claimForeverFree()
end

----------------------------------------------------------------
-- 5c) АВТО-ПЕРЕЗАПУСК (queue_on_teleport + реджойн при дисконнекте)
----------------------------------------------------------------
local function setupAutoRejoin()
    local TeleportService = svc("TeleportService")
    local GuiService = svc("GuiService")
    local placeId = game.PlaceId

    -- queue_on_teleport: перезапустить скрипт после любого телепорта/реджойна
    if CONFIG.QUEUE_ON_TELEPORT and type(queue_on_teleport) == "function" then
        local url = CONFIG.GITHUB_RAW_URL
        local path = CONFIG.SCRIPT_PATH
        local code

        if type(readfile) == "function" and type(isfile) == "function"
            and isfile(path) then
            code = ([[
local function loadLocal(p)
    if isfile and isfile(p) then loadstring(readfile(p))() end
end
loadLocal("bootstrap.lua")
loadLocal("%s")
]]):format(path:gsub("\\", "\\\\"))
            pcall(queue_on_teleport, code)
            print("[SoccerAuto] Авто-перезапуск после телепорта настроен (локальные файлы).")
        elseif type(url) == "string" and url ~= "" then
            local base = CONFIG.GITHUB_BASE or url:gsub("/soccer_auto%.lua$", "")
            code = ([[
loadstring(game:HttpGet("%s/bootstrap.lua"))()
loadstring(game:HttpGet("%s/soccer_auto.lua"))()
]]):format(base, base)
            pcall(queue_on_teleport, code)
            print("[SoccerAuto] Авто-перезапуск после телепорта настроен (GitHub).")
        else
            print(("[SoccerAuto] Для авто-перезапуска укажи GITHUB_RAW_URL или сохрани скрипт как '%s'."):format(path))
        end
    end

    -- авто-реджойн при ошибке соединения / вылете
    if CONFIG.AUTO_REJOIN then
        local function rejoin()
            pcall(function()
                TeleportService:Teleport(placeId, LocalPlayer)
            end)
        end
        track(GuiService.ErrorMessageChanged:Connect(function(msg)
            if Runtime.running and type(msg) == "string" and msg ~= "" then
                task.wait(1)
                rejoin()
            end
        end))
        print("[SoccerAuto] Авто-реджойн при дисконнекте активен.")
    end
end

----------------------------------------------------------------
-- 6) ОПТИМИЗАЦИЯ ИГРЫ  (обратимая)
----------------------------------------------------------------
local function stripSoccerVfx()
    if not CONFIG.STRIP_SOCCER_VFX then return end
    local inst = getSoccerInstance()
    if not inst then return end
    Runtime.restore.soccerVfx = Runtime.restore.soccerVfx or {}
    local seen = {}
    for _, e in ipairs(Runtime.restore.soccerVfx) do seen[e] = true end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ParticleEmitter") and d.Enabled then
            if not seen[d] then
                Runtime.restore.soccerVfx[#Runtime.restore.soccerVfx + 1] = d
                seen[d] = true
            end
            pcall(function() d.Enabled = false end)
        elseif d:IsA("BasePart") and d.CastShadow then
            if not seen[d] then
                Runtime.restore.soccerVfx[#Runtime.restore.soccerVfx + 1] = d
                seen[d] = true
            end
            pcall(function() d.CastShadow = false end)
        end
    end
end

local function applyPotatoMode()
    if not CONFIG.POTATO_MODE or not Ev_GraphicsSet then return end
    pcall(Ev_GraphicsSet.FireServer, Ev_GraphicsSet, "PotatoMode", true)
    pcall(Ev_GraphicsSet.FireServer, Ev_GraphicsSet, "Particles", false)
    pcall(Ev_GraphicsSet.FireServer, Ev_GraphicsSet, "Shadows", false)
end

local function applyOptimization()
    -- FPS cap
    if CONFIG.FPS_CAP and CONFIG.FPS_CAP > 0 and type(U.setfpscap) == "function" then
        Runtime.restore.fps = (getfpscap and getfpscap()) or nil
        pcall(U.setfpscap, CONFIG.FPS_CAP)
    end
    -- Пост-эффекты
    if CONFIG.DISABLE_POSTFX then
        Runtime.restore.postfx = {}
        for _, e in ipairs(Lighting:GetDescendants()) do
            if e:IsA("PostEffect") and e.Enabled then
                Runtime.restore.postfx[#Runtime.restore.postfx + 1] = e
                pcall(function() e.Enabled = false end)
            end
        end
    end
    -- Качество рендера
    if CONFIG.LOWER_QUALITY then
        pcall(function()
            local r = settings().Rendering
            Runtime.restore.quality = r.QualityLevel
            r.QualityLevel = Enum.QualityLevel.Level01
        end)
    end
    applyPotatoMode()
    stripSoccerVfx()
    print("[SoccerAuto] Оптимизация применена.")
end

local function restoreOptimization()
    if Runtime.restore.fps and type(U.setfpscap) == "function" then
        pcall(U.setfpscap, Runtime.restore.fps)
    end
    if Runtime.restore.postfx then
        for _, e in ipairs(Runtime.restore.postfx) do
            pcall(function() e.Enabled = true end)
        end
    end
    if Runtime.restore.soccerVfx then
        for _, e in ipairs(Runtime.restore.soccerVfx) do
            pcall(function()
                if e:IsA("ParticleEmitter") then e.Enabled = true
                elseif e:IsA("BasePart") then e.CastShadow = true end
            end)
        end
    end
    if Runtime.restore.quality ~= nil then
        pcall(function() settings().Rendering.QualityLevel = Runtime.restore.quality end)
    end
end

local function setupMaintenanceLoops()
    if CONFIG.STRIP_SOCCER_VFX then
        spawnLoop("vfx", function()
            if inSoccer() then safe("vfx", stripSoccerVfx) end
            task.wait(CONFIG.STRIP_VFX_INTERVAL or 45)
        end)
    end
    if CONFIG.INTERMISSION_BURST then
        spawnLoop("intermission", function()
            if inSoccer() and not isPlaying() then
                safe("claims", claimsTick)
                safe("upgrade", Upgrades.tick)
                safe("equip", function() PetEquip.tick(false) end)
            end
            task.wait(2.0)
        end)
    end
end

----------------------------------------------------------------
-- ЖИЗНЕННЫЙ ЦИКЛ
----------------------------------------------------------------
function App.Stop()
    if not Runtime.running then return end
    Runtime.running = false
    for _, c in ipairs(Runtime.connections) do
        if c and type(c.Disconnect) == "function" then
            pcall(c.Disconnect, c)
        end
    end
    table.clear(Runtime.connections)
    Runtime._hatchUiConn = nil
    Runtime._mainUiGuard = nil
    Runtime._animBlockSetup = nil
    restoreOptimization()
    print("[SoccerAuto] Остановлено и очищено.")
end

function App.EnableKickHook()
    if getgenv().__KickHook then
        print("[SoccerAuto] Kick-hook уже активен → getgenv().__KickHook.Log()")
        return getgenv().__KickHookLog
    end
    local ok, src = pcall(readfile, "kick_hook.lua")
    if ok and type(src) == "string" then
        local fn = loadstring(src)
        if fn then pcall(fn) end
    else
        warn("[SoccerAuto] Положи kick_hook.lua рядом со скриптом или выполни его вручную.")
    end
    return getgenv().__KickHookLog
end

function App.DisableKickHook()
    local kh = getgenv().__KickHook
    if kh and kh.Stop then pcall(kh.Stop) end
    if getgenv().__SoccerKickHookRestore then
        pcall(getgenv().__SoccerKickHookRestore)
        getgenv().__SoccerKickHookRestore = nil
    end
end

function App.Status()
    local s = Runtime.stats
    local save = getSave()
    local credits = ""
    if save then
        credits = (" | gift=%d huge1=%d huge2=%d titanic=%d garg=%d")
            :format(save.SoccerGiftCredits or 0, save.SoccerHuge1Credits or 0,
                save.SoccerHuge2Credits or 0, save.SoccerTitanicCredits or 0,
                save.SoccerGargCredits or 0)
    end
    local zoneInfo = ""
    if InstanceZoneCmds then
        local ok, z = pcall(InstanceZoneCmds.GetMaximumOwnedZoneNumber)
        zoneInfo = (" | zone=%s/%d"):format(ok and tostring(z) or "?", CONFIG.MAX_SOCCER_ZONE or 5)
    end
    local petInfo = ""
    if PetCmds then
        local ok, items = pcall(PetCmds.GetEquippedItems)
        local ok2, max = pcall(PetCmds.GetMaxEquipped)
        if ok and ok2 then
            petInfo = (" | pets=%d/%d"):format(type(items) == "table" and #items or 0, max or 0)
        end
    end
    print(("[SoccerAuto] kicks=%d orbs=%d hatches=%d upgrades=%d claims=%d errors=%d running=%s playing=%s%s%s%s")
        :format(s.kicks, s.orbs, s.hatches, s.upgrades, s.claims, s.errors,
            tostring(Runtime.running), tostring(isPlaying()), credits, zoneInfo, petInfo))
    return s
end

----------------------------------------------------------------
-- ЗАПУСК
----------------------------------------------------------------
print(("[SoccerAuto] v5.15 старт | executor=%s"):format(tostring(U.identify())))

ensureInSoccer()
if CONFIG.AUTO_EQUIP_PETS then
    task.defer(function()
        task.wait(2)
        if Runtime.running then safe("equip", function() PetEquip.tick(true) end) end
    end)
end
if CONFIG.COLLECT_ORBS then safe("orbListeners", OrbCollector.setupListeners) end
if CONFIG.AUTO_ZONE_PROGRESS then
    task.spawn(function()
        task.wait(2)
        if Runtime.running and inSoccer() and not ZoneProgress.isComplete() then
            safe("zoneBoot", ZoneProgress.tick)
            print("[SoccerAuto] Авто-прогрессия зон: Shoot + покупка зон.")
        end
    end)
end

if CONFIG.OPTIMIZE_GAME then safe("optimize", applyOptimization) end
if CONFIG.ANTI_AFK then safe("antiafk", setupAntiAFK) end
if CONFIG.AUTO_REJOIN or CONFIG.QUEUE_ON_TELEPORT then safe("autorejoin", setupAutoRejoin) end
safe("maint", setupMaintenanceLoops)

-- Поток авто-клеймов (низкая частота)
if CONFIG.AUTO_CLAIM then
    spawnLoop("claims", function()
        safe("claims", claimsTick)
        task.wait(CONFIG.CLAIM_CHECK_INTERVAL)
    end)
end

-- Поток сбора орбов (высокая частота, не должен блокироваться)
if CONFIG.COLLECT_ORBS then
    spawnLoop("orbs", function()
        local n = 0
        local ok, count = pcall(OrbCollector.tick)
        if ok and type(count) == "number" then n = count end
        task.wait(n > 0 and CONFIG.CLAIM_INTERVAL or (CONFIG.CLAIM_INTERVAL_IDLE or 0.65))
    end)
end

-- Поток кика (изолирован: InvokeServer yield-ит)
if CONFIG.AUTO_KICK then
    task.spawn(function() safe("kick", Kicker.run) end)
end

-- Поток хэтча (изолирован: CustomEggs_Hatch yield-ит ~1.6с = серверный темп)
if CONFIG.AUTO_HATCH then
    task.spawn(function() safe("hatch", EggHatcher.run) end)
end

-- Поток апгрейдов (низкая частота)
if CONFIG.AUTO_UPGRADE then
    spawnLoop("upgrade", function()
        safe("upgrade", Upgrades.tick)
        task.wait(CONFIG.UPGRADE_INTERVAL)
    end)
end

if CONFIG.AUTO_EQUIP_PETS then
    spawnLoop("equip", function()
        safe("equip", function() PetEquip.tick(false) end)
        task.wait(CONFIG.EQUIP_BEST_INTERVAL or 30)
    end)
end

print(("[SoccerAuto] Готов | Орбы:%s Кик:%s Хэтч:%s Апгр:%s Экип:%s Клейм:%s Вход:%s Зоны:%s Телепорт:%s АнтиАФК:%s")
    :format(tostring(CONFIG.COLLECT_ORBS), tostring(CONFIG.AUTO_KICK), tostring(CONFIG.AUTO_HATCH),
        tostring(CONFIG.AUTO_UPGRADE), tostring(CONFIG.AUTO_EQUIP_PETS), tostring(CONFIG.AUTO_CLAIM),
        tostring(CONFIG.AUTO_ENTER), tostring(CONFIG.AUTO_ZONE_PROGRESS),
        tostring(CONFIG.AUTO_TELEPORT_EGG), tostring(CONFIG.ANTI_AFK)))
print("[SoccerAuto] Стоп: getgenv().__SoccerAuto.Stop()  |  Статус: getgenv().__SoccerAuto.Status()")
