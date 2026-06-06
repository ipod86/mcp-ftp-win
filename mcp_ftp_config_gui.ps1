# mcp_ftp_config_gui.ps1
# Grafische Oberflaeche zum Verwalten der FTP-Zugangsdaten fuer mcp-ftp.
# Muss als Administrator ausgefuehrt werden (Lesen/Schreiben der Config erfordert erhoehte Rechte).
#
# Ausfuehren:
#   Rechtsklick -> "Als Administrator ausfuehren"  -oder-
#   In erhoehter PowerShell: & "C:\path\to\mcp_ftp_config_gui.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CfgPath = "C:\ProgramData\mcp-ftp\ftp_config.ini"
$TaskName = "mcp-ftp"

# -----------------------------------------------------------------------
# UAC: selbst neu starten als Administrator, falls noetig
# -----------------------------------------------------------------------
function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [Security.Principal.WindowsPrincipal] $id
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    $args = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $args
    exit
}

# -----------------------------------------------------------------------
# WinForms laden
# -----------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# -----------------------------------------------------------------------
# INI-Hilfsfunktionen (kein Credential-Wert in Ausgabe/Fehler)
# -----------------------------------------------------------------------
function Read-Ini {
    param([string]$Path)
    $result = [ordered]@{}
    if (-not (Test-Path $Path)) { return $result }

    $currentSection = $null
    foreach ($line in (Get-Content $Path -Encoding UTF8)) {
        $line = $line.Trim()
        if ($line -match '^\[(.+)\]$') {
            $currentSection = $Matches[1]
            $result[$currentSection] = [ordered]@{}
        } elseif ($currentSection -and $line -match '^([^=;#]+?)\s*=\s*(.*)$') {
            $result[$currentSection][$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $result
}

function Write-Ini {
    param([string]$Path, [System.Collections.Specialized.OrderedDictionary]$Data)
    $lines = @()
    foreach ($section in $Data.Keys) {
        $lines += "[$section]"
        foreach ($key in $Data[$section].Keys) {
            $lines += "$key = $($Data[$section][$key])"
        }
        $lines += ""
    }
    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

# -----------------------------------------------------------------------
# Globaler Zustand
# -----------------------------------------------------------------------
$script:IniData = Read-Ini -Path $CfgPath

# -----------------------------------------------------------------------
# Hauptfenster
# -----------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text            = "mcp-ftp Konfiguration"
$form.Size            = New-Object System.Drawing.Size(520, 420)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

# ---- Liste links ----
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(12, 12)
$listBox.Size     = New-Object System.Drawing.Size(180, 310)
$listBox.Font     = New-Object System.Drawing.Font("Consolas", 10)
$form.Controls.Add($listBox)

function Refresh-List {
    $sel = $listBox.SelectedItem
    $listBox.Items.Clear()
    foreach ($s in $script:IniData.Keys) { $listBox.Items.Add($s) | Out-Null }
    if ($sel -and $listBox.Items.Contains($sel)) {
        $listBox.SelectedItem = $sel
    } elseif ($listBox.Items.Count -gt 0) {
        $listBox.SelectedIndex = 0
    }
}

# ---- Buttons links ----
$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text     = "Neu"
$btnAdd.Location = New-Object System.Drawing.Point(12, 328)
$btnAdd.Size     = New-Object System.Drawing.Size(55, 28)
$form.Controls.Add($btnAdd)

$btnEdit = New-Object System.Windows.Forms.Button
$btnEdit.Text     = "Bearbeiten"
$btnEdit.Location = New-Object System.Drawing.Point(72, 328)
$btnEdit.Size     = New-Object System.Drawing.Size(80, 28)
$form.Controls.Add($btnEdit)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text     = "Loeschen"
$btnDelete.Location = New-Object System.Drawing.Point(157, 328)
$btnDelete.Size     = New-Object System.Drawing.Size(35, 28)
$btnDelete.ForeColor = [System.Drawing.Color]::DarkRed
$form.Controls.Add($btnDelete)

# ---- Detail-Panel rechts ----
$panelDetail = New-Object System.Windows.Forms.Panel
$panelDetail.Location    = New-Object System.Drawing.Point(204, 12)
$panelDetail.Size        = New-Object System.Drawing.Size(298, 340)
$panelDetail.BorderStyle = "FixedSingle"
$form.Controls.Add($panelDetail)

function Make-Label([string]$text, [int]$y) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text     = $text
    $lbl.Location = New-Object System.Drawing.Point(8, $y)
    $lbl.Size     = New-Object System.Drawing.Size(80, 20)
    $lbl.TextAlign = "MiddleLeft"
    return $lbl
}
function Make-TextBox([int]$y, [bool]$pw = $false) {
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location      = New-Object System.Drawing.Point(92, ($y - 1))
    $tb.Size          = New-Object System.Drawing.Size(194, 22)
    $tb.UseSystemPasswordChar = $pw
    return $tb
}

$lblName = Make-Label "Name:"     10
$lblHost = Make-Label "Host:"     42
$lblPort = Make-Label "Port:"     74
$lblUser = Make-Label "Benutzer:" 106
$lblPass = Make-Label "Passwort:" 138

$tbName = Make-TextBox 10
$tbHost = Make-TextBox 42
$tbPort = Make-TextBox 74
$tbUser = Make-TextBox 106
$tbPass = Make-TextBox 138 $true

$chkShowPw = New-Object System.Windows.Forms.CheckBox
$chkShowPw.Text     = "Passwort anzeigen"
$chkShowPw.Location = New-Object System.Drawing.Point(92, 163)
$chkShowPw.Size     = New-Object System.Drawing.Size(160, 20)

foreach ($c in @($lblName,$lblHost,$lblPort,$lblUser,$lblPass,
                  $tbName,$tbHost,$tbPort,$tbUser,$tbPass,$chkShowPw)) {
    $panelDetail.Controls.Add($c)
}

$chkShowPw.Add_CheckedChanged({
    $tbPass.UseSystemPasswordChar = -not $chkShowPw.Checked
})

# Trennlinie
$sep = New-Object System.Windows.Forms.Label
$sep.BorderStyle = "Fixed3D"
$sep.Location    = New-Object System.Drawing.Point(8, 192)
$sep.Size        = New-Object System.Drawing.Size(278, 2)
$panelDetail.Controls.Add($sep)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text     = "Speichern"
$btnSave.Location = New-Object System.Drawing.Point(8, 202)
$btnSave.Size     = New-Object System.Drawing.Size(278, 30)
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.FlatStyle = "Flat"
$panelDetail.Controls.Add($btnSave)

$chkRestart = New-Object System.Windows.Forms.CheckBox
$chkRestart.Text     = "Dienst nach dem Speichern neu starten"
$chkRestart.Location = New-Object System.Drawing.Point(8, 240)
$chkRestart.Size     = New-Object System.Drawing.Size(278, 20)
$chkRestart.Checked  = $true
$panelDetail.Controls.Add($chkRestart)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location  = New-Object System.Drawing.Point(8, 268)
$lblStatus.Size      = New-Object System.Drawing.Size(278, 60)
$lblStatus.Text      = ""
$lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
$panelDetail.Controls.Add($lblStatus)

# -----------------------------------------------------------------------
# Hilfsfunktionen fuer UI
# -----------------------------------------------------------------------
function Set-Fields-ReadOnly([bool]$ro) {
    foreach ($tb in @($tbName, $tbHost, $tbPort, $tbUser, $tbPass)) {
        $tb.ReadOnly = $ro
        $tb.BackColor = if ($ro) { [System.Drawing.SystemColors]::Control } else { [System.Drawing.Color]::White }
    }
    $btnSave.Enabled = -not $ro
}

function Show-Server([string]$name) {
    if (-not $name -or -not $script:IniData.Contains($name)) {
        $tbName.Text = ""; $tbHost.Text = ""; $tbPort.Text = ""
        $tbUser.Text = ""; $tbPass.Text = ""
        Set-Fields-ReadOnly $true
        return
    }
    $s = $script:IniData[$name]
    $tbName.Text = $name
    $tbHost.Text = if ($s.Contains("host"))     { $s["host"] }     else { "" }
    $tbPort.Text = if ($s.Contains("port"))     { $s["port"] }     else { "21" }
    $tbUser.Text = if ($s.Contains("username")) { $s["username"] } else { "" }
    $tbPass.Text = if ($s.Contains("password")) { $s["password"] } else { "" }
    Set-Fields-ReadOnly $false
}

function Clear-Fields-ForNew {
    $tbName.Text = ""; $tbHost.Text = ""; $tbPort.Text = "21"
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
    $lblStatus.Text      = ""
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $listBox.ClearSelected()
    Clear-Fields-ForNew
})

$btnEdit.Add_Click({
    $sel = $listBox.SelectedItem
    if (-not $sel) {
        [System.Windows.Forms.MessageBox]::Show("Bitte zuerst einen Server auswaehlen.", "Hinweis") | Out-Null
        return
    }
    Set-Fields-ReadOnly $false
    $tbName.Focus() | Out-Null
})

$btnDelete.Add_Click({
    $sel = $listBox.SelectedItem
    if (-not $sel) {
        [System.Windows.Forms.MessageBox]::Show("Bitte zuerst einen Server auswaehlen.", "Hinweis") | Out-Null
        return
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
    $host    = $tbHost.Text.Trim()
    $port    = $tbPort.Text.Trim()
    $user    = $tbUser.Text.Trim()
    $pass    = $tbPass.Text  # kein Trim bei Passwort

    if (-not $newName) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "Fehler: Name darf nicht leer sein."
        $tbName.Focus() | Out-Null
        return
    }
    if (-not $host) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "Fehler: Host darf nicht leer sein."
        $tbHost.Focus() | Out-Null
        return
    }
    if ($port -and ($port -notmatch '^\d+$' -or [int]$port -lt 1 -or [int]$port -gt 65535)) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "Fehler: Port muss eine Zahl von 1-65535 sein."
        $tbPort.Focus() | Out-Null
        return
    }

    # Alter Name (falls umbenannt)
    $oldName = $listBox.SelectedItem
    if ($oldName -and $oldName -ne $newName) {
        $script:IniData.Remove($oldName) | Out-Null
    }

    $section = [ordered]@{}
    $section["host"]     = $host
    $section["port"]     = if ($port) { $port } else { "21" }
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

if ($listBox.Items.Count -gt 0) {
    $listBox.SelectedIndex = 0
}

# Hinweis: Config-Datei fehlt
if (-not (Test-Path $CfgPath)) {
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkOrange
    $lblStatus.Text = "Hinweis: Config-Datei noch nicht vorhanden -- wird beim ersten Speichern angelegt."
    Clear-Fields-ForNew
}

# -----------------------------------------------------------------------
# Fenster anzeigen
# -----------------------------------------------------------------------
[System.Windows.Forms.Application]::Run($form)
