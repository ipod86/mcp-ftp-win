#!/usr/bin/env python3
"""MCP server providing FTP / FTPS / SFTP access for Claude Code — Windows edition.

Config:   C:\\ProgramData\\mcp-ftp\\ftp_config.ini
Exchange: C:\\ProgramData\\mcp-ftp\\exchange

Each server block supports an optional  type = ftp | ftps | sftp  field (default: ftp).
"""

import configparser
import fnmatch
import ftplib
import io
import stat
from pathlib import Path

from mcp.server.fastmcp import FastMCP

try:
    import paramiko
    _PARAMIKO = True
except ImportError:
    _PARAMIKO = False

CONFIG_PATH  = Path(r"C:\ProgramData\mcp-ftp\ftp_config.ini")
EXCHANGE_DIR = Path(r"C:\ProgramData\mcp-ftp\exchange")

mcp = FastMCP("ftp-win", host="127.0.0.1", port=8765)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def _load_config() -> configparser.ConfigParser:
    cfg = configparser.ConfigParser()
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(
            f"Config not found: {CONFIG_PATH}\n"
            "Run windows_admin_setup.ps1 as Administrator, then add credentials."
        )
    cfg.read(CONFIG_PATH)
    return cfg


def _scrub(msg: str, s: configparser.SectionProxy) -> str:
    for key in ("password", "username", "host"):
        val = s.get(key, "")
        if val:
            msg = msg.replace(val, f"<{key}>")
    return msg


# ---------------------------------------------------------------------------
# Unified connection wrapper (FTP / FTPS / SFTP)
# ---------------------------------------------------------------------------

