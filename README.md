# PS99GAGAAGAGAGA

Авто-фарм для **Soccer Event** в Pet Sim 99: сбор орбов, кик, хэтч яиц, апгрейды, клеймы, анти-АФК.

## Запуск

Вставь в executor одну строку:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fornamess/PS99GAGAAGAGAGA/main/soccer_auto.lua"))()
```

Или загрузи короткий лоадер:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fornamess/PS99GAGAAGAGAGA/main/load.lua"))()
```

## Управление

| Действие | Команда |
|----------|---------|
| Остановить | `getgenv().__SoccerAuto.Stop()` |
| Статус | `getgenv().__SoccerAuto.Status()` |

## Настройки

Все опции в начале файла `soccer_auto.lua` в таблице `CONFIG`.

После телепорта/реджойна скрипт перезапускается сам (через `queue_on_teleport` + GitHub URL).
