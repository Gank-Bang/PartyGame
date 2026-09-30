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

Routes HTTP (GET, blind test) :
  /blindtest/tracks?count=N  → {"tracks": [{id, title, artist, preview}]}
  /blindtest/search?q=...    → {"results": [{id, title, artist}]}
"""

import asyncio
import json
import os
import random
import re
import struct
import unicodedata
import urllib.parse
import urllib.request
from http import HTTPStatus

import websockets
from websockets.asyncio.server import ServerConnection
from websockets.datastructures import Headers
from websockets.http11 import Request, Response

# code -> {"clients": {peer_id: ws}, "next_id": int}
lobbies: dict = {}
MAX_PLAYERS = 4

# ── Blind test : proxy vers l'API Deezer ──────────────────────────────────────
# L'API Deezer n'envoie pas d'en-tête CORS, la version web du jeu passe donc par
# ici. Les extraits MP3 (cdnt-preview.dzcdn.net) autorisent le CORS : les joueurs
# les téléchargent directement.

DEEZER_API = "https://api.deezer.com"
# Playlists publiques où l'hôte pioche : Top France + deux blind tests « tubes ».
BLINDTEST_PLAYLISTS = (1109890291, 7089916404, 9431716902)
BLINDTEST_MAX_TRACKS = 20
BLINDTEST_SEARCH_RESULTS = 8


def deezer_get(path: str, params: dict) -> dict:
    url = f"{DEEZER_API}{path}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=6) as resp:
        data = json.loads(resp.read())
    if "error" in data:
        raise RuntimeError(f"{path} : {data['error']}")
    return data


def track_summary(track: dict) -> dict:
    return {
        "id": track.get("id"),
        "title": track.get("title_short") or track.get("title", ""),
        "artist": track.get("artist", {}).get("name", "").replace(";", ", "),
    }


def title_key(title: str) -> str:
    """Clé de dédoublonnage : sans accents, versions « (...) » / « - Remastered » ni ponctuation."""
    short = re.sub(r"[(\[].*?[)\]]", "", title.split(" - ")[0])
    ascii_title = unicodedata.normalize("NFKD", short).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]", "", ascii_title.lower()) or title.lower()


def pick_blindtest_tracks(count: int) -> list:
    pool = {}
    for playlist_id in BLINDTEST_PLAYLISTS:
        try:
            tracks = deezer_get(f"/playlist/{playlist_id}/tracks", {"limit": 500}).get("data", [])
        except Exception as exc:
            print(f"[blindtest] Playlist {playlist_id} ignorée : {exc}")
            continue
        for track in tracks:
            if track.get("readable") and track.get("preview"):
                summary = track_summary(track)
                pool.setdefault(title_key(summary["title"]), {**summary, "preview": track["preview"]})
    if not pool:
        raise RuntimeError("aucun extrait disponible")
    return random.sample(list(pool.values()), min(count, len(pool)))


def search_tracks(query: str) -> list:
    results = {}
    for track in deezer_get("/search/track", {"q": query, "limit": 25}).get("data", []):
        summary = track_summary(track)
        results.setdefault((title_key(summary["title"]), summary["artist"].lower()), summary)
    return list(results.values())[:BLINDTEST_SEARCH_RESULTS]


def json_response(status: HTTPStatus, payload: dict) -> Response:
    body = json.dumps(payload).encode()
    headers = Headers()
    headers["Content-Type"] = "application/json; charset=utf-8"
    headers["Content-Length"] = str(len(body))
    headers["Access-Control-Allow-Origin"] = "*"
    headers["Cache-Control"] = "no-store"
    return Response(status.value, status.phrase, headers, body)


async def handle_http(connection: ServerConnection, request: Request):
    """Répond aux routes /blindtest/ ; renvoie None pour laisser passer le handshake WebSocket."""
    url = urllib.parse.urlsplit(request.path)
    if not url.path.startswith("/blindtest/"):
        return None
    params = urllib.parse.parse_qs(url.query)
    try:
        if url.path == "/blindtest/tracks":
            raw_count = params.get("count", ["10"])[0]
            count = int(raw_count) if raw_count.isdecimal() else 10
            count = min(max(count, 1), BLINDTEST_MAX_TRACKS)
            tracks = await asyncio.to_thread(pick_blindtest_tracks, count)
            return json_response(HTTPStatus.OK, {"tracks": tracks})
        if url.path == "/blindtest/search":
            query = params.get("q", [""])[0].strip()[:80]
            results = await asyncio.to_thread(search_tracks, query) if len(query) >= 2 else []
            return json_response(HTTPStatus.OK, {"results": results})
    except Exception as exc:
        print(f"[blindtest] Deezer indisponible : {exc}")
        return json_response(HTTPStatus.BAD_GATEWAY, {"error": "deezer_unavailable"})
    return json_response(HTTPStatus.NOT_FOUND, {"error": "not_found"})


async def fanout(clients: dict, payload, sender_id, exclude=None) -> None:
    """Diffuse en parallele : un client lent ne retarde plus les autres."""
    targets = [
        cws for pid, cws in clients.items()
        if pid != sender_id and pid != exclude
    ]
    if targets:
        await asyncio.gather(
            *(cws.send(payload) for cws in targets), return_exceptions=True
        )


async def send_one(clients: dict, target_id, payload) -> None:
    cws = clients.get(target_id)
    if cws is None:
        return
    try:
        await cws.send(payload)
    except Exception:
        pass


async def handler(ws: ServerConnection) -> None:
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

            if len(lobby["clients"]) >= MAX_PLAYERS:
                await ws.send(json.dumps({
                    "type": "error",
                    "msg": "lobby_full"
                }))
                await ws.close()
                return
            
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
                            await fanout(clients, payload, peer_id)
                        else:
                            await send_one(clients, target_id, payload)
                except Exception:
                    pass
                continue

            # — Paquets binaires (données de jeu futures) —
            if not isinstance(message, bytes) or len(message) < 4:
                continue

            target_id = struct.unpack(">i", message[:4])[0]
            payload = struct.pack(">i", peer_id) + message[4:]

            if target_id == 0:
                # Broadcast : envoyer à tous sauf l'expéditeur
                await fanout(clients, payload, peer_id)
            elif target_id < 0:
                # Broadcast excluant abs(target_id)
                await fanout(clients, payload, peer_id, exclude=abs(target_id))
            else:
                await send_one(clients, target_id, payload)

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
    # compression=None : le deflate coûte plus cher qu'il ne rapporte sur ces petits JSON.
    async with websockets.serve(
        handler, "0.0.0.0", port, compression=None, ping_interval=20, ping_timeout=20,
        process_request=handle_http,
    ):
        print(f"[relais] Serveur démarré sur le port {port}")
        await asyncio.Future()  # tourne indéfiniment


if __name__ == "__main__":
    asyncio.run(main())
