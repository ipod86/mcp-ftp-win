# mcp-ftp-win — Windows Edition

MCP server that provides FTP access for [Claude Code](https://claude.ai/code) — **Windows-native version**.

Runs as an isolated local user (`mcpftp`) via a scheduled task. FTP credentials are stored in
`C:\ProgramData\mcp-ftp\ftp_config.ini` with NTFS permissions that block access from
non-elevated processes — so Claude Code cannot read them.

> **Linux/macOS?** Use the [mcp-ftp](https://github.com/ipod86/mcp-ftp) repo instead.

---

## Requirements

- Windows 10 / 11 or Windows Server 2019+
- Python 3.10 or newer installed **system-wide** with the **py launcher**
  (select "Add python.exe to PATH" and "py launcher" during installation)
  Download: https://www.python.org/downloads/

Check: open PowerShell and run `py --version`. If that fails, install Python first.

---

## Security model

| Layer | Measure |
|-------|---------|
| Windows user | Server runs as local standard user `mcpftp` (not in Administrators group) |
| NTFS permissions | Config readable only by `mcpftp` + SYSTEM + elevated Administrators |
| UAC | Non-elevated Claude Code gets a filtered token — Administrators group only denies, not grants |
| Scheduled task | `/RL LIMITED` — restricted privilege level |
| Network | Server listens only on 127.0.0.1:8765, not reachable from the LAN |
| Claude Code | deny rules + PreToolUse hook block any read attempt on the config path |

**Important:** Never start Claude Code "Run as administrator" — that would bypass the UAC protection.

---

## Installation

### Step 1 — Clone the repository

```powershell
git clone https://github.com/ipod86/mcp-ftp-win.git "$HOME\mcp-ftp-win"
```

### Step 2 — Register the MCP client (no admin required)

```powershell
claude mcp add --transport sse ftp-win http://127.0.0.1:8765/sse
```

### Step 3 — Run the admin setup (once, as Administrator)

Close Claude Code first, then open PowerShell **as Administrator** and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "$HOME\mcp-ftp-win\windows_admin_setup.ps1"
```

The script will:
- Prompt you for a password for the new `mcpftp` user
- Create the local standard user `mcpftp`
- Install server code to `C:\Program Files\mcp-ftp\` with a Python venv
- Create `C:\ProgramData\mcp-ftp\ftp_config.ini` (from the example) with strict NTFS rights
- Create `C:\ProgramData\mcp-ftp\exchange\` (read/write for both `mcpftp` and normal users)
- Register and start a scheduled task `mcp-ftp` running as `mcpftp`

### Step 4 — Enter your FTP credentials

#### Option A — GUI (recommended)

Right-click `mcp_ftp_config_gui.ps1` in the cloned repo folder and choose **Run as administrator**.

![GUI: server list on the left, fields for Name / Host / Port / Username / Password on the right]

The GUI will auto-elevate via UAC if needed. Use it to:

- **Add** a server: click **Neu**, fill in the fields, click **Speichern**
- **Edit** a server: select it in the list, click **Bearbeiten**, change the fields, click **Speichern**
- **Delete** a server: select it in the list, click **Löschen**
- The checkbox **"Dienst nach dem Speichern neu starten"** restarts the scheduled task automatically after saving (on by default)

You can also start the GUI from an elevated PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "$HOME\mcp-ftp-win\mcp_ftp_config_gui.ps1"
```

#### Option B — Notepad (manual)

Right-click Notepad → **Run as administrator**, then open:
```
C:\ProgramData\mcp-ftp\ftp_config.ini
```

Format — one block per server:

```ini
[mein-server]
host = ftp.beispiel.de
port = 21
username = benutzername
password = passwort
```

After saving, restart the task manually:
```powershell
Stop-ScheduledTask  -TaskName mcp-ftp
Start-ScheduledTask -TaskName mcp-ftp
```

### Step 5 — Verify

```powershell
schtasks /Query /TN mcp-ftp /FO LIST
```

The MCP tools become available in Claude Code once the scheduled task is running.

---

## Exchange folder

Because the `mcpftp` service account cannot access your user profile, files for
upload/download are passed through a shared exchange folder:

| Path | Purpose |
|------|---------|
| `C:\ProgramData\mcp-ftp\exchange\` | Place files here before uploading; downloads land here |

Both `mcpftp` and your normal user account have read/write access to this folder.

---

## Available tools

| Tool | Description |
|------|-------------|
| `list_servers` | List all configured server names |
| `list_directory` | List files and folders in a directory on a server |
| `upload_file` | Upload a file from the exchange folder to the FTP server |
| `download_file` | Download a file from the FTP server into the exchange folder |
| `delete_file` | Delete a file on the FTP server |
| `rename_file` | Rename or move a file on the FTP server |
| `make_directory` | Create a directory on the FTP server |
| `get_permissions` | Show the permissions (chmod) of a file or directory |
| `set_permissions` | Set the permissions (chmod) of a file or directory |

---

## Security check

In a **normal (non-elevated)** PowerShell:

```powershell
Get-Content C:\ProgramData\mcp-ftp\ftp_config.ini
```

Expected result: `Access to the path ... is denied.`
If the file is readable: the NTFS permissions are wrong — re-run the setup script.

---

## One-liner for a new Windows machine

Paste this into Claude Code:

```
Install the MCP FTP server (Windows) from https://github.com/ipod86/mcp-ftp-win:
clone the repo to %USERPROFILE%\mcp-ftp-win, then run:
  claude mcp add --transport sse ftp-win http://127.0.0.1:8765/sse
After that, run windows_admin_setup.ps1 as Administrator (outside Claude Code).
Do NOT fill in or read the credentials file — the user does that manually.
```

---

## License

MIT (c) 2026 ipod86
