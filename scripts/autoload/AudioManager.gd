extends Node
## AudioManager —— 音效播放单例
##
## 集中管理 UI 音效与警报音。音频文件由内容/美术同学放入 res://assets/audio/，
## 此处按逻辑事件名播放，缺资源时静默跳过（不阻断流程）。

## 事件名 → 音频资源路径（资源缺失时跳过）
const SOUND_PATHS := {
	"ui_click": "res://assets/audio/ui_click.ogg",
	"ui_hover": "res://assets/audio/ui_hover.ogg",
	"token_drop": "res://assets/audio/token_drop.ogg",
	"alarm": "res://assets/audio/alarm.ogg",
	"disruption": "res://assets/audio/disruption.ogg",
	"round_start": "res://assets/audio/round_start.ogg",
	"ending": "res://assets/audio/ending.ogg",
}

## 预加载的音频流缓存：事件名 → AudioStream
var _streams: Dictionary = {}
## 复用的播放器池
var _players: Array[AudioStreamPlayer] = []
const POOL_SIZE := 8


func _ready() -> void:
	# 预创建播放器池
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	# 预加载存在的音频资源
	for name in SOUND_PATHS:
		var path: String = SOUND_PATHS[name]
		if ResourceLoader.exists(path):
			_streams[name] = load(path)


## 按事件名播放音效；资源不存在则静默跳过
func play(sound_name: String) -> void:
	if not _streams.has(sound_name):
		return
	var player := _get_free_player()
	if player == null:
		return
	player.stream = _streams[sound_name]
	player.volume_db = linear_to_db(SaveManager.settings.get("master_volume", 1.0))
	player.play()


## 取一个空闲播放器，无空闲则复用第一个
func _get_free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0] if not _players.is_empty() else null
