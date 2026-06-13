# 工程优化计划 · 聚变纪元·启元一号（V3.1 · 聚焦版）

> 本文档将 `new.md`（聚焦版优化方案）落地为**增量工程计划**。
> 注意：本项目 **V3.0 已开发完成并交付**（已有 `win/`、`h5/` 导出产物与 GitHub Pages 部署）。
> 因此本计划不是从零搭建，而是**在现有可运行代码库上做定向优化**，核心目标遵循 `new.md`：
> **所有机制必须强化"有限信息下的诊断决策"核心循环，而非提供绕过思考的捷径。**
> 所有改动遵守 `Claude.md` 红线：Godot 4.6+ / GDScript / 配置化驱动 / 严格离线 / 向下兼容。

---

## 一、现状基线（V3.0 已实现）

| 模块 | 文件 | 现状 |
|------|------|------|
| 数据加载校验 | `scripts/autoload/DataManager.gd` | 10 份 JSON 加载 + 结构校验，运行期只读 |
| 全局状态 | `scripts/autoload/GameState.gd` | 轮次/Q/稳定度/燃料/经费/根因识别/历史日志 |
| 存档成就 | `scripts/autoload/SaveManager.gd` | ConfigFile 本地存档；成就=已解锁结局键 |
| 核心计算 | `scripts/core/FusionEngine.gd` | 经费边际递减→Q/稳定/燃料；含实时悬停预测 |
| 故障树 | `scripts/core/FaultTree.gd` | 根因→表象偏移、指标惩罚、识别判定 |
| 专家简报 | `scripts/core/BriefingSystem.gd` | **隐瞒/夸大**机制（专家会说谎） |
| 结局矩阵 | `scripts/core/EndingResolver.gd` | 3 Q区间 × 4 识别数 = 12 结局 |
| 中控台 | `scripts/ui/ControlRoom.gd` | 拖放分配 + **实时悬停预测** + 限时 + 报警 |
| 历史日志 | `scripts/ui/LogPanel.gd` | 各轮读数快照（文本，无曲线图） |
| 难度 | `data/difficulty.json` | novice/chief/custom；chief 噪声=`randf` 随机 |

**结论**：核心循环、数据流、导出链路均已跑通。本轮优化是**机制深化与信息系统重构**，不动工程骨架。

---

## 二、12 项优化与现有实现的关系（开工前必读）

> 类型：**新增**=现无此功能；**强化**=在现有基础上扩展；**推翻**=与现有已实现/已文档化行为冲突，需迁移。

| # | new.md 优化点 | 类型 | 主要触达 |
|---|--------------|------|---------|
| 1 | 经费"超额投入奖励"（不跨轮累积） | 新增 | `GameState` `FaultTree` `balance.json` `ControlRoom` `Gauge` |
| 2 | 故障链耦合可读化（2~3 组，第3轮后） | 强化 | `faults.json` `FaultTree` `ControlRoom` `BriefingSystem` |
| 3 | 专家：信任度影响**情报精度**而非是否说谎 | **推翻** | `BriefingSystem` `GameState` `experts.json` `briefings.json` `ControlRoom` |
| 4 | 仪表趋势图 + 噪声改为**规律周期波动** | 强化 | `LogPanel`→复盘 `ControlRoom._setup_noise` `difficulty.json` |
| 5 | 单次**锁定预览**取代实时悬停试探 | **推翻** | `ControlRoom` `DropZone` `FusionEngine` |
| 6 | 内生后果驱动；限时降级为**可选挑战模式** | **推翻** | `GameState` `FaultTree` `difficulty.json` `ControlRoom` |
| 7 | 5~6 套手作剧本随机抽取 | 新增 | `data/scenarios.json` `DataManager` `GameState` `faults/briefings` |
| 8 | 行为多样性成就（偏听则暗/耦合猎手…） | 强化 | `data/achievements.json` `SaveManager` `GameState` `EndingPanel` |
| 9 | 教学战役（渐进解锁）+ 标准模式全开放 | 新增 | 教学数据 `MainMenu` `GameState` `ControlRoom` |
| 10 | 逻辑一致性检测 + 复盘三图 | 新增 | `ControlRoom` 复盘面板（扩展 `LogPanel`/`EndingPanel`） |
| 11 | 本地双人合作（分屏，无背叛） | 新增 | 新场景/模式（高成本，末期） |
| 12 | 沙盒降级为内部开发工具 | 减法 | 调试面板（开发期 flag，不进正式包） |

