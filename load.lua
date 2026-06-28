-- Загрузчик Soccer Auto с GitHub (Pet Sim 99 — Soccer Event)
local BASE = "https://raw.githubusercontent.com/fornamess/PS99GAGAAGAGAGA/main"
repeat task.wait() until game:IsLoaded()
game:GetService("ReplicatedStorage"):WaitForChild("Network", 120)
loadstring(game:HttpGet(BASE .. "/bootstrap.lua"), "bootstrap")()
loadstring(game:HttpGet(BASE .. "/soccer_auto.lua"), "soccer_auto")()
