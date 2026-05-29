#!/usr/bin/env python3
"""Déploie les exports Godot (Linux serveur + Web) sur le VPS.

Prérequis : exporter depuis Godot (presets Linux + Web), puis :

  set PQ_SSH_PASSWORD=ton_mot_de_passe
  python deploy/push_exports.py

Variables optionnelles : PQ_SSH_HOST, PQ_SSH_USER, PQ_WEB_ROOT
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

try:
    import paramiko
except ImportError:
    print("pip install paramiko")
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
LINUX_BIN = ROOT / "export" / "linux" / "power_quest_server.x86_64"
WEB_DIR = ROOT / "export" / "web"
BRIDGE_SRC = Path(__file__).resolve().parent / "web" / "pq_bridge.js"
BRIDGE_TAG = '<script src="pq_bridge.js"></script>'
REMOTE_DEPLOY = "/root/deploy"
REMOTE_WEB = os.environ.get("PQ_WEB_ROOT", "/var/www/html")

HOST = os.environ.get("PQ_SSH_HOST", "185.194.218.27")
USER = os.environ.get("PQ_SSH_USER", "root")
PASSWORD = os.environ.get("PQ_SSH_PASSWORD", "")


def _prepare_web_export() -> None:
    """Copie pq_bridge.js et patche index.html (Godot écrase le HTML à chaque export)."""
    if not BRIDGE_SRC.is_file():
        print(f"Attention : {BRIDGE_SRC} introuvable")
        return
    dest_bridge = WEB_DIR / "pq_bridge.js"
    dest_bridge.write_bytes(BRIDGE_SRC.read_bytes())
    print("  pq_bridge.js → export/web/")

    index_html = WEB_DIR / "index.html"
    if not index_html.is_file():
        return
    text = index_html.read_text(encoding="utf-8")
    if BRIDGE_TAG in text:
        return
    needle = '<script src="index.js"></script>'
    if needle in text:
        text = text.replace(needle, BRIDGE_TAG + "\n\t\t" + needle, 1)
    else:
        text = text.replace("</head>", "\t\t" + BRIDGE_TAG + "\n\t</head>", 1)
    index_html.write_text(text, encoding="utf-8")
    print("  index.html patché (pq_bridge.js avant index.js)")


def _sftp_put_dir(sftp: paramiko.SFTPClient, local: Path, remote: str) -> None:
    for item in local.iterdir():
        rpath = f"{remote}/{item.name}"
        if item.is_dir():
            try:
                sftp.mkdir(rpath)
            except OSError:
                pass
            _sftp_put_dir(sftp, item, rpath)
        else:
            print(f"  upload {item.name}")
            sftp.put(str(item), rpath)


def main() -> int:
    if not PASSWORD:
        print("Définir PQ_SSH_PASSWORD")
        return 1
    if not LINUX_BIN.is_file():
        print(f"Export Linux manquant : {LINUX_BIN}")
        return 1
    if not (WEB_DIR / "index.html").is_file():
        print(f"Export Web manquant : {WEB_DIR / 'index.html'}")
        return 1

    print("Préparation export Web…")
    _prepare_web_export()

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"Connexion {USER}@{HOST}…")
    client.connect(HOST, username=USER, password=PASSWORD, timeout=30)

    sftp = client.open_sftp()
    remote_bin = f"{REMOTE_DEPLOY}/power_quest_server.x86_64"
    print(f"Serveur → {remote_bin}")
    sftp.put(str(LINUX_BIN), remote_bin)
    client.exec_command(f"chmod 755 {remote_bin}")

    print(f"Web → {REMOTE_WEB}")
    _sftp_put_dir(sftp, WEB_DIR, REMOTE_WEB)
    sftp.close()

    print("systemctl restart powerquest-game")
    _, stdout, stderr = client.exec_command("systemctl restart powerquest-game && systemctl is-active powerquest-game")
    print(stdout.read().decode(), stderr.read().decode())
    client.close()
    print("Déploiement terminé.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
