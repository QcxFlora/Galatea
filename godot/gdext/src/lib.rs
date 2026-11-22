//! Galatea × Godot —— GDExtension 绑定（我们自己写的那层）。
//!
//! # 它做什么
//!
//! 把 `galatea-core` 的剧情 VM / 脚本解释器 / `.gal` 读取挂进 Godot，
//! 让 Godot 只负责它最擅长的部分：3D 渲染、场景、物理、音频、输入。
//!
//! ```gdspeech
//! var rt = GalateaRuntime.new()
//! rt.load_gal("res://stories/arknights_demo.gal")
//! var ev = rt.advance()          # JSON: {"type":"say", "text":"...", "portrait":"..."}
//! rt.choose(0)                   # 选择分支
//! ```
//!
//! # 为什么不自己写渲染
//!
//! 自研光栅化只适合验证概念；真要做小游戏（碰撞、骨骼动画、粒子、
//! 后处理），Godot 的成熟管线是几十万行代码的积累。所以：
//!
//! * **剧本 / 分支 / 变量 / 权重 / 脚本** → Rust（`galatea-core`，纯逻辑，好测试）
//! * **画面 / 物理 / 音频 / 输入** → Godot
//! * **两者的缝** → 本文件（GDExtension，C ABI）
//!
//! # 事件协议
//!
//! 所有事件都以 JSON 字符串（`GString`）跨边界，这样 GDScript 侧不用
//! 关心 Rust 的类型布局，协议也能单独演进。

use godot::prelude::*;

use galatea_core::gal::Archive;
use galatea_core::json::Json;
use galatea_core::vm::{Event, Vm};

/// 把 Rust 的 Event 转成 GDScript 能吃的 JSON
fn event_to_json(ev: &Event) -> String {
    let mut o = Json::obj();
    match ev {
        Event::Say {
            speaker_name,
            text,
            portrait,
            bg,
            extra_portraits,
            ..
        } => {
            o.set("type", Json::s("say"));
            o.set("name", Json::s(speaker_name.clone()));
            o.set("text", Json::s(text.clone()));
            if let Some(p) = portrait {
                o.set("portrait", Json::s(p.clone()));
            }
            if let Some(b) = bg {
                o.set("bg", Json::s(b.clone()));
            }
            if !extra_portraits.is_empty() {
                o.set(
                    "extra_portraits",
                    Json::Arr(
                        extra_portraits
                            .iter()
                            .map(|s| Json::s(s.clone()))
                            .collect(),
                    ),
                );
            }
        }
        Event::Choices { prompt, options, .. } => {
            o.set("type", Json::s("choices"));
            o.set("prompt", Json::s(prompt.clone()));
            let mut arr = Json::arr();
            for (i, opt) in options.iter().enumerate() {
                let mut oo = Json::obj();
                oo.set("index", Json::n(i as f64));
                oo.set("text", Json::s(opt.text.clone()));
                arr.push(oo);
            }
            o.set("options", arr);
        }
        Event::Ending { ending, text, .. } => {
            o.set("type", Json::s("ending"));
            o.set("ending", Json::s(ending.clone()));
            o.set("text", Json::s(text.clone()));
        }
        Event::Script { entry, ret, emits, .. } => {
            o.set("type", Json::s("script"));
            o.set("entry", Json::s(entry.clone()));
            o.set("ret", ret.clone());
            let mut eo = Json::obj();
            for (k, v) in emits {
                eo.set(k, v.clone());
            }
            o.set("emits", eo);
        }
        Event::Halt { reason } => {
            o.set("type", Json::s("halt"));
            o.set("reason", Json::s(reason.clone()));
        }
    }
    o.to_string()
}

/// 挂到场景树上的运行时节点
#[derive(GodotClass)]
#[class(base = Node)]
struct GalateaRuntime {
    base: Base<Node>,
    vm: Option<Vm>,
    /// .gal 里解出来的资源（立绘等），供 Godot 侧按需取用
    assets: std::collections::BTreeMap<String, Vec<u8>>,
}

#[godot_api]
impl INode for GalateaRuntime {
    fn init(base: Base<Node>) -> Self {
        godot_print!("[galatea] runtime ready");
        Self {
            base,
            vm: None,
            assets: Default::default(),
        }
    }
}

