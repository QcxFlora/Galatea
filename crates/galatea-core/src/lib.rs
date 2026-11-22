//! Galatea —— 思维导图式 Galgame 引擎核心
//!
//! ```text
//!   Flutter 编辑器  ──┐
//!   Flutter 播放器  ──┼──►  galatea-core（本 crate）──►  .gala 剧本文件
//!   CLI / CI 校验   ──┘
//! ```
//!
//! 设计原则：
//! 1. **同一份图，两种跑法**：编辑器里试玩和导出后的游戏用同一个 [`Vm`]，
//!    不会出现"编辑器里好好的，打包后就错了"。
//! 2. **零依赖**：JSON、表达式解析都在这里手写，交叉编译到 Android / iOS /
//!    桌面 / wasm 都不会因为依赖树崩掉。
//! 3. **一切皆节点**：台词、选择、条件、变量、跳转、子图、结局都是节点，
//!    连线即流程，所以整部作品能被当成一张流程图审视。

pub mod compact;
pub mod expr;
pub mod gal;
pub mod graph;
pub mod json;
pub mod lint;
pub mod script;
pub mod vm;

pub use graph::{Character, Choice, Effect, Meta, Node, NodeKind, Op, Story};
pub use json::Json;
pub use lint::{lint, Issue, Level};
pub use vm::{Event, OptionView, Vm};

/// crate 版本，方便存档带上引擎版本号
pub const VERSION: &str = env!("CARGO_PKG_VERSION");