-- Загрузчик Soccer Auto (Pet Sim 99 — Soccer Event)
-- Локальный soccer_auto.lua в папке Volt имеет приоритет над GitHub.
local BASE = "https://raw.githubusercontent.com/fornamess/PS99GAGAAGAGAGA/main"

if type(clearteleportqueue) == "function" then pcall(clearteleportqueue) end

task.spawn(function()
    for _ = 1, 180 do
        if game:IsLoaded() then
            local rs = game:GetService("ReplicatedStorage")
            if rs and rs:FindFirstChild("Network") then break end
        end
        task.wait(1)
    end
    local rs = game:GetService("ReplicatedStorage")
    if not rs or not rs:FindFirstChild("Network") then return end
    pcall(function()
        local g = getgenv and getgenv() or _G
        if type(g.__SoccerAuto) == "table" and type(g.__SoccerAuto.Stop) == "function" then
            g.__SoccerAuto.Stop(true)
            task.wait(0.35)
        end
    end)
    local function loadLocal(name)
        if type(readfile) == "function" and type(isfile) == "function" and isfile(name) then
            pcall(function() loadstring(readfile(name), name)() end)
            return true
        end
        return false
    end
    if not loadLocal("bootstrap.lua") then
        pcall(function() loadstring(game:HttpGet(BASE .. "/bootstrap.lua"), "bootstrap")() end)
    end
    if not loadLocal("soccer_auto.lua") then
        pcall(function() loadstring(game:HttpGet(BASE .. "/soccer_auto.lua"), "soccer_auto")() end)
    end
end)
