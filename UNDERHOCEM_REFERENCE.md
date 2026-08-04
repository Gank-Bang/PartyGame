# UnderHocem — Référence du minijeu

## Contexte projet
- **Moteur** : Godot 4.7, GDScript
- **Réseau** : WebSocket relay server (Railway) — chaque joueur sur sa propre machine
- **Framework** : système de lobby/minijeux déjà en place (`BaseGame`, `NetworkManager`, `PlayerCharacter`)
- **Serveur relay** : `wss://partygame-production-c66e.up.railway.app`
- **Branche git** : `hocem/underhocem`

## Concept du jeu
Bullet hell style Undertale à 4 joueurs en ligne.
- Les joueurs sont dans un rectangle et doivent survivre le plus longtemps possible aux projectiles d'un boss
- Le joueur avec le **meilleur temps de survie** gagne
- Le jeu continue même quand il reste 1 joueur — il meurt aussi pour faire son meilleur temps

## Mécaniques de jeu
| Mécanique | Détail |
|---|---|
| Mouvement | Vitesse constante (flèches directionnelles) |
| Déflection | Maintien Espace = figé + charge. Si un projectile est dans la ReflectZone (rayon 80) au relâchement → renvoyé x1.5 vitesse vers la souris. Sinon rien ne se passe (pas de tir joueur). |
| Vies | 3 HP par joueur, affichés avec des cœurs dans le HUD |
| Fin de partie | Tout le monde meurt → classement par temps de survie |
| Taille de la zone | Réduite (murs gauche/droite/bas intérieurs) à 1-2 joueurs ; zone complète à 3-4 joueurs (sinon trop petit) — voir `INNER_WALLS` dans `UnderHocemScript.gd` |

## Boss — 4 phases
| Phase | Timing | Pattern | Vitesse |
|---|---|---|---|
| 1 | 0–20s | Ligne droite vers le bas + légère déviation aléatoire | 340 |
| 2 | 20–41s | Éventail **5** projectiles + offset random, cadence doublée (0.6s) | 400 |
| — (pause) | 41–48s | Le boss se tait, **vibre** sur place et déroule son dialogue. Aucun tir. | — |
| 3 | 48–68s | **Explosion** de 16 projectiles à l'entrée, puis spirale dense (0.25s) | 450 |
| 4 | 68s+ | Mix aléatoire des 3 patterns, cadence 0.25s | variable |

### Musique & synchro (BossScript.gd)

Deux `AudioStreamPlayer` enfants du Boss :

| Nœud | Fichier | Rôle | Boucle |
|---|---|---|---|
| `MusicPhase12` | *Spear of Justice* | Thème des phases 1-2 | oui |
| `MusicPhase3` | *rustyMachiine.mp3* | Démarre pendant la phase 2 (fondu croisé) et porte toute la synchro | oui |

`rustyMachiine.mp3` est la version longue de `rustymachine.mp3` : assez longue pour couvrir la fin de la partie, ce qui évite d'avoir à enchaîner sur un 3e morceau.

**Toute la timeline des phases 3/4 est calculée à partir du démarrage de la 2e musique**, ce qui permet de changer de morceau sans toucher au code.

| Réglage (`@export`) | Défaut | Rôle |
|---|---|---|
| `phase2_start` | 20s | Fin phase 1 / début phase 2 |
| `music_phase3_start` | 25s | Instant (temps de jeu) où la 2e musique démarre, **pendant** la phase 2 |
| `music_fade_duration` | 1.5s | Durée du fondu croisé entre la 1re et la 2e musique (seul fondu du jeu) |
| `pause_offset` | 16s | Décalage **dans la 2e musique** où la pause (vibration, plus de tirs) commence |
| `phase3_offset` | 23s | Décalage **dans la 2e musique** où la phase 3 explose |
| `phase3_duration` | 20s | Durée de la phase 3 avant la phase 4 |
| `dialogue_lines` | 4 répliques | BBCode autorisé (`[font_size=96]mot[/font_size]`) |
| `dialogue_times` | 16 / 19 / 21 / 23s | Instant de chaque réplique, **dans la 2e musique** |
| `dialogue_hold` | 4s | Durée d'affichage de la dernière réplique |
| `shake_amplitude` / `burst_count` | 6px / 16 | Vibration pendant la pause / taille de l'explosion |

Le dialogue est un `RichTextLabel` (BBCode) : la dernière réplique (`POUVOIR`, en gros, en majuscules et **qui vibre** via le tag BBCode natif `[shake]`) est calée sur `phase3_offset` (23s) pour tomber **pile sur l'explosion**, et reste affichée `dialogue_hold` secondes — elle survit donc à la fin de la pause.

**La dernière réplique de `dialogue_lines` déclenche automatiquement les particules** du nœud `DialogueParticles` (CPUParticles2D, one-shot). Si tu ajoutes des répliques après elle, c'est la nouvelle dernière qui prendra les particules.

