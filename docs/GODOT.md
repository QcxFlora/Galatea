# Godot 集成

Galatea 用 **Godot 4** 作为 3D 运行时：Godot 负责渲染、场景、物理、音频、输入，
Rust（`galatea-core`）负责剧本、分支、变量、权重和自定义脚本。
两者之间是一层**自己写的 GDExtension**（`godot/gdext`）。

```
Flutter（编辑器 / 书柜）
   │  galatea pack → 作品.gal
   ▼
作品.gal（剧本 + 立绘 + 脚本，池化 + DEFLATE）
   │  复制到 Godot 工程的 stories/
   ▼
Godot 4 运行时
   ├─ scenes/main.gd     3D 场景 / 对话框 / 选项 / 立绘
   └─ gdext/ (Rust)      GDExtension：读 .gal、跑 VM、暴露事件
                          ↓
                   galatea-core（与 CLI / Flutter 同一份）
```

## 目录

```
godot/
├── project.godot               Godot 4.3 工程
├── scenes/main.tscn            3D 场景（相机 / 光照 / UI 层）
├── scenes/main.gd              剧情驱动（事件 JSON → 画面）
├── stories/demo.gal            内置示例（由 galatea pack 生成）
└── gdext/                      Rust GDExtension
    ├── Cargo.toml              独立 workspace（不被主 workspace 拉进去）
    ├── src/lib.rs              GalateaRuntime 节点
    └── galatea.gdextension     库路径声明
```

## 构建步骤

### 1. 编译 Rust 扩展

```bash
cd godot/gdext
cargo build --release
mkdir -p bin
cp target/release/libgalatea_godot.so bin/          # Linux / macOS 用 .dylib
```

Android 需要 `cargo-ndk`：

```bash
cargo install cargo-ndk
rustup target add aarch64-linux-android
cargo ndk -t arm64-v8a -o bin build --release
# 产物：bin/arm64-v8a/libgalatea_godot.so
```

把 `.so` 放到 `gdext/bin/`，并让 `galatea.gdextension` 的路径对上。

### 2. 用 Godot 打开工程

```bash
godot --path godot --editor      # 首次会生成 .godot/ 缓存
godot --path godot               # 直接运行
```

运行时默认加载 `res://stories/demo.gal`，也可以用命令行指定：

```bash
godot --path godot -- res://stories/我的作品.gal
```

### 3. 导出 Android

Godot 4 需要先在编辑器里装 **Android 导出模板**（Editor → Manage Export Templates），
再 `Project → Export → Android`。GDExtension 的 `.so` 要放在
`godot/gdext/bin/arm64-v8a/` 并在 `.gdextension` 里声明 `android.release.arm64`。

## 事件协议

GDExtension 的 `advance()` / `choose()` 都返回**一行 JSON**：

```json
{"type":"say","name":"阿米娅","text":"博士，报告写完了吗？","portrait":"assets/characters/amiya.webp"}
{"type":"choices","prompt":"事已至此……","options":[{"index":0,"text":"我可以解释"}]}
{"type":"ending","ending":"tea","text":"结局 · 一杯茶的时间"}
{"type":"script","entry":"opening","ret":null,"emits":{"bgm":"rain_theme","cameraY":40}}
{"type":"halt","reason":"剧情结束"}
```

GDScript 侧只需要 `JSON.parse_string()`，不依赖任何 Rust 类型布局。

## 为什么不让 Godot 自己管剧情

Godot 的对话插件（Dialogic 等）很好，但 **剧本格式会被引擎锁死**：
导出成 Godot 的 `.dtl` 就再也拿不出来，也做不了「一张图看全部支线」。
Galatea 的选择是：剧情图是**独立的、可版本控制的 `.gal`**，
任何运行时（CLI / Flutter / Godot）都能读它。

## 与 Flutter 的关系

| 环节 | 谁负责 |
|---|---|
| 写剧情（思维导图编辑器） | Flutter |
| 静态检查 / 体积统计 / 打包 | Rust CLI |
| 3D 小游戏 / 演出 | Godot（本目录） |
| 纯文字试玩（不装 Godot） | Flutter 内置播放器 + CLI |

Flutter 侧点「导出 .gal」后，把文件放进 `godot/stories/` 即可在 Godot 里运行；
两端的剧情数据完全一致（同一个 VM 实现，Rust 侧单源）。
