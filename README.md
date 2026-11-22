<div align="center">

# Galatea

**思维导图式 Galgame 引擎**

剧情是一张图 · 连线即分支 · 一键打包成游戏

Rust 核心 + Flutter 编辑器，把整部视觉小说当作一张可拖拽、可体检、可试玩的思维导图。写剧情就像画流程图：台词、选择、条件、变量都是节点，从卡片右侧拖一条线出去，故事就往那边生长。作者在编辑器里点「试玩」用的运行时，和玩家拿到的游戏包里的运行时，是同一个。

[简体中文](README.md)

![Galatea](https://img.shields.io/badge/Galatea-0.1.0-blue?style=for-the-badge&logo=rust&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Web%20%7C%20Windows%20%7C%20Linux%20%7C%20macOS-green?style=for-the-badge)
![License](https://img.shields.io/badge/License-GPL%203.0-red?style=for-the-badge)
![Rust](https://img.shields.io/badge/Rust-1.75%2B-blue?style=for-the-badge&logo=rust)
![Flutter](https://img.shields.io/badge/Flutter-3.22%2B-blue?style=for-the-badge&logo=flutter)

[![Stars](https://img.shields.io/github/stars/QcxFlora/galatea?style=social)](https://github.com/QcxFlora/galatea)
[![Forks](https://img.shields.io/github/forks/QcxFlora/galatea?style=social)](https://github.com/QcxFlora/galatea)
[![Issues](https://img.shields.io/github/issues/QcxFlora/galatea)](https://github.com/QcxFlora/galatea/issues)
[![CI](https://github.com/QcxFlora/galatea/actions/workflows/ci.yml/badge.svg)](https://github.com/QcxFlora/galatea/actions/workflows/ci.yml)

**动画手感致敬 [chhongzh/lilt](https://github.com/chhongzh/lilt) —— 所有会动的东西都由阻尼弹簧驱动。**

</div>

---

**许可证** · 采用 [GPL-3.0-or-later](LICENSE)。引擎本体、编辑器、以及用本引擎打包出来的游戏均为同一份感染性协议，修改就要开源。

---

## 更新日志

| 日期 | 版本 | 内容 |
|------|------|------|
| ✨ 2026-11-22 | 0.1.0 | 初始版本：`galatea-core` 引擎核心（JSON / 表达式 / 剧情图 / VM / lint / CLI，19 个单元测试全绿）；示例剧本《雨声与自动门》上线；Flutter 端模型层与 VM 的 Dart 实现 |
| 🌐 2026-11-22 | 0.1.0 | **Web 先行版**上线（`web/index.html` 单文件，含 lilt 弹簧动画 + 扁平 3D 首界面 + 思维导图编辑器 + 播放器，37 项逻辑测试通过，手机浏览器可玩） |
| 🧭 计划 | — | 自定义 Rust 脚本宿主、`galatea pack` 打包器、Flutter 桌面端 |

---

## 目录

1. [快速开始](#快速开始)
2. [理念](#理念)
3. [编辑器 · Studio](#编辑器--studio)
4. [播放器 · Player](#播放器--player)
5. [引擎核心 · galatea-core](#引擎核心--galatea-core)
6. [剧本体检 · lint](#剧本体检--lint)
7. [动画系统 · lilt 手感](#动画系统--lilt-手感)
8. [自定义 Rust 脚本](#自定义-rust-脚本)
9. [扁平化 3D](#扁平化-3d)
10. [后端架构](#后端架构)
11. [可选配置](#可选配置)
12. [剧本格式速查](#剧本格式速查)
13. [故障排除](#故障排除)
14. [贡献](#贡献)

---

## 快速开始

### 环境要求

- Rust 1.75+（`rustup` 安装即可，无第三方依赖）
- 可选：Flutter 3.22+（编辑器 GUI）

### 三分钟跑起来

```bash
git clone https://github.com/QcxFlora/galatea.git
cd galatea

# 生成一个模板剧本
cargo run -p galatea-core --bin galatea -- new 我的剧本.json

# 终端里直接试玩（回车继续 / 数字选择 / u 撤销 / s 存档）
cargo run -p galatea-core --bin galatea -- play 我的剧本.json

# 体检：断线、孤岛、走不到结局、未定义变量
cargo run -p galatea-core --bin galatea -- lint 我的剧本.json

# 统计：节点 / 字数 / 结局数 / 主线覆盖率
cargo run -p galatea-core --bin galatea -- stat 我的剧本.json
```

打开 `samples/rain.json` 可以立刻试玩示例《雨声与自动门》（20 节点 / 3 结局）。

```bash
cargo run -p galatea-core --bin galatea -- play samples/rain.json
```

### 最快体验：Web 先行版（无需安装任何东西）

```bash
# 本地起个静态服务（直接双击 file:// 打开也行，但 localStorage 会被部分浏览器限制）
cd web && python3 -m http.server 8000
# 浏览器打开 http://localhost:8000 —— 手机上也能玩
```

`web/index.html` 是一个 87KB 的单文件：内置 lilt 式弹簧动画引擎、扁平 3D 首界面、
完整的思维导图编辑器（拖节点 / 拉线连线 / 属性面板 / 实时体检 / 自动布局 / localStorage 自动保存）
和播放器（打字机 / 变量插值 / 撤销 / 存读档 / 回想 / 自动模式）。核心逻辑（表达式 / VM / lint）
与 Rust 版同构，`node web/test_logic.js` 跑 37 项对齐测试。

### Flutter 端

```bash
cd app
flutter pub get
flutter run          # 桌面；flutter run -d chrome 跑 Web 版
```

---

## 理念

| # | 原则 | 说明 |
|---|------|------|
| 1 | **一切皆节点** | 台词、选择、条件、变量、跳转、子图、结局，都是图上的一个卡片。整个作品可以被当成一张流程图通盘审视 |
| 2 | **连线即分支** | 拖一条线就是一条剧情边。端口有类型：`next` / `yes·no` / `opt1..n` / `to·back` |
| 3 | **同一份图，两种跑法** | 编辑器「试玩」和导出后的游戏共用同一个 VM，不存在「编辑器里好好的，打包后错了」 |
| 4 | **零依赖核心** | JSON、表达式解析、lint 全部手写，交叉编译到 Android / iOS / 桌面 / wasm 不受依赖树拖累 |
| 5 | **感染性自由** | GPL-3.0-or-later。你用 Galatea 做的游戏，连同你的修改，都保持开源 |

---

## 编辑器 · Studio

从画布底部的工具条长出节点；点卡片选中；从右侧端口圆点**按住拖到目标节点**松手即连线，拖到空白处松手即断线。

| 能力 | 说明 |
|------|------|
| 思维导图画布 | 双指缩放、单指平移、节点拖拽、全览一键适配 |
| 节点生长 | 在选中节点旁新建时自动接上一条空闲端口，像思维导图一样「长」出来 |
| 属性面板 | 台词、说话人、条件、变量效果、选项（条件 / 一次性 / 效果）全部就地编辑 |
| 体检栏 | 底部实时显示 错误/警告/提示 计数，点开可跳转到出问题的节点 |
| 自动布局 | 从入口做深度优先，兄弟横向排开、孤岛集中收纳 |
| 试玩 | 随时切到播放器全流程试玩，再切回来改图 |
| 自动保存 | 700ms 防抖写入 `.gala.json`，AppBar 上有保存状态指示 |
| 导入导出 | 剧本即纯 JSON，复制到剪贴板即可分享 |

---

## 播放器 · Player

| 能力 | 说明 |
|------|------|
| 逐字演出 | 打字机式台词，点一下跳到全文 |
| `{变量}` 插值 | 台词里写 `{好感}`，播放时替换成当前值 |
| 选项分支 | 条件不满足的选项自动隐藏；`once` 选项选过后消失 |
| 撤销 | 回退到上一个停顿点（台词/选择），变量状态一并回滚 |
| 存档 / 读档 | 存档是 JSON 快照，含变量、调用栈、已见节点 |
| 回想 | 已读台词历史一览 |
| 自动模式 | 1.4s 自动推进 |
| 结局卡 | 结局代号 + 文本 + 本次路线覆盖率（`14/20`） |

---

## 引擎核心 · galatea-core

```
crates/galatea-core/
├── src/json.rs    极小 JSON（解析/紧凑/美化序列化，含代理对、错误定位）
├── src/expr.rs    表达式语言（支持中文变量名、「中文引号」字符串）
├── src/graph.rs   剧情图模型 + 端口编辑 + JSON 双向
├── src/vm.rs      解释器（快照撤销 / 存档 / 防死循环 / 防递归爆栈）
├── src/lint.rs    剧本体检
└── src/bin/galatea.rs   CLI：new / play / lint / fmt / stat
```

**表达式语言**（优先级：`||` → `&&` → 比较 → `+ -` → `* / %` → 一元）：

```
aff >= 3 && met_yuki          好感度数值比较
!flags.seen                   点号路径 + 取反
"你好，" + name                 字符串拼接
好感 + 1 * 2 == 7              中文变量名、正常运算优先级
```

**八种节点：**

| 类型 | 卡片色 | 端口 | 语义 |
|------|--------|------|------|
| 💬 say | 蓝 | `next` | 一句台词 / 旁白，可带 bg、立绘 |
| 🔀 choice | 紫 | `opt1..n` | 选项，每个选项可带条件、一次性、效果 |
| ❓ branch | 黄 | `yes` / `no` | 条件二分 |
| 🎚️ set | 绿 | `next` | 改一组变量后继续 |
| ↪️ jump | 灰 | `to` | 无条件跳转（跨远距离连线，免得线绕成一团） |
| 📦 call | 青 | `to` / `back` | 进子图，执行完返回（剧情组件化） |
| ↩️ return | 灰 | — | 从子图返回 |
| 🎬 end | 红 | — | 结局 |

**安全护栏**（都在 VM 里，不是 lint 建议）：连续 4096 个自动节点判死循环停机；子图嵌套 64 层判递归停机；撤销快照最多 256 张。

---

## 剧本体检 · lint

编辑器底部实时运行，CLI 里 `galatea lint` 同一份代码，CI 可直接调用（有错误退出码 1）。

| 类别 | 检查 |
|------|------|
| 结构错误 | 入口缺失/不存在、连线指向不存在的节点、id 重复、空选项 |
| 断头路 | 台词没有 next、分支缺一边、选项没有目标 |
| 死代码 | 从入口走不到的孤岛节点 |
| 状态错误 | 使用从未赋值的变量、表达式语法错误 |
| 剧情完整性 | 从入口走不到任何结局 |

---

## 动画系统 · lilt 手感

Galatea 的一切动效采用 [chhongzh/lilt](https://github.com/chhongzh/lilt) 的动画哲学：**不用缓动曲线，全部由阻尼弹簧驱动**（半隐式欧拉积分、1/240s 子步、帧率无关）。

| 预设 | Response | Damping | 用在 |
|------|----------|---------|------|
| `Smooth` | 0.39 | 0.85 | 页面 / 弹层进出 |
| `Snappy` | 0.31 | 0.80 | 滚动条、长按进度 |
| `Bouncy` | 0.25 | 0.45 | 勾选、失败抖动（`Kick`/`Bump`） |
| `Interactive` | 0.14 | 1.00 | 跟手元素，不过冲 |

落地形态：画布上节点卡片被拖动时邻居连线像弹簧一样牵动；选中卡片有 Bouncy 呼吸；编辑器切播放器是 Smooth 飞入；选项按钮按下 Interactive 收缩、松手 Bouncy 回弹。越界拖拽使用 `RubberBand`（0.55 系数，与 UIScrollView 相同）。

---

## 自定义 Rust 脚本

剧本 JSON 里的节点效果不只内置算子。`script` 节点可以指向一段随包分发的 Rust 源码，由引擎内置的解释宿主执行，供你自搓动画曲线、首界面演出、小游戏：

```json
{
  "type": "script",
  "src": "scripts/intro.rs",
  "entry": "intro_screen",
  "args": { "title": "雨声与自动门" }
}
```

宿主提供 `springs`（弹簧值）、`camera`（伪 3D 透视）、`tween`、`draw`（扁平几何图形）等沙箱 API。脚本与剧情 VM 共享变量表，因此「播完一段自搓动画再推进剧情」就是一行 `vm.set_pc(next)`。*（本节为设计规格，宿主 API 正在实现，详见 issue #1。）*

---

## 扁平化 3D

视觉走 **flat 3D**：真实透视 + 平涂材质，无贴图、无光照烘焙。画布是一张有深度的舞台——节点卡片按类型分布在不同景深平面（连线在中景、卡片在前、网格在底），视差跟随缩放手势；播放器的立绘以 2.5D 层次进入，对话框浮在最近平面。所有 Z 轴运动同样由弹簧驱动。

---

## 后端架构

```
┌────────────────────────────────────────────────┐
│                  Flutter 层                     │
│                                                │
│  Studio（编辑器）          Player（播放器）     │
│  画布/体检/属性面板         演出/存档/回想       │
└──────────┬─────────────────────────┬───────────┘
           │ 同一份 Story 模型        │
           │                         │
┌──────────▼─────────────────────────▼───────────┐
│              galatea-core (Rust)                │
│  graph.rs 图模型 ── vm.rs 解释器 ── lint.rs 体检 │
│  expr.rs 表达式    json.rs 序列化               │
│                                                │
│  脚本宿主：自搓动画 / 首界面（沙箱 API）        │
└──────────┬─────────────────────────────────────┘
           │
     .gala.json 剧本（人可读、可 git、可分享）
```

### 目录结构

```
galatea/
├── crates/galatea-core/          # 引擎核心（Rust，零依赖）
│   ├── src/json.rs               #   极小 JSON
│   ├── src/expr.rs               #   表达式语言
│   ├── src/graph.rs              #   剧情图模型
│   ├── src/vm.rs                 #   解释器（撤销/存档/护栏）
│   ├── src/lint.rs               #   剧本体检
│   └── src/bin/galatea.rs        #   CLI：new/play/lint/fmt/stat
├── app/                          # Flutter 端（Studio + Player）
│   └── lib/
│       ├── models/graph.dart     #   与 Rust 侧同构的模型
│       ├── engine/               #   expr / vm / lint 的 Dart 版
│       ├── editor/               #   画布 / 属性面板 / 管理弹层
│       └── player/               #   演出 UI
├── samples/rain.json             # 示例剧本《雨声与自动门》
└── docs/                         # 设计文档
```

---

## 可选配置

<details>
<summary><b>角色与变量</b></summary>

剧本 `characters` 段定义说话人（显示名 / 主题色 / 头像路径），`vars` 段定义初始变量。台词节点 `speaker` 填 key；`text` 里的 `{var}` 播放时插值。

```json
{
  "characters": { "yuki": { "name": "雪", "color": "#C3A6FF" } },
  "vars": { "好感": 0, "know": false }
}
```
</details>

<details>
<summary><b>CLI 完整用法</b></summary>

```bash
galatea new  <文件> [标题]   生成最小模板
galatea lint <文件>          体检（有错误时退出码 1，可直接进 CI）
galatea play <文件>          终端试玩
galatea fmt  <文件>          规范化 JSON 格式
galatea stat <文件>          节点/字数/结局/覆盖率统计
```
</details>

<details>
<summary><b>终端试玩操作</b></summary>

回车 = 继续 · 数字 = 选择 · `u` = 撤销 · `s` = 存档到 `save.json` · `l` = 读档 · `q` = 退出
</details>

---

## 剧本格式速查

```json
{
  "format": "galatea.graph/1",
  "meta": { "title": "雨声与自动门", "start": "n_open" },
  "characters": { "xiayu": { "name": "夏雨", "color": "#7aa2f7" } },
  "vars": { "aff": 0 },
  "nodes": [
    { "id": "n_open", "type": "say", "x": 0, "y": 0,
      "text": "雨下得很大。……", "next": "n_choice1" },
    { "id": "n_choice1", "type": "choice", "x": 0, "y": 420,
      "prompt": "怎么办？",
      "options": [
        { "text": "在店里等到雨停", "to": "n_wait",
          "effects": [{ "target": "aff", "op": "add", "expr": "1" }] }
      ] },
    { "id": "n_end", "type": "end", "x": 300, "y": 840,
      "ending": "soaked", "text": "结局 · 落汤鸡" }
  ]
}
```

| 顶层键 | 作用 |
|--------|------|
| `meta` | 标题 / 作者 / 简介 / 版本 / **start 入口节点** |
| `characters` | 说话人表（显示名 / 主题色 / 头像） |
| `vars` | 变量初值表 |
| `nodes` | 节点数组；`x` `y` 是画布坐标 |

---

## 故障排除

| 问题 | 解决方案 |
|------|----------|
| `cargo build` 报找不到 compiler | Rust 需要 1.75+；`rustup update` |
| play 提示「找不到节点」 | 有连线指向已删除的节点；跑 `galatea lint`，会给出具体 id |
| play 提示死循环 | jump/next 绕圈了；lint 的 `unreachable` 也能辅助定位 |
| 撤销没反应 | 撤销最少需要两个停顿点（一句台词 + 一个选择）；刚开场就撤销属于此列 |
| Flutter 端跑不起来 | 先 `flutter pub get`；本仓库的 Flutter CI 在 Actions 上持续验证 |
| Web 版无 localStorage | 用 file:// 直接打开时部分浏览器限制存储；建议本地起 `python3 -m http.server` |

---

## 贡献

欢迎 Issue / Pull Request。动画手感的调参（弹簧预设）特别欢迎实测反馈。

---

## Star History

[![Star History Chart](https://star-history.dera.page/svg?repos=QcxFlora/galatea&type=date&legend=top-left)](https://star-history.dera.page/#QcxFlora/galatea&type=date&legend=top-left)