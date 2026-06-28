--[[
    Ранний bootstrap для PS99 — запускать ПЕРВЫМ при join/rejoin.
    Убирает Intro/PreloadAsync-зависания на экране BIG GAMES.
    Полностью убрать паузу без фокуса окна из Luau нельзя — нужен focus_helper.ps1.
]]
local G = (getgenv and getgenv()) or _G
if G.__PS99BootstrapDone then return end
G.__PS99BootstrapDone = true

pcall(function()
    local RF = game:GetService("ReplicatedFirst")
    RF:RemoveDefaultLoadingScreen()
    local intro = RF:FindFirstChild("Intro")
    if intro then intro.Disabled = true end
end)

pcall(function()
    if type(hookfunction) ~= "function" then return end
    local CP = game:GetService("ContentProvider")
    if not CP or type(CP.PreloadAsync) ~= "function" then return end
    hookfunction(CP.PreloadAsync, function(_, _, cb)
        if cb then task.defer(cb) end
    end)
end)

pcall(function()
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    if not lp then
        local ok, plr = pcall(function() return Players.PlayerAdded:Wait() end)
        lp = ok and plr or nil
    end
    if not lp then return end
    local pg = lp:FindFirstChild("PlayerGui")
    if not pg then
        local ok, child = pcall(function() return lp:WaitForChild("PlayerGui", 30) end)
        pg = ok and child or nil
    end
    if not pg then return end
    local misc = pg:FindFirstChild("_MISC")
    local loading = misc and misc:FindFirstChild("Loading")
    if loading and loading:IsA("ScreenGui") then
        loading.Enabled = false
    end
end)
