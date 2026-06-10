# 工程计划 · 聚变纪元·启元一号

> 本文档将 `design.md` (V3.0) 的玩法方案落地为可执行的 Godot 工程计划，覆盖目录结构、场景树、数据 Schema、系统模块拆分、开发排期与风险控制。
> 所有约束遵循 `Claude.md`：Godot 4.6+ / GDScript 优先 / 配置化驱动 / 严格离线。

---

## 一、技术基线

| 项 | 决策 | 说明 |
|----|------|------|
| 引擎 | Godot 4.3+，Forward+ 渲染器 | 桌面端 Jolt Physics（本项目几乎不用物理，可保持默认）|
| 语言 | GDScript（100%） | 不引入 C#，降低导出与维护复杂度 |
| UI | Control 节点体系 + Theme 资源 | 仪表盘/简报/手册全用 Control，便于多分辨率适配 |
| 特效 | GPUParticles2D + 自定义 shader | 等离子体、磁场线、第一壁烧蚀 |
| 数据 | `res://data/*.json` | `JSON.parse_string` 读取，运行期只读 |
| 存档 | `ConfigFile` → `user://` | 存档/设置/成就，禁用任何远程同步 |
| 分辨率 | 基准 1920×1080，`canvas_items` 拉伸 | `aspect=keep` 保证展柜全屏 |
| 离线红线 | 无 HTTP/HTTPRequest/WebSocket/第三方 SDK | CI 阶段静态扫描关键字兜底 |

---

## 二、工程目录结构

```
res://
├── project.godot
├── main.tscn                      # 启动场景（主菜单）
├── data/                          # 全部配置（非程序员可改）
│   ├── experts.json               # 四位专家：性格、立场、头像路径
│   ├── faults.json                # 故障树：根因→四轮表象、触发条件
│   ├── rounds.json                # 每轮：仪表基准值、噪声、限时
│   ├── briefings.json             # 专家简报模板（带隐瞒/夸大字段）
│   ├── kb_glossary.json           # 运行手册：科普词条
│   ├── kb_timeline.json           # 中国聚变成果时间线 / 辟谣 / 考研就业
│   ├── endings.json               # 12 种结局矩阵文案
│   ├── popups.json                # 上下文浮动科普标签文案
│   └── difficulty.json            # 三种难度参数
├── scenes/
│   ├── menu/MainMenu.tscn
│   ├── control_room/ControlRoom.tscn      # 核心中控台
│   ├── components/
│   │   ├── Gauge.tscn             # 单个仪表盘（可复用）
│   │   ├── BudgetToken.tscn       # 可拖拽经费代币
│   │   ├── DropZone.tscn          # 装置部位投放区
│   │   ├── BriefingCard.tscn      # 专家简报卡
│   │   ├── PopupTag.tscn          # 浮动科普标签
│   │   └── AlarmLight.tscn        # 报警灯
│   ├── panels/
│   │   ├── ManualPanel.tscn       # 运行手册（可检索）
│   │   ├── LogPanel.tscn          # 历史运行日志（总工模式）
│   │   └── EndingPanel.tscn       # 结局面板
│   └── fx/
│       ├── PlasmaCore.tscn        # 等离子体粒子
│       ├── FieldLines.tscn        # 磁场线
│       └── WallAblation.tscn      # 第一壁烧蚀
├── scripts/
│   ├── autoload/
│   │   ├── DataManager.gd         # 启动加载并校验全部 JSON（单例）
│   │   ├── GameState.gd           # 全局运行态：轮次/Q/稳定度/根因识别（单例）
│   │   ├── SaveManager.gd         # ConfigFile 存读档/成就（单例）
│   │   └── AudioManager.gd        # 警报/UI 音效（单例）
│   ├── core/
│   │   ├── FusionEngine.gd        # 核心计算：Q值/稳定度/经费效果公式
│   │   ├── FaultTree.gd           # 根因→表象推演、识别判定
│   │   ├── BriefingSystem.gd      # 专家立场过滤、信息隐瞒/夸大
│   │   └── EndingResolver.gd      # 2D 结局矩阵判定
│   └── ui/                        # 各场景挂载脚本
├── assets/
│   ├── art/  (头像、剖面图、图标、Theme)
│   ├── shaders/  (plasma.gdshader, field_lines.gdshader)
│   └── audio/
└── export_presets.cfg
```