---

## 三、待确认的边界变更（开工前需拍板）

以下三项**推翻了 V3.0 已实现且部分写入 `Claude.md` 的设计**，必须先确认再动手，否则白做返工。

### 决策项 A —— 专家机制：说谎 → 信任度影响精度（#3）
- **冲突**：现 `BriefingSystem` 用 `is_hiding/is_exaggerating` 让专家**主动隐瞒/夸大**；`Claude.md` 项目描述亦明确写"隐瞒微小异常""夸大贫化"。`new.md` #3 要求**专家不说谎**，仅因信任度高低改变信息粒度（数据范围宽窄、语气确定度、对应仪表抖动）。
- **影响**：需重写 `BriefingSystem` 立场逻辑、`briefings.json` 改为"宽/窄区间双版本"、新增专家信任度状态与变化规则、同步修订 `Claude.md` 专家描述。
- **建议默认**：**采纳 #3**。理由：信任度博弈比"猜谎言"更贴合真实工程（专家不会蓄意造假，只是数据置信度不同），且与 #4 仪表"验证者"定位自洽。保留旧逻辑为 `legacy` 难度可选。

### 决策项 B —— 决策反馈：实时悬停预测 → 单次锁定预览（#5）
- **冲突**：现 `ControlRoom._on_hover_preview` + `FusionEngine.predict_with_extra` 提供**逐次拖放实时预测**，玩家可反复试探。`new.md` #5 要求**删除实时试探**，改为"锁定方案→一次性预览(≤10s)→自动确认"，杜绝微操刷解。
- **影响**：移除 hover 预测链路与 `DropZone.hover_preview` 用法，新增"锁定→预览→确认"状态机与短倒计时。
- **建议默认**：**采纳 #5，但分两步**。先保留拖放即时数值回显（非预测，仅显示已投入效果），叠加"锁定预览"；彻底关掉"假想增量预测"。避免一次性砍掉手感。

### 决策项 C —— 压力来源：限时默认 → 内生后果默认、限时转挑战模式（#6）
- **冲突**：现 `novice` 不限时、`chief` 300s 限时为标准压力。`new.md` #6 要求**标准模式无外部倒计时**，压力来自失误后果（稳定度连降警告、不可逆损伤）；限时/审计风暴归入独立"挑战模式"，单独计分。
- **影响**：`difficulty.json` 拆分"标准档"与"挑战档"；新增稳定度历史与不可逆损伤状态；限时系统保留但仅挑战档启用。
- **建议默认**：**采纳 #6**。限时代码已存在，仅改触发条件，成本低；内生后果是纯增量。

> 以上三项若全部采纳，即为本计划 Phase 2/3 的核心；若用户否决某项，对应任务从计划中剔除，不影响其余。

---

## 四、分阶段实施

> 原则：先做**低成本、纯增量、强化诊断核心**的项；推翻型改动集中在中段；高成本扩展（双人）置于末期。每阶段标 **验收点**。

### Phase 1 · 诊断核心强化（纯增量，不碰已实现交互）
**目标**：在不推翻任何现有逻辑的前提下，先把"信息验证"与"专注投入"两个核心爽点补强。

- **T1.1 仪表趋势图（#4）**
  - 现 `LogPanel` 仅文本快照。扩展为**复盘曲线**：每轮提交时 `GameState.add_log` 已记录 `gauges` 快照，新增按仪表绘制折线（`Control._draw` 或 `Line2D`），识别渐变 vs 突发故障。
  - 新增"呼出上一轮快照"按钮（不要求记数值）。
  - 文件：`scripts/ui/LogPanel.gd`、`LogPanel.tscn`。
  - 验收：完成 ≥2 轮后，复盘面板可见各仪表跨轮折线，渐变故障趋势可读。