**Pour changer une musique :** glisser le fichier dans la propriété `Stream` du nœud concerné, puis ajuster `pause_offset`, `phase3_offset` et `dialogue_times` sur les temps forts du nouveau morceau.

Le bouclage est piloté par `_set_looping()` (compatible MP3/Ogg). La musique est locale à chaque client, comme la simulation du boss.

Le passage d'une musique à l'autre est un **fondu croisé** sur `volume_db` : la 2e piste démarre malgré tout *pile* à `music_phase3_start` (seul le volume monte progressivement), pour que la synchro dialogue/phase 3 reste exacte.

En plus du pattern normal, à partir de la phase 2 le boss a 25% de chance (`SPECIAL_CHANCE` dans `BossScript.gd`) de tirer un projectile spécial façon Undertale :
- **Bleu** (`Color.CORNFLOWER_BLUE`) : le joueur doit rester **immobile** pour le traverser sans dégâts
- **Orange** (`Color.ORANGE`) : le joueur doit **bouger** pour le traverser sans dégâts
- Un projectile normal continue de faire des dégâts quel que soit l'état du joueur

## Architecture des fichiers

### Scènes (`Scenes/hocem/`)
```
underhocem.tscn       ← scène principale, hérite de BaseGame.tscn
                         Enfants : Arena(ColorRect), Boss, MurHaut/Bas/Gauche/Droite, MurSeparateur,
                                   MurGaucheInterieur/MurDroiteInterieur/MurBasInterieur (retirés si >2 joueurs),
                                   HUD, ResultScreen
                         Boss > Sprite2D, ColorRect, MusicPhase12, MusicPhase3,
                                Dialogue(RichTextLabel, BBCode), DialogueParticles(CPUParticles2D)
                         GameTimer(Label) ← chrono de survie affiché au-dessus du boss
Projectile.tscn       ← Area2D + Sprite2D + CollisionShape2D + CPUParticles2D (groupe "projectile")
UnderHocemPlayer.tscn ← hérite de PlayerCharacter.tscn
                         Enfants supplémentaires : ReflectZone (Area2D, rayon 80), CooldownBar (ProgressBar)
HUD.tscn              ← CanvasLayer > HBoxContainer > 4x VBoxContainer
                         Chaque slot : Label (nom) + HBoxContainer (3 cœurs Label ♥) + Portrait (ColorRect placeholder)
ResultScreen.tscn     ← CanvasLayer > PanelContainer > VBoxContainer
                         Enfants : Label titre, RankingList (VBoxContainer), "Retour au lobby" (Button)
```

### Scripts (`Scripts/hocem/`)
```
UnderHocemScript.gd       ← extends BaseGame — logique principale
UnderHocemPlayerScript.gd ← extends PlayerCharacter — réflexion, dégâts
BossScript.gd             ← extends Node2D — 4 phases de tir
ProjectileScript.gd       ← extends Area2D — mouvement + collision + groupe "projectile"
HUDScript.gd              ← extends CanvasLayer — portraits + cœurs
ResultScreenScript.gd     ← extends CanvasLayer — classement + retour lobby
```

## Collision layers
| Noeud | Layer | Mask |
|---|---|---|
| PlayerCharacter (racine) | 1 | 2 |
| Projectile | 2 | 1 |
| ReflectZone (Area2D) | 3 | 2 |

## Réseau — messages custom
| action | Émetteur | Données | Effet |
|---|---|---|---|
| `hp_update` | client local (celui qui prend le coup, via `damage_player`) | `{peer_id: X, hp: N}` | Tous les clients mettent à jour `player_hp[X]` et les cœurs du HUD |
| `eliminated` | client local | `{peer_id: X}` | Tous les clients cachent le joueur X et mettent à jour player_hp |
| `proj_spawn` | **hôte** | `{id, x, y, dx, dy, speed, type}` | Chaque client crée le même projectile avec le même `net_id` |
| `proj_reflect` | client qui dévie | `{id, x, y, vx, vy, speed, by}` | Tous repositionnent le projectile et appliquent la nouvelle trajectoire |
| `proj_destroy` | client dont le joueur est touché | `{id}` | Tous retirent le projectile |

⚠️ Le relais **n'envoie pas le broadcast à son propre émetteur** (`to: 0` = tous sauf soi). Toute action doit donc être appliquée localement **et** diffusée.

### Synchronisation des projectiles (host-authority)

Seul l'hôte fait tirer le boss (`_spawn_projectile` sort immédiatement si `not NetworkManager.is_host`). Il attribue à chaque projectile un `net_id` incrémental et le réplique.

Le déplacement est **déterministe** (vitesse constante, ligne droite) : aucune sync par frame n'est nécessaire, seuls les *événements* transitent. La sortie d'écran est recalculée localement par chaque client.

