#!/usr/bin/env python3
"""Sync lobby.lua + restart Nakama on VPS. Usage: python deploy/_vps_sync.py <password>"""
import sys
from pathlib import Path
import paramiko

HOST = "185.194.218.27"
USER = "root"
LOCAL_LOBBY = Path(__file__).resolve().parent / "nakama" / "modules" / "lobby.lua"
REMOTE_LOBBY = "/root/deploy/nakama/modules/lobby.lua"


def main() -> None:
	if len(sys.argv) < 2:
		print("Usage: python deploy/_vps_sync.py <ssh_password>")
		sys.exit(1)
	password = sys.argv[1]
	c = paramiko.SSHClient()
	c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
	c.connect(HOST, username=USER, password=password, timeout=25)
	sftp = c.open_sftp()
	sftp.put(str(LOCAL_LOBBY), REMOTE_LOBBY)
	sftp.close()
	print("Uploaded", LOCAL_LOBBY.name)
	_, stdout, stderr = c.exec_command("cd /root/deploy && docker compose restart nakama")
	print(stdout.read().decode())
	err = stderr.read().decode()
	if err:
		print(err)
	c.close()
	print("Done — Nakama restarted.")


if __name__ == "__main__":
	main()
