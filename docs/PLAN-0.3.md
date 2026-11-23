# Galatea 0.3 计划与欠账清单

> 本文件是「开工前先记着」的总账。每项都有验收标准，做完勾掉。
> 状态标记：⬜ 没做 / 🔧 进行中 / ✅ 能用（有验证）/ ❌ 坏了（明确失败）

---

## 一、上一轮遗留（必须先收口）

| # | 事项 | 状态 | 验收标准 |
|---|---|---|---|
| L1 | APK 构建 | 🔧 根因=最新Flutter要Gradle9.3.1与AGP8.x互斥；已固定Flutter3.24.5+AGP8.7.3+Gradle8.9，`bde5fae`验证中 | Release 出现 arm64 包，签名指纹不变，包名 com.galatea.studio |
| L2 | Godot GDScript 运行时真机验证 | ⬜ sandbox 无 Godot SDK | 用 Godot 4.2+ 打开导出工程，F5 能播完 demo.gal |
| L3 | 书柜视觉对照参考图 | ⬜ 见第四节 | 深色卡片浮浅底 + 黑胶囊 + 圆底座 + 线稿图标 |
| L4 | 支线折叠渲染 | ⬜ groups 数据层已通，画布不画合并块 | 折叠组在画布渲染成一个合并方块，可展开 |
| L5 | 完成度标记 | ⬜ 数据层都没有 | 节点 todo/wip/done + 过滤 + 进度统计 |
| L6 | MCP 接口 | ⬜ | galatea-mcp 暴露 12 工具，可被 AI 客户端调用 |
| L7 | Web 版同步 | ⬜ 浅色/3D/新方块未同步 | web/index.html 与 Flutter 端视觉/方块一致 |
| L8 | 编辑器新方块 UI | 🔧 inspector 面板已补，多值端口可视化未做 | 画布上 cast/art/bg/add 多端口可见可拖 |

---

## 二、新需求：图块（image）

**目的**：用一个统一的「图块」承担背景、立绘等一切图片资源的声明职责，
取代分散的 portrait / background。台词靠连线引用图块，资源与流程彻底解耦。

### 数据模型（Rust `NodeKind::Image`）
```rust
Image {
    key: String,          // 资源标识（唯一，供连线/引用）
    path: String,         // 图片相对路径（.webp/.png/.jpg）
    label: Option<String>,// 显示名（可选，画布卡片标题）
    next: Option<String>, // 资源块通常不进流程，但允许串接
}
```

### 语义
- `say.art` / `say.bg` 端口可连向 image 块；VM 解析时取 image 的 `path`。
- 一个 image 块可被多个 say 引用（资源复用，打包只存一份）。
- `portrait` / `background` 保留为 **legacy 兼容**（旧剧本能读），
  新剧本一律用 image；lint 对 legacy 块给 Warning 提示迁移。

### 验收
- ✅ Rust：Image 变体 + 序列化往返 + lint（path 必填、key 唯一）+ 测试
- ✅ VM：say.art/bg 连 image 块能正确解析出 path
- ✅ Dart：NodeType.image + 模型往返 + inspector 面板 + 画布图标
- ⬜ 打包：image 的 path 指向的文件进 .gal，重复引用只存一份

---

## 三、新需求：音频块（audio）

**目的**：顾名思义，管理音频资源与播放（BGM / 音效 / 配音）。

### 数据模型
```rust
Audio {
    key: String,
    path: String,                 // .ogg/.mp3/.wav
    kind: AudioKind,              // Bgm | Sfx | Voice
    looping: bool,                // BGM 默认 true，Sfx/Voice 默认 false
    volume: f64,                  // 0.0..1.0，默认 1.0
    next: Option<String>,
}
enum AudioKind { Bgm, Sfx, Voice }
```

### 语义
- audio 块是**动作块**：流程走到它就发 `Event::Audio { path, kind, looping, volume }`，
  播放器据此播放/切换/停止。
- `say` 增加 `voice` 端口，可连 audio(kind=Voice) 块做台词配音。
- BGM 切换：新的 Bgm audio 块覆盖上一首；looping=false 的播完即止。

### 验收
- ✅ Rust：Audio + AudioKind + 序列化 + lint（path 必填、volume 范围）+ 测试
- ✅ VM：Event::Audio 正确发出，voice 端口解析
- ✅ Dart：NodeType.audio + 模型 + inspector（kind/loop/volume）+ 播放器音频输出
- ⬜ 打包：音频文件进 .gal（已压缩格式原样存，不再 DEFLATE）

