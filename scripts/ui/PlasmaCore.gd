extends GPUParticles2D
class_name PlasmaCore
## PlasmaCore —— 等离子体核心粒子特效
##
## 可视化即科普：粒子整体色调严格对应"约束稳定度"——稳定度高时呈蓝白炽热态，
## 下降时转橙、再转暗红（约束变差、温度跌落）。粒子数按性能档位可配，便于
## HTML5 端降级，保证不卡顿。

const BASE_AMOUNT := 240

# 稳定度 → 颜色锚点
const COLOR_HOT := Color(0.55, 0.82, 1.0)    # 蓝白（炽热、约束良好）
const COLOR_WARM := Color(1.0, 0.65, 0.20)   # 橙（正常）
const COLOR_COLD := Color(0.72, 0.20, 0.16)  # 暗红（约束恶化）


func _ready() -> void:
	apply_quality()


## 按性能档位调整粒子数 / 开关（high / low / off）
func apply_quality() -> void:
	var q: String = SaveManager.settings.get("particle_quality", "high")
	match q:
		"off":
			emitting = false
		"low":
			amount = maxi(8, int(BASE_AMOUNT / 4))
			emitting = true
		_:
			amount = BASE_AMOUNT
			emitting = true


## 用约束稳定度（0~1）驱动等离子体色调
func set_state(stability: float) -> void:
	var s: float = clampf(stability, 0.0, 1.0)
	var c: Color
	if s >= 0.6:
		c = COLOR_WARM.lerp(COLOR_HOT, (s - 0.6) / 0.4)
	else:
		c = COLOR_COLD.lerp(COLOR_WARM, s / 0.6)
	modulate = c
