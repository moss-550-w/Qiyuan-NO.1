extends Panel
class_name BriefingCard
## BriefingCard —— 单个专家简报卡
##
## 显示专家姓名、性格、立场话术，新手模式下高亮可疑点（隐瞒/夸大）。
## 数据由 BriefingSystem.generate() 提供，卡片只负责呈现。

## 性格 → 主题色（左侧色点 + 高亮边框）
const PERSONALITY_COLOR := {
	"conservative": Color(0.30, 0.55, 0.95),
	"aggressive": Color(0.90, 0.30, 0.30),
	"pessimistic": Color(0.95, 0.60, 0.20),
	"idealistic": Color(0.65, 0.40, 0.90),
}

@onready var _dot: ColorRect = $Margin/VBox/Header/Dot
@onready var _name: Label = $Margin/VBox/Header/Name
@onready var _personality: Label = $Margin/VBox/Personality
@onready var _text: RichTextLabel = $Margin/VBox/Text
@onready var _suspect: RichTextLabel = $Margin/VBox/Suspect


func setup(data: Dictionary) -> void:
	_name.text = data.get("name", "")
	_personality.text = data.get("personality_label", "")
	_dot.color = PERSONALITY_COLOR.get(data.get("personality", ""), Color.GRAY)
	_text.text = data.get("text", "")

	var suspect_point: String = data.get("suspect_point", "")
	if bool(data.get("highlight", false)) and suspect_point != "":
		_suspect.visible = true
		var tag: String = "隐瞒" if bool(data.get("is_hiding", false)) else "夸大"
		_suspect.text = "[color=#f5c63f]⚠ 疑似%s：%s[/color]" % [tag, suspect_point]
	else:
		_suspect.visible = false