- **T1.2 噪声改为规律周期波动（#4）**
  - 现 `ControlRoom._setup_noise` 用 `randf_range` 每轮随机一次。改为**确定性低频正弦**：`offset = amp * sin(round * freq + phase[gauge])`，`amp/freq/phase` 入 `difficulty.json`，使玩家可多轮观察识别干扰模式、与真实异常区分。
  - 仅 `chief`/挑战档启用；不引入"付费校准"。
  - 文件：`scripts/ui/ControlRoom.gd`、`data/difficulty.json`。
  - 验收：chief 模式下噪声跨轮呈可识别周期，novice 模式无噪声。

- **T1.3 超额投入奖励（#1）**
  - 同一部位本轮投入超阈值 `bonus_threshold` → **仅影响下一轮**：该部位关联根因基础故障强度 ×(1−`bonus_relief`)，且对应仪表附"✓稳定确认"角标。不跨轮累积、不记账。
  - `GameState` 增 `last_round_bonus: Dictionary`（part→bool），`start_round` 时结算并清零。`FaultTree.metric_offsets`/`gauge_reading` 读该减免。
  - 文件：`GameState.gd`、`FaultTree.gd`、`balance.json`、`ControlRoom.gd`、`Gauge.gd`。
  - 验收：对磁体超额投入后，下一轮磁体故障强度可见降低 + 仪表显示稳定确认。

- **T1.4 行为成就系统（#8）**
  - 现成就=结局键。新增 `data/achievements.json`（id/名称/描述/触发条件类型）。`SaveManager` 增**条件型成就**评估；`GameState` 累计判定所需信号（如"某专家零采信通关""稳定度跌破阈值后回升""总经费<80%通关""识破完整故障链"）。
  - 结局结算时统一评估并解锁，`EndingPanel` 展示本局新解成就。
  - 文件：`data/achievements.json`、`SaveManager.gd`、`GameState.gd`、`scripts/ui/EndingPanel.gd`。
  - 验收：满足"预算狂人"等条件通关 → 结局页弹出对应成就。

- **T1.5 逻辑一致性检测（#10）**
  - 提交前检测"分配方向与诊断方向明显矛盾"（仪表强烈指向某根因部位、玩家却零投入且重投他处）→ 锁定/提交前温和提示，**不评判对错**，可继续。
  - 文件：`ControlRoom.gd`（提交前钩子）、阈值入 `balance.json`。
  - 验收：构造矛盾分配 → 提交前出现一次性温和确认提示。

**Phase 1 验收里程碑（M1）**：诊断核心四件套（趋势/周期噪声/专注奖励/行为成就）上线，旧交互零回归。

---

### Phase 2 · 信息系统重构（含推翻项，依赖决策 A/C）
**目标**：把"信息粒度博弈"与"内生后果"做实，这是 `new.md` 的灵魂。**需决策 A、C 确认后开工。**

- **T2.1 专家信任度系统（#3，依赖决策 A）**
  - `GameState` 增 `expert_trust: Dictionary`（expert→0..1，初值中性）。变化规则：分配与某专家陈述一致→其信任 +；完全无视其警告→ −。
  - 重写 `BriefingSystem`：**移除说谎逻辑**，改为按信任度选择简报"区间精度"——高信任=窄区间+确定语气，低信任=宽区间+模糊措辞。`briefings.json` 每条改为 `{precise, vague, value_hint}` 多粒度版本。
  - **专家信息差**：每专家只精确掌握自身部位，对他部位仅间接推断（数据中标 `direct/indirect`）。
  - 低信任→其负责仪表叠加"有规律抖动"（接 T1.2 周期波动通道，幅度随信任反比）。
  - 文件：`BriefingSystem.gd`、`GameState.gd`、`experts.json`、`briefings.json`、`ControlRoom.gd`（信任度 UI + 抖动）。
  - 同步：修订 `Claude.md` 专家段落（隐瞒/夸大 → 信任度精度）。
  - 验收：连续采信某专家 → 其简报区间收窄、仪表趋稳；无视警告 → 简报转模糊、仪表抖动加剧。

- **T2.2 深度诊断＝趋势报告（#3）**
  - 消耗少量经费，让某专家给出其部位**近三轮历史趋势图 + 专家解读**（不直接判定真假）。
  - 文件：`ControlRoom.gd`（购买入口）、`LogPanel`/复盘复用 T1.1 曲线、`balance.json`（费用）。
  - 验收：付费后弹出该部位三轮趋势 + 一句专家解读，经费相应扣减。

