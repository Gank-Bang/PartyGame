## Échelle d'interface adaptative pour le web et le mobile : une unité logique ≈ un pixel CSS tant que la scène tient à l'écran.
extends Node

const DESIGN_SIZE: Vector2 = Vector2(1920, 1080)
## Taille logique minimale par scène (en dessous, le contenu déborde) ; les scènes absentes gardent la taille de conception.
const SCENE_MIN_SIZE: Dictionary = {
	"res://Scenes/Main.tscn": Vector2(560, 500),
	"res://Scenes/Lobby/LobbyMenu.tscn": Vector2(700, 740),
	"res://Scenes/Lobby/WaitingRoom.tscn": Vector2(700, 640),
	"res://Scenes/Lobby/SelectGames.tscn": Vector2(1260, 960),
	"res://Scenes/RafGames/MotusMiniGame.tscn": Vector2(320, 440),
	"res://Scenes/RafGames/EquationMiniGame.tscn": Vector2(780, 720),
	"res://Scenes/RafGames/PileOuFaceMiniGame.tscn": Vector2(580, 480),
	"res://Scenes/RafGames/RunesMiniGame.tscn": Vector2(760, 780),
	"res://Scenes/RafGames/PairesRunesMiniGame.tscn": Vector2(1080, 840),
	"res://Scenes/RafGames/BlindTestMiniGame.tscn": Vector2(1180, 660),
	"res://Scenes/RafGames/BlindTestAnimeMiniGame.tscn": Vector2(1180, 660),
	"res://Scenes/RafGames/CercleInfernalMiniGame.tscn": Vector2(1200, 1080),
}
const BOTTOM_MARGIN_CSS: float = 28.0

var dpr: float = 1.0
## Pixels physiques par unité logique.
var ui_scale: float = 1.0
var _min_size: Vector2 = DESIGN_SIZE

func _ready() -> void:
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		return
	get_tree().node_added.connect(_on_node_added)
	get_window().size_changed.connect(_refresh)
	_refresh()

func _on_node_added(node: Node) -> void:
	if node.get_parent() != get_tree().root or node.scene_file_path.is_empty():
		return
	_min_size = SCENE_MIN_SIZE.get(node.scene_file_path, DESIGN_SIZE)
	_refresh()

func _refresh() -> void:
	var win: Window = get_window()
	if win.size.x <= 0 or win.size.y <= 0:
		return
	dpr = maxf(DisplayServer.screen_get_scale(), 1.0)
	var fit: float = minf(win.size.x / _min_size.x, win.size.y / _min_size.y)
	ui_scale = minf(dpr, fit)
	win.content_scale_factor = ui_scale

func css_to_logical(css_px: float) -> float:
	return css_px * dpr / ui_scale

func bottom_margin() -> float:
	return css_to_logical(BOTTOM_MARGIN_CSS)
