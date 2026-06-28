--[[
  Безопасный хук для перехвата кика/instancing remotes.
  НЕ ломает игру (без битого unpack, без подмены RemoteFunction).

  Запуск:
    loadstring(readfile("kick_hook.lua"))()
    -- или вставь содержимое в executor

  Снять:
    getgenv().__KickHook.Stop()

  Лог:
    getgenv().__KickHook.Log()
    print(getgenv().__KickHookLog)
]]

local G = getgenv()

if G.__KickHook and G.__KickHook.Stop then
    pcall(G.__KickHook.Stop)
end

local log = {}
G.__KickHookLog = log

local function ser(v, d)
    d = d or 0
    if d > 3 then return "..." end
    local t = typeof(v)
    if t == "Instance" then return v.ClassName .. ":" .. v.Name end
    if t == "Vector3" then
        return string.format("V3(%.1f,%.1f,%.1f)", v.X, v.Y, v.Z)
    end
    if t == "CFrame" then
        local p = v.Position
        return string.format("CF(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
    end
    if t == "table" then
        local parts, n = {}, 0
        for k, val in pairs(v) do
            n += 1
            if n <= 10 then
                parts[#parts + 1] = tostring(k) .. "=" .. ser(val, d + 1)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

local function shouldLog(name)
    local n = string.lower(tostring(name))
    return n:find("instanc")
        or n:find("egg")
        or n:find("soccer")
        or n:find("zone")
end

local function push(remote, method, args)
    local row = {
        t = os.clock(),
        remote = remote,
        method = method,
        args = {},
    }
    for i, a in ipairs(args) do
        row.args[i] = ser(a)
    end
    table.insert(log, row)
    if #log > 100 then table.remove(log, 1) end
    print(("[KickHook] %s:%s(%s)"):format(remote, method, table.concat(row.args, ", ")))
end

local restores = {}

-- InstancingCmds (только лог, без изменения поведения)
pcall(function()
    local IC = require(game.ReplicatedStorage.Library.Client.InstancingCmds)
    if not G.__KickHookICOrig then
        G.__KickHookICOrig = {
            FireCustom = IC.FireCustom,
            InvokeCustom = IC.InvokeCustom,
        }
    end
    function IC.FireCustom(...)
        push("InstancingCmds", "FireCustom", { ... })
        return G.__KickHookICOrig.FireCustom(...)
    end
    function IC.InvokeCustom(...)
        push("InstancingCmds", "InvokeCustom", { ... })
        return G.__KickHookICOrig.InvokeCustom(...)
    end
    table.insert(restores, function()
        IC.FireCustom = G.__KickHookICOrig.FireCustom
        IC.InvokeCustom = G.__KickHookICOrig.InvokeCustom
    end)
end)

-- namecall: только лог + return old(...)
local restores_nc = nil
if hookmetamethod and getnamecallmethod then
    local old
    old = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        if (method == "InvokeServer" or method == "FireServer") and shouldLog(self.Name) then
            push(self.Name, method, { ... })
        end
        return old(self, ...)
    end)
    restores_nc = function()
        hookmetamethod(game, "__namecall", old)
    end
elseif hookfunction and getnamecallmethod and getrawmetatable then
    local old
    old = hookfunction(getrawmetatable(game).__namecall, function(self, ...)
        local method = getnamecallmethod()
        if (method == "InvokeServer" or method == "FireServer") and shouldLog(self.Name) then
            push(self.Name, method, { ... })
        end
        return old(self, ...)
    end)
    restores_nc = function()
        hookfunction(getrawmetatable(game).__namecall, old)
    end
end
if restores_nc then
    table.insert(restores, restores_nc)
end

-- снять старый сломанный gag2 хук если остался
G.__SoccerKickHookActive = nil
if G.__SoccerKickHookRestore then
    pcall(G.__SoccerKickHookRestore)
    G.__SoccerKickHookRestore = nil
end

G.__KickHook = {
    Stop = function()
        for i = #restores, 1, -1 do
            pcall(restores[i])
        end
        print("[KickHook] Снят.")
    end,
    Log = function()
        for i, row in ipairs(log) do
            print(i, row.remote, row.method, table.concat(row.args, ", "))
        end
        return log
    end,
    Clear = function()
        table.clear(log)
    end,
}

print("[KickHook] Активен. Забей мяч вручную → getgenv().__KickHook.Log()")
