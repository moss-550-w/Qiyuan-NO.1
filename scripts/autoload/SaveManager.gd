extends Node
## SaveManager —— 存档 / 设置 / 成就单例
##
## 使用 Godot ConfigFile 持久化到 user://，纯本地、无任何云同步。
## - 存档：当前局进度（GameState 快照）
## - 设置：难度、音量、限时开关等
## - 成就：已解锁结局、统计

const SAVE_PATH := "user://savegame.cfg"
const SETTINGS_PATH := "user://settings.cfg"

signal achievement_unlocked(id: String)

var settings := {
	"difficulty": "novice",
	"master_volume": 1.0,
	"time_limit_enabled": true,
}


func _ready() -> void:
	load_settings()


# ---------------------------------------------------------------------------
# 存档
# ---------------------------------------------------------------------------

## 保存当前局进度
func save_game() -> void:
	var cfg := ConfigFile.new()
	var snapshot := GameState.to_save_dict()
	for key in snapshot:
		cfg.set_value("game", key, snapshot[key])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("[SaveManager] 存档失败：%d" % err)


## 读取存档并恢复到 GameState，成功返回 true
func load_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	var d := {}
	for key in cfg.get_section_keys("game"):
		d[key] = cfg.get_value("game", key)
	GameState.from_save_dict(d)
	return true


## 是否存在存档
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 删除存档
func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


# ---------------------------------------------------------------------------
# 设置
# ---------------------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in cfg.get_section_keys("settings"):
		settings[key] = cfg.get_value("settings", key)


# ---------------------------------------------------------------------------
# 成就
# ---------------------------------------------------------------------------

## 解锁成就（含已解锁结局矩阵格）
func unlock_achievement(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var unlocked: Array = cfg.get_value("achievements", "unlocked", [])
	if not unlocked.has(id):
		unlocked.append(id)
		cfg.set_value("achievements", "unlocked", unlocked)
		cfg.save(SETTINGS_PATH)
		achievement_unlocked.emit(id)


## 获取已解锁成就列表
func get_unlocked() -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return []
	return cfg.get_value("achievements", "unlocked", [])