class Connection:
    def __init__(self, *, ftp=None, sftp=None, ssh=None, s: configparser.SectionProxy):
        self._ftp  = ftp
        self._sftp = sftp
        self._ssh  = ssh
        self._s    = s

    @property
    def is_sftp(self) -> bool:
        return self._sftp is not None

    def close(self):
        for obj, method in [(self._sftp, "close"), (self._ssh, "close"), (self._ftp, "quit")]:
            if obj:
                try: getattr(obj, method)()
                except Exception: pass

    def __enter__(self): return self
    def __exit__(self, *_): self.close()

    # ---- listing ----

    def list_dir(self, path: str) -> list[str]:
        if self.is_sftp:
            lines = []
            for a in self._sftp.listdir_attr(path):
                mode = stat.filemode(a.st_mode) if a.st_mode else "----------"
                lines.append(f"{mode} {a.st_size:>12}  {a.filename}")
            return lines
        lines: list[str] = []
        self._ftp.retrlines(f"LIST {path}", lines.append)
        return lines

    def _entries(self, path: str) -> list[tuple[str, bool]]:
        """[(name, is_dir), ...] for immediate children of path (. and .. excluded)."""
        if self.is_sftp:
            return [
                (a.filename, stat.S_ISDIR(a.st_mode))
                for a in self._sftp.listdir_attr(path)
                if a.st_mode is not None and a.filename not in (".", "..")
            ]
        lines: list[str] = []
        self._ftp.retrlines(f"LIST {path}", lines.append)
        result = []
        for line in lines:
            parts = line.split(None, 8)
            if len(parts) >= 9 and parts[8] not in (".", ".."):
                result.append((parts[8], line[0] == "d"))
        return result

    def _walk(self, path: str):
        """Yield all file paths recursively under path."""
        for name, is_dir in self._entries(path):
            full = f"{path.rstrip('/')}/{name}"
            if is_dir:
                yield from self._walk(full)
            else:
                yield full

    # ---- transfer ----

    def upload(self, local: Path, remote: str):
        if self.is_sftp:
            self._sftp.put(str(local), remote)
        else:
            with local.open("rb") as f:
                self._ftp.storbinary(f"STOR {remote}", f)

    def download(self, remote: str, local: Path):
        local.parent.mkdir(parents=True, exist_ok=True)
        if self.is_sftp:
            self._sftp.get(remote, str(local))
        else:
            with local.open("wb") as f:
                self._ftp.retrbinary(f"RETR {remote}", f.write)

    def read_text(self, remote: str, max_bytes: int) -> str:
        buf = io.BytesIO()
        if self.is_sftp:
            with self._sftp.open(remote, "rb") as f:
                buf.write(f.read(max_bytes))
        else:
            def _collect(chunk):
                remaining = max_bytes - buf.tell()
                if remaining > 0:
                    buf.write(chunk[:remaining])
            self._ftp.retrbinary(f"RETR {remote}", _collect, blocksize=8192)
        return buf.getvalue().decode("utf-8", errors="replace")

    def write_text(self, remote: str, content: str):
        data = content.encode("utf-8")
        if self.is_sftp:
            with self._sftp.open(remote, "wb") as f:
                f.write(data)
        else:
            self._ftp.storbinary(f"STOR {remote}", io.BytesIO(data))

    def copy_internal(self, src: str, dst: str):
        """Copy a file within the same server (download to memory, re-upload)."""
        buf = io.BytesIO()
        if self.is_sftp:
            with self._sftp.open(src, "rb") as f:
                buf.write(f.read())
            buf.seek(0)
            with self._sftp.open(dst, "wb") as f:
                f.write(buf.read())
        else:
            self._ftp.retrbinary(f"RETR {src}", buf.write)
            buf.seek(0)
            self._ftp.storbinary(f"STOR {dst}", buf)

    def file_size(self, path: str) -> int:
        """Return file size in bytes, or -1 if not available."""
        if self.is_sftp:
            try: return self._sftp.stat(path).st_size or -1
            except Exception: return -1
        try: return self._ftp.size(path) or -1
        except Exception: return -1

    # ---- file/dir operations ----

    def delete_file(self, path: str):
        if self.is_sftp: self._sftp.remove(path)
        else: self._ftp.delete(path)

    def rename(self, src: str, dst: str):
        if self.is_sftp: self._sftp.rename(src, dst)
        else: self._ftp.rename(src, dst)

    def mkdir(self, path: str):
        if self.is_sftp: self._sftp.mkdir(path)
        else: self._ftp.mkd(path)

    def rmdir(self, path: str):
        if self.is_sftp: self._sftp.rmdir(path)
        else: self._ftp.rmd(path)

    def chmod(self, path: str, mode: str):
        if self.is_sftp: self._sftp.chmod(path, int(mode, 8))
        else: self._ftp.sendcmd(f"SITE CHMOD {mode} {path}")

    # ---- metadata ----

    def get_info(self, path: str) -> dict:
        if self.is_sftp:
            a = self._sftp.stat(path)
            return {
                "size":        a.st_size,
                "modified":    str(a.st_mtime),
                "permissions": stat.filemode(a.st_mode) if a.st_mode else "unknown",
            }
        info: dict = {}
        try: info["size"] = self._ftp.size(path)
        except Exception: info["size"] = "unknown"
        try:
            ts = self._ftp.sendcmd(f"MDTM {path}")[4:].strip()
            info["modified"] = f"{ts[:4]}-{ts[4:6]}-{ts[6:8]} {ts[8:10]}:{ts[10:12]}:{ts[12:14]}"
        except Exception: info["modified"] = "unknown"
        parent = path.rsplit("/", 1)[0] or "/"
        name   = path.rsplit("/", 1)[-1]
        lines: list[str] = []
        self._ftp.retrlines(f"LIST {parent}", lines.append)
        for line in lines:
            if line.split()[-1] == name:
                info["permissions"] = line.split()[0]
                break
        return info

    def server_info(self) -> str:
        if self.is_sftp:
            transport = self._ssh.get_transport()
            return f"SFTP — remote version: {transport.remote_version}" if transport else "SFTP connected"
        parts = []
        try: parts.append(f"Welcome: {self._ftp.getwelcome()}")
        except Exception: pass
        try: parts.append(f"Features:\n{self._ftp.sendcmd('FEAT')}")
        except Exception: pass
        return "\n".join(parts) or "No server info available"


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

def _connect(server_name: str) -> Connection:
    cfg = _load_config()
    if server_name not in cfg:
        raise ValueError(f"Server '{server_name}' not found. Available: {cfg.sections()}")
    s = cfg[server_name]
    conn_type = s.get("type", "ftp").lower()
    host = s["host"]

    if conn_type == "sftp":
        if not _PARAMIKO:
            raise ImportError(
                "paramiko is required for SFTP connections.\n"
                r'Install: & "C:\Program Files\mcp-ftp\venv\Scripts\pip" install paramiko'
            )
        port = int(s.get("port", 22))
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(host, port=port, username=s["username"], password=s["password"], timeout=10)
            sftp = ssh.open_sftp()
        except Exception as e:
            raise ConnectionError(
                f"SFTP connection to '{server_name}' ({host}:{port}) failed: {_scrub(str(e), s)}"
            ) from None
        return Connection(sftp=sftp, ssh=ssh, s=s)

    if conn_type in ("ftp", "ftps"):
        port = int(s.get("port", 21))
        try:
            ftp = ftplib.FTP_TLS() if conn_type == "ftps" else ftplib.FTP()
            ftp.connect(host, port, timeout=10)
        except Exception as e:
            raise ConnectionError(
                f"Cannot reach '{server_name}' ({host}:{port}): {_scrub(str(e), s)}"
            ) from None
        try:
            ftp.login(s["username"], s["password"])
            if conn_type == "ftps":
                ftp.prot_p()
        except ftplib.error_perm as e:
            ftp.close()
            raise PermissionError(
                f"Login to '{server_name}' failed — check username/password.\n"
                f"Server response: {_scrub(str(e), s)}"
            ) from None
        return Connection(ftp=ftp, s=s)

    raise ValueError(f"Unknown connection type '{conn_type}'. Use: ftp, ftps, sftp")