- **T2.3 故障链耦合可读化（#2）**
  - `faults.json` 新增 `fault_chains`：每链含触发轮(≥3)、主因→次因、**可区分仪表特征**（如"磁体电流波动 且 壁温周期尖峰与之同步")、专家线索（双方各自抱怨但不主动关联）。
  - `FaultTree` 增链激活判定与"次因偏移随主因强度联动"；`ControlRoom` 在仪表上以同步标记呈现关联模式。**不做全连接耦合**，每链一种可识别模式。
  - 验收：第3轮后出现一组故障链，交叉比对仪表可发现主次关联，处理优先级影响结算。

- **T2.4 内生后果与挑战模式拆分（#6，依赖决策 C）**
  - `GameState` 增 `stability_history`、`irreversible_damage: Dictionary`（part→level）。规则：稳定度连续两轮下降→"约束退化"警告；某部位严重投入不足累计→"不可逆损伤"标记，抬高后续轮该部位故障强度。
  - `difficulty.json` 重构：标准档（无限时、内生后果）/ 挑战档（破裂倒计时、经费审计风暴，单独计分）。限时代码保留，仅挑战档启用。
  - 文件：`GameState.gd`、`FaultTree.gd`、`difficulty.json`、`ControlRoom.gd`。
  - 验收：标准档零倒计时；连续误判触发退化警告；不可逆损伤后续轮可见恶化；挑战档限时如常。

**Phase 2 验收里程碑（M2）**：专家从"测谎对象"变为"信息源博弈"，压力从外部计时转为内生后果，故障具备可推理的耦合层次。

---

### Phase 3 · 交互范式与可重玩（含推翻项，依赖决策 B）
**目标**：收束决策手感，提升重玩价值。

- **T3.1 锁定预览取代实时试探（#5，依赖决策 B）**
  - 移除 `_on_hover_preview` 假想增量预测与 `DropZone.hover_preview` 试探用法；保留"已投入即时效果回显"。
  - 新增"锁定方案"按钮 → 一次性预览（等离子体颜色、稳定度趋势、各部位参数升降箭头），短倒计时（≤10s，参数化）逾期自动确认；预览期不可再调。
  - 删除分配中实时仪表跳动、中期检查。
  - 文件：`ControlRoom.gd`、`DropZone.gd`、`FusionEngine.gd`（保留 `predict`，弃用 `predict_with_extra` 的悬停调用）。
  - 验收：拖放期无预测试探；点锁定后出现一次预览+倒计时，逾期自动提交。

- **T3.2 手作剧本随机（#7）**
  - 新增 `data/scenarios.json`：5~6 套，每套含 3 根因内部逻辑、专家立场分配（谁模糊/谁精确）、专属台词集与仪表初始偏移、1~2 组耦合链。
  - `DataManager` 加载 `scenarios`；`GameState.reset` 随机抽取一套（专家**人设固定、角色由剧本驱动**）；`faults/briefings` 取数改为"当前剧本优先，缺省回退基础表"。
  - **隐藏结局**：由系统状态自然触发（如某部位连续零投入后爆裂意外触发新约束构型），`EndingResolver` 增隐藏键。
  - 文件：`data/scenarios.json`、`DataManager.gd`、`GameState.gd`、`FaultTree.gd`、`BriefingSystem.gd`、`EndingResolver.gd`。
  - 验收：连开两局剧本不同（台词/立场/链不同）；满足隐藏条件触发专属结局。

- **T3.3 复盘三图 + 教学模式（#10、#9）**
  - 复盘面板（扩展或新建）展示三图：分配比例图、实际故障强度变化图、关键仪表趋势曲线，**无"最优方案"标注**，纯视觉对比教学。
  - 教学战役（可选）：三章渐进解锁（2专家2部位→3→全系统），脚本化引导；标准模式开局全开放 + T1.5 智能引导。`MainMenu` 增模式入口，`GameState` 增子系统解锁门控。
  - 文件：复盘面板（`LogPanel.tscn`/新 `ReviewPanel`）、`MainMenu.gd`、`GameState.gd`、`ControlRoom.gd`、教学脚本数据。
  - 验收：结算后可调出三图对比；教学战役按章逐步开放系统；标准模式直接全开放。

