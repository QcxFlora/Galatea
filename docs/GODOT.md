# Godot 集成：引用，而不是内置

**Godot 引擎本体不随 Galatea 分发。** 作者自行安装 Godot 4.2+
（<https://godotengine.org/download>）来编写、调试 GDScript；
Galatea 只负责「引用脚本 + 打包成工程」。

## 分工

| 谁 | 干什么 |
|---|---|
| **Galatea 本体**（Flutter + Rust） | 剧情图、变量、表达式、分支、权重、动画、2D 演出、`.gal` 打包 |
| **脚本块 `engine=rust`** | 内置安全子集解释器，编辑器里预览即所得 |
| **脚本块 `engine=godot`** | 只存引用：`src`（`.gd` 路径）+ `entry`（入口函数名） |
| **Godot**（作者自己装） | 写/调试 `.gd`；打开导出的工程，运行或导出成最终游戏 |

变量**不在 Godot 里算** —— 全部由 Galatea 本体管理，脚本通过注入的
`galatea.vars` 读写，剧情后续的 `branch` 块立刻能用。

## 导出

```bash
galatea export-godot 作品.gal -o 我的游戏 --scripts ./godot
```

生成：

```
我的游戏/
├── project.godot          # Godot 4.2+，GL Compatibility，横屏 1280×720
├── story.gal              # 剧情包（池化 + DEFLATE，唯一交付格式）
├── runtime/galatea.gd     # 纯 GDScript 运行时：读 .gal + 剧情 VM + 表达式
├── scenes/main.tscn
├── scenes/main.gd         # 默认演出（背景/立绘/对话框/选项），想换皮改这里
├── scripts/*.gd           # 剧情引用到的脚本，逐个校验存在后拷入
└── assets/…               # 包里的立绘/背景，按原相对路径落盘
```

用 Godot 打开 `project.godot`，F5 运行；「项目 → 导出」出 APK/EXE。

**零扩展依赖**：Godot 4 自带 deflate 解压，`galatea.gd` 直接读 `.gal`
二进制（magic `GAL\x01`、小端索引），不需要编译任何 GDExtension。

## 脚本约定

```gdscript
extends RefCounted

var galatea            # 运行时自动注入

func run() -> void:    # 入口默认 run()，可在脚本块里改 entry
    galatea.vars["score"] = 42
```

- 入口函数应当是**同步**的。
- 要做带交互的小游戏 / 3D 演出：直接改导出工程的 `scenes/main.gd` ——
  那是完整 Godot 工程，渲染、物理、音频、输入全归你。
- 引用路径写成 `res://scripts/x.gd` 或 `scripts/x.gd` 都行，导出时会剥掉前缀。
- `lint` 会检查：godot 脚本块必须有 `src`、必须是 `.gd`；
  导出时引用的文件不存在会**直接报错**，绝不静默跳过。

## 已废弃的方案

早期设计过「单包共存 + Godot headless + 自写 GDExtension + 状态镜像」
（见 `SINGLE-PACKAGE.md`、`godot/gdext/`）。该方案要求把 `libgodot.so`
编进 APK 并掐掉 Godot 显示层，复杂且从未编译验证过。
**现方案取代它**：Godot 由作者自行安装，Galatea 导出标准工程，不嵌入引擎。
`godot/gdext/` 保留作历史参考，不参与构建。
