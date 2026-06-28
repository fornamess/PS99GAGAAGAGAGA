# Авто-фокус окон Roblox — без этого клиент Roblox на Windows почти не грузится в фоне.
# Запуск: правый клик -> "Выполнить с PowerShell" или: powershell -ExecutionPolicy Bypass -File focus_helper.ps1
#
# Режимы:
#   -PulseSeconds 20   — держать фокус на новом окне Roblox N секунд (по умолчанию 25)
#   -RotateMulti      — если несколько окон, по очереди давать фокус каждому (для мульти-аккаунта)

param(
    [int]$PulseSeconds = 25,
    [switch]$RotateMulti,
    [int]$RotateInterval = 20
)

Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public static class WinFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;

    public static void ForceFocus(IntPtr hWnd) {
        if (hWnd == IntPtr.Zero) return;
        if (IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);
        else ShowWindow(hWnd, SW_SHOW);
        IntPtr fg = GetForegroundWindow();
        uint fgThread = GetWindowThreadProcessId(fg, out _);
        uint curThread = GetCurrentThreadId();
        if (fgThread != curThread) AttachThreadInput(curThread, fgThread, true);
        SetForegroundWindow(hWnd);
        if (fgThread != curThread) AttachThreadInput(curThread, fgThread, false);
    }
}
"@

function Get-RobloxWindows {
    $result = @()
    Get-Process -Name "RobloxPlayerBeta" -ErrorAction SilentlyContinue | ForEach-Object {
        $h = $_.MainWindowHandle
        if ($h -ne [IntPtr]::Zero -and [WinFocus]::IsWindowVisible($h)) {
            $len = [WinFocus]::GetWindowTextLength($h)
            $title = ""
            if ($len -gt 0) {
                $sb = New-Object System.Text.StringBuilder ($len + 1)
                [void][WinFocus]::GetWindowText($h, $sb, $sb.Capacity)
                $title = $sb.ToString()
            }
            $result += [PSCustomObject]@{
                Handle = $h
                Pid = $_.Id
                Title = $title
            }
        }
    }
    return $result
}

$seen = @{}
$pulseUntil = @{}
$rotateIndex = 0

Write-Host "[FocusHelper] Roblox auto-focus ON | pulse=${PulseSeconds}s | rotate=$RotateMulti"
Write-Host "[FocusHelper] Ctrl+C чтобы остановить"

while ($true) {
    $now = Get-Date
    $windows = Get-RobloxWindows

    foreach ($w in $windows) {
        $key = "$($w.Pid)"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $pulseUntil[$key] = $now.AddSeconds($PulseSeconds)
            Write-Host "[FocusHelper] Новое окно Roblox pid=$($w.Pid) -> фокус на ${PulseSeconds}с"
            [WinFocus]::ForceFocus($w.Handle)
        }
    }

    # Пульс фокуса для свежих окон (загрузка BIG GAMES)
    foreach ($w in $windows) {
        $key = "$($w.Pid)"
        if ($pulseUntil.ContainsKey($key) -and $now -lt $pulseUntil[$key]) {
            $fg = [WinFocus]::GetForegroundWindow()
            if ($fg -ne $w.Handle) {
                [WinFocus]::ForceFocus($w.Handle)
            }
        }
    }

    # Ротация между несколькими окнами (мульти-аккаунт)
    if ($RotateMulti -and $windows.Count -gt 1) {
        $idx = $rotateIndex % $windows.Count
        $target = $windows[$idx]
        [WinFocus]::ForceFocus($target.Handle)
        $rotateIndex++
        Start-Sleep -Seconds $RotateInterval
    } else {
        Start-Sleep -Seconds 2
    }
}
