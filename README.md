# PS99GAGAAGAGAGA

Авто-фарм для **Soccer Event** в Pet Sim 99: сбор орбов, кик, хэтч яиц, апгрейды, клеймы, анти-АФК.

## Запуск

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fornamess/PS99GAGAAGAGAGA/main/load.lua"))()
```

## Зависание на BIG GAMES без фокуса окна

Roblox на Windows **почти останавливает клиент**, если окно не в фокусе. Экран BIG GAMES (Intro + PreloadAsync) из-за этого может висеть бесконечно.

**Что делать:**

1. Запусти **`focus_helper.ps1`** — автоматически даёт фокус новым окнам Roblox на ~25 секунд при реджойне:
   ```powershell
   powershell -ExecutionPolicy Bypass -File focus_helper.ps1
   ```
   Для нескольких аккаунтов:
   ```powershell
   powershell -ExecutionPolicy Bypass -File focus_helper.ps1 -RotateMulti
   ```

2. Скрипт грузит **`bootstrap.lua`** первым — отключает Intro и ускоряет PreloadAsync (помогает, но **не заменяет** фокус окна).

## Управление

| Действие | Команда |
|----------|---------|
| Остановить | `getgenv().__SoccerAuto.Stop()` |
| Статус | `getgenv().__SoccerAuto.Status()` |

## Настройки

Все опции в начале `soccer_auto.lua` в таблице `CONFIG`.

После телепорта/реджойна скрипт перезапускается сам (`queue_on_teleport` + GitHub + bootstrap).
