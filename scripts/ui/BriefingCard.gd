extends Panel
class_name BriefingCard
## BriefingCard —— 单个专家简报卡（信任度→精度模型）
##
## 显示专家姓名、性格、简报文本（精确/模糊取决于信任度），
## 以及信任度指示条和"深度诊断"购买按钮。
## 不再显示"隐瞒/夸大"：新模型中专家不说谎，只是精度随信任变化。

## 性格 → 主题色
const PERSONALITY_COLOR := {
	"conservative": Color(0.30, 0.55, 0.95),
	"aggressive":   Color(0.90, 0.30, 0.30),
	"pessimistic":  Color(0.95, 0.60, 0.20),
	"idealistic":   Color(0.65, 0.40, 0.90),
}

signal deep_diagnose_requested(expert_id: String)

@onready var _dot:        ColorRect     = $Margin/VBox/Header/Dot
@onready var _name:       Label         = $Margin/VBox/Header/Name
@onready var _personality: Label        = $Margin/VBox/Personality
@onready var _text:       RichTextLabel = $Margin/VBox/Text
@onready var _trust_row:  RichTextLabel = $Margin/VBox/Suspect   # 复用 Suspect 节点显示信任度
@onready var _deep_btn:   Button        = $Margin/VBox/DeepBtn

var _expert_id: String = ""


func setup(data: Dictionary) -> void:
	_expert_id = data.get("expert_id", "")
	_name.text = data.get("name", "")
	_personality.text = data.get("personality_label", "")
	_dot.color = PERSONALITY_COLOR.get(data.get("personality", ""), Color.GRAY)
	_text.text = data.get("text", "")

	var trust: float = float(data.get("trust", 0.6))
	var precise: bool = bool(data.get("precise", true))
	var bars: String = _trust_bars(trust)
	var conf: String = "[color=#4ed36a]精确[/color]" if precise else "[color=#e09040]模糊[/color]"
	_trust_row.visible = true
	_trust_row.text = "[color=#8893a5]信任度 %s  %s[/color]" % [bars, conf]

	var cost: int = int(DataManager.get_balance().get("deep_diagnose", {}).get("cost", 10))
	_deep_btn.text = "深度诊断 ¥%d" % cost
	_deep_btn.pressed.connect(func() -> void: deep_diagnose_requested.emit(_expert_id))


## 生成信任度点阵（5格）
static func _trust_bars(trust: float) -> String:
	var filled: int = roundi(trust * 5.0)
	return "●".repeat(filled) + "○".repeat(5 - filled)
