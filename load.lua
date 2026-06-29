-- Загрузчик Soccer Auto с GitHub (Pet Sim 99 — Soccer Event)
local BASE = "https://raw.githubusercontent.com/fornamess/PS99GAGAAGAGAGA/main"
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
    pcall(function() loadstring(game:HttpGet(BASE .. "/bootstrap.lua"), "bootstrap")() end)
    pcall(function() loadstring(game:HttpGet(BASE .. "/soccer_auto.lua"), "soccer_auto")() end)
end)
