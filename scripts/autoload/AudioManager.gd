extends Node
## AudioManager —— 音效 + 背景音乐播放单例
##
## 集中管理 UI 音效、警报音与背景音乐（BGM）。音频文件放入 res://assets/audio/，
## 按逻辑名播放，缺资源时静默跳过（不阻断流程）。作为 autoload，BGM 跨场景持续。

## 事件名 → 音效资源路径（资源缺失时跳过）
const SOUND_PATHS := {
	"ui_click": "res://assets/audio/ui_click.ogg",
	"ui_hover": "res://assets/audio/ui_hover.ogg",
	"token_drop": "res://assets/audio/token_drop.ogg",
	"alarm": "res://assets/audio/alarm.ogg",
	"disruption": "res://assets/audio/disruption.ogg",
	"round_start": "res://assets/audio/round_start.ogg",
	"ending": "res://assets/audio/ending.ogg",
}

## BGM 名 → 资源路径
const BGM_PATHS := {
	"menu": "res://assets/audio/bgm_menu.wav",
	"control": "res://assets/audio/bgm_control.wav",
	"ending": "res://assets/audio/bgm_ending.wav",
}

const MIN_DB := -60.0   # 视为静音的 dB 下限

## 预加载的音效流缓存：事件名 → AudioStream
var _streams: Dictionary = {}
## 复用的音效播放器池
var _players: Array[AudioStreamPlayer] = []
const POOL_SIZE := 8

## BGM 专用播放器
var _bgm_player: AudioStreamPlayer = null
var _current_bgm: String = ""
var _bgm_tween: Tween = null


func _ready() -> void:
	# 音效播放器池
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

	# 预加载存在的音效资源
	for name in SOUND_PATHS:
		var path: String = SOUND_PATHS[name]
		if ResourceLoader.exists(path):
			_streams[name] = load(path)

	# BGM 播放器
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)


## 按事件名播放音效；资源不存在则静默跳过
func play(sound_name: String) -> void:
	if not _streams.has(sound_name):
		return
	var player := _get_free_player()
	if player == null:
		return
	player.stream = _streams[sound_name]
	player.volume_db = _linear_to_db(SaveManager.settings.get("master_volume", 1.0))
	player.play()


## 取一个空闲播放器，无空闲则复用第一个
func _get_free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0] if not _players.is_empty() else null


# ---------------------------------------------------------------------------
# 背景音乐
# ---------------------------------------------------------------------------

## 播放指定 BGM（循环）。同一曲目正在播则不打断；切换时淡入淡出。
func play_bgm(bgm_name: String, fade_in: float = 1.2) -> void:
	if _current_bgm == bgm_name and _bgm_player.playing:
		return
	var path: String = BGM_PATHS.get(bgm_name, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	_current_bgm = bgm_name

	var stream: AudioStream = load(path)
	# WAV 资源运行时设为整段循环
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)

	var target_db: float = _linear_to_db(SaveManager.settings.get("bgm_volume", 0.5))
	_kill_bgm_tween()
	_bgm_player.stream = stream
	_bgm_player.play()
	if fade_in > 0.0:
		_bgm_player.volume_db = MIN_DB
		_bgm_tween = create_tween()
		_bgm_tween.tween_property(_bgm_player, "volume_db", target_db, fade_in)
	else:
		_bgm_player.volume_db = target_db


## 停止 BGM（可淡出）
func stop_bgm(fade_out: float = 0.6) -> void:
	_current_bgm = ""
	_kill_bgm_tween()
	if fade_out > 0.0 and _bgm_player.playing:
		_bgm_tween = create_tween()
		_bgm_tween.tween_property(_bgm_player, "volume_db", MIN_DB, fade_out)
		_bgm_tween.tween_callback(_bgm_player.stop)
	else:
		_bgm_player.stop()


## 实时调整 BGM 音量（0~1）
func set_bgm_volume(v: float) -> void:
	SaveManager.settings["bgm_volume"] = v
	if _bgm_player and _bgm_player.playing:
		_bgm_player.volume_db = _linear_to_db(v)


func _kill_bgm_tween() -> void:
	if _bgm_tween and _bgm_tween.is_valid():
		_bgm_tween.kill()


## 线性音量转 dB，0（及以下）视为静音
func _linear_to_db(v: float) -> float:
	if v <= 0.0:
		return MIN_DB
	return linear_to_db(v)
