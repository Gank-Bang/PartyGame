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
| Tir joueur | Maintien Espace = figé + charge, Relâché = balle lancée vers le boss |
| Réflexion | Si un projectile est dans la ReflectZone (rayon 80) et que le joueur relâche Espace → projectile renvoyé x1.5 vitesse |
| Vies | 3 HP par joueur, affichés avec des cœurs dans le HUD |
| Fin de partie | Tout le monde meurt → classement par temps de survie |

## Boss — 4 phases
| Phase | Timing | Pattern | Vitesse |
|---|---|---|---|
| 1 | 0–20s | Ligne droite vers le bas + légère déviation aléatoire | 300 |
| 2 | 20–40s | Éventail 3 projectiles (gauche/centre/droite) + offset random | 350 |
| 3 | 40–60s | Spirale balayant de droite à gauche (moitié basse seulement) | 400 |
| 4 | 60s+ | Mix aléatoire des 3 patterns | variable |

## Architecture des fichiers

### Scènes (`Scenes/hocem/`)
```
underhocem.tscn       ← scène principale, hérite de BaseGame.tscn
                         Enfants : Arena(ColorRect), Boss, MurHaut/Bas/Gauche/Droite,
                                   HUD, ResultScreen
Projectile.tscn       ← Area2D + Sprite2D + CollisionShape2D (groupe "projectile")
PlayerBullet.tscn     ← Area2D + Sprite2D + CollisionShape2D
UnderHocemPlayer.tscn ← hérite de PlayerCharacter.tscn
                         Enfants supplémentaires : ReflectZone (Area2D, rayon 80)
HUD.tscn              ← CanvasLayer > HBoxContainer > 4x VBoxContainer
                         Chaque slot : Label (nom) + HBoxContainer (3 cœurs Label ♥)
ResultScreen.tscn     ← CanvasLayer > PanelContainer > VBoxContainer
                         Enfants : Label titre, RankingList (VBoxContainer), "Retour au lobby" (Button)
```

### Scripts (`Scripts/hocem/`)
```
UnderHocemScript.gd       ← extends BaseGame — logique principale
UnderHocemPlayerScript.gd ← extends PlayerCharacter — tir, réflexion, dégâts
BossScript.gd             ← extends Node2D — 4 phases de tir
ProjectileScript.gd       ← extends Area2D — mouvement + collision + groupe "projectile"
PlayerBulletScript.gd     ← extends Area2D — balle tirée par le joueur
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
| `eliminated` | client local | `{peer_id: X}` | Tous les clients cachent le joueur X et mettent à jour player_hp |

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
- [ ] Sprites réels (joueurs, boss, projectiles) à la place des placeholders
- [ ] Portraits joueurs dans le HUD (3 états : sain / blessé / très blessé) avec AnimatedSprite2D
- [ ] Effets visuels : flash au hit, particules projectiles
- [ ] Sons
- [ ] Synchronisation réseau des HP (actuellement local seulement)
- [ ] Invincibilité temporaire après un hit (iframes)
- [ ] Tir joueur : direction vers le boss plutôt que toujours vers le haut

## Bugs connus / points d'attention
- En test local (2 instances sur la même machine), les 2 joueurs partagent le même clavier → normal, en prod chacun a sa machine
- La réflexion fonctionne uniquement pour le joueur local (pas de sync réseau de la réflexion — le projectile change de trajectoire localement)
