/// 版本号由 CI 注入：`flutter build apk --dart-define=APP_VERSION=$VER`
/// 本地跑时用默认值。
const String kAppVersion =
    String.fromEnvironment('APP_VERSION', defaultValue: '0.2.0-dev');