#[godot_api]
impl GalateaRuntime {
    /// 载入 .gal：返回剧本标题（失败返回空串并打印原因）
    #[func]
    fn load_gal(&mut self, path: GString) -> GString {
        let path_str = path.to_string();
        let bytes = match std::fs::read(&path_str) {
            Ok(b) => b,
            Err(e) => {
                godot_error!("[galatea] 读不到 {}：{}", path_str, e);
                return GString::new();
            }
        };
        let archive = match Archive::parse(&bytes) {
            Ok(a) => a,
            Err(e) => {
                godot_error!("[galatea] .gal 解析失败：{}", e);
                return GString::new();
            }
        };
        let raw = match archive.read(&archive.story_name.clone()) {
            Ok(r) => r,
            Err(e) => {
                godot_error!("[galatea] 剧本读取失败：{}", e);
                return GString::new();
            }
        };
        let json_text = String::from_utf8_lossy(&raw).to_string();
        let doc = match galatea_core::json::parse(&json_text) {
            Ok(d) => d,
            Err(e) => {
                godot_error!("[galatea] 剧本 JSON 坏了：{}", e);
                return GString::new();
            }
        };
        let plain = match galatea_core::compact::unpack(&doc) {
            Ok(p) => p,
            Err(e) => {
                godot_error!("[galatea] 池化还原失败：{}", e);
                return GString::new();
            }
        };
        let story = match galatea_core::graph::Story::from_json(&plain) {
            Ok(s) => s,
            Err(e) => {
                godot_error!("[galatea] 剧本结构不对：{}", e);
                return GString::new();
            }
        };
        let title = story.meta.title.clone();
        self.assets.clear();
        for entry in &archive.entries {
            if entry.name == archive.story_name {
                continue;
            }
            if let Ok(data) = archive.read(&entry.name) {
                self.assets.insert(entry.name.clone(), data);
            }
        }
        godot_print!("[galatea] 载入《{}》，资源 {} 个", title, self.assets.len());
        self.vm = Some(Vm::new(story));
        GString::from(&title)
    }

    /// 推进到下一个事件（JSON 字符串）
    #[func]
    fn advance(&mut self) -> GString {
        let Some(vm) = self.vm.as_mut() else {
            return GString::from("{\"type\":\"halt\",\"reason\":\"未载入剧本\"}");
        };
        GString::from(&event_to_json(&vm.step()))
    }

    /// 选择第 index 个选项，返回下一个事件
    #[func]
    fn choose(&mut self, index: i64) -> GString {
        let Some(vm) = self.vm.as_mut() else {
            return GString::from("{\"type\":\"halt\",\"reason\":\"未载入剧本\"}");
        };
        match vm.choose(index.max(0) as usize) {
            Ok(ev) => GString::from(&event_to_json(&ev)),
            Err(e) => GString::from(&format!(
                "{{\"type\":\"halt\",\"reason\":\"{}\"}}",
                e.replace('"', "'")
            )),
        }
    }

    /// 撤销
    #[func]
    fn undo(&mut self) -> bool {
        self.vm.as_mut().map(|v| v.undo()).unwrap_or(false)
    }

    /// 读变量（给 Godot 侧做 UI 显示）
    #[func]
    fn get_var(&mut self, name: GString) -> Variant {
        let Some(vm) = self.vm.as_ref() else {
            return Variant::nil();
        };
        match vm.var(&name.to_string()) {
            Json::Num(n) => Variant::from(n as f64),
            Json::Bool(b) => Variant::from(b),
            Json::Str(s) => Variant::from(GString::from(&s)),
            _ => Variant::nil(),
        }
    }

    /// 取一个资源字节（立绘 PNG/WebP），GDScript 侧用 Image.load_webp_from_buffer
    #[func]
    fn asset_bytes(&self, name: GString) -> PackedByteArray {
        match self.assets.get(&name.to_string()) {
            Some(d) => PackedByteArray::from(d.as_slice()),
            None => PackedByteArray::new(),
        }
    }

    /// 存档（JSON）
    #[func]
    fn save_state(&self) -> GString {
        match self.vm.as_ref() {
            Some(vm) => GString::from(&vm.save()),
            None => GString::new(),
        }
    }

    /// 读档
    #[func]
    fn load_state(&mut self, json: GString) -> bool {
        let Some(vm) = self.vm.as_mut() else { return false };
        match galatea_core::json::parse(&json.to_string()) {
            Ok(j) => vm.load(&j).is_ok(),
            Err(_) => false,
        }
    }
}

#[cfg(test)]
mod tests {
    // GDExtension 的测试需要在 Godot 里跑，这里只保证纯逻辑编译
    #[test]
    fn event_json_shape() {
        use galatea_core::vm::Event;
        let json = super::event_to_json(&Event::Say {
            node: "n1".into(),
            speaker: None,
            speaker_name: "阿米娅".into(),
            color: None,
            text: "博士。".into(),
            bg: None,
            portrait: Some("a.webp".into()),
            extra_portraits: vec![],
        });
        assert!(json.contains("\"type\":\"say\""));
        assert!(json.contains("阿米娅"));
    }
}
