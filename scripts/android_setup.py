#!/usr/bin/env python3
"""把 `flutter create` 生成的 Android 工程改造成 Galatea 的样子。

CI 里在 `flutter create` 之后、`flutter build` 之前跑：

    python3 scripts/android_setup.py app

做四件事：
1. 包名改成 `com.galatea.studio`（applicationId / namespace）
2. MainActivity 挪到对应包路径并改 package 声明
3. 注入 release 签名配置（读 android/key.properties）
4. 用仓库里的 signing/release.jks 签名（固定指纹，升级 APK 不用卸载）

不用 GitHub Secrets：密钥就在仓库里。这是开源项目换取
「任何人 clone 下来都能签出同一指纹」的取舍，别拿它上架应用商店。
"""
import os
import re
import shutil
import sys
from pathlib import Path

APP_ID = "com.galatea.studio"
PKG_PATH = APP_ID.replace(".", "/")


def main(app_dir: str) -> int:
    app = Path(app_dir)
    android = app / "android"
    if not android.is_dir():
        print(f"!! {android} 不存在，先跑 flutter create", file=sys.stderr)
        return 1

    # ── 1. build.gradle(.kts)
    gradle_kts = android / "app" / "build.gradle.kts"
    gradle_groovy = android / "app" / "build.gradle"
    if gradle_kts.exists():
        s = gradle_kts.read_text(encoding="utf-8")
        s = re.sub(r'namespace\s*=\s*"[^"]*"', f'namespace = "{APP_ID}"', s)
        s = re.sub(r'applicationId\s*=\s*"[^"]*"', f'applicationId = "{APP_ID}"', s)

        # 用正则定位 buildTypes（不依赖缩进），在它前面插 signingConfigs
        if not re.search(r"signingConfigs\s*\{", s):
            m = re.search(r"^(\s*)buildTypes\s*\{", s, re.M)
            if not m:
                print("!! build.gradle.kts 里找不到 buildTypes", file=sys.stderr)
                return 1
            indent = m.group(1)
            signing = (
                f"{indent}signingConfigs {{\n"
                f"{indent}    create(\"release\") {{\n"
                f"{indent}        val propsFile = rootProject.file(\"key.properties\")\n"
                f"{indent}        if (!propsFile.exists()) {{\n"
                f"{indent}            throw GradleException(\"缺少 android/key.properties —— 先跑 python3 scripts/android_setup.py app\")\n"
                f"{indent}        }}\n"
                f"{indent}        val props = Properties()\n"
                f"{indent}        propsFile.inputStream().use {{ props.load(it) }}\n"
                f"{indent}        val ks = file(props.getProperty(\"storeFile\"))\n"
                f"{indent}        if (!ks.exists()) {{\n"
                f"{indent}            throw GradleException(\"keystore 不存在：${{ks}} —— 确认 signing/release.jks 在仓库里\")\n"
                f"{indent}        }}\n"
                f"{indent}        storeFile = ks\n"
                f"{indent}        storePassword = props.getProperty(\"storePassword\")\n"
                f"{indent}        keyAlias = props.getProperty(\"keyAlias\")\n"
                f"{indent}        keyPassword = props.getProperty(\"keyPassword\")\n"
                f"{indent}    }}\n"
                f"{indent}}}\n\n"
            )
            s = s[: m.start()] + signing + s[m.start():]
            print(f"✓ 插入 signingConfigs（缩进 {len(indent)} 空格）")
        # 用 release 签名替换模板里的 debug 签名
        s = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                   'signingConfig = signingConfigs.getByName("release")', s)
        # AGP 9.0 把旧 android {} 标成 ERROR 级弃用，newDsl=false 也救不回来。
        # 固定到已知稳定的 AGP 8.7.3 + Gradle 8.9，不跟 runner 上的最新版碰运气。
        if not s.lstrip().startswith("import "):
            s = "import java.util.Properties\n\n" + s
        settings = android / "settings.gradle.kts"
        if settings.exists():
            st = settings.read_text(encoding="utf-8")
            st = re.sub(r'(id\("com\.android\.application"\) version ")[^"]+(")', r'\g<1>8.7.3\g<2>', st)
            st = re.sub(r'(id\("com\.android\.library"\) version ")[^"]+(")', r'\g<1>8.7.3\g<2>', st)
            st = re.sub(r'(id\("org\.jetbrains\.kotlin\.android"\) version ")[^"]+(")', r'\g<1>2.1.0\g<2>', st)
            settings.write_text(st, encoding="utf-8")
            print("✓ settings.gradle.kts：AGP 8.7.3 / Kotlin 2.1.0")
        wrapper = android / "gradle" / "wrapper" / "gradle-wrapper.properties"
        if wrapper.exists():
            wt = wrapper.read_text(encoding="utf-8")
            wt = re.sub(r'gradle-[0-9.]+-(bin|all)\.zip', r'gradle-8.9-\1.zip', wt)
            wrapper.write_text(wt, encoding="utf-8")
            print("✓ gradle-wrapper：8.9")
        gradle_kts.write_text(s, encoding="utf-8")
        print("✓ build.gradle.kts：包名 + release 签名")
    elif gradle_groovy.exists():
        s = gradle_groovy.read_text(encoding="utf-8")
        # CI 的 flutter groovy 模板用赋值语法 applicationId = "…"，两种都要兼容
        s = re.sub(r'applicationId\s*=?\s*"[^"]*"', f'applicationId = "{APP_ID}"', s)
        s = re.sub(r'namespace\s*=?\s*"[^"]*"', f'namespace = "{APP_ID}"', s)
        if not re.search(r"signingConfigs\s*\{", s):
            m = re.search(r"^(\s*)buildTypes\s*\{", s, re.M)
            if not m:
                print("!! build.gradle 里找不到 buildTypes", file=sys.stderr)
                return 1
            ind = m.group(1)
            signing = (
                f"{ind}signingConfigs {{\n"
                f"{ind}    release {{\n"
                f"{ind}        def propsFile = rootProject.file('key.properties')\n"
                f"{ind}        if (!propsFile.exists()) {{\n"
                f"{ind}            throw new GradleException('缺少 android/key.properties —— 先跑 python3 scripts/android_setup.py app')\n"
                f"{ind}        }}\n"
                f"{ind}        def props = new Properties()\n"
                f"{ind}        propsFile.withInputStream {{ props.load(it) }}\n"
                f"{ind}        def ks = file(props['storeFile'])\n"
                f"{ind}        if (!ks.exists()) {{\n"
                f"{ind}            throw new GradleException('keystore 不存在: ' + ks + ' —— 确认 signing/release.jks 在仓库里')\n"
                f"{ind}        }}\n"
                f"{ind}        storeFile ks\n"
                f"{ind}        storePassword props['storePassword']\n"
                f"{ind}        keyAlias props['keyAlias']\n"
                f"{ind}        keyPassword props['keyPassword']\n"
                f"{ind}    }}\n"
                f"{ind}}}\n\n"
            )
            s = s[:m.start()] + signing + s[m.start():]
            print(f"✓ 插入 signingConfigs（groovy，缩进 {len(ind)}）")
        # 兼容 groovy 两种写法：signingConfig signingConfigs.debug / signingConfig = ...
        s2 = re.sub(r'signingConfig\s*=?\s*signingConfigs\.debug',
                    'signingConfig signingConfigs.release', s)
        if s2 == s and 'signingConfigs.release' not in s:
            # release 块里根本没有 signingConfig 行 → 补一行
            s2 = re.sub(r'(release\s*\{)', r'\1\n            signingConfig signingConfigs.release', s, count=1)
        s = s2
        gradle_groovy.write_text(s, encoding="utf-8")
        print("✓ build.gradle：包名 + release 签名")
    else:
        print("!! 找不到 build.gradle(.kts)", file=sys.stderr)
        return 1

    # ── 1b. 自检：改完必须真的生效，否则立刻失败（不带着错签/错包名去构建 6 分钟）
    gfile = gradle_kts if gradle_kts.exists() else gradle_groovy
    final = gfile.read_text(encoding="utf-8")
    print(f"── gradle 自检（{gfile.name}）──")
    for line in final.splitlines():
        if any(k in line for k in ("applicationId", "namespace", "signingConfig", "storeFile", "keyAlias")):
            print("   ", line.strip())
    ok = True
    if APP_ID not in final:
        print("!! 包名没写进 gradle", file=sys.stderr); ok = False
    if not re.search(r"signingConfigs\s*\{", final):
        print("!! signingConfigs 块缺失", file=sys.stderr); ok = False
    if not re.search(r'signingConfig\s*=?\s*signingConfigs\.(release|getByName\("release"\))', final):
        print("!! release buildType 没接 release 签名", file=sys.stderr); ok = False
    if not ok:
        return 1

    # ── 2. MainActivity 搬家
    src_root = android / "app" / "src" / "main" / "kotlin"
    if not src_root.is_dir():
        src_root = android / "app" / "src" / "main" / "java"
    moved = 0
    if src_root.is_dir():
        for f in list(src_root.rglob("MainActivity.kt")):
            old_pkg_dir = f.parent
            text = f.read_text(encoding="utf-8")
            text = re.sub(r"^package\s+\S+", f"package {APP_ID}", text, flags=re.M)
            new_dir = src_root / PKG_PATH
            new_dir.mkdir(parents=True, exist_ok=True)
            (new_dir / "MainActivity.kt").write_text(text, encoding="utf-8")
            if old_pkg_dir != new_dir:
                shutil.rmtree(old_pkg_dir, ignore_errors=True)
            moved += 1
            print(f"✓ MainActivity → {PKG_PATH}/MainActivity.kt")
    if moved == 0:
        print("!! 没找到 MainActivity.kt（模板可能变了）", file=sys.stderr)

    # ── 2b. AGP 9.0 默认 android.newDsl=true，会让 flutter 模板的 android {} 编译失败。
    # 关掉新 DSL，沿用模板写法（明确固定，不靠 runner 上的 AGP 版本碰运气）。
    gp = android / "gradle.properties"
    txt = gp.read_text(encoding="utf-8") if gp.exists() else ""
    if "android.newDsl" not in txt:
        txt += "\nandroid.newDsl=false\n"
        gp.write_text(txt, encoding="utf-8")
        print("✓ gradle.properties：android.newDsl=false")

    # ── 3. key.properties
    key_props = android / "key.properties"
    repo_root = app.parent
    jks = repo_root / "signing" / "release.jks"
    if not jks.exists():
        print(f"!! 找不到 {jks}", file=sys.stderr)
        return 1
    key_props.write_text(
        f"storePassword=galatea2026\n"
        f"keyPassword=galatea2026\n"
        f"keyAlias=galatea\n"
        f"storeFile={jks.resolve()}\n",
        encoding="utf-8",
    )
    print(f"✓ key.properties → {key_props}")

    # ── 4. 顺手把应用名改成 Galatea（若有 locale 资源也一起）
    for manifest in android.rglob("AndroidManifest.xml"):
        t = manifest.read_text(encoding="utf-8")
        t2 = re.sub(r'android:label="[^"]*"', 'android:label="Galatea"', t)
        if t2 != t:
            manifest.write_text(t2, encoding="utf-8")
    print("✓ 应用名 → Galatea")
    print("\n完成。包名：", APP_ID)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "app"))