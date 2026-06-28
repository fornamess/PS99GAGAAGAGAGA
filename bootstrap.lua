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
    hookfunction(CP.PreloadAsync, function(_, _, cb)
        if cb then task.defer(cb) end
    end)
end)

pcall(function()
    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    if not lp then return end
    local pg = lp:FindFirstChild("PlayerGui") or lp:WaitForChild("PlayerGui", 30)
    if not pg then return end
    local misc = pg:FindFirstChild("_MISC")
    local loading = misc and misc:FindFirstChild("Loading")
    if loading and loading:IsA("ScreenGui") then
        loading.Enabled = false
    end
end)