---

## 四、新需求：书柜视觉（严格对照《来自星尘》两张参考图）

### 参考图提取的设计 token
**图 1（道具栏）**
- 背景：左上白 → 右下灰蓝渐变 + 噪点颗粒
- 物品：**圆形底座**（细灰圆环）承载 + 右下**黑底白字胶囊**数量 + 左上**青色小标记**
- 左侧竖排**几何线稿图标**栏，每个带青色沙漏标记
- 顶部中央标题带**装饰纹章括号**；右上资源计数黑胶囊
- 底部：花体 logo + 线稿「任务」按钮 + 蓝色立方体选中态 + 白色胶囊

**图 2（记录/书架）**
- 背景：浅灰白 + 噪点 + 右侧淡彩地图纹理
- 顶部：**黑圆底白 X** + 服务器状态 + 中央纹章 logo + 右上编号大字
- 主区：**深色卡片**（墨蓝/蓝紫）浮在浅底上，圆角 ~12
  - 左：白色大标题 + 状态行（云图标 + 小字）
  - 右：**多张图斜切拼贴**
  - 「进入当前最新记录」**黑底白字胶囊**
- 统计条：**细体大数字** + 名称 + 上方小字状态 + **竖线分隔**
- 左下：圆形花体 logo + 手绘箭头「点击展开」

### 当前差距（按严重度）
1. ❌ **卡片是白底浮白底**（参考图是深卡片浮浅底）—— 最致命，等于没对比
2. ❌ 缺黑底白字胶囊（数字/标签）
3. ❌ 缺圆形底座（方块/物品列表）
4. ❌ 缺手绘线稿图标（现在用 Material Icons，太"标准"）
5. ⚠️ 封面是两道色带，不是多图斜切拼贴
6. ⚠️ 统计条缺上方状态行
7. ⚠️ 顶部缺纹章 logo / 编号 / 黑圆底 X
8. ⚠️ 背景缺淡彩纹理层次

### 验收
- ✅ 书柜卡片改深色渐变（#1E2749 → #2A2F5C），白标题 + 浅灰状态行
- ✅ 「最近记录」等标签改黑底白字胶囊
- ✅ 封面改多层斜切拼贴（≥3 层）
- ✅ 统计条：细体大数字 + 上方状态小字 + 竖线分隔
- 🔧 顶部：黑圆底 X + 右上编号 ✅，中央纹章 ⬜
- ⬜ 方块/物品列表用圆形底座 + 黑胶囊计数 + 青色标记
- ⬜ 手绘线稿图标集（替换关键 Material Icons）

---

## 五、新需求：客户端分级（主机端完整 / 移动端受限）

**原则**（遵循 RULES.md 第 5 条）：可选能力用**显式开关**，
关闭时功能**根本不存在**，不允许"半开"或静默降级。

### 能力矩阵
| 能力 | 主机端 Host（桌面） | 移动端 Mobile（Android/iOS） |
|---|---|---|
| 剧情编辑 / 变量 / 表达式 | ✅ | ✅ |
| rust 脚本块（内置解释器） | ✅ | ✅ |
| **godot 脚本块** | ✅ | ❌ 编辑器不提供该选项，lint 报错 |
| 试玩 / 预览 | ✅ | ✅ |
| 导入 .gal 游玩 | ✅ | ✅ |
| **自主打包成游戏 / export-godot** | ✅ | ❌ 命令拒绝 + UI 无入口 |
| .gal 资源打包（pack） | ✅ | ✅（仅资源包，非游戏导出） |
| 3D 场景编辑 | ✅ | ⬜ 受限（只读预览） |

### 实现
- Dart `lib/engine/capability.dart`：
  ```dart
  enum EngineTier { host, mobile }
  EngineTier currentTier();  // 按 Platform 显式判定，可 --dart-define 覆盖
  bool can(String capability);  // 能力表查询
  ```
- 编辑器：mobile 下 godot 引擎选项**不渲染**（不是灰掉），导出按钮不存在。
- Rust CLI：`export-godot` 在 mobile target 下**直接报错退出**，
  错误信息写明「移动端不支持自主打包，请在主机端操作」。
- lint：mobile 下 godot 脚本块报 Error。
- 文档：README 增加分级说明。

### 验收
- ✅ capability.dart + 单测（host/mobile 能力表正确）
- ✅ 编辑器 mobile 无 godot 选项 / 无导出入口
- ✅ CLI export-godot 在 mobile 拒绝并写明修法
- ✅ lint mobile 下 godot 块报错
- ⬜ 主机端全功能不受影响（回归测试）

