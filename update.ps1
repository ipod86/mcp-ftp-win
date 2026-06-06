# update.ps1
# Aktualisiert mcp-ftp-win auf die neueste GitHub-Version.
# Muss als Administrator ausgefuehrt werden.
#
# Ausfuehren:
#   Rechtsklick -> "Als Administrator ausfuehren"  -oder-
#   In erhoehter PowerShell: & "$HOME\mcp-ftp-win\update.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Repo   = "$HOME\mcp-ftp-win"
$AppDir = "C:\Program Files\mcp-ftp"

Write-Host "=== mcp-ftp Update ===" -ForegroundColor Cyan

# 1) Dienst stoppen
Write-Host "Stoppe Dienst..." -ForegroundColor Yellow
Stop-ScheduledTask -TaskName "mcp-ftp" -ErrorAction SilentlyContinue

# 2) Neueste Version aus GitHub holen
Write-Host "Hole neueste Version (git pull)..." -ForegroundColor Yellow
git -C $Repo pull

# 3) Server-Code kopieren
Write-Host "Aktualisiere Server-Code in $AppDir ..." -ForegroundColor Yellow
Copy-Item "$Repo\ftp_server.py" $AppDir -Force

# 4) Python-Packages aktualisieren (mcp + paramiko fuer SFTP)
Write-Host "Aktualisiere Python-Packages..." -ForegroundColor Yellow
& "$AppDir\venv\Scripts\python.exe" -m pip install --upgrade mcp paramiko --quiet

# 5) Dienst wieder starten
Write-Host "Starte Dienst neu..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName "mcp-ftp"

# 6) Status
$state = (Get-ScheduledTask -TaskName "mcp-ftp").State
$color = if ($state -eq "Running") { "Green" } else { "Yellow" }
Write-Host ""
Write-Host "=== Update abgeschlossen ===" -ForegroundColor Green
Write-Host "Dienst-Status: $state" -ForegroundColor $color
