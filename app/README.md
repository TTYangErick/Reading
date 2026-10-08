# Reading Flutter App

支持 EPUB 2/3、TXT／粘贴导入、书架、英汉/英英离线查词、单页/双页和滚动阅读、脚注、目录、图片、简单表格、样式与精确位置保存，以及原生句子翻译和译文缓存管理。
完整执行状态和验收结果只见上层 `PLAN.md`；原计划见 `../docs/original-plan.md`。

## 重建与运行

从 Reading 根目录执行：

```sh
python3 scripts/fetch_assets.py
python3 dict_builder/build_ecdict.py
python3 scripts/fetch_wiktionary.py
python3 dict_builder/build_wiktionary.py
cd app
../scripts/flutterw pub get
READING_PROXY_URL='' ../scripts/flutterw run --no-pub
```

词典 CSV/JSONL/gzip 与生成的 SQLite 不纳入 Git；`dict_builder/source.json` 固定 ECDICT 版本及 SHA-256，`assets/dictionaries/manifest.json` 记录数据库版本、行数、校验值。Wiktionary 快照与生成结果分别由 `dict_builder/wiktionary-source.json` / `assets/dictionaries/wiktionary-manifest.json` 锁定，来源与许可证见 [词典契约](../docs/dictionaries.md)。字体文件及许可证已纳入 Git。无需付费 API 或联网查词。

`scripts/flutterw` 默认只给子进程配置本地代理 `127.0.0.1:7897`。可通过 `READING_PROXY_URL` 覆盖；设为空字符串可关闭。它不改变系统网络设置。

本机实测：下载依赖时需代理；安卓调试曾有间歇断连，代理并未被证实为唯一原因。最终双平台集成测试采用先正常 `pub get`，再用 `READING_PROXY_URL=''` 运行或执行设备集成测试的方式通过。空值会清除该子进程的大小写 HTTP/HTTPS/ALL_PROXY。Gradle 保留已有的下载代理配置。

## 验证

```sh
# Reading 根目录
python3 -m unittest discover -s tests -v
python3 -m unittest discover -s dict_builder -p test_wiktionary.py
# app 目录
../scripts/flutterw analyze
../scripts/flutterw test --reporter expanded
READING_PROXY_URL='' ../scripts/flutterw test integration_test/reading_flow_test.dart -d <设备ID> --no-pub --reporter expanded
../scripts/flutterw build ios --simulator --debug
../scripts/flutterw build apk --debug
```

集成测试的业务数据使用临时数据库，但 `flutter test -d` 工具会重装/卸载测试应用：仅在专用模拟器运行，勿在已有真实书架的设备运行。测试覆盖真实词典、粘贴导入、气泡与复制、即时设置、跳转、销毁并重建 App/数据库后的位置恢复、书名搜索/修改/删除。

## 代码与数据

- `lib/book`：可替换 BookParser，UTF-8/GBK TXT 和可重排 EPUB 2/3 解析、目录及图片资源。
- `lib/text`：LanguageSupport，英文点词范围、句子范围及候选词。
- `lib/dict`：DictionaryProvider，组合只读 ECDICT 英汉与 Wiktionary 英英；词形、来源和释义顺序查询。
- `lib/db`：drift 业务数据库，书架/正文/段落索引/设置/译文缓存；不修改词典包。
- `lib/reader`：单/双页排版、正文与脚注位置、字形矩形定位、气泡、阅读设置。
- `lib/backup`：单文件备份、限额/完整性预检、确认与事务恢复。
- `lib/core`：Riverpod 依赖、平台沉浸模式。
- `lib/translate`：Apple Translation / Android ML Kit 原生接口、句子面板和缓存管理；模型需先下载，Apple 翻译需 iOS/iPadOS 18+ 真机。

数据仅保存在 App 的 Application Support 目录。卸载 App 会清除本地书架；书架“更多 → 备份与恢复”可保存和导入 `.readingbackup` 文件；预检与确认后整库替换，不合并。备份业务数据与图片的具体范围、兼容规则和限额见 [备份与恢复](../docs/backup.md)。

当前 TXT 上限 20 MB，EPUB 上限 50 MB；分页位置保存原文块内偏移或媒体/表格行，不保存易变页码。EPUB 基础功能范围和限制见 [EPUB 验收记录](../docs/epub-acceptance.md)，链接与补充脚注见 [链接契约](../docs/epub-links.md)。词汇本、备份和剩余设备验收见 `../PLAN.md`。

TXT 真实文件与错误重试回归：`test/file_import_test.dart`（替代原生选择对话框）；样本在 `test/fixtures/txt/`。原生操作的当前未关闭项见 [PLAN.md](../PLAN.md)；[阶段 2 验收表](../docs/phase-2-acceptance.md)仅保留历史观察。

两份词典均未收录的词会在原气泡尝试英译中机器翻译，并明确标注；首次模型下载需点击确认。词库出错或只有所选释义语言缺失时不会用机器译文替换词条。点气泡外仍只关闭当前释义。

书架“更多 → 查词历史”可搜索最近200个原词、重新查看释义并确认清空。自动历史与生词收藏分开，备份包含历史；旧备份恢复时历史为空。

通过目录跳转后，可在原阅读操作中选择“返回目录跳转前”；连续目录跳转保留最初来处。跳转位置照常保存，重开不会恢复临时返回点。

书内图片可点击进入查看器，双指缩放、放大后拖动，双击或按钮还原；关闭/系统返回回到原阅读位置。有点词释义时第一次点图片仅关闭释义。大图按解码上限显示，不影响正文排版。

首次书架提示可查看或跳过阅读指南，也可从“更多 → 阅读与离线准备”随时重开。指南区分内置词典和单独的句子翻译模型；只查看状态，不自动下载。需要时主动点击下载语言模型，之后可先断网用新句检查。

## 原生图标与发布构建

在macOS从仓库根目录运行 `swift scripts/generate_app_icons.swift`，从共享矢量几何重建iOS/Android书本图标及启动素材；启动背景颜色分别在Android `res/values*/colors.xml` 和iOS `LaunchBackground.colorset` 中，与Flutter浅/深色背景对齐。

Android本地优化测试包（在app目录）：

```sh
../scripts/flutterw build apk --release --target-platform android-arm64 --split-per-abi -P force-version-code-ignoring-abi=true
```

产物为 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`，只支持ARM64。当前Release沿用debug签名，iOS沿用开发签名；这些是本地测试配置，不是正式商店分发配置。发布前需要所有者管理的签名与渠道配置，并完成隐私申报及设备验收；具体状态只记录于上层PLAN.md。不要为替换图标修改现有应用标识或卸载用户数据。
