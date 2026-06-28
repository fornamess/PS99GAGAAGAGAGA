--[[
    ================================================================
       SOCCER EVENT AUTO  v4  —  Pet Sim 99 / Soccer Event
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
    ANTI_AFK     = true,
    OPTIMIZE_GAME = true,  -- обратимая оптимизация графики

    -- Кик
    KICK_ACCURACY = 1.0,   -- 0..1, 1.0 = идеал (игра шлёт ~0.98)
    KICK_RATE     = 3.05,  -- пауза между киками (сек). Серверный guard = 3с.
    KICK_BACKOFF  = 0.6,   -- пауза, если кик отклонён сервером

    -- Орбы
    CLAIM_INTERVAL = 0.15, -- частота прохода по реестру (сек)
    DESTROY_MODEL  = true, -- убирать модель орба после сбора

    -- Апгрейды
    UPGRADE_INTERVAL = 2.0,
    ORB_RESERVE      = 0,
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
    HATCH_BEST_EGG    = true,  -- true = лучший tier в радиусе; false = ближайшая будка
    HATCH_BOOTH_UID   = nil,   -- nil = авто; или GUID вручную
    HATCH_EGG_ID      = nil,   -- nil = авто через CustomEggsCmds.Get
    HATCH_SKIP_ANIM   = true,  -- НЕ запускать AttemptHatch (обход "Click to open!")
    HATCH_HIDE_GUI    = true,  -- скрыть оверлей EggOpenAnimation (insurance)
    HATCH_RETRY       = 0.15,  -- пауза при отклонённом хэтче (сек)
    HATCH_DEFAULT_COUNT = 27,  -- запасной count, если не удалось определить max

    -- Апгрейды: "priority" | "smart" (самый дешёвый из приоритетных) | "cheapest" (глобально дешёвый)
    UPGRADE_MODE = "smart",

    -- Авто-вход / питомцы
    AUTO_ENTER        = true,  -- InstancingCmds.Enter("SoccerEvent") если не в ивенте
    AUTO_EQUIP_BEST   = true,  -- Pets_EquipBest при старте

    -- Кик: recovery при серверных ошибках
    KICK_FAIL_REJOIN_AFTER = 8, -- после N подряд fail — Leave+Enter (проверено через MCP)

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
        if base ~= "" and game.HttpGet then
            loadstring(game:HttpGet(base .. "/bootstrap.lua"))()
        else
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
local function safe(tag, fn, ...)
    local ok, err = pcall(fn, ...)
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
local EventUpgradeCmds = safeRequire(Client:FindFirstChild("EventUpgradeCmds"))
local CurrencyCmds     = safeRequire(Client:FindFirstChild("CurrencyCmds"))
local Hatching         = safeRequire(Client:FindFirstChild("HatchingCmds"))
local EggCmds          = safeRequire(Client:FindFirstChild("EggCmds"))
local CustomEggsCmds   = safeRequire(Client:FindFirstChild("CustomEggsCmds"))
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
local Ev_EquipBest  = Network:FindFirstChild("Pets_EquipBest")

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
    if ok then print("[SoccerAuto] Авто-вход в SoccerEvent.") end
end

local function equipBestPets()
    if not CONFIG.AUTO_EQUIP_BEST or not Ev_EquipBest then return end
    pcall(Ev_EquipBest.FireServer, Ev_EquipBest)
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

    function OrbCollector.tick()
        local reg = getRegistry()
        if not reg then
            findAccessor()
            return
        end
        for key, orb in pairs(reg) do
            if isOrbEntry(orb) then
                local uid = rawget(orb, "UID")
                -- closure-free вызов (без аллокаций в горячем пути)
                pcall(FireCustom.FireServer, FireCustom, "SoccerEvent", "ClaimOrb", uid)
                if CONFIG.DESTROY_MODEL then
                    local model = rawget(orb, "Model")
                    if typeof(model) == "Instance" then
                        pcall(model.Destroy, model)
                    end
                end
                rawset(reg, key, nil)
                Runtime.stats.orbs += 1
            end
        end
    end
end

----------------------------------------------------------------
-- 2) КИК  (отдельный поток: Invoke yield не блокирует орбы)
----------------------------------------------------------------
local Kicker = {}
do
    local acc = math.clamp(tonumber(CONFIG.KICK_ACCURACY) or 1, 0, 1)
    local failStreak = 0

    local function disableGameAutoKick()
        if not InstancingCmds then return end
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
                local ok, res = pcall(InvokeCustom.InvokeServer, InvokeCustom,
                    "SoccerEvent", "InfiniteShoot", acc)
                if ok and type(res) == "table" then
                    failStreak = 0
                    Runtime.stats.kicks += 1
                    task.wait(CONFIG.KICK_RATE)
                else
                    failStreak += 1
                    if failStreak >= (CONFIG.KICK_FAIL_REJOIN_AFTER or 8) and InstancingCmds then
                        failStreak = 0
                        pcall(InstancingCmds.Leave)
                        task.wait(1.0)
                        pcall(InstancingCmds.Enter, "SoccerEvent")
                        task.wait(2.0)
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
    -- кеш по UID будки: { count, setupDone }
    local cache = {}

    local function getHRP()
        local char = LocalPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function eggTier(info)
        if not info or not info._id then return 0 end
        local id = info._id
        return tonumber(id:match("Tier (%d+)"))
            or tonumber(id:match("Egg (%d+)"))
            or 0
    end

    -- Лучшая или ближайшая будка в радиусе.
    local function findTargetBooth()
        local uid = CONFIG.HATCH_BOOTH_UID
        if uid then return uid end

        local hrp = getHRP()
        if not hrp then return nil end
        local folder = workspace:FindFirstChild("__THINGS")
        folder = folder and folder:FindFirstChild("CustomEggs")
        if not folder then return nil end

        local bestUID, bestScore, bestDist
        for _, booth in ipairs(folder:GetChildren()) do
            if booth:FindFirstChild("Egg") and booth:FindFirstChild("Center") then
                local dist = (booth.Center.Position - hrp.Position).Magnitude
                if dist <= CONFIG.HATCH_RANGE then
                    local info = getEggInfo(booth.Name)
                    local tier = eggTier(info)
                    local pick
                    if CONFIG.HATCH_BEST_EGG then
                        pick = tier > (bestScore or -1)
                            or (tier == (bestScore or -1) and dist < (bestDist or math.huge))
                    else
                        pick = not bestDist or dist < bestDist
                    end
                    if pick then
                        bestUID, bestScore, bestDist = booth.Name, tier, dist
                    end
                end
            end
        end
        return bestUID
    end

    -- Надёжно получаем данные яйца по UID через CustomEggsCmds.Get
    -- (НЕ читаем Title GUI — он ненадёжен и отличается между яйцами/серверами).
    local function getEggInfo(uid)
        if not CustomEggsCmds then return nil end
        local ok, info = pcall(CustomEggsCmds.Get, uid)
        if ok and type(info) == "table" then return info end
        return nil
    end

    -- Определяем count (max hatch). Best-effort, с запасным значением.
    local function resolveCount(info)
        if info and info._dir and EggCmds then
            local ok, c = pcall(EggCmds.GetMaxHatch, info._dir)
            if ok and type(c) == "number" and c > 0 then return c end
        end
        return CONFIG.HATCH_DEFAULT_COUNT or 27
    end

    -- Настройка (best-effort, НЕ блокирует хэтч при неудаче).
    local function ensureSetup(uid, info, count)
        local c = cache[uid]
        if c and c.setupDone then return end
        if Hatching and info and info._dir then
            pcall(Hatching.SetupCustomEgg, uid, info._dir, count)
            if AutoHatchEnable and info._id then
                pcall(AutoHatchEnable.FireServer, AutoHatchEnable, info._id, count)
            end
        end
        cache[uid] = { count = count, setupDone = true }
        print(("[SoccerAuto] Хэтч-цель: %s x%d (будка %s)")
            :format((info and info._id) or "?", count, uid:sub(1, 8)))
    end

    -- скрыть оверлей "Click to open!" + держать выключенным.
    -- Переустанавливаем коннект, если GUI пересоздан (новый сервер/респавн).
    local function hideRevealGui()
        if not CONFIG.HATCH_HIDE_GUI then return end
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if not pg then return end
        local eoa = pg:FindFirstChild("EggOpenAnimation")
        if not eoa or not eoa:IsA("ScreenGui") then return end

        if eoa.Enabled then pcall(function() eoa.Enabled = false end) end

        -- если коннект мёртв или к старому объекту — пересоздаём
        if Runtime._eoa ~= eoa then
            if Runtime._eoaConn then pcall(function() Runtime._eoaConn:Disconnect() end) end
            Runtime._eoa = eoa
            Runtime._eoaConn = track(eoa:GetPropertyChangedSignal("Enabled"):Connect(function()
                if Runtime.running and CONFIG.HATCH_HIDE_GUI and eoa.Enabled then
                    pcall(function() eoa.Enabled = false end)
                end
            end))
        end
    end

    -- единичная попытка хэтча (без анимации). true при успехе.
    local function hatchOnce()
        if not CustomEggsHatch then return false end

        local uid = findTargetBooth()
        if not uid then return false end

        local info = getEggInfo(uid)
        -- даже если info=nil (не успело прогрузиться) — всё равно пробуем хэтч,
        -- т.к. чистый CustomEggs_Hatch(uid, count) работает без setup (проверено).
        local count = (cache[uid] and cache[uid].count) or resolveCount(info)

        if not (cache[uid] and cache[uid].setupDone) then
            ensureSetup(uid, info, count)
        end

        -- ОБХОД "Click to open!": НЕ зовём AttemptHatch (это анимация-ревил).
        if not CONFIG.HATCH_SKIP_ANIM and Hatching then
            pcall(Hatching.AttemptHatch)
        end

        local ok, res = pcall(CustomEggsHatch.InvokeServer, CustomEggsHatch, uid, count)
        if ok and res == true then
            Runtime.stats.hatches += 1
            return true
        end
        return false
    end

    -- отдельный поток: InvokeServer сам держит темп (~серверный debounce 1.6с)
    function EggHatcher.run()
        local lastHide = 0
        while Runtime.running do
            -- периодически переустанавливаем скрытие оверлея (на случай пересоздания GUI)
            local now = os.clock()
            if (now - lastHide) >= 1.0 then
                lastHide = now
                hideRevealGui()
            end

            if inSoccer() then
                local ok = hatchOnce()
                if not ok then
                    task.wait(CONFIG.HATCH_RETRY)
                end
                -- при успехе НЕ ждём: следующий InvokeServer заблокируется до
                -- ответа сервера, что и даёт естественный темп без перегруза.
            else
                task.wait(1.0)
            end
        end
    end

    function EggHatcher.reset()
        table.clear(cache)
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

        if type(url) == "string" and url ~= "" then
            local base = CONFIG.GITHUB_BASE or url:gsub("/soccer_auto%.lua$", "")
            code = ([[
loadstring(game:HttpGet("%s/bootstrap.lua"))()
loadstring(game:HttpGet("%s/soccer_auto.lua"))()
]]):format(base, base)
            pcall(queue_on_teleport, code)
            print("[SoccerAuto] Авто-перезапуск после телепорта настроен (GitHub + bootstrap).")
        elseif type(readfile) == "function" and type(isfile) == "function"
            and isfile(path) then
            code = ("local s='%s' if isfile and isfile(s) then loadstring(readfile(s))() end")
                :format(path)
            pcall(queue_on_teleport, code)
            print("[SoccerAuto] Авто-перезапуск после телепорта настроен (файл).")
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
    if Runtime.restore.quality ~= nil then
        pcall(function() settings().Rendering.QualityLevel = Runtime.restore.quality end)
    end
end

----------------------------------------------------------------
-- ЖИЗНЕННЫЙ ЦИКЛ
----------------------------------------------------------------
function App.Stop()
    if not Runtime.running then return end
    Runtime.running = false
    for _, c in ipairs(Runtime.connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(Runtime.connections)
    restoreOptimization()
    print("[SoccerAuto] Остановлено и очищено.")
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
    print(("[SoccerAuto] kicks=%d orbs=%d hatches=%d upgrades=%d claims=%d errors=%d running=%s playing=%s%s")
        :format(s.kicks, s.orbs, s.hatches, s.upgrades, s.claims, s.errors,
            tostring(Runtime.running), tostring(isPlaying()), credits))
    return s
end

----------------------------------------------------------------
-- ЗАПУСК
----------------------------------------------------------------
print(("[SoccerAuto] v4 старт | executor=%s"):format(tostring(U.identify())))

ensureInSoccer()
equipBestPets()

if CONFIG.OPTIMIZE_GAME then safe("optimize", applyOptimization) end
if CONFIG.ANTI_AFK then safe("antiafk", setupAntiAFK) end
if CONFIG.AUTO_REJOIN or CONFIG.QUEUE_ON_TELEPORT then safe("autorejoin", setupAutoRejoin) end

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
        safe("orbs", OrbCollector.tick)
        task.wait(CONFIG.CLAIM_INTERVAL)
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
    spawnLoop("maint", function()
        safe("upgrade", Upgrades.tick)
        task.wait(CONFIG.UPGRADE_INTERVAL)
    end)
end

print(("[SoccerAuto] Готов | Орбы:%s Кик:%s Хэтч:%s Апгр:%s Клейм:%s Вход:%s Питомцы:%s АнтиАФК:%s Реджойн:%s")
    :format(tostring(CONFIG.COLLECT_ORBS), tostring(CONFIG.AUTO_KICK), tostring(CONFIG.AUTO_HATCH),
        tostring(CONFIG.AUTO_UPGRADE), tostring(CONFIG.AUTO_CLAIM), tostring(CONFIG.AUTO_ENTER),
        tostring(CONFIG.AUTO_EQUIP_BEST), tostring(CONFIG.ANTI_AFK), tostring(CONFIG.AUTO_REJOIN)))
print("[SoccerAuto] Стоп: getgenv().__SoccerAuto.Stop()  |  Статус: getgenv().__SoccerAuto.Status()")
