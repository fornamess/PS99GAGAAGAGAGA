--[[
    ================================================================
       SOCCER EVENT AUTO  v3  —  Pet Sim 99 / Soccer Event
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
    HATCH_BOOTH_UID   = nil,   -- nil = авто ближайшая будка; или GUID вручную
    HATCH_EGG_ID      = nil,   -- nil = взять название с будки (Title); или "Soccer Egg 5 Tier 3"
    HATCH_SKIP_ANIM   = true,  -- НЕ запускать AttemptHatch (обход "Click to open!")
    HATCH_HIDE_GUI    = true,  -- скрыть оверлей EggOpenAnimation (insurance)
    HATCH_RETRY       = 0.15,  -- пауза при отклонённом хэтче (сек)
    HATCH_DEFAULT_COUNT = 27,  -- запасной count, если не удалось определить max

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
local SoccerType       = safeRequire(Library.Types and Library.Types:FindFirstChild("Soccer"))

-- клейм-ремоуты (RemoteFunction)
local Rf_LoginClaim = Network:FindFirstChild("Login Streaks: Claim")
local Rf_MailboxAll = Network:FindFirstChild("Mailbox: Claim All")

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

    function Kicker.run()
        -- выключаем встроенный авто-кик, чтобы наш цикл был единственным
        if InstancingCmds then
            for _ = 1, 6 do
                if not Runtime.running then return end
                if inSoccer() then break end
                task.wait(0.5)
            end
            pcall(InstancingCmds.FireCustom, "Auto", false)
        end

        while Runtime.running do
            if inSoccer() then
                -- На intermission сервер отклоняет кики — не тратим вызовы
                if CONFIG.PAUSE_ON_INTERMISSION and not isPlaying() then
                    task.wait(1.0)
                else
                    local ok, res = pcall(InvokeCustom.InvokeServer, InvokeCustom,
                        "SoccerEvent", "InfiniteShoot", acc)
                    if ok and type(res) == "table" then
                        Runtime.stats.kicks += 1
                        task.wait(CONFIG.KICK_RATE)
                    else
                        task.wait(CONFIG.KICK_BACKOFF)
                    end
                end
            else
                task.wait(1.0)
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

    -- Ближайшая будка кастом-яйца. Возвращает UID (имя папки) или nil.
    local function findNearestBooth()
        local hrp = getHRP()
        if not hrp then return nil end
        local folder = workspace:FindFirstChild("__THINGS")
        folder = folder and folder:FindFirstChild("CustomEggs")
        if not folder then return nil end

        local bestUID, bestDist
        for _, booth in ipairs(folder:GetChildren()) do
            if booth:FindFirstChild("Egg") and booth:FindFirstChild("Center") then
                local dist = (booth.Center.Position - hrp.Position).Magnitude
                if dist <= CONFIG.HATCH_RANGE and (not bestDist or dist < bestDist) then
                    bestUID, bestDist = booth.Name, dist
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

        local uid = CONFIG.HATCH_BOOTH_UID or findNearestBooth()
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
        for _, id in ipairs(priority) do
            local cost, maxed = nextCost(id)
            if not maxed and type(cost) == "number" and cost <= budget then
                if pcall(EventUpgradeCmds.Purchase, id) then
                    Runtime.stats.upgrades += 1
                    print(("[SoccerAuto] Апгрейд %s куплен за %d орбов."):format(id, cost))
                end
                return -- одна покупка за тик
            end
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
-- 5b) АВТО-КЛЕЙМЫ (Login Streak по CanClaim, Mailbox Claim All)
-- Free Gift НЕ включён: требует конкретный id подарка (сотни типов).
----------------------------------------------------------------
local function claimsTick()
    -- Login Streak — только если реально доступно
    if LoginStreakCmds and Rf_LoginClaim then
        local ok, can = pcall(LoginStreakCmds.CanClaim)
        if ok and can == true then
            if pcall(Rf_LoginClaim.InvokeServer, Rf_LoginClaim) then
                Runtime.stats.claims += 1
                print("[SoccerAuto] Login Streak забран.")
            end
        end
    end
    -- Mailbox Claim All — безопасно (возвращает false когда пусто)
    if Rf_MailboxAll then
        local ok, res = pcall(Rf_MailboxAll.InvokeServer, Rf_MailboxAll)
        if ok and res and res ~= false then
            Runtime.stats.claims += 1
            print("[SoccerAuto] Mailbox забран.")
        end
    end
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
    print(("[SoccerAuto] kicks=%d orbs=%d hatches=%d upgrades=%d claims=%d errors=%d running=%s playing=%s")
        :format(s.kicks, s.orbs, s.hatches, s.upgrades, s.claims, s.errors,
            tostring(Runtime.running), tostring(isPlaying())))
    return s
end

----------------------------------------------------------------
-- ЗАПУСК
----------------------------------------------------------------
print(("[SoccerAuto] v3 старт | executor=%s"):format(tostring(U.identify())))

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

print(("[SoccerAuto] Готов | Орбы:%s Кик:%s Хэтч:%s Апгр:%s Клейм:%s АнтиАФК:%s Реджойн:%s")
    :format(tostring(CONFIG.COLLECT_ORBS), tostring(CONFIG.AUTO_KICK), tostring(CONFIG.AUTO_HATCH),
        tostring(CONFIG.AUTO_UPGRADE), tostring(CONFIG.AUTO_CLAIM), tostring(CONFIG.ANTI_AFK),
        tostring(CONFIG.AUTO_REJOIN)))
print("[SoccerAuto] Стоп: getgenv().__SoccerAuto.Stop()  |  Статус: getgenv().__SoccerAuto.Status()")