**Phase 3 验收里程碑（M3）**：决策不可反复试探、每局剧本新鲜、教学与复盘闭环。

---

### Phase 4 · 扩展与减法（末期，可裁剪）

- **T4.1 本地双人合作（#11）**：单设备分屏，P1/P2 各看部分仪表与专家简报，口头交流拼合，共同决定分配；**无背叛、无隐藏计分**。高成本，独立场景，置于最后，资源不足可砍。
- **T4.2 沙盒降级（#12）**：**不开发独立沙盒**。将参数调试/故障模拟封装为开发期内部工具（`debug` flag 控制，不进正式导出包），抢先体验阶段向核心社区开放收集反馈。

---

## 五、数据 Schema 变更汇总

**新增文件**
- `data/scenarios.json`（#7）：剧本数组，每套 `{id, root_logic, expert_roles, briefings_override, gauge_offset, chains}`。
- `data/achievements.json`（#8）：`{id, name, desc, condition:{type, params}}`。

**修改文件**
- `difficulty.json`：拆 标准/挑战 两类档；噪声改 `{amp, freq, phase}` 周期参数（替换单一 `gauge_noise`）；限时仅挑战档。
- `balance.json`：新增 `over_invest`（`bonus_threshold`/`bonus_relief`）、`deep_diagnose_cost`、`consistency_check` 阈值、`irreversible_damage` 参数。
- `faults.json`：新增 `fault_chains` 段（主次因 + 同步特征）。
- `experts.json`：每专家增 `info_scope`（direct/indirect 部位）、移除/降级 `hide_signal`/`exaggerate_signal`（决策 A 后）。
- `briefings.json`：每条由单 `spin` 改为多粒度 `{precise, vague, value_hint}`（决策 A 后）。
- `endings.json`：增隐藏结局键（#7）。

**校验**：`DataManager._validate` 同步新增剧本/成就/链的结构校验，缺字段明确报错（沿用现有 `_require_*` 风格）。

---

## 六、风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| 决策 A/B/C 未确认即开工 | 高（返工） | Phase 2/3 开工前必须拍板第三节三项；未定则只做 Phase 1 |
| 信任度系统使难度失衡 | 高 | 信任度→精度映射全入 `balance.json`，留调参；保 `legacy` 隐瞒模式回退 |
| 剧本化与现有单故障树取数耦合 | 中 | `scenarios` 走"覆盖+回退基础表"，缺省即等价 V3.0，向下兼容 |
| 锁定预览砍掉手感 | 中 | 分两步：先保即时效果回显，再叠锁定预览，灰度切换 |
| 趋势图/复盘绘制 HTML5 性能 | 中 | 用轻量 `_draw`/`Line2D`，点数上限可配，D 前 Web 抽测 |
| 双人模式成本挤压核心 | 中 | 置 Phase 4 且标"可裁剪"，核心优化不依赖它 |
| 误引入网络依赖 | 红线 | 导出前静态扫描 `HTTPRequest/WebSocket/http`，沿用现有 CI 兜底 |
| `Claude.md` 描述与新机制脱节 | 低 | 决策 A 落地时同步修订项目文档专家段落 |

---

## 七、落地顺序建议（立即可执行）

1. **先确认第三节决策 A/B/C**（采纳/否决/默认），确定 Phase 2/3 范围。
2. **直接开工 Phase 1**（T1.1→T1.5，纯增量、零推翻、不阻塞决策）：先上趋势图与周期噪声，立即强化"仪表验证者"地位。
3. 决策确认后进入 Phase 2（信息系统重构），再 Phase 3（交互范式 + 剧本）。
4. Phase 4 视余量决定是否纳入。

> 关键路径：`决策确认 → BriefingSystem 重构(T2.1) → scenarios 数据架构(T3.2) → 锁定预览(T3.1)`。
> 其中 **T2.1 信任度模型**是最大不确定点，需先冻结"信任度→精度"映射接口，再铺数据。

*本文件随项目推进持续更新；与 `new.md`（方案）、`Claude.md`（约束）配套阅读。*
