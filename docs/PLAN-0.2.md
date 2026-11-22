# Galatea v0.2 改造规划

> 状态：**待确认后开工** · 目标形态：横屏 · 明日方舟 ×《来自星尘》视觉 · 脚本即方块 · 支线折叠 · 完成度标记 · MCP 接入 · 兼容 3 按钮导航

---

## 0. 需求映射

| # | 你的要求 | 落地方案 | 影响面 |
|---|----------|----------|--------|
| 1 | 改成横屏 | 锁定 landscape；三栏布局（工具条 / 画布 / 属性面板） | Flutter · Web |
| 2 | 不要现在这种风格，参照明日方舟，多参考《来自星尘》 | 整套 design token 重构（色板 / 字体 / 切角 / 细线 / 字距 / 动效） | Flutter · Web |
| 3 | 脚本也作为方块连线 | `script` 节点升级为「代码方块」：入口函数、`next` 端口、emit 通道、代码预览 | 三端 + schema |
| 4 | 支线折叠 | `groups` 数据模型 + 折叠块（显示内部节点数 / 完成度 / 块间连线） | 三端 + schema |
| 5 | 标记完成与否，默认未完成/收尾 | `node.status = todo \| wip \| done`，默认 `todo`；角标 + 筛选 + 进度环 + lint 汇总 | 三端 + schema |
| 6 | 增加 MCP 接口让 AI 接入 | 新增 `galatea-mcp` 二进制（stdio JSON-RPC 2.0），12 个工具 | Rust |
| 7 | 3 按钮导航没适配 | 系统栏/刘海安全区适配 + 安全区调试开关 | Flutter · Web |

---

## 1. 设计语言：Arknights × Ex Astris

依据来源（已核对，非猜测）：

- **YunYouJun/ak-ui**（`UI Tokens for Arknights`）的 `src/scss/_tokens.scss`
- **ak-ui 官方站点 CSS 实测采样**：`research/official-site/2026-09-15.json`
- 明日方舟官网 `<https://ak.hypergryph.com/>` 真实样式声明
- 《来自星尘》视觉特征（深空、轨道线、大留白、冷蓝紫 + 暖金、克制动效）

### 1.1 色板（直接采用 ak-ui token）

| Token | 值 | 用途 |
|---|---|---|
| `canvas` | `#111315` | 全局底（比现在的 `#0E1117` 更冷更黑） |
| `surface.panel` | `rgba(253,253,251,.92)` | **米白纸面板**（方舟标志：白面板承载信息） |
| `surface.muted` | `rgba(235,236,235,.92)` | 次级面板 |
| `surface.raised` | `rgba(66,66,66,.92)` | 浮起层（`#585858` 悬停态） |
| `text.primary` | `#F8F8F5` | 暖白（不是纯白） |
| `text.secondary` | `#D2D2D2` → 68% | 正文/说明 |
| `signal.info` | `#19D1FF` | **青蓝**：导航激活、连线、选中（官网实测值） |
| `signal.action` | `#F6540E` | 橙红：主操作、danger 邻域 |
| `signal.accent` | `#F1C644` | 暖金：强调、星级、来自星尘点缀 |
| `signal.success` | `#46C47C` | 已完成状态 |
| `signal.danger` | `#E33B3B` | 错误、断线 |
| `line.hairline` | `1px solid hsla(0,0%,100%,.30)` | **所有分隔线**（官网实测） |
| `line.strong` | `4px` | 强调边（选中框） |

**节点类型色**改用方舟职业色（比现在的糖果色克制得多）：

| 节点 | 色 | 来源 |
|---|---|---|
| 台词 say | `#528CFF` defender 蓝 | 职业色 |
| 选择 choice | `#B58AFF` caster 紫 | 职业色 |
| 条件 branch | `#F5BD38` vanguard 黄 | 职业色 |
| 变量 set | `#68D5BA` medic 薄荷 | 职业色 |
| 脚本 script | `#FF9445` specialist 橙 | 职业色 |
| 子图 call | `#ED91BD` supporter 粉 | 职业色 |
| 结局 end | `#ED5265` guard 红 | 职业色 |
| 跳转 jump / 返回 | `#9C9C9C` low 灰 | token |

### 1.2 字体（方舟的双字体系统）

| 用途 | 字体 | 说明 |
|---|---|---|
| 拉丁标题 | **Oswald Medium**（窄体、工业感） | 官网实测就是它；OFL 可内嵌 |
| 中文正文 | 系统思源黑体 / HarmonyOS Sans / MiSans | 官网用 SourceHanSans-Medium |
| 数字与代码 | **JetBrains Mono**（替代 Bender，OFL 安全） | 官网日期用 Bender-Regular，授权不明，换 OFL 等价物 |
| 字距 | 标题 `2px`、日期/数据 `1px`、小标签 `+0.12em`、大标题 `-0.04em` | 官网实测 |
| 字号 | display `clamp(36px,5vw,72px)` · title `48px` · label `12px` · data `16px` | ak-ui token |
| 行高 | 列表行 `96px`（6rem，极松） | 官网实测 |

### 1.3 几何

