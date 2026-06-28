local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- ===== Настройки =====
local CLAIM_INTERVAL = 0.15   -- частота прохода по реестру (сек)
local FIND_RETRY     = 1.0    -- как часто пытаться найти реестр, пока не нашли
local DESTROY_MODEL  = true   -- удалять модель орба после сбора (визуально пропадает)
-- =====================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
repeat task.wait() until game:IsLoaded()
local Network = ReplicatedStorage:WaitForChild("Network", 120)
if not Network then
    warn("[Orbs] Network не найден")
    return
end
local FireCustom = Network:WaitForChild("Instancing_FireCustomFromClient", 30)

getgenv = getgenv or function() return _G end
local ENV = getgenv()

-- ---- кросс-executor функции ----
local _getgc        = ENV.getgc        or getgc        or (debug and rawget(debug, "getgc"))
local _getupvalue   = ENV.getupvalue   or getupvalue   or (debug and rawget(debug, "getupvalue"))
local _getupvalues  = ENV.getupvalues  or getupvalues  or (debug and rawget(debug, "getupvalues"))

-- ---- проверка записи орба ----
local function isOrbEntry(t)
    if type(t) ~= "table" then return false end
    local ok, uid = pcall(function() return rawget(t, "UID") end)
    if not ok then return false end
    if type(uid) ~= "number" and type(uid) ~= "string" then return false end
    return rawget(t, "Amount") ~= nil and rawget(t, "Model") ~= nil
end

-- ---- содержит ли таблица записи орбов среди значений ----
local function tableHasOrbs(t)
    if type(t) ~= "table" then return false end
    for _, v in pairs(t) do
        if isOrbEntry(v) then return true end
    end
    return false
end

-- ---- разовый поиск: функция модуля + индекс upvalue с реестром ----
-- Вызывается getgc ТОЛЬКО здесь и только пока реестр не найден.
local function findRegistryAccessor()
    if type(_getgc) ~= "function" then return nil end

    -- getgc() (без true) обычно не тащит таблицы — легче, чем getgc(true)
    local ok, objects = pcall(_getgc)
    if not ok or type(objects) ~= "table" then
        ok, objects = pcall(_getgc, true)
        if not ok then return nil end
    end

    for _, f in ipairs(objects) do
        if type(f) == "function" then
            -- читаем upvalues этой функции
            local ups
            if _getupvalues then
                local okv, res = pcall(_getupvalues, f)
                if okv then ups = res end
            end
            if ups then
                for i, v in pairs(ups) do
                    if type(i) == "number" and tableHasOrbs(v) then
                        return f, i
                    end
                end
            end
        end
    end
    return nil
end

-- ---- получить текущий реестр (без сканов памяти) ----
local accFn, accIdx = nil, nil

local function getRegistry()
    if not accFn or not accIdx then return nil end
    if _getupvalue then
        local ok, reg = pcall(_getupvalue, accFn, accIdx)
        if ok and type(reg) == "table" then return reg end
    elseif _getupvalues then
        local ok, ups = pcall(_getupvalues, accFn)
        if ok and type(ups) == "table" and type(ups[accIdx]) == "table" then
            return ups[accIdx]
        end
    end
    return nil
end

-- ---- сбор одного орба ----
local function claimOrb(registry, key, orb)
    local uid = rawget(orb, "UID")
    pcall(function()
        FireCustom:FireServer("SoccerEvent", "ClaimOrb", uid)
    end)
    if DESTROY_MODEL then
        local model = rawget(orb, "Model")
        if typeof(model) == "Instance" then
            pcall(function() model:Destroy() end)
        end
    end
    rawset(registry, key, nil)
end

-- ===== запуск =====
ENV.__OrbCollectorRunning = true
print("[OrbCollector] Запущен. Останов: getgenv().__OrbCollectorRunning = false")

if type(_getgc) ~= "function" then
    warn("[OrbCollector] getgc недоступен — работать не будет.")
end

task.spawn(function()
    local lastFind = 0
    while ENV.__OrbCollectorRunning do
        local registry = getRegistry()

        if registry then
            for key, orb in pairs(registry) do
                if isOrbEntry(orb) then
                    claimOrb(registry, key, orb)
                end
            end
        else
            -- реестр ещё не найден — редкие попытки через getgc
            local now = os.clock()
            if (now - lastFind) >= FIND_RETRY then
                lastFind = now
                accFn, accIdx = findRegistryAccessor()
                if accFn then
                    print("[OrbCollector] Реестр орбов найден, дальше без сканов памяти.")
                end
            end
        end

        task.wait(CLAIM_INTERVAL)
    end
    print("[OrbCollector] Остановлен.")
end)
