# Reading Flutter App

支持 EPUB 2/3、TXT／粘贴及外部文件导入、书架、可选启动续读、英汉/英英离线查词、单页/双页和滚动阅读、脚注、目录、图片、简单表格、样式与精确位置保存，以及原生句子翻译和译文缓存管理。
完整执行状态和验收结果只见上层 `PLAN.md`；原计划见 `../docs/original-plan.md`。

## 从其他 App 导入

在 iPhone/iPad 的文件 App 选择 EPUB/TXT，使用“用 Reading 打开”；Android 可从文件管理器打开或分享单个 EPUB/TXT 给 Reading。回到书架，确认待导入卡片即可添加；也可忽略。正在读书时只接收，不会跳走。待处理文件不跨应用进程保存，必要时重新分享；V1不接收批量文件或网页链接。完整入口、限制和兼容规则见 [导入契约](../docs/import.md)，真实系统投递验收状态见PLAN。

## 启动时继续阅读

在书架“更多 → 启动设置”开启“启动时继续阅读”，下次启动可直接打开最近读过且仍在书架的书。默认关闭；返回书架或切回App不会再次自动打开。外部待导入文件优先，完整规则见 [启动契约](../docs/startup.md)。

## 阅读方向

阅读时可在“阅读设置 → 阅读方向”选择手机横竖屏；离开阅读恢复系统方向。iPad及大屏保留窗口/多任务能力，跟随系统，可用系统旋转锁定。规则与兼容边界见 [阅读方向](../docs/orientation.md)。

## 文字选择与翻译

长按选句后拖动，可选择多个正文段落或左右双页文字；分页时在整个阅读区域左右外侧边缘停留片刻，可继续向前/后翻页选择，中缝不触发。松手后回到起始阅读页并打开原翻译/复制面板，取消也恢复原页，不改变已保存位置。滚动模式不自动滚动，图注/表格单元格仍单独选择，正文选区不跨图片/表格，详见 [选区规则](../docs/translation.md#拖动选区与短语)。

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

首次分页性能诊断单独按需运行，样本、命令和测量边界见 [benchmark/README.md](benchmark/README.md)；不包含在常规全量测试，也不代替真机Profile。

宿主GBK测试间歇崩溃的普通Dart/Flutter最小对照与采证入口见 [运行时诊断](benchmark/README.md#gbk-测试运行时诊断)；当前结论只见PLAN，不把一次通过当作问题已修复。

原生构建按上述入口刷新插件配置；不要与会重新生成插件注册文件的其他Flutter任务并发。若Android Release报告 integration_test 插件缺失，先按正常入口构建（不要跳过pub刷新），不手改生成文件或把测试插件加入生产依赖。

## 代码与数据

- `lib/book`：可替换 BookParser，UTF-8/GBK TXT 和可重排 EPUB 2/3 解析、目录、作者与本地封面/图片资源。
- `lib/imports`：有界外部文件收件箱、确认卡片与读取；原生文件入口分别在Android ReadingImports和iOS ReadingImports/SceneDelegate。
- `lib/library`：书架、导入与管理，EPUB作者/封面展示；旧书或缺图沿用文字封面，识别与资源边界见 [阅读契约](../docs/epub-links.md#书架作者与封面)。
- `lib/text`：LanguageSupport，英文点词范围、句子范围及候选词。
- `lib/dict`：DictionaryProvider，组合只读 ECDICT 英汉与 Wiktionary 英英；词形、来源和释义顺序查询。
- `lib/db`：drift 业务数据库，书架/正文/段落索引/设置/译文缓存；不修改词典包。
- `lib/reader`：单/双页排版、正文与脚注位置、字形矩形定位、气泡、阅读设置。
- `lib/backup`：单文件备份、限额/完整性预检、确认与事务恢复。
- `lib/core`：Riverpod 依赖、平台沉浸模式。
- `lib/startup`：可选启动续读与全局开关，复用书架书籍对象及阅读位置，不增加每书样式字段。
- `lib/orientation`：全局阅读方向偏好、嵌套阅读会话和系统方向请求，不保存正文位置。
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

## 集中交付与真机性能记录

此处是操作入口；待验项目和结论只维护在PLAN。仓库根目录执行下列命令，仅构建和核验，不安装应用：

```sh
python3 scripts/prepare_delivery.py
# 此后可单独核验已生成目录（实际路径由准备命令输出）
python3 scripts/prepare_delivery.py --verify 'artifacts/delivery/reading-版本-源码短revision'
```

准备命令要求应用源码及样本已提交（保留本机未跟踪Gradle运行时配置），顺序构建同一revision的Release/Profile，检查版本/包名/ARM64/签名、两包身份一致及内置词典的固定manifest/SHA，然后复制两包和五份既有EPUB样本，生成记录源码、大小和SHA的manifest。已有目标目录会拒绝覆盖；失败仅清理本次临时目录，旧交付保留。目录在忽略的artifacts内，不是跨机器恢复前提；换机器可由已提交源码、词库恢复入口及此脚本重建。需要本机Android SDK build-tools及可用JDK；脚本沿用JAVA_HOME，未设置时使用现有macOS Android Studio JDK，不安装运行时。

构建原件仍在 `build/app/outputs/flutter-apk/app-arm64-v8a-{release,profile}.apk`；交付使用准备命令输出的固定副本，后续构建不会覆盖副本。Release用于通常的体验检查；Profile用于连接DevTools采集UI/Raster帧耗时、CPU及内存，不以Debug包或宿主基准判定真机流畅度。依据和工具入口见 [Flutter性能测量](https://docs.flutter.dev/perf/ui-performance)、[DevTools Performance](https://docs.flutter.dev/tools/devtools/performance)。

用户安排安装后，先读取新的设备/当前包版本与签名、书库/位置/设置基线；同应用标识、同签名且不降级才正常覆盖更新。不卸载、不清库、不在用户设备运行flutter test -d；无法读取一致基线时先解决基线，不用旧快照替代。需完整业务快照时先通过应用导出备份；原始SQLite复制必须包含当次WAL并保证一致性。备份替换验收用专用环境。

已正常更新并手动打开Profile应用后，在app目录连接（此命令本身不安装）：

```sh
READING_PROXY_URL='' ../scripts/flutterw attach --profile -d <设备ID>
```

按工具给出的DevTools入口录制/导出性能快照。记录设备/系统、刷新率、包版本/校验值、书籍稳定标识与大小、布局/字体、测量场景；不将原文或私人书库放进Git。分别测新进程首次开书、同会话重开、翻页/点词面板、书架滚动，先记录默认追踪，再为定位慢帧单独开启详细追踪。每场景重复三次，保留全部结果及首次/重开区别，不只挑最好的一次；结合屏幕刷新率看UI/Raster耗时与慢帧比例，记录峰值RSS和GC，不把Dart堆大小等同进程总内存。仍显示重新分页时核对缓存是否被预算拒绝，不先提高资源上限。

小样本只用于功能检查：封面/作者三份样本的预期见 [样本说明](test/fixtures/epub/README.md)；脚注继续复用footnotes-epub2/3。真实性能用原先出现卡顿的同一本书和同一设备。Trace、截图、设备快照、安装包放忽略的 `../artifacts/`，当前结论回写PLAN，不另建验收计划。