# ---------------------------------------------------------------------------
# Exchange path helper
# ---------------------------------------------------------------------------

def _resolve_exchange(local_path: str) -> Path:
    if not local_path:
        return EXCHANGE_DIR
    p = Path(local_path)
    if not p.is_absolute():
        return EXCHANGE_DIR / p
    try:
        p.relative_to(EXCHANGE_DIR)
        return p
    except ValueError:
        raise ValueError(
            f"Path must be inside the exchange folder ({EXCHANGE_DIR}). Got: {local_path}"
        )


# ---------------------------------------------------------------------------
# MCP tools
# ---------------------------------------------------------------------------

@mcp.tool()
def list_servers() -> list[str]:
    """List all configured server names (FTP / FTPS / SFTP)."""
    return _load_config().sections()


@mcp.tool()
def test_connection(server_name: str) -> str:
    """Test whether a server is reachable and the credentials are correct.

    Args:
        server_name: Name of the server as defined in the config
    """
    with _connect(server_name):
        pass
    cfg = _load_config()
    conn_type = cfg[server_name].get("type", "ftp").upper()
    return f"OK — {conn_type} connection to '{server_name}' succeeded."


@mcp.tool()
def get_server_info(server_name: str) -> str:
    """Return server banner, welcome message and supported features.

    Args:
        server_name: Name of the server as defined in the config
    """
    with _connect(server_name) as conn:
        return conn.server_info()


@mcp.tool()
def list_directory(server_name: str, path: str = "/") -> list[str]:
    """List files and folders in a directory on the server.

    Args:
        server_name: Name of the server as defined in the config
        path:        Remote directory path (default: /)
    """
    with _connect(server_name) as conn:
        return conn.list_dir(path)


@mcp.tool()
def get_file_info(server_name: str, remote_path: str) -> dict:
    """Return size, modification time and permissions of a remote file.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file on the server
    """
    with _connect(server_name) as conn:
        return conn.get_info(remote_path)


@mcp.tool()
def get_directory_size(server_name: str, remote_path: str) -> dict:
    """Calculate the total size of all files in a directory (recursive).

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Remote directory path
    """
    with _connect(server_name) as conn:
        total = 0
        count = 0
        for file_path in conn._walk(remote_path):
            size = conn.file_size(file_path)
            if size >= 0:
                total += size
            count += 1
        return {"files": count, "total_bytes": total, "total_human": _human_size(total)}


@mcp.tool()
def list_large_files(server_name: str, remote_path: str, min_size_kb: int = 1024) -> list[dict]:
    """Find files larger than a given size threshold (sorted by size, largest first).

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Directory to search in (recursive)
        min_size_kb: Minimum file size in kilobytes (default: 1024 = 1 MB)
    """
    min_bytes = min_size_kb * 1024
    results = []
    with _connect(server_name) as conn:
        for file_path in conn._walk(remote_path):
            size = conn.file_size(file_path)
            if size >= min_bytes:
                results.append({"path": file_path, "size_bytes": size, "size_human": _human_size(size)})
    results.sort(key=lambda x: x["size_bytes"], reverse=True)
    return results


@mcp.tool()
def upload_file(server_name: str, remote_path: str, local_filename: str = "") -> str:
    """Upload a file from the exchange folder to the server.

    Place the file in C:\\ProgramData\\mcp-ftp\\exchange first (the service
    account cannot access your user profile).

    Args:
        server_name:    Name of the server as defined in the config
        remote_path:    Destination path on the server
        local_filename: File name or relative sub-path inside the exchange folder.
                        Defaults to the basename of remote_path.
    """
    src = _resolve_exchange(local_filename)
    if src.is_dir():
        src = src / Path(remote_path).name
    if not src.is_file():
        raise FileNotFoundError(
            f"File not found in exchange folder: {src}\nCopy it to {EXCHANGE_DIR} first."
        )
    with _connect(server_name) as conn:
        conn.upload(src, remote_path)
    return f"Uploaded {src} -> {remote_path}"


