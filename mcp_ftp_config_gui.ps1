# mcp_ftp_config_gui.ps1
# Grafische Oberflaeche zum Verwalten der FTP/FTPS/SFTP-Zugangsdaten fuer mcp-ftp.
# Muss als Administrator ausgefuehrt werden.
#
# Ausfuehren:
#   Rechtsklick -> "Als Administrator ausfuehren"  -oder-
#   In erhoehter PowerShell: & "C:\path\to\mcp_ftp_config_gui.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CfgPath  = "C:\ProgramData\mcp-ftp\ftp_config.ini"
$TaskName = "mcp-ftp"

# -----------------------------------------------------------------------
# UAC: selbst neu starten als Administrator, falls noetig
# -----------------------------------------------------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal] $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $elevArgs = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs
    exit
}

# -----------------------------------------------------------------------
# WinForms laden
# -----------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------------------------------------------------
# INI-Hilfsfunktionen
# -----------------------------------------------------------------------
function Read-Ini {
    param([string]$Path)
    $result = [ordered]@{}
    if (-not (Test-Path $Path)) { return $result }
    $sec = $null
    foreach ($line in (Get-Content $Path -Encoding UTF8)) {
        $line = $line.Trim()
        if ($line -match '^\[(.+)\]$') {
            $sec = $Matches[1]; $result[$sec] = [ordered]@{}
        } elseif ($sec -and $line -match '^([^=;#]+?)\s*=\s*(.*)$') {
            $result[$sec][$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $result
}

function Write-Ini {
    param([string]$Path, [System.Collections.Specialized.OrderedDictionary]$Data)
    $lines = @()
    foreach ($sec in $Data.Keys) {
        $lines += "[$sec]"
        foreach ($k in $Data[$sec].Keys) { $lines += "$k = $($Data[$sec][$k])" }
        $lines += ""
    }
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

# -----------------------------------------------------------------------
# Zustand
# -----------------------------------------------------------------------
$script:IniData = Read-Ini -Path $CfgPath

# Standardport je Protokoll
$DefaultPort = @{ ftp = "21"; ftps = "21"; sftp = "22" }

# -----------------------------------------------------------------------
# Hauptfenster
# -----------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "mcp-ftp Konfiguration"
$form.Size            = New-Object System.Drawing.Size(520, 460)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

# ---- Serverliste links ----
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(12, 12)
$listBox.Size     = New-Object System.Drawing.Size(180, 350)
$listBox.Font     = New-Object System.Drawing.Font("Consolas", 10)
$form.Controls.Add($listBox)

function Refresh-List {
    $sel = $listBox.SelectedItem
    $listBox.Items.Clear()
    foreach ($s in $script:IniData.Keys) { $listBox.Items.Add($s) | Out-Null }
    if ($sel -and $listBox.Items.Contains($sel)) { $listBox.SelectedItem = $sel }
    elseif ($listBox.Items.Count -gt 0)          { $listBox.SelectedIndex = 0 }
}

# ---- Buttons links ----
$btnAdd    = New-Object System.Windows.Forms.Button
$btnAdd.Text     = "Neu"
$btnAdd.Location = New-Object System.Drawing.Point(12, 368)
$btnAdd.Size     = New-Object System.Drawing.Size(55, 28)
$form.Controls.Add($btnAdd)

$btnEdit   = New-Object System.Windows.Forms.Button
$btnEdit.Text     = "Bearbeiten"
$btnEdit.Location = New-Object System.Drawing.Point(72, 368)
$btnEdit.Size     = New-Object System.Drawing.Size(80, 28)
$form.Controls.Add($btnEdit)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text      = "Loeschen"
$btnDelete.Location  = New-Object System.Drawing.Point(157, 368)
$btnDelete.Size      = New-Object System.Drawing.Size(35, 28)
$btnDelete.ForeColor = [System.Drawing.Color]::DarkRed
$form.Controls.Add($btnDelete)

# -----------------------------------------------------------------------
# Detail-Panel rechts
# -----------------------------------------------------------------------
$panel = New-Object System.Windows.Forms.Panel
$panel.Location    = New-Object System.Drawing.Point(204, 12)
$panel.Size        = New-Object System.Drawing.Size(298, 384)
$panel.BorderStyle = "FixedSingle"
$form.Controls.Add($panel)

function Make-Label([string]$text, [int]$y) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $text; $lbl.Location = New-Object System.Drawing.Point(8, $y)
    $lbl.Size = New-Object System.Drawing.Size(80, 20); $lbl.TextAlign = "MiddleLeft"
    return $lbl
}
function Make-TextBox([int]$y, [bool]$pw = $false) {
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(92, ($y - 1))
    $tb.Size     = New-Object System.Drawing.Size(194, 22)
    $tb.UseSystemPasswordChar = $pw
    return $tb
}

# Felder (Name / Typ / Host / Port / Benutzer / Passwort)
$lblName = Make-Label "Name:"     10
$lblTyp  = Make-Label "Typ:"      42
$lblHost = Make-Label "Host:"     74
$lblPort = Make-Label "Port:"     106
$lblUser = Make-Label "Benutzer:" 138
$lblPass = Make-Label "Passwort:" 170

$tbName = Make-TextBox 10
$tbHost = Make-TextBox 74
$tbPort = Make-TextBox 106
$tbUser = Make-TextBox 138
$tbPass = Make-TextBox 170 $true

$cbTyp = New-Object System.Windows.Forms.ComboBox
$cbTyp.Location      = New-Object System.Drawing.Point(92, 41)
$cbTyp.Size          = New-Object System.Drawing.Size(100, 22)
$cbTyp.DropDownStyle = "DropDownList"
@("ftp", "ftps", "sftp") | ForEach-Object { $cbTyp.Items.Add($_) | Out-Null }
$cbTyp.SelectedIndex = 0

$chkShowPw = New-Object System.Windows.Forms.CheckBox
$chkShowPw.Text     = "Passwort anzeigen"
$chkShowPw.Location = New-Object System.Drawing.Point(92, 195)
$chkShowPw.Size     = New-Object System.Drawing.Size(160, 20)

foreach ($c in @($lblName,$lblTyp,$lblHost,$lblPort,$lblUser,$lblPass,
                  $tbName,$cbTyp,$tbHost,$tbPort,$tbUser,$tbPass,$chkShowPw)) {
    $panel.Controls.Add($c)
}

$chkShowPw.Add_CheckedChanged({
    $tbPass.UseSystemPasswordChar = -not $chkShowPw.Checked
})

# Auto-Port bei Typ-Wechsel
$cbTyp.Add_SelectedIndexChanged({
    $newTyp  = $cbTyp.SelectedItem
    $curPort = $tbPort.Text.Trim()
    # Nur ueberschreiben wenn noch der Default eines anderen Typs drin steht
    if ($curPort -eq "" -or $curPort -in @("21","22")) {
        $tbPort.Text = $DefaultPort[$newTyp]
    }
})

# Trennlinie
$sep = New-Object System.Windows.Forms.Label
$sep.BorderStyle = "Fixed3D"
$sep.Location    = New-Object System.Drawing.Point(8, 224)
$sep.Size        = New-Object System.Drawing.Size(278, 2)
$panel.Controls.Add($sep)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text      = "Speichern"
$btnSave.Location  = New-Object System.Drawing.Point(8, 234)
$btnSave.Size      = New-Object System.Drawing.Size(278, 30)
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.FlatStyle = "Flat"
$panel.Controls.Add($btnSave)

$chkRestart = New-Object System.Windows.Forms.CheckBox
$chkRestart.Text     = "Dienst nach dem Speichern neu starten"
$chkRestart.Location = New-Object System.Drawing.Point(8, 272)
$chkRestart.Size     = New-Object System.Drawing.Size(278, 20)
$chkRestart.Checked  = $true
$panel.Controls.Add($chkRestart)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location  = New-Object System.Drawing.Point(8, 300)
$lblStatus.Size      = New-Object System.Drawing.Size(278, 72)
$lblStatus.Text      = ""
$lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
$panel.Controls.Add($lblStatus)

# -----------------------------------------------------------------------
# UI-Hilfsfunktionen
# -----------------------------------------------------------------------
function Set-Fields-ReadOnly([bool]$ro) {
    foreach ($tb in @($tbName,$tbHost,$tbPort,$tbUser,$tbPass)) {
        $tb.ReadOnly = $ro
        $tb.BackColor = if ($ro) { [System.Drawing.SystemColors]::Control } else { [System.Drawing.Color]::White }
    }
    $cbTyp.Enabled  = -not $ro
    $btnSave.Enabled = -not $ro
}

function Show-Server([string]$name) {
    if (-not $name -or -not $script:IniData.Contains($name)) {
        $tbName.Text = ""; $cbTyp.SelectedIndex = 0
        $tbHost.Text = ""; $tbPort.Text = "21"
        $tbUser.Text = ""; $tbPass.Text = ""
        Set-Fields-ReadOnly $true; return
    }
    $s = $script:IniData[$name]
    $tbName.Text = $name
    $typ = if ($s.Contains("type")) { $s["type"].ToLower() } else { "ftp" }
    $cbTyp.SelectedItem = if ($cbTyp.Items.Contains($typ)) { $typ } else { "ftp" }
    $tbHost.Text = if ($s.Contains("host"))     { $s["host"] }     else { "" }
    $tbPort.Text = if ($s.Contains("port"))     { $s["port"] }     else { $DefaultPort[$cbTyp.SelectedItem] }
    $tbUser.Text = if ($s.Contains("username")) { $s["username"] } else { "" }
    $tbPass.Text = if ($s.Contains("password")) { $s["password"] } else { "" }
    Set-Fields-ReadOnly $false
}

function Clear-Fields-ForNew {
    $tbName.Text = ""; $cbTyp.SelectedIndex = 0
    $tbHost.Text = ""; $tbPort.Text = "21"
    $tbUser.Text = ""; $tbPass.Text = ""
    Set-Fields-ReadOnly $false
    $tbName.Focus() | Out-Null
}

# -----------------------------------------------------------------------
# Event-Handler
# -----------------------------------------------------------------------
$listBox.Add_SelectedIndexChanged({
    $sel = $listBox.SelectedItem
    if ($sel) { Show-Server $sel } else { Show-Server "" }
})

$btnAdd.Add_Click({
    $lblStatus.Text = ""; $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $listBox.ClearSelected(); Clear-Fields-ForNew
})

$btnEdit.Add_Click({
    if (-not $listBox.SelectedItem) {
        [System.Windows.Forms.MessageBox]::Show("Bitte zuerst einen Server auswaehlen.", "Hinweis") | Out-Null; return
    }
    Set-Fields-ReadOnly $false; $tbName.Focus() | Out-Null
})

$btnDelete.Add_Click({
    $sel = $listBox.SelectedItem
    if (-not $sel) {
        [System.Windows.Forms.MessageBox]::Show("Bitte zuerst einen Server auswaehlen.", "Hinweis") | Out-Null; return
    }
    $res = [System.Windows.Forms.MessageBox]::Show(
        "Server '$sel' wirklich loeschen?", "Bestaetigung",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($res -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $script:IniData.Remove($sel) | Out-Null
    Write-Ini -Path $CfgPath -Data $script:IniData

    if ($chkRestart.Checked) {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Stop-ScheduledTask  -TaskName $TaskName -ErrorAction SilentlyContinue
            Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        }
    }
    Refresh-List
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblStatus.Text = "Server '$sel' geloescht."
    Show-Server ($listBox.SelectedItem)
})

$btnSave.Add_Click({
    $lblStatus.Text = ""
    $newName = $tbName.Text.Trim()
    $newTyp  = $cbTyp.SelectedItem
    $ftpHost = $tbHost.Text.Trim()
    $port    = $tbPort.Text.Trim()
    $user    = $tbUser.Text.Trim()
    $pass    = $tbPass.Text

    if (-not $newName) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "Fehler: Name darf nicht leer sein."
        $tbName.Focus() | Out-Null; return
    }
    if (-not $ftpHost) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "Fehler: Host darf nicht leer sein."
        $tbHost.Focus() | Out-Null; return
    }
    if ($port -and ($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535)) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "Fehler: Port muss eine Zahl von 1-65535 sein."
        $tbPort.Focus() | Out-Null; return
    }

    $oldName = $listBox.SelectedItem
    if ($oldName -and $oldName -ne $newName) { $script:IniData.Remove($oldName) | Out-Null }

    $section             = [ordered]@{}
    $section["type"]     = $newTyp
    $section["host"]     = $ftpHost
    $section["port"]     = if ($port) { $port } else { $DefaultPort[$newTyp] }
    $section["username"] = $user
    $section["password"] = $pass
    $script:IniData[$newName] = $section

    Write-Ini -Path $CfgPath -Data $script:IniData

    if ($chkRestart.Checked) {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Stop-ScheduledTask  -TaskName $TaskName -ErrorAction SilentlyContinue
            Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            $lblStatus.Text = "Gespeichert. Dienst wurde neu gestartet."
        } else {
            $lblStatus.ForeColor = [System.Drawing.Color]::DarkOrange
            $lblStatus.Text = "Gespeichert. Aufgabe '$TaskName' nicht gefunden -- bitte manuell starten."
        }
    } else {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblStatus.Text = "Gespeichert (kein Neustart)."
    }
    Refresh-List
    $listBox.SelectedItem = $newName
})

# -----------------------------------------------------------------------
# Initialisierung
# -----------------------------------------------------------------------
Set-Fields-ReadOnly $true
Refresh-List
if ($listBox.Items.Count -gt 0) { $listBox.SelectedIndex = 0 }

if (-not (Test-Path $CfgPath)) {
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    $lblStatus.Text = "Config-Datei noch nicht vorhanden -- wird beim ersten Speichern angelegt."
    Clear-Fields-ForNew
}

[System.Windows.Forms.Application]::Run($form)
