# 发布规范（版本 / 签名 / 包名 / 更新内容）

> 每次推送都要按这个来。违反任何一条，用户那边就会出现"装了没用"「覆盖安装失败」「存档丢失」。

## 1. 版本号

| 位置 | 格式 | 谁改 |
|---|---|---|
| `VERSION` 文件 | `0.2.0`（**三段基线**，手工维护） | 人 |
| 显示版本 / APK 文件名 / Release tag | `0.2.0.<CI流水线号>` | CI 自动 |
| `Cargo.toml` | `0.2.0-build.<流水线号>`（Cargo 只认三段） | CI 自动 |
| `app/pubspec.yaml` | `0.2.0+<流水线号>`（Flutter 只认三段+构建号） | CI 自动 |

**铁律**：

- 不要手改 `pubspec.yaml` / `Cargo.toml` 里的 `version` —— 交给 CI
- 每次发版版本号必须**比上一版大**，否则 Android 拒绝升级
- 用户能看到的版本号在 App 里（`--dart-define=APP_VERSION`），必须和 APK 名一致

## 2. 更新内容

### commit message

```
<type>(<scope>): <一句话说清"用户能感知到什么">

<为什么这么改 / 踩了什么坑 / 验证方式>
```

type：`feat` 新功能 · `fix` 修问题 · `refactor` 结构调整 · `docs` 文档 · `chore` 杂项

**禁止**：「更新代码」「修复问题」「优化」这种没有任何信息量的提交。

### 每次推送后给用户的摘要（固定格式）

```
【推送 <sha>】<时间>  CI ✅ / APK ✅
■ 新增：用户能点到/看到的新东西
■ 改动：行为变化（含"以前怎样、现在怎样"）
■ 修复：具体问题 → 具体结果
■ 验证：测试数 / 构建结果 / 需要真机确认的点
■ 遗留：这轮没做的，明确列出
```

### Release notes 要写

1. 这一版能做什么（用户视角）
2. 已知问题
3. 怎么验证（装哪个包、点哪里）

## 3. 签名（最不能动的东西）

- 唯一签名文件：`signing/release.jks`，别名 `galatea`
- 证书指纹：`DC:69:0C:61:75:99:56:43:46:53:1F:F2:53:4E:DB:89:6D:5B:D9:EA:6B:A9:8D:8D:71:C8:28:CF:FC:F8:6E:69`
- **永远不要重新生成**：换了签名，用户必须先卸载再装，书柜和存档全丢
- **必须备份**：keystore 丢了 = 永久失去升级能力（这是不可逆的）
- 密码写在 `scripts/android_setup.py` 与 CI 里，改之前先确认没有历史包需要兼容
- 验证：`keytool -list -keystore signing/release.jks -storepass galatea2026`

## 4. 包名

- `applicationId` / `namespace` = **`com.galatea.studio`**
- **一旦发过版就不能改**：改了就是另一个应用，装不上、覆盖不了、数据隔离
- 改包名要同步搬 `MainActivity` 的包路径（`scripts/android_setup.py` 负责）
- 验证：`aapt dump badging app-release.apk | grep package`

## 5. 构建

- APK **只出 arm64-v8a**（Redmi 23113RKC6C 是 arm64），通用包 48MB 纯浪费
- 3D 原生库由 CI 的 `cargo ndk` 编进 `jniLibs/arm64-v8a/`
- 应用名 `Galatea`，图标来自 `app/icon/ic_launcher_*.png`

## 6. 发布前检查清单

- [ ] `cargo test` 全绿（当前 45 个）
- [ ] `flutter analyze` 无 error
- [ ] 「代码纪律」job 绿（无空捕获 / errorBuilder / ?? SizedBox）
- [ ] `VERSION` 与 Release tag 一致
- [ ] APK 是 arm64（不是 48MB 通用包）
- [ ] 签名指纹未变（对比上面那串）
- [ ] 包名仍是 `com.galatea.studio`
- [ ] Release 里有 `galatea-<ver>.apk` **和** `galatea-latest.apk`
- [ ] 更新内容写的是"用户能感知的变化"，不是"改了某函数"
- [ ] 推送后**确认 CI 和 APK 都成功**，不是只看 push 成功

## 7. 血泪教训（这个项目真实踩过的）

| 事故 | 后果 |
|---|---|
| 版本号拼成四段 `0.2.0.57` | Cargo/Flutter 都拒绝，`pub get` 直接失败 |
| 只推了代码没触发 APK | 用户装了发现"完全没变化" |
| Release 的 `files:` 写了 `${VER}`（shell 语法） | 只上传了 latest，带版本号的那个丢失 |
| 用 `cargo ndk` 在 `flutter create` 之前跑 | jniLibs 目录不存在，白跑 |
| 空 `catch` + errorBuilder | 坏文件被静默吞掉，用户以为"功能没做" |