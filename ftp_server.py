#!/usr/bin/env python3
"""MCP server providing FTP access for Claude Code — Windows edition.

Config:   C:\\ProgramData\\mcp-ftp\\ftp_config.ini  (owned by mcpftp, not readable by normal users)
Exchange: C:\\ProgramData\\mcp-ftp\\exchange         (read/write for mcpftp and normal users)

Downloads land in the exchange folder.
Files to upload must be placed in the exchange folder first.
"""

import configparser
import ftplib
import os
from pathlib import Path, PureWindowsPath

from mcp.server.fastmcp import FastMCP

CONFIG_PATH  = Path(r"C:\ProgramData\mcp-ftp\ftp_config.ini")
EXCHANGE_DIR = Path(r"C:\ProgramData\mcp-ftp\exchange")

mcp = FastMCP("ftp-win", host="127.0.0.1", port=8765)


def _load_config() -> configparser.ConfigParser:
    cfg = configparser.ConfigParser()
    if not CONFIG_PATH.exists():
        raise FileNotFoundError(
            f"Config file not found: {CONFIG_PATH}\n"
            "Run windows_admin_setup.ps1 as Administrator, then fill in credentials:\n"
            f"  Start Notepad as Administrator and open {CONFIG_PATH}"
        )
    cfg.read(CONFIG_PATH)
    return cfg


def _safe_error(msg: str, cfg: configparser.SectionProxy) -> str:
    """Strip any credential values from an error message before returning it."""
    for key in ("password", "username", "host"):
        val = cfg.get(key, "")
        if val:
            msg = msg.replace(val, f"<{key}>")
    return msg


def _connect(server_name: str) -> tuple[ftplib.FTP, configparser.SectionProxy]:
    cfg = _load_config()
    if server_name not in cfg:
        available = cfg.sections()
        raise ValueError(f"Server '{server_name}' not found. Available: {available}")
    s = cfg[server_name]
    host = s["host"]
    port = int(s.get("port", 21))
    try:
        ftp = ftplib.FTP()
        ftp.connect(host, port, timeout=10)
    except Exception as e:
        raise ConnectionError(
            f"Cannot reach '{server_name}' ({host}:{port}): {_safe_error(str(e), s)}"
        ) from None
    try:
        ftp.login(s["username"], s["password"])
    except ftplib.error_perm as e:
        ftp.close()
        raise PermissionError(
            f"Login to '{server_name}' ({host}:{port}) failed — "
            f"check username/password in {CONFIG_PATH}\n"
            f"Server response: {_safe_error(str(e), s)}"
        ) from None
    return ftp, s


def _resolve_exchange(local_path: str) -> Path:
    """Resolve a user-supplied path to a location inside EXCHANGE_DIR.

    - Empty or relative path  -> placed under EXCHANGE_DIR
    - Absolute path inside EXCHANGE_DIR -> allowed
    - Absolute path outside EXCHANGE_DIR -> rejected
    """
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
            f"Path must be inside the exchange folder ({EXCHANGE_DIR}). "
            f"Got: {local_path}"
        )


@mcp.tool()
def list_servers() -> list[str]:
    """List all configured FTP server names."""
    cfg = _load_config()
    return cfg.sections()


@mcp.tool()
def list_directory(server_name: str, path: str = "/") -> list[str]:
    """List files and folders in a directory on the FTP server.

    Args:
        server_name: Name of the server as defined in the config
        path: Remote directory path (default: /)
    """
    ftp, _ = _connect(server_name)
    try:
        lines: list[str] = []
        ftp.retrlines(f"LIST {path}", lines.append)
        return lines
    finally:
        ftp.quit()


