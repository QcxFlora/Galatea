# 单包共存：一个 APK，一个显示层

## 结论先放这儿

**不让 Godot 往屏幕上画。** 它只当引擎（场景树 / 物理 / GDScript），
像素由 `galatea-3d`（Rust）算，Flutter 当唯一的显示层。

```
┌─────────────────────────────────────────────────────────┐
│                   一个 APK / 一个进程                     │
│                                                         │
│  ┌───────────────┐   ┌──────────────────┐               │
│  │  Godot        │   │  Flutter          │              │
│  │  (headless)   │   │  （唯一显示层）     │              │
│  │               │   │                   │              │
│  │ 场景树 / 物理  │   │ Text / Button     │              │
│  │ GDScript 小游戏│   │ 浮层 / 字幕        │              │
│  └───────┬───────┘   └────────▲──────────┘              │
│          │ 状态               │ RawImage                │
│          ▼                    │                         │
│  ┌────────────────────────────┴──────────┐              │
│  │  galatea-3d（Rust cdylib，dart:ffi）    │              │
│  │  场景图 → 三角形 → RGBA 像素            │              │
│  └───────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────┘
```

## 为什么不让 Godot 自己显示

Godot 的 Android 导出会创建自己的 `SurfaceView` + GL 上下文；
Flutter 也有自己的 `FlutterView` + 上下文。同一个 Activity 里两套
会让下面这些直接出问题：

- 纹理/上下文互相污染（花屏、闪黑）
- 触摸事件被 Godot 的 View 吃掉，Flutter 的浮层点不到
- 生命周期不同步（切后台、旋转、分屏）
- 音视频焦点互相抢

**"掐掉 Godot 的显示"** 在工程上就是：用 headless 模式初始化它
（`--headless` 或 libgodot 的 `DisplayServer` 不创建窗口），
让 `DisplayServer` 变成 no-op，`RenderingServer` 不接入窗口。

## 数据怎么从 Godot 到像素

三条路，按控制力从高到低：

| 路径 | 说明 | 用在哪 |
|---|---|---|
| **A. 状态镜像** | Godot 只维护逻辑状态（位置/旋转/可见性），每帧把对象的变换写成一块扁平数组，Rust 读它重建场景 | **默认**：跨语言开销最小，只传几十个 float |
| B. 共享内存 | 用 `mmap` 一块 buffer，两边直接读写 | 对象上千时 |
| C. 渲染目标回读 | Godot 渲染到 Image，`get_image()` 拷出来 | 只在需要 Godot 特有特效时 |

`galatea-3d` 的 C ABI 已经覆盖路径 A 需要的全部操作：
`g3d_add / set_position / set_rotation / set_color / set_visible / set_camera / render`。
GDScript 里一行 `rt.sync_scene(engine_handle)` 就能把场景推过来。

## 落地步骤

1. **Rust 侧**（已完成）：`galatea-3d` 出 `cdylib`，C ABI 稳定
2. **Flutter 侧**（已完成）：
   - `lib/engine/ffi3d.dart`：`dart:ffi` 绑 C ABI，`Scene3DView` 用
     `decodeImageFromPixels` + `RawImage` 显示（**不需要任何 Surface**）
   - 库加载失败会退化成占位框，不会崩
3. **打包**：`.so` 放到 `android/app/src/main/jniLibs/arm64-v8a/`
   ```bash
   cargo ndk -t arm64-v8a -o app/android/app/src/main/jniLibs build --release -p galatea-3d
   ```
4. **Godot**：编译 `libgodot`（`scons platform=android target=template_release libgodot=yes`），
   宿主进程里 `godot::initialize_headless()`，GDExtension 只暴露逻辑接口

## 现在的状态

| 环节 | 状态 |
|---|---|
| Rust 3D 后端（场景/相机/光栅/PNG） | ✅ 45+3 测试通过 |
| Flutter 显示层（FFI + RawImage） | ✅ 代码完成（含降级） |
| Android 打包 `.so` | ⏳ CI 待加 cargo-ndk 步骤 |
| Godot headless 嵌入 | ⏳ 需要 libgodot（编译一次，官方支持） |
| 状态镜像协议 | ⏳ 下一步 |

**为什么先做"Flutter 显示 + Rust 渲染"**：它是整条链路里唯一必须由我们
写死的部分（显示层只能有一个），Godot 在哪一侧都不影响它。
先把这段打通，Godot 接进来时只需要"往这个渲染器里灌状态"。
