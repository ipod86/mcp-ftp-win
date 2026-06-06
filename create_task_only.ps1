# create_task_only.ps1
# Legt NUR die geplante Aufgabe 'mcp-ftp' an -- alle anderen Schritte
# (Benutzer, Code, ACLs, Config) wurden bereits durch windows_admin_setup.ps1
# erledigt und muessen nicht wiederholt werden.
#
# Ausfuehren in einer ALS ADMINISTRATOR gestarteten PowerShell:
#   Set-ExecutionPolicy -Scope Process Bypass
#   & "$HOME\mcp-ftp-win\create_task_only.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$AppDir = "C:\Program Files\mcp-ftp"
$Cfg    = "C:\ProgramData\mcp-ftp\ftp_config.ini"

Write-Host "=== mcp-ftp: Geplante Aufgabe anlegen ===" -ForegroundColor Cyan

# Passwort von mcpftp abfragen (wird fuer Register-ScheduledTask benoetigt)
$pw = Read-Host "Passwort des Benutzers 'mcpftp' eingeben" -AsSecureString
$pwPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))

Write-Host "Erstelle geplante Aufgabe 'mcp-ftp'..." -ForegroundColor Yellow

$taskAction   = New-ScheduledTaskAction `
    -Execute  "$AppDir\venv\Scripts\pythonw.exe" `
    -Argument "`"$AppDir\ftp_server.py`""

$taskTrigger  = New-ScheduledTaskTrigger -AtStartup

$taskSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount       3 `
    -RestartInterval    (New-TimeSpan -Minutes 1) `
    -MultipleInstances  IgnoreNew

# -Principal und -Password zusammen sind ungueltig -- stattdessen
# -User / -Password / -RunLevel direkt an Register-ScheduledTask uebergeben
Register-ScheduledTask `
    -TaskName "mcp-ftp" `
    -Action   $taskAction `
    -Trigger  $taskTrigger `
    -Settings $taskSettings `
    -User     "mcpftp" `
    -Password $pwPlain `
    -RunLevel Limited `
    -Force | Out-Null

Start-ScheduledTask -TaskName "mcp-ftp"

Write-Host "  Aufgabe registriert und gestartet." -ForegroundColor Green
Write-Host ""
Write-Host "Status:" -ForegroundColor Cyan
Write-Host "  Get-ScheduledTask -TaskName mcp-ftp | Select-Object -ExpandProperty State"
Write-Host ""
Write-Host "Zugangsdaten eintragen (falls noch nicht geschehen):" -ForegroundColor Cyan
Write-Host "  Rechtsklick auf Notepad -> Als Administrator ausfuehren"
Write-Host "  Datei oeffnen: $Cfg"
Write-Host "  Je Server einen Block [name] mit host / port / username / password eintragen."
Write-Host ""
Write-Host "Aufgabe stoppen / neu starten nach Aenderungen:" -ForegroundColor Cyan
Write-Host "  Stop-ScheduledTask  -TaskName mcp-ftp"
Write-Host "  Start-ScheduledTask -TaskName mcp-ftp"
Write-Host ""
Write-Host "Sicherheits-Check (in normaler, NICHT erhoehter PowerShell):" -ForegroundColor Cyan
Write-Host "  Get-Content C:\ProgramData\mcp-ftp\ftp_config.ini"
Write-Host "  --> Erwartet: 'Zugriff verweigert'. Falls lesbar: Rechte pruefen!"
Write-Host ""
Write-Host "WICHTIG: Claude Code NIEMALS 'Als Administrator ausfuehren' starten!" -ForegroundColor Red