@mcp.tool()
def upload_file(server_name: str, remote_path: str, local_filename: str = "") -> str:
    """Upload a file from the exchange folder to the FTP server.

    The file to upload must be placed in C:\\ProgramData\\mcp-ftp\\exchange first,
    because the service account (mcpftp) cannot access your user profile.

    Args:
        server_name:    Name of the server as defined in the config
        remote_path:    Destination path on the FTP server (e.g. /htdocs/file.txt)
        local_filename: File name (or relative sub-path) inside the exchange folder.
                        If empty, the basename of remote_path is used.
    """
    src = _resolve_exchange(local_filename)
    if src.is_dir():
        src = src / Path(remote_path).name
    if not src.is_file():
        raise FileNotFoundError(
            f"File not found in exchange folder: {src}\n"
            f"Copy the file to {EXCHANGE_DIR} first."
        )
    ftp, _ = _connect(server_name)
    try:
        with src.open("rb") as f:
            ftp.storbinary(f"STOR {remote_path}", f)
        return f"Uploaded {src} -> {remote_path}"
    finally:
        ftp.quit()


@mcp.tool()
def download_file(server_name: str, remote_path: str, local_path: str = "") -> str:
    """Download a file from the FTP server into the exchange folder.

    Downloaded files land in C:\\ProgramData\\mcp-ftp\\exchange and can be
    read from there by your normal user account.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file on the FTP server
        local_path:  Destination. If relative or empty, resolved inside the exchange
                     folder. Absolute paths outside the exchange folder are rejected.
    """
    base = _resolve_exchange(local_path)
    if base.is_dir() or not local_path:
        dest = base / Path(remote_path).name
    else:
        dest = base
    dest.parent.mkdir(parents=True, exist_ok=True)
    ftp, _ = _connect(server_name)
    try:
        with dest.open("wb") as f:
            ftp.retrbinary(f"RETR {remote_path}", f.write)
        return f"Downloaded {remote_path} -> {dest}"
    finally:
        ftp.quit()


@mcp.tool()
def delete_file(server_name: str, remote_path: str) -> str:
    """Delete a file on the FTP server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file to delete on the FTP server
    """
    ftp, _ = _connect(server_name)
    try:
        ftp.delete(remote_path)
        return f"Deleted {remote_path}"
    finally:
        ftp.quit()


@mcp.tool()
def rename_file(server_name: str, from_path: str, to_path: str) -> str:
    """Rename or move a file on the FTP server.

    Args:
        server_name: Name of the server as defined in the config
        from_path:   Current path of the file on the FTP server
        to_path:     New path / name on the FTP server
    """
    ftp, _ = _connect(server_name)
    try:
        ftp.rename(from_path, to_path)
        return f"Renamed {from_path} -> {to_path}"
    finally:
        ftp.quit()


@mcp.tool()
def make_directory(server_name: str, remote_path: str) -> str:
    """Create a directory on the FTP server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the directory to create
    """
    ftp, _ = _connect(server_name)
    try:
        ftp.mkd(remote_path)
        return f"Created directory {remote_path}"
    finally:
        ftp.quit()


@mcp.tool()
def get_permissions(server_name: str, remote_path: str) -> str:
    """Show the permissions (chmod) of a file or directory on the FTP server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file or directory
    """
    ftp, _ = _connect(server_name)
    try:
        lines: list[str] = []
        parent = remote_path.rsplit("/", 1)[0] or "/"
        name = remote_path.rsplit("/", 1)[-1]
        ftp.retrlines(f"LIST {parent}", lines.append)
        for line in lines:
            if line.split()[-1] == name:
                return line
        return "\n".join(lines) if lines else "Not found"
    finally:
        ftp.quit()


@mcp.tool()
def set_permissions(server_name: str, remote_path: str, mode: str) -> str:
    """Set the permissions (chmod) of a file or directory on the FTP server.

    Args:
        server_name: Name of the server as defined in the config
        remote_path: Path of the file or directory
        mode:        Permission mode as octal string, e.g. '755' or '644'
    """
    ftp, _ = _connect(server_name)
    try:
        ftp.sendcmd(f"SITE CHMOD {mode} {remote_path}")
        return f"Set permissions {mode} on {remote_path}"
    finally:
        ftp.quit()


if __name__ == "__main__":
    mcp.run(transport="sse")