@mcp.tool()
def download_file(server_name: str, remote_path: str, local_path: str = "") -> str:
    """Download a file from the server into the exchange folder.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file on the server
        local_path:  Destination inside the exchange folder (relative or empty).
                     Absolute paths outside the exchange folder are rejected.
    """
    base = _resolve_exchange(local_path)
    dest = base / Path(remote_path).name if (base.is_dir() or not local_path) else base
    with _connect(server_name) as conn:
        conn.download(remote_path, dest)
    return f"Downloaded {remote_path} -> {dest}"


@mcp.tool()
def upload_directory(server_name: str, remote_path: str, local_dir: str = "") -> str:
    """Recursively upload a folder from the exchange directory to the server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Destination directory on the server
        local_dir:   Sub-folder inside the exchange folder to upload.
                     Defaults to the exchange folder root.
    """
    local_base = _resolve_exchange(local_dir)
    if not local_base.is_dir():
        raise NotADirectoryError(f"Not a directory in exchange folder: {local_base}")
    with _connect(server_name) as conn:
        uploaded = []
        for local_file in sorted(local_base.rglob("*")):
            relative = local_file.relative_to(local_base).as_posix()
            remote = f"{remote_path.rstrip('/')}/{relative}"
            if local_file.is_dir():
                try: conn.mkdir(remote)
                except Exception: pass
            elif local_file.is_file():
                conn.upload(local_file, remote)
                uploaded.append(remote)
    return f"Uploaded {len(uploaded)} file(s) to {remote_path}"


@mcp.tool()
def download_directory(server_name: str, remote_path: str, local_dir: str = "") -> str:
    """Recursively download a remote directory into the exchange folder.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Directory to download on the server
        local_dir:   Sub-folder inside the exchange folder to download into.
                     Defaults to a folder named after the remote directory.
    """
    if not local_dir:
        local_dir = remote_path.rstrip("/").rsplit("/", 1)[-1]
    local_base = _resolve_exchange(local_dir)
    with _connect(server_name) as conn:
        downloaded = []
        remote_base = remote_path.rstrip("/")
        for remote_file in conn._walk(remote_base):
            relative = remote_file[len(remote_base):].lstrip("/")
            local_file = local_base / relative
            conn.download(remote_file, local_file)
            downloaded.append(str(local_file))
    return f"Downloaded {len(downloaded)} file(s) to {local_base}"


@mcp.tool()
def sync_directory(server_name: str, remote_path: str, local_dir: str = "") -> str:
    """Upload only new or changed files from the exchange folder to the server (size-based).

    Skips files where the remote already exists with the same size.
    Files present only on the server are left untouched.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Destination directory on the server
        local_dir:   Sub-folder inside the exchange folder to sync from.
                     Defaults to the exchange folder root.
    """
    local_base = _resolve_exchange(local_dir)
    if not local_base.is_dir():
        raise NotADirectoryError(f"Not a directory in exchange folder: {local_base}")
    with _connect(server_name) as conn:
        uploaded = skipped = 0
        for local_file in sorted(local_base.rglob("*")):
            if not local_file.is_file():
                continue
            relative = local_file.relative_to(local_base).as_posix()
            remote = f"{remote_path.rstrip('/')}/{relative}"
            if conn.file_size(remote) == local_file.stat().st_size:
                skipped += 1
                continue
            parent = remote.rsplit("/", 1)[0]
            try: conn.mkdir(parent)
            except Exception: pass
            conn.upload(local_file, remote)
            uploaded += 1
    return f"Synced {local_base} -> {remote_path}: {uploaded} uploaded, {skipped} unchanged"


@mcp.tool()
def find_files(server_name: str, remote_path: str, pattern: str = "*") -> list[str]:
    """Recursively search for files matching a name pattern on the server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Directory to search in
        pattern:     fnmatch pattern, e.g. '*.log', 'backup_*', '*.php' (default: *)
    """
    with _connect(server_name) as conn:
        return [
            p for p in conn._walk(remote_path)
            if fnmatch.fnmatch(p.rsplit("/", 1)[-1], pattern)
        ]