**Autorité des collisions :** chaque client ne juge que les collisions de **son** joueur (`if "is_local" in body and not body.is_local: return` dans `ProjectileScript`). C'est nécessaire car `velocity` n'est pas répliquée — un joueur distant a toujours `velocity == Vector2.ZERO`, ce qui fausserait complètement la règle bleu/orange. Le client touché diffuse ensuite `proj_destroy`.

En revanche, **les phases, la musique, le dialogue et les animations du boss tournent en local sur tous les clients** (pure présentation, pas besoin de réseau).

Le registre `projectiles: {net_id → nœud}` se nettoie tout seul : chaque projectile est connecté à `tree_exited`, donc peu importe la cause de sa disparition, son entrée disparaît avec lui.

Les messages standards (`player_state`, `game_over`) sont gérés par `BaseGameScript.gd`.

## API BaseGame à connaître
```gdscript
# Méthodes virtuelles à surcharger
func _on_game_ready() -> void       # appelé au démarrage
func _on_custom_message(from_id, data) -> void  # messages réseau custom
func _on_game_over(winner_peer_id) -> void       # fin de partie

# Méthodes disponibles
NetworkManager.send_game_message(target_id, data)  # 0 = broadcast
NetworkManager.is_host                              # bool
NetworkManager.players                              # Dictionary {peer_id: {name: ...}}
NetworkManager.local_peer_id()                      # peer_id local
end_game(winner_peer_id)                            # à appeler depuis l'hôte
players                                             # Dictionary {peer_id: PlayerCharacter}
```

## Ce qui reste à faire (TODO)

- [x] Ajout d'un countdown de deflection (1,5 secondes). Chaque joueur a son propre compte. (le tir joueur a été retiré, seule la deflection reste)
- [x] Mur séparateur horizontal entre la zone joueurs et le boss (StaticBody2D invisible, bloque les joueurs, laisse passer les projectiles)
- [x] Rendre le mur séparateur visible pour les joueurs (ColorRect gris clair, même pattern que le visuel du boss)
- [x] Réduire la taille des joueurs
- [x] Indicateur visuel du cooldown de déflection (ProgressBar sous le joueur, se remplit pendant le cooldown)
- [x] Ajout d'un invincibilité temporaire après un hit (iframes)
- [x] Déflection : direction du renvoi vers la position de la souris au moment du relâchement.
- [x] Déflection : le joueur qui dévie un projectile n'en subit pas les dégâts si celui-ci le retouche, mais un autre joueur touché par ce même projectile prend bien les dégâts.
- [x] Portraits joueurs dans le HUD — placeholder coloré (ColorRect vert/orange/rouge/gris) en attendant les vrais sprites/AnimatedSprite2D
- [x] Effets visuels : flash rouge au hit (Tween modulate), pulse d'échelle pendant le chargement de la déflection
- [x] Effets visuels : particules sur les projectiles (CPUParticles2D, traînée simple, couleur assortie au type bleu/orange/normal)
- [x] Ajout des tirs spéciaux du boss : projectile bleu (rester immobile pour le traverser) et orange (rester en mouvement), façon Undertale. Le boss en tire un en plus du pattern normal avec 25% de chance à partir de la phase 2.
- [x] Musique de fond : thème phases 1-2, puis 2e thème lancé pendant la phase 2 avec pause + dialogue + explosion synchronisés
- [ ] Sons (SFX : projectiles, réflexion, morts, fin de partie)
- [x] Synchronisation réseau des HP (broadcast `hp_update` à chaque coup, pas seulement à l'élimination)
- [x] Synchronisation réseau des projectiles (host-authority : `proj_spawn` / `proj_reflect` / `proj_destroy`)
- [ ] Sprites réels (joueurs, boss, projectiles) à la place des placeholders
- [x] Lors de changements de phase le boss il y a une animation (flash blanc + pulse d'échelle via Tween)
- [ ] (futur, pas encore implémenté) Dans les dernières phases, le boss doit pouvoir aussi envoyer des projectiles depuis le bas de la zone joueurs (en plus du haut), et switcher de temps en temps entre tirer du haut et tirer du bas

## Bugs connus / points d'attention
- En test local (2 instances sur la même machine), les 2 joueurs partagent le même clavier → normal, en prod chacun a sa machine
- Les projectiles apparaissent chez les clients avec un décalage égal à la latence réseau (pas de compensation). La déflection renvoie la position exacte pour limiter la dérive.
- **[à corriger plus tard]** Un joueur qui vient coller un autre joueur par le dessous peut ensuite le pousser / le diriger. Les `PlayerCharacter` sont des `CharacterBody2D` qui se collisionnent entre eux : `move_and_slide()` pousse la copie locale de l'autre joueur, et comme chaque client fait autorité sur sa propre position, ça crée un conflit de positions. Piste : retirer les joueurs du masque de collision des autres joueurs (ils n'ont pas besoin de se bloquer entre eux).