- **右上 45° 切角**（方舟灵魂）：`clip-path: polygon(0 0, calc(100% - .75rem) 0, 100% .75rem, 100% 100%, 0 100%)`
- 圆角几乎为 0（`2px`），**不用大圆角**
- 阴影几乎不用；改用 1px 细线 + 半透明色块表达层级
- 3D 保留但收敛：`perspective: 30em`（ak-ui 的 `--ak-depth-perspective`），卡片只在选中/入场时轻微倾斜，不持续晃

### 1.4 来自星尘的补充（"星图感"）

- 背景：深空 + 极淡同心圆轨道（1px，6% 白）+ 点阵网格
- 连线：细线 + 端点小圆点（1px + 3px 圆点），不用粗箭头
- 留白：画布四周 ≥ 48px 保护带；信息密度降低，字号层级拉开
- 点缀：暖金 `#F1C644` 只用于「进度/星级/结局」，面积 < 5%
- 动效：缓慢漂浮（6-12s 周期）、呼吸光晕；交互反馈仍用 lilt 弹簧

### 1.5 动效规范

| 场景 | 手段 | 参数 |
|---|---|---|
| 按钮/卡片按下 | lilt 弹簧 `Interactive` | response 0.14 / damping 1.0 |
| 面板/页面转场 | `cubic-bezier(0.2, 0, 0, 1)` | fast 120ms / base 200ms / slow 420ms |
| 列表项进入 | lilt 弹簧 `Bouncy` | 55ms stagger |
| 折叠/展开 | lilt 弹簧 `Smooth` | 高度 + 透明度同时驱动 |
| 背景轨道 | 线性慢漂 | 6-12s，`sin` 采样 |

> 结论：**交互用弹簧，转场用 bezier**。lilt 质感保留，但大面积界面的移动改用短时长曲线，避免方舟式界面出现"橡皮糖感"。

---

## 2. 横屏布局

```
┌──────────────────────────────────────────────────────────────┐
│ ▍GALATEA  《雨声与自动门》        ✓体检  ▶试玩  ⋯        ● 已存 │ 44dp
├──┬────────────────────────────────────────────────┬──────────┤
│▣ │                                                │ 属性面板  │
│⚙ │              画布（思维导图 + 星图背景）          │ 320dp   │
│🔀│                                                │ 可折叠    │
│❓ │        ┌──────┐        ┌──────┐               │          │
│🎚 │        │ 台词 │───────▶│ 选择 │               │ 台词     │
│📦 │        └──────┘        └──────┘               │ [....]   │
│🎬 │                                                │ 说话人   │
│  │                                                │ [雪 ▾]   │
├──┴────────────────────────────────────────────────┴──────────┤
│ 过滤: 全部 · 未完成 12 · 收尾 3 · 已完成 25   进度 ●●●●○○ 62%  │ 32dp
└──────────────────────────────────────────────────────────────┘
     ↑ 左工具条 56dp                ↑ 底部状态条 = 3 按钮导航的避让区
```

- 禁用竖屏：`SystemChrome.setPreferredOrientations([landscapeLeft, landscapeRight])`
- 小屏（< 640dp 宽）：自动收起属性面板，改为底部抽屉
- 播放器：16:9 舞台，立绘右侧 2/3 高，对话框横跨底部（高度 30%），选项在对话框上方居中

---

## 3. 系统栏适配（3 按钮导航）

现状问题：底部 48dp 被系统导航栏覆盖，工具条按钮点不到。

方案：

1. **读取真实安全区**：`MediaQuery.of(context).viewPadding`（不是 `padding`，避免键盘弹出时抖动）
2. **所有贴边容器**统一走 `SafeArea(bottom: true, left: true, right: true)`，并在自绘布局里手动加
   `EdgeInsets.only(bottom: viewPadding.bottom, left: viewPadding.left, right: viewPadding.right)`
3. **Android 侧**：
   - `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` + 透明状态栏
   - `android:windowSoftInputMode="adjustResize"`
   - 3 按钮导航栏高度按 `viewPadding.bottom`（典型 48dp）自动避让，不写死
4. **Web 侧**：`padding-bottom: env(safe-area-inset-bottom)`
5. **新增「安全区调试」开关**（⋯ 菜单）：把 `viewPadding` 用青蓝色半透明条画出来，方便你在真机上核对
6. CI 加一条 `flutter analyze` + 单元测试验证 `SafeAreaInsets` 计算函数（纯函数，可测）

---

## 4. 脚本方块

`script` 节点从"小卡片"升级为**代码方块**：

```
┌───────────────────────────┐
│⚙ SCRIPT          scripts/intro.rs │  ← 右上切角
│ entry: opening()          │
│───────────────────────────│
│ 1  fn opening() {         │  ← 等宽字体，只读预览 2 行
│ 2    set("看过开场", true) │
│───────────────────────────│
│  emit: bgm · cameraY · beat│  ← emit 通道标签
│  ⏱ 0.8s                   │
└───────────────────────────┘
       ○ enter    ○ next
```

