# 贡献指南

1. **先签 CLA**：见 `CLA.md`。首次 PR 须在描述中声明同意，否则不合并。
2. **代码纪律**：遵循 `RULES.md` —— 不许静默降级、不许空捕获、坏了必须明显坏。
   CI 有「代码纪律」job 强制检查。
3. **测试**：Rust `cargo test`、Dart `flutter test`、Web `node web/test_logic.js` 必须全绿。
4. **提交信息**：写用户能感知的变化（feat/fix/refactor/docs/chore + 一句话结果），
   不写「改了某函数」。
5. **许可**：你的贡献将按双许可分发（GPL-3.0 或商业许可），见 COMMERCIAL-LICENSE.md。