---

## 六、开源协议：闭源游戏需联系作者（可行性探讨）

### 现状
引擎以 **GPL-3.0-or-later** 发布。GPL 是强 copyleft：
游戏若链接/组合 GPL 运行时，通常构成衍生作品 → 必须同样 GPL → **无法闭源**。
这与「让用引擎做的游戏可以闭源」直接冲突。

### 四种可行路径对比
| 方案 | 机制 | 游戏可闭源 | 需联系作者 | 引擎仍算开源 | 成熟度 |
|---|---|---|---|---|---|
| A 改 MIT/Apache | 宽松许可 | ✅ 自动 | ❌ | ✅ OSI | 高 |
| **B 双许可** | GPL 默认 + 商业闭源许可 | ✅ 经授权 | ✅ 必须 | ✅ 引擎仍 GPL | 高（Qt/MySQL） |
| C 运行时例外 | 引擎 GPL + 运行时宽松例外 | ✅ 自动 | ❌ | ✅ | 中（GCC RLE） |
| D 自定义 source-available | 「开源免费，闭源需书面授权」 | ✅ 经授权 | ✅ | ❌ 非 OSI | 中（fair-code） |

### 结论：推荐 B（双许可），完全满足需求且法律成熟
- **引擎本体保持 GPL-3.0**：社区版开源，任何人可自由用引擎做 **GPL 游戏**（无需联系）。
- **闭源游戏走商业许可**：需向原作者申请**书面授权**（commercial license），
  「获得支持」落地为商业许可协议中的授权 + 可选技术支持条款。
- 这正是 Qt / MySQL / SideFX 的模式，判例与实务成熟。

### B 的前提与风险（必须满足，否则方案无效）
1. **版权集中**：作者须持有全部版权。外部贡献者需签 **CLA**（贡献者许可协议），
   把版权授予作者，否则作者**无权**对含他人代码的版本双许可。→ 需 CONTRIBUTING + CLA。
2. **无 GPL 第三方依赖**：galatea-core **零依赖** ✅；
   Flutter(BSD)、Godot(MIT) 均宽松，不阻碍商业许可 ✅。
   若未来引入 GPL 依赖，商业许可即失效，需替换。
3. **措辞法律化**：不能写模糊的「获得支持」，要写「取得书面商业许可」。
   支持/服务是商业许可的附加条款，不是授权本身。
4. **fork 保护**：别人 fork GPL 版仍须保持 GPL，无法绕开商业许可做闭源 ✅。
5. **商标**：Galatea 名称/图标建议另设商标政策，与代码许可分离。

### 为什么不选 D
D 把引擎本身改成「闭源需授权」的自定义许可 → 引擎**不再是 OSI 开源**
（违反开源定义第 6 条「不歧视领域」与自由再分发）。
用户说的是「修改开源协议」，B 保留引擎开源属性、只对**闭源游戏**设门槛，更贴合。
若作者明确要引擎也变 source-available，再切 D（文档保留此选项）。

### 落地文件
- ⬜ `LICENSE`：保持 GPL-3.0 全文
- ✅ `COMMERCIAL-LICENSE.md`：闭源游戏须联系作者取得书面商业许可的说明 + 联系方式
- ✅ `CONTRIBUTING.md` + `CLA.md`：贡献者授权作者双许可
- ✅ `README.md` 许可证段：说明双许可（GPL 社区版 / 商业闭源版）
- ⬜ 文件头 SPDX：`GPL-3.0-or-later OR LicenseRef-Galatea-Commercial`

---

## 七、本轮开工顺序

1. ✅ APK 修复推送（`aa9211c`，AGP 8.7.3）—— 等构建结果
2. ⬜ 协议落地（B 双许可：COMMERCIAL-LICENSE / CONTRIBUTING / CLA / README）
3. ⬜ 图块 image（Rust → VM → Dart → 打包 → 测试）
4. ⬜ 音频块 audio（Rust → VM → Dart → 播放器 → 测试）
5. ⬜ 客户端分级（capability → 编辑器 → CLI → lint → 测试）
6. ⬜ 书柜视觉（深色卡片 → 黑胶囊 → 拼贴 → 统计条 → 顶部 → 圆底座 → 线稿图标）
7. ⬜ 全量测试 + CI 绿 + APK 出包 + 按格式汇报

> 每完成一项，回本文件把 ⬜ 改 ✅ 并附验证记录。不做完不勾。