@mcp.tool()
def search_file_content(server_name: str, remote_path: str, search_text: str,
                        file_pattern: str = "*", max_results: int = 50,
                        max_file_kb: int = 512) -> list[dict]:
    """Search for text within files on the server (grep-like).

    Returns a list of matches, each with file path, line number, and line content.

    Args:
        server_name:  Name of the server as defined in the config
        remote_path:  Directory to search in (recursive)
        search_text:  Text to search for (case-sensitive)
        file_pattern: Only search files matching this fnmatch pattern (default: *)
        max_results:  Stop after this many matches (default: 50)
        max_file_kb:  Maximum kilobytes to read per file (default: 512)
    """
    results: list[dict] = []
    with _connect(server_name) as conn:
        for file_path in conn._walk(remote_path):
            if len(results) >= max_results:
                break
            if not fnmatch.fnmatch(file_path.rsplit("/", 1)[-1], file_pattern):
                continue
            try:
                content = conn.read_text(file_path, max_file_kb * 1024)
                for i, line in enumerate(content.splitlines(), 1):
                    if search_text in line:
                        results.append({"file": file_path, "line": i, "content": line.strip()})
                        if len(results) >= max_results:
                            break
            except Exception:
                continue
    return results


@mcp.tool()
def read_text_file(server_name: str, remote_path: str, max_kb: int = 64) -> str:
    """Read a text file from the server and return its content as a string.

    Useful for config files, logs, or small source files without downloading them.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file on the server
        max_kb:      Maximum number of kilobytes to read (default: 64)
    """
    with _connect(server_name) as conn:
        return conn.read_text(remote_path, max_kb * 1024)


@mcp.tool()
def write_text_file(server_name: str, remote_path: str, content: str) -> str:
    """Write text content directly to a file on the server (creates or overwrites).

    No exchange folder needed — content is passed as a string directly.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Destination path on the server
        content:     Text content to write (UTF-8)
    """
    with _connect(server_name) as conn:
        conn.write_text(remote_path, content)
    return f"Written {len(content.encode('utf-8'))} bytes to {remote_path}"


@mcp.tool()
def copy_file(server_name: str, from_path: str, to_path: str) -> str:
    """Copy a file to a new location on the same server.

    The file is buffered in memory and re-uploaded — no exchange folder needed.

    Args:
        server_name: Name of the server as defined in the config
        from_path:   Source file path on the server
        to_path:     Destination path on the server
    """
    with _connect(server_name) as conn:
        conn.copy_internal(from_path, to_path)
    return f"Copied {from_path} -> {to_path}"


@mcp.tool()
def bulk_delete(server_name: str, remote_path: str, pattern: str) -> str:
    """Delete all files matching a name pattern in a directory (recursive).

    Only files are deleted — directories are never removed.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Directory to search in (recursive)
        pattern:     fnmatch pattern, e.g. '*.log', 'tmp_*'
    """
    with _connect(server_name) as conn:
        to_delete = [
            p for p in conn._walk(remote_path)
            if fnmatch.fnmatch(p.rsplit("/", 1)[-1], pattern)
        ]
        for path in to_delete:
            conn.delete_file(path)
    return f"Deleted {len(to_delete)} file(s) matching '{pattern}' in {remote_path}"


@mcp.tool()
def delete_file(server_name: str, remote_path: str) -> str:
    """Delete a file on the server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file to delete
    """
    with _connect(server_name) as conn:
        conn.delete_file(remote_path)
    return f"Deleted {remote_path}"


@mcp.tool()
def remove_directory(server_name: str, remote_path: str) -> str:
    """Remove an empty directory on the server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the directory to remove (must be empty)
    """
    with _connect(server_name) as conn:
        conn.rmdir(remote_path)
    return f"Removed directory {remote_path}"


@mcp.tool()
def rename_file(server_name: str, from_path: str, to_path: str) -> str:
    """Rename or move a file on the server.

    Args:
        server_name: Name of the server as defined in the config
        from_path:   Current path of the file
        to_path:     New path / name
    """
    with _connect(server_name) as conn:
        conn.rename(from_path, to_path)
    return f"Renamed {from_path} -> {to_path}"


@mcp.tool()
def make_directory(server_name: str, remote_path: str) -> str:
    """Create a directory on the server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the directory to create
    """
    with _connect(server_name) as conn:
        conn.mkdir(remote_path)
    return f"Created directory {remote_path}"


@mcp.tool()
def get_permissions(server_name: str, remote_path: str) -> str:
    """Show the permissions of a file or directory on the server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file or directory
    """
    with _connect(server_name) as conn:
        return conn.get_info(remote_path).get("permissions", "unknown")


@mcp.tool()
def set_permissions(server_name: str, remote_path: str, mode: str) -> str:
    """Set the permissions (chmod) of a file or directory on the server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file or directory
        mode:        Octal permission string, e.g. '755' or '644'
    """
    with _connect(server_name) as conn:
        conn.chmod(remote_path, mode)
    return f"Set permissions {mode} on {remote_path}"


if __name__ == "__main__":
    mcp.run(transport="sse")
