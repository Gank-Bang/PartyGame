# PartyGame

PartyGame est un jeu de soiree multijoueur en 2D, pense pour 1 a 4 joueurs. Le projet combine un client Godot et un serveur relais WebSocket en Python pour permettre de creer un lobby, rejoindre une partie avec un code a 4 chiffres, puis lancer differents mini-jeux depuis une meme base commune.

## Vue d'ensemble

L'application est organisee autour de trois etapes simples:

1. Le menu principal permet de creer ou rejoindre une partie.
2. Le salon d'attente affiche les joueurs connectes et laisse l'hote lancer la partie.
3. L'ecran de selection permet a l'hote de choisir le mini-jeu, puis tous les joueurs sont rediriges vers la scene correspondante.

Le client Godot gere l'interface, la logique de jeu et la synchronisation des evenements. Le serveur Python ne fait pas tourner la logique de jeu: il relaie les messages entre les joueurs et attribue les identifiants reseau.

## Architecture

### Cote Godot

- `project.godot` declare le projet, la scene principale et l'autoload `NetworkManager`.
- `Scripts/Lobby/NetworkManager.gd` centralise toute la couche reseau et expose des signaux pour les scenes.
- `Scripts/Lobby/BaseGameScript.gd` sert de base aux mini-jeux et gere le spawn des joueurs, les messages reseau et la fin de partie.
- `Scripts/Lobby/*.gd` contient le menu principal, le lobby, l'attente et la selection de mini-jeu.
- `Scripts/RafGames/*.gd` contient les mini-jeux de type quiz / score.
- `Scripts/Yanis/*.gd` contient le mini-jeu top-down action.

### Cote serveur

Le dossier `server/` contient un relais WebSocket minimal:

- il cree et rejoint des lobbies via un code a 4 chiffres;
- il attribue un identifiant a chaque joueur;
- il relaie les messages de jeu vers la bonne cible;
- il gere les deconnexions et ferme le lobby si l'hote part.

## Mini-jeux

### Equation

Le mini-jeu `EquationMiniGame` demande de retrouver la valeur cachee dans une equation simple. La partie se joue en plusieurs rounds, avec timer, score et cooldown apres erreur.

### Pile ou Face

Le mini-jeu `PileOuFaceMiniGame` propose une prediction simple: chaque joueur choisit pile ou face avant la fin du compte a rebours. Un point est attribue a chaque bonne reponse.

### Hotline Miami

Le mode `Yanis` est un mini-jeu d'action top-down. Les joueurs se deplacent dans une carte, visent a la souris et tirent avec le clic gauche. L'hote gere les degats et la condition de fin de partie.

## Comment ca marche

### Flux reseau

1. Le client Godot se connecte au serveur relais WebSocket.
2. L'hote cree un lobby avec un code aleatoire a 4 chiffres.
3. Les autres joueurs rejoignent avec ce code.
4. Les scenes de lobby maintiennent la liste des joueurs via `NetworkManager.players`.
5. Au lancement d'un mini-jeu, les evenements de partie passent par `NetworkManager.send_game_message(...)`.
6. Le serveur relaie les messages au bon destinataire et ajoute l'id de l'emetteur.

### Autorite de partie

Le comportement est essentiellement host-authoritative:

- l'hote choisit le mini-jeu;
- l'hote valide les rounds et les scores dans les mini-jeux;
- les clients recoivent les resultats et synchronisent leur affichage;
- le serveur se contente de transmettre les messages, il ne calcule pas les regles du jeu.

## Controles

### Menu / lobby

- `Jouer` : accede au lobby.
- `Quitter` : ferme l'application.
- Dans le lobby, l'hote voit le code de session et peut demarrer la partie.

### Equation

- Utiliser le pavé numerique a l'ecran pour entrer la reponse.
- Une erreur applique un court cooldown avant de retenter.

### Pile ou Face

- Cliquer sur `PILE` ou `FACE` pendant le compte a rebours.

### Yanis

- Deplacement: fleches ou ZQSD selon le clavier.
- Tir: clic gauche.
- La camera suit le joueur local.

## Lancer le projet en local

### 1. Prerequis

- Godot 4.x compatible avec le projet.
- Python 3.11+.
- `pip` pour installer les dependances du serveur.

### 2. Lancer le serveur relais

Depuis la racine du projet:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r server/requirements.txt
python3 server/main.py
```

Le serveur ecoute par defaut sur le port `8765`.

### 3. Pointer le client vers le serveur local

Dans `Scripts/Lobby/NetworkManager.gd`, remplace temporairement `RELAY_URL` par:

```gdscript
const RELAY_URL := "ws://localhost:8765"
```

### 4. Lancer le client Godot

Ouvre `project.godot` dans Godot, puis lance la scene principale definie dans le projet. Le jeu demarre sur le menu principal.

### 5. Jouer a plusieurs

- Un joueur cree le lobby.
- Les autres joueurs rejoignent avec le code a 4 chiffres.
- Quand tout le monde est pret, l'hote lance la partie depuis le salon.

## Deploiement

Le serveur est deja configure pour un deploiement simple sur Railway ou un service similaire.

- `server/Procfile` lance `python main.py`.
- `railway.toml` utilise `python3 server/main.py` comme commande de demarrage.
- `nixpacks.toml` installe Python et les dependances du serveur.

Si tu deploies le serveur, pense a mettre a jour `RELAY_URL` dans le client Godot avec l'URL `ws://` ou `wss://` fournie par ton hebergeur.

## Structure utile

- `Scenes/Main.tscn` : menu principal.
- `Scenes/Lobby/` : lobby, attente et selection de mini-jeu.
- `Scenes/RafGames/` : scenes des mini-jeux quiz.
- `Scenes/Yanis/` : scene du mini-jeu action.
- `Scripts/Lobby/` : logique reseau et navigation entre ecrans.
- `Scripts/RafGames/` : logique des mini-jeux de selection et de score.
- `Scripts/Yanis/` : logique du mode top-down.
- `server/main.py` : relais WebSocket.

## Notes techniques

- La fenetre est configuree en `1920x1080` et non redimensionnable.
- Le projet utilise `Jolt Physics`.
- Le rendu est en mode `GL Compatibility`.
- `NetworkManager` est un autoload, donc il est accessible depuis toutes les scenes.

## Ameliorations possibles

- Ajouter un ecran de resultat plus propre a la fin des mini-jeux.
- Rendre l'adresse du serveur configurable depuis l'interface ou une variable d'environnement.
- Ajouter une section d'aide in-game pour les controles.