- 双击方块 → 全屏只读代码（行号 + 关键字高亮）
- 端口：`enter`（可选，被 call 时用）、`next`
- emit 通道作为**小标签**列出，播放器按通道消费
- 校验：`src` 文件不存在 / `entry` 函数不存在 → lint 报错（Rust 侧已能检测）

---

## 5. 支线折叠

```json
"groups": [
  { "id": "g1", "title": "雨夜相遇", "color": "#19D1FF",
    "collapsed": false, "nodes": ["n1","n2","n3"], "x": 0, "y": 0, "w": 640, "h": 480 }
]
```

- **框选**：长按空白拖框 → 选中多个节点 → 「折叠成支线」
- 折叠后：显示一个 `▣ 雨夜相遇 · 3 节点 · 2/3 完成` 的块，块间连线保留（连到块边框）
- 展开：点击块上的 `▸`
- 嵌套：**只支持一层**（v0.2 不做嵌套，避免布局爆炸）
- 删除块 ≠ 删除节点；块只是视图

---

## 6. 完成状态

```json
{ "id": "n3", "status": "todo" }
```

| 状态 | 显示 | 含义 |
|---|---|---|
| `todo`（默认） | 左上角空心小方块 `□` 灰 | 还没写完 / 占位 |
| `wip` | 半填充 `◧` 黄 | 收尾中（有内容但要打磨） |
| `done` | 实心 `■` + 勾 青 | 已完成、可交付 |

- 新建节点默认 `todo`
- 顶部/底部过滤条：`全部 / 未完成 / 收尾 / 已完成`
- 进度环：`已完成 / 总数`（方舟式细环 + 中心数字）
- 框选批量改状态
- lint 汇总：`还有 12 个节点未完成`（warning 级，不阻塞导出）
- 导出时可选「只导出已完成节点」（做 demo 切片用）

---

## 7. MCP 接口

新增二进制 `galatea-mcp`：**stdio JSON-RPC 2.0**，实现 MCP 规范（`initialize` / `tools/list` / `tools/call`），零依赖（与引擎同风格）。

| 工具 | 作用 |
|---|---|
| `story_open` | 打开/新建剧本文件 |
| `story_save` | 保存（自动 fmt） |
| `story_graph` | 读全图：节点（含 status）、连线、分组、统计 |
| `node_add` | 加节点（类型 / 位置 / 字段 / 自动连线到选中节点） |
| `node_update` | 改任意字段（text / speaker / cond / effects…） |
| `node_delete` | 删节点（自动剪线） |
| `node_connect` | 连一条边（from + port + to） |
| `node_disconnect` | 断一条边 |
| `node_set_status` | 批量设 todo/wip/done |
| `group_create` / `group_fold` | 建/折叠支线 |
| `story_lint` | 返回问题列表（error/warning/info） |
| `story_simulate` | 从入口跑到某节点，给定选择序列，返回事件流 |
| `script_run` | 跑脚本函数（含 `--sample` 曲线） |

**AI 的典型工作流**（这就是"让 AI 接入"的价值）：

```
story_graph → 看到 40 个节点、12 个 todo
  → node_add 加 5 个台词节点
  → node_connect 串起来
  → story_lint 自检
  → story_simulate 跑通主线
  → node_set_status 标 done
```

测试：`tests/mcp_*.rs`，用 JSON 行喂 stdin，断言 stdout JSON；CI 里跑。

---

## 8. 交付节奏

| 里程碑 | 内容 | 预估 |
|---|---|---|
| **M1 视觉与横屏** | token 重构（色板/字体/切角/细线）、横屏三栏、系统栏适配、安全区调试 | 1 轮 |
| **M2 图上的信息** | 脚本方块、完成状态、支线折叠、过滤与进度 | 1 轮 |
| **M3 MCP** | `galatea-mcp` + 12 工具 + 集成测试 + README 章节 | 1 轮 |
| **M4 收尾** | Web 版同步新风格、APK 重新打包、文档/截图 | 1 轮 |

## 9. 验收标准

- [ ] 真机（3 按钮导航）横屏下，底部过滤条与工具条**完整可点**，无遮挡
- [ ] 视觉对照 ak-ui token：米白面板、青蓝信号色、45° 切角、1px 细线、Oswald 标题
- [ ] `script` 节点可连线、可预览、可报错
- [ ] 支线可折叠/展开，块间连线正确
- [ ] 每个节点有 status，默认 todo，过滤与进度正确
- [ ] MCP：`initialize` / `tools/list` / 12 个 `tools/call` 全部有测试
- [ ] CI 三端绿 + APK 构建成功

## 10. 风险

| 风险 | 应对 |
|---|---|
| Bender 字体授权不明 | 换 JetBrains Mono（OFL） |
| 思源黑体体积大（10MB+） | 不内嵌中文，走系统字体 fallback |
| 横屏小屏画布窄 | 属性面板可折叠 + 画布全览快捷键 |
| 折叠组让连线变乱 | v0.2 只做单层折叠，块间连线走边框锚点 |
| 大改容易一次崩 | 每里程碑独立 commit，CI 必须绿才进下一个 |

---

**下一步**：你确认后我从 M1 开始（视觉 token + 横屏 + 3 按钮避让），一轮内交出可装机的 APK。