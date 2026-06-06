# windows_admin_setup.ps1
# Einmalig in einer ALS ADMINISTRATOR gestarteten PowerShell ausfuehren.
# Quelle: geklontes Repo in %USERPROFILE%\mcp-ftp-win
#
# Voraussetzung: Python muss systemweit installiert sein (py-Launcher).
#   Test: py --version
#   Falls nicht vorhanden: https://www.python.org/downloads/
#   Option "Add python.exe to PATH" und "py launcher" aktivieren.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Repo    = "$HOME\mcp-ftp-win"
$AppDir  = "C:\Program Files\mcp-ftp"
$DataDir = "C:\ProgramData\mcp-ftp"
$Cfg     = "$DataDir\ftp_config.ini"
$Exch    = "$DataDir\exchange"

Write-Host "=== mcp-ftp Windows Setup ===" -ForegroundColor Cyan

# -----------------------------------------------------------------------
# 1) Passwort abfragen und lokalen Standardbenutzer 'mcpftp' anlegen
# -----------------------------------------------------------------------
$pw = Read-Host "Passwort fuer neuen Benutzer 'mcpftp' festlegen" -AsSecureString
$pwPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))

Write-Host "Lege Benutzer 'mcpftp' an..." -ForegroundColor Yellow
net user mcpftp $pwPlain /add /passwordchg:no | Out-Null
# PasswordExpires=false (wmic ist deprecated ab Win11 24H2, net user hat kein Flag dafuer)
$localUser = Get-LocalUser -Name "mcpftp"
$localUser | Set-LocalUser -PasswordNeverExpires $true
# Sicherstellen: mcpftp ist NICHT in der Administratorengruppe
$admins = (Get-LocalGroupMember -SID "S-1-5-32-544" | Where-Object { $_.Name -match "mcpftp" })
if ($admins) {
    Remove-LocalGroupMember -SID "S-1-5-32-544" -Member "mcpftp"
    Write-Host "  mcpftp aus Administratorengruppe entfernt." -ForegroundColor Yellow
}
Write-Host "  Benutzer 'mcpftp' angelegt (Standardbenutzer)." -ForegroundColor Green

# -----------------------------------------------------------------------
# 2) Server-Code installieren
#    AppDir: Admins = Vollzugriff, Benutzer = Lesen/Ausfuehren, mcpftp = Lesen/Ausfuehren
# -----------------------------------------------------------------------
Write-Host "Installiere Server-Code nach $AppDir ..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
Copy-Item "$Repo\ftp_server.py" $AppDir -Force

py -m venv "$AppDir\venv"
& "$AppDir\venv\Scripts\python.exe" -m pip install mcp --quiet

# Eigentuemer auf Admins setzen (verhindert WRITE_DAC ueber Alltagsbenutzer-SID)
icacls $AppDir /setowner "*S-1-5-32-544" /T | Out-Null
# Rechte: Admins voll, Benutzer (S-1-5-32-545) und mcpftp lesen/ausfuehren
icacls $AppDir /inheritance:r | Out-Null
icacls $AppDir /grant "*S-1-5-18:(OI)(CI)(F)"      | Out-Null  # SYSTEM voll
icacls $AppDir /grant "*S-1-5-32-544:(OI)(CI)(F)"  | Out-Null  # Administratoren voll
icacls $AppDir /grant "*S-1-5-32-545:(OI)(CI)(RX)" | Out-Null  # Benutzer lesen/ausfuehren
icacls $AppDir /grant "mcpftp:(OI)(CI)(RX)"        | Out-Null  # Dienstbenutzer lesen/ausfuehren
Write-Host "  $AppDir eingerichtet (Eigentuemer: Administratoren)." -ForegroundColor Green

# -----------------------------------------------------------------------
# 3) Datenverzeichnis + Austauschordner
# -----------------------------------------------------------------------
Write-Host "Richte Datenverzeichnis $DataDir ein..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
New-Item -ItemType Directory -Force -Path $Exch    | Out-Null
Copy-Item "$Repo\ftp_config.ini.example" $Cfg -Force