**约定**：`scripts/autoload/` 全部注册为单例（Project Settings → Autoload）；场景脚本只做视图与交互，业务逻辑下沉到 `scripts/core/`。

---

## 三、核心数据流（单向）

```
启动 → DataManager 加载校验 JSON
       ↓
GameState 初始化本局（难度/轮次=1）
       ↓
[每轮循环]
  BriefingSystem 据 experts+faults+难度 生成四份简报
       ↓
  玩家拖放 BudgetToken → DropZone 触发 FusionEngine 实时预测
       ↓
  玩家提交/超时 → FaultTree 推演下一轮表象、记录根因识别
       ↓
  GameState 更新 Q/稳定度/经费 → 刷新仪表与 FX
       ↓
  轮次<4 ? 回到顶部 : EndingResolver 判定 → EndingPanel
       ↓
SaveManager 写入存档/成就
```

数据单向流动：视图层不直接改 `GameState`，统一通过 core 模块方法 + 信号回传，避免状态散乱。

---

## 四、关键数据 Schema（草案）

> 仅定字段骨架，数值由内容同学填充。最终以 DataManager 的校验为准。

`experts.json`
```json
{
  "magnet_eng": {
    "name": "磁体工程师",
    "personality": "conservative",
    "avatar": "res://assets/art/avatars/magnet.png",
    "bias_target": "magnet_coil",
    "hide_signal": ["magnet_psu_aging"],
    "exaggerate_signal": []
  }
}
```

`faults.json`（根因驱动）
```json
{
  "root_causes": {
    "magnet_psu_aging":   { "name": "磁体电源老化", "fix_part": "magnet_coil" },
    "wall_microcrack":    { "name": "第一壁微裂纹", "fix_part": "first_wall" },
    "tritium_pump_decay": { "name": "氚提取泵效率下降", "fix_part": "breeder_blanket" }
  },
  "rounds": [
    {
      "round": 1,
      "symptoms": [
        { "cause": "magnet_psu_aging", "gauge": "toroidal_field", "deviation": -0.08 }
      ]
    }
  ]
}
```

`endings.json`（矩阵）
```json
{
  "Q_lt1__root0": { "title": "...", "summary": "..." },
  "Q_1to11__root2": { "title": "...", "summary": "..." }
}
```
矩阵键 = `Q区间(3) × 根因识别数(0-3 共4)` = 12 条。

`difficulty.json`
```json
{
  "novice": { "gauge_noise": 0.0, "highlight_suspect": true,  "show_hint_dash": true,  "time_limit": 0 },
  "chief":  { "gauge_noise": 0.03, "highlight_suspect": false, "show_hint_dash": false, "time_limit": 300 }
}
```

---

## 五、核心计算模型（FusionEngine 草案）

> 数值需内容同学结合 EAST/ITER 真实量级标定，此处给口径与方向，便于程序先行搭框架。

- **经费效果**：每个部位投入 `b` 单位 → 效能增益 `gain = k * (1 - exp(-b/τ))`（边际递减，避免单点堆满）。
- **Q 值**：`Q = base_Q * f(磁体效能, 控制效能) - penalty(未修根因)`。
- **稳定度**：受第一壁效能、控制效能、决策延迟惩罚共同影响，低于阈值触发破裂报警。
- **燃料自持**：受氚增殖包层效能影响，过低触发氚循环预警。
- **根因识别**：玩家在对应部位的投入达到"有效修复阈值" → 标记该根因为"已识别并处置"，计入结局纵轴。

所有系数集中在 `data/rounds.json` / 独立 `balance.json`，禁止硬编码进 `.gd`。

---

## 六、开发排期（10 天，对齐 design.md，细化到可勾选）

> P=程序，C=内容/美术。每天产出标注 **验收点**。

### 阶段一：骨架与核心交互（D1-D3）
- **D1** P：建工程、Autoload 四单例、`DataManager` 加载校验、`Gauge.tscn` + 数据绑定。C：中控台布局草图、视觉风格定调、四专家头像与性格草稿。
  - 验收：空 JSON 能正常加载报错；仪表能显示假数据。
