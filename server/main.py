"""
Serveur relais WebSocket pour PartyGame.
Tous les joueurs (hôte inclus) se connectent ici — aucun port forwarding requis.

Déploiement gratuit :
  Railway  : https://railway.app  (import ce dossier, buildpack Python)
  Render   : https://render.com   (Web Service, build: pip install -r requirements.txt)
  Fly.io   : https://fly.io

Variables d'environnement :
  PORT  — port d'écoute (défaut : 8765)

Protocole :
  Premier message (JSON texte) :
    {"action": "create", "code": "1234"}  ← hôte crée le lobby
    {"action": "join",   "code": "1234"}  ← client rejoint

  Réponses serveur (JSON texte) :
    {"type": "id",               "id": N}      ← pair ID assigné (hôte = 1)
    {"type": "peer_connected",   "id": N}      ← nouveau joueur (envoyé à l'hôte)
    {"type": "peer_disconnected","id": N}      ← joueur parti
    {"type": "error",            "msg": "..."}

  Paquets de jeu (binaire) :
    [4 octets big-endian int32 : peer_id cible (0 = broadcast)] [payload]
    Le relais préfixe chaque paquet reçu avec [4 octets : peer_id source].
"""

import asyncio
import json
import os
import struct
import websockets
from websockets.server import WebSocketServerProtocol

# code -> {"clients": {peer_id: ws}, "next_id": int}
lobbies: dict = {}


async def handler(ws: WebSocketServerProtocol) -> None:
    lobby_code: str | None = None
    peer_id: int | None = None

    try:
        # ── Handshake ────────────────────────────────────────────────────────
        raw = await asyncio.wait_for(ws.recv(), timeout=15.0)
        msg = json.loads(raw)
        action = msg.get("action", "")
        code = str(msg.get("code", "")).strip()

        if action == "create":
            lobby_code = code
            lobbies[code] = {"clients": {1: ws}, "next_id": 2}
            peer_id = 1
            await ws.send(json.dumps({"type": "id", "id": 1}))
            print(f"[relais] Lobby créé : {code}")

        elif action == "join":
            lobby_code = code
            if code not in lobbies:
                await ws.send(json.dumps({"type": "error", "msg": "lobby_not_found"}))
                return
            lobby = lobbies[code]
            peer_id = lobby["next_id"]
            lobby["next_id"] += 1
            lobby["clients"][peer_id] = ws
            await ws.send(json.dumps({"type": "id", "id": peer_id}))
            # Notifier UNIQUEMENT l'hôte du nouveau pair
            if 1 in lobby["clients"]:
                await lobby["clients"][1].send(
                    json.dumps({"type": "peer_connected", "id": peer_id})
                )
            print(f"[relais] Joueur {peer_id} a rejoint {code}")
        else:
            return

        # ── Routage des paquets ───────────────────────────────────────────────
        async for message in ws:
            lobby = lobbies.get(lobby_code)
            if not lobby:
                break
            clients = lobby["clients"]

            # — Messages JSON (lobby + signaux de jeu) —
            if isinstance(message, str):
                try:
                    msg = json.loads(message)
                    if msg.get("type") == "game":
                        target_id = int(msg.get("to", 0))
                        msg["from"] = peer_id
                        payload = json.dumps(msg)
                        if target_id == 0:
                            for pid, cws in list(clients.items()):
                                if pid != peer_id:
                                    try:
                                        await cws.send(payload)
                                    except Exception:
                                        pass
                        elif target_id in clients:
                            try:
                                await clients[target_id].send(payload)
                            except Exception:
                                pass
                except Exception:
                    pass
                continue

            # — Paquets binaires (données de jeu futures) —            if not isinstance(message, bytes) or len(message) < 4:
                continue

            target_id = struct.unpack(">i", message[:4])[0]
            payload = struct.pack(">i", peer_id) + message[4:]

            clients = lobby["clients"]
            if target_id == 0:
                # Broadcast : envoyer à tous sauf l'expéditeur
                for pid, cws in list(clients.items()):
                    if pid != peer_id:
                        try:
                            await cws.send(payload)
                        except Exception:
                            pass
            elif target_id < 0:
                # Broadcast excluant abs(target_id)
                exclude = abs(target_id)
                for pid, cws in list(clients.items()):
                    if pid != peer_id and pid != exclude:
                        try:
                            await cws.send(payload)
                        except Exception:
                            pass
            elif target_id in clients:
                try:
                    await clients[target_id].send(payload)
                except Exception:
                    pass

    except (asyncio.TimeoutError, json.JSONDecodeError):
        pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        # ── Nettoyage ─────────────────────────────────────────────────────────
        if lobby_code and lobby_code in lobbies and peer_id is not None:
            lobby = lobbies[lobby_code]
            lobby["clients"].pop(peer_id, None)

            disc_msg = json.dumps({"type": "peer_disconnected", "id": peer_id})

            if peer_id == 1:
                # L'hôte s'est déconnecté → fermer le lobby, notifier tous les clients
                for cws in list(lobby["clients"].values()):
                    try:
                        await cws.send(disc_msg)
                    except Exception:
                        pass
                del lobbies[lobby_code]
                print(f"[relais] Lobby {lobby_code} fermé (hôte parti)")
            else:
                # Un client s'est déconnecté → notifier l'hôte
                if 1 in lobby["clients"]:
                    try:
                        await lobby["clients"][1].send(disc_msg)
                    except Exception:
                        pass
                if not lobby["clients"]:
                    del lobbies[lobby_code]


async def main() -> None:
    port = int(os.environ.get("PORT", 8765))
    async with websockets.serve(handler, "0.0.0.0", port):
        print(f"[relais] Serveur démarré sur le port {port}")
        await asyncio.Future()  # tourne indéfiniment


if __name__ == "__main__":
    asyncio.run(main())