# -----------------------------------------------------------------------
# 4) Strenge Rechte auf die Config
#    SYSTEM + mcpftp: Lesen; Administratoren: Vollzugriff (nur erhoeht nutzbar)
#    KEIN Zugriff fuer normale Benutzer (S-1-5-32-545) oder Jeder
# -----------------------------------------------------------------------
Write-Host "Setze Eigentuemer und Rechte auf $Cfg ..." -ForegroundColor Yellow
# Eigentuemer auf Admins setzen (kein WRITE_DAC ueber ungefilterte Benutzer-SID)
icacls $Cfg /setowner "*S-1-5-32-544" | Out-Null
icacls $Cfg /inheritance:r             | Out-Null
icacls $Cfg /grant "*S-1-5-18:(R)"    | Out-Null  # SYSTEM lesen
icacls $Cfg /grant "mcpftp:(R)"       | Out-Null  # Dienstbenutzer lesen
icacls $Cfg /grant "*S-1-5-32-544:(F)"| Out-Null  # Administratoren voll (nur erhoeht!)
Write-Host "  Config-Rechte gesetzt (Eigentuemer: Administratoren, normale Benutzer kein Zugriff)." -ForegroundColor Green

# -----------------------------------------------------------------------
# 5) Austauschordner: mcpftp + normale Benutzer duerfen lesen/schreiben
# -----------------------------------------------------------------------
Write-Host "Setze Rechte auf $Exch ..." -ForegroundColor Yellow
icacls $Exch /inheritance:r                        | Out-Null
icacls $Exch /grant "*S-1-5-18:(OI)(CI)(F)"       | Out-Null  # SYSTEM voll
icacls $Exch /grant "*S-1-5-32-544:(OI)(CI)(F)"   | Out-Null  # Administratoren voll
icacls $Exch /grant "mcpftp:(OI)(CI)(M)"          | Out-Null  # Dienstbenutzer aendern
icacls $Exch /grant "*S-1-5-32-545:(OI)(CI)(M)"   | Out-Null  # Benutzer aendern
Write-Host "  Austauschordner-Rechte gesetzt." -ForegroundColor Green

# -----------------------------------------------------------------------
# 6) Geplante Aufgabe: Server als mcpftp, eingeschraenkt, beim Systemstart,
#    kein Zeitlimit, Neustart bei Absturz
# -----------------------------------------------------------------------
Write-Host "Erstelle geplante Aufgabe 'mcp-ftp'..." -ForegroundColor Yellow

$taskAction = New-ScheduledTaskAction `
    -Execute "$AppDir\venv\Scripts\python.exe" `
    -Argument "`"$AppDir\ftp_server.py`""

$taskTrigger = New-ScheduledTaskTrigger -AtStartup

$taskPrincipal = New-ScheduledTaskPrincipal `
    -UserId    "mcpftp" `
    -LogonType Password `
    -RunLevel  Limited

$taskSettings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit  ([TimeSpan]::Zero) `
    -RestartCount        3 `
    -RestartInterval     (New-TimeSpan -Minutes 1) `
    -MultipleInstances   IgnoreNew `
    -DisallowHardTerminate $false

Register-ScheduledTask `
    -TaskName  "mcp-ftp" `
    -Action    $taskAction `
    -Trigger   $taskTrigger `
    -Principal $taskPrincipal `
    -Settings  $taskSettings `
    -Password  $pwPlain `
    -Force | Out-Null

Start-ScheduledTask -TaskName "mcp-ftp"
Write-Host "  Geplante Aufgabe erstellt und gestartet (kein Zeitlimit, Neustart bei Absturz)." -ForegroundColor Green

# -----------------------------------------------------------------------
# Fertig
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Fertig ===" -ForegroundColor Green
Write-Host ""
Write-Host "Status pruefen:" -ForegroundColor Cyan
Write-Host "  Get-ScheduledTask -TaskName mcp-ftp | Select-Object -ExpandProperty State"
Write-Host ""
Write-Host "Zugangsdaten eintragen (als Administrator):" -ForegroundColor Cyan
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
Write-Host "  Nur als normaler Benutzer gestartet greift der UAC-Schutz."