- **D2** P：`BudgetToken` 拖放 + `DropZone` 命中 + 实时预测数值，与仪表联动。C：托卡马克剖面基础美术（矢量+粒子占位）。
  - 验收：拖一枚代币到磁体，预测 Q 值变化并回显。
- **D3** P：`FusionEngine` 公式落地、`FaultTree` 第一轮触发逻辑。C：第一轮故障台词、词条、仪表读数规则。
  - 验收：完整跑通第 1 轮：分配→提交→数值结算。

### 阶段二：博弈与结局（D4-D5）
- **D4** P：`BriefingSystem`（立场过滤/隐瞒/夸大）+ `BriefingCard` 面板。C：第 2、3 轮故障配置，等离子体粒子效果。
  - 验收：四份简报按专家偏见生成，与仪表存在可甄别偏差。
- **D5** P：`FaultTree` 四轮串联 + `EndingResolver` 12 结局判定 + `EndingPanel`。C：第一壁裂纹/磁场线特效，结局框架文案。
  - 验收：四轮全程贯通，落到正确结局键。

### 阶段三：科普与系统（D6-D7）
- **D6** P：`ManualPanel` 运行手册（本地检索）。C：填充全部词条、EAST/ITER 数据、辟谣内容。
  - 验收：手册可搜索关键词并定位词条。
- **D7** P：`SaveManager` 存读档 + 成就 + `LogPanel` 历史日志。C：12 结局科普总结文案细化。
  - 验收：退出重进续档；总工模式可查历史趋势。

### 阶段四：打磨与交付（D8-D10）
- **D8** P：限时系统、难度切换、UI 动画与 `PopupTag` 浮动科普。C：整体 UI 美化、警报/UI 音效。
  - 验收：三难度可切换并生效；浮标 3 秒消退/可钉住。
- **D9** P：全流程测试、修 bug、粒子性能优化。C：文本校对、逻辑一致性、补漏科普点。
  - 验收：HTML5 端粒子不卡顿（目标 ≥50 FPS）。
- **D10** P：导出 Win/macOS/Linux/HTML5、打包、README。C：宣传文案、截图、玩法说明、部署。
  - 验收：四平台产物可运行；Web 版 GitHub Pages 离线可玩。

---

## 七、里程碑与依赖

```
M1 (D3末) 单轮可玩闭环      —— 解锁内容同学批量填轮次配置
M2 (D5末) 全流程+结局贯通   —— 解锁手册/存档/打磨并行
M3 (D7末) 系统功能完整      —— 进入纯打磨与内容收口
M4 (D10末) 全平台交付       —— 发布
```

关键路径：`DataManager → FusionEngine → FaultTree → BriefingSystem → EndingResolver`。其中 `FusionEngine` 公式标定是最大不确定点，D3 必须冻结接口（即便数值待调），否则后续模块阻塞。

---

## 八、风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| 数值平衡难调（Q/稳定度手感） | 高 | 公式接口 D3 冻结，系数全外置 `balance.json`，留调参热加载 |
| 故障树耦合逻辑复杂易乱 | 高 | 先用"根因→表象"纯数据表驱动，禁止散落 if-else |
| HTML5 粒子性能 | 中 | 粒子数上限可配；Web 端降级开关；提前 D9 前抽测 |
| 内容产能跟不上程序 | 中 | D1 先定全部 JSON Schema，内容同学并行填充不等程序 |
| 拖放交互在 Web 触控端体验 | 中 | DropZone 命中容差放大；保留点击分配兜底 |
| 误引入网络依赖 | 红线 | 导出前静态扫描 `HTTPRequest/WebSocket/http` 关键字 |

---

## 九、下一步（立即执行）

1. 建立 `res://` 工程与目录骨架、注册四个 Autoload 单例。
2. 落地 `DataManager.gd`：加载 + Schema 校验 + 缺字段报错。
3. 产出全部 `data/*.json` 的**空骨架文件**（字段齐全、数值占位），供内容同学并行填充。
4. 实现 `Gauge.tscn` + 假数据绑定，验证数据流通。

> 经确认后，建议从第 1、2、3 步开始落地——先把"配置化骨架"立起来，内容与程序即可并行。
