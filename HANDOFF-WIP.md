# Reading 临时交接快照（未完成验收）

更新：2026-09-30。用户要求在额度用尽前保存，并总结当前成果。

## 第一结论

不要从头开始。正式 Flutter App 和真实词典已经写好，阶段 2 主流程曾分别在 iPhone 与安卓模拟器通过集成测试；后来新增的「点击空白进入沉浸模式」断言在两端失败，当前最新版集成测试不是全绿。阶段 2 尚未全部验收；阶段 3 尚未开始。

## 项目与基线

- 根目录 `/Users/tty/Desktop/Coding/Reading`，正式工程 `app/`，网页参考 `prototype/reader.html` 保留未改。
- 当前计划 `PLAN.md`；原计划逐字副本 `docs/original-plan.md`；原始来源 `/Users/tty/.claude/plans/linga-macos-iphone-whimsical-wozniak.md`。
- 独立 Git 已建立，原型/交接基线提交 `ed8fabc`。本快照随 WIP 检查点保存；用 `git log -2 --oneline` 查看最新提交。
- 用户要求：Flutter iPhone/iPad/安卓、离线词典、词旁气泡、三档释义。阶段 2 滚动阅读；阶段 3 最终默认翻页及必做 iPad 横屏双页。EPUB 必须后续完成。
- 教材只先支持文字、图片、简单表格；不扩展公式或复杂固定版式。真机型号/系统版本仍未提供，不阻塞当前开发。

## 本轮已实现的代码

1. **真实 ECDICT 词典**：`scripts/fetch_assets.py` 下载固定源版本，`dict_builder/build_ecdict.py` 生成 entries/senses/forms 和 manifest。770,611 词条、1,183,688 条释义、57,247 条词形映射；数据库 118,620,160 bytes。源版本 `bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b`。CSV、生成 SQLite 在本机，按计划不入 Git；源版本/校验值/生成器/许可证入 Git。不要误删大数据库后直接构建，需先重建。
2. **Flutter 工程**：Riverpod 3、drift 2.35、sqlite3 3.6；已打包四款 OFL 字体及许可证。App 包名 iOS `dev.reading.readingApp`、Android `dev.reading.reading_app`。
3. **导入和书架**：UTF-8/GBK TXT 解析、粘贴文本、章节识别、文字封面、最近阅读排序、书名搜索/重命名/删除、继续阅读。20 MB TXT 上限。示例是原型里的《Pride and Prejudice》公版节选，不含旧原型模拟词典/译文。
4. **阅读**：懒加载滚动段落、进度显示/跳转、TXT 目录、自动存段落位置、长按选句/复制、词语复制、保持亮屏调用。
5. **查词**：字形矩形定位、淡色高亮、真实离线查词、词形还原、极简 1–3 义（默认 2）、简洁、完整卡片、未收录提示、边缘限制和长内容滚动。完整卡片用 ECDICT 自带英文定义，未冒充 Wiktionary/例句。
6. **设置**：字体/字号/粗体/行距/字距/段距/边距/对齐/四主题/跟随深色/气泡字号/释义档位与数量；默认样式及每书样式保存。New York 未作为未验证的字体选项提供。
7. **架构接口**：BookParser、LanguageSupport、DictionaryProvider、Translator 已保留；Translator 仅接口，未接假翻译。Android 原生 Insets 通道已写入，用于 API 36 的系统栏控制。
8. **文档**：AGENTS.md、PLAN.md、HANDOFF.md、根 README、app/README、原计划副本。当前临时快照是最精确断点。

## 已经得到的验证结果

- `python3 -m unittest discover -s tests -v`：2 项通过（生成器释义顺序、schema、词形、manifest）。
- `flutter test --reporter expanded`：8 项通过（UTF-8/BOM/GBK、章节/空文件、英文范围/句子、样式、数据库真实关闭重开、完整 ECDICT、三档/展开/未命中、窄屏长气泡/角落几何）。最后一次 8/8 通过。
- `flutter analyze`：最后一次 No issues found。之后仅添加了沉浸测试的诊断输出，需要收尾再跑一次。
- iOS 模拟器 debug 构建成功；Android debug APK 构建成功。
- **新增沉浸断言之前**：主集成流程在 iPhone 18 Pro 和 Android API 36 都有 `All tests passed`：粘贴 → 真词典查词 → 展开 → 复制句子 → 即时设置 → 进度 51% → 销毁并重建 App 和数据库 → 恢复段落/粗体 → 书名修改/搜索/删除。
- 查词是本地 SQLite；1000 次 debug 模拟器查询典型 p95：iOS 0.159 ms，Android 0.179 ms；最大值分别曾约 9.8 ms/17.9 ms。因此不能把每次 `<5ms` 目标宣称已全部达成，也不能用模拟器代替真机性能验收。
- CUA 在 iOS 已实际看到书架、文字封面、正文排版、系统 TXT 文件选择器（空 Recents）。字体/排版基本可显示。**没有完成从原生选择器选一份实际 TXT 的端到端验收，也没有完成气泡截图视觉验收**。不要把解析测试等同于原生文件选择测试。

## 当前最高优先级问题：沉浸空白点击

位置：`app/lib/reader/reader.dart` 的 `toggleChrome()`，约第 122 行；`app/integration_test/reading_flow_test.dart` 约第 127 行起新增断言。

- 设置关闭后，没有 WordBubble。
- 测试读取 reader-text 的矩形：`Rect.fromLTRB(0.0, 62.0, 402.0, 840.0)`。
- 点左空白 `(6, 451)` 和右空白 `(390, 451)`，两者都未隐藏 reader-settings 工具栏。
- 在 `toggleChrome` 加了临时 `debugPrint('Reader toggle: ...')`，失败的测试日志里没有该输出，说明手势没有进入此方法。**不能简单断言是系统返回边缘手势问题：右侧也失败。**
- 两端同样失败，优先检查 Flutter 层的 hit test/覆盖层/手势事件路径。字号/粗体/进度等此前能操作。
- 目前仍保留这两个诊断打印（Reader toggle、Reader area）。不要把失败断言删掉来声称通过。

**精确下一步：**
1. 在这个断言前输出 `tester.hitTestOnBinding(margin)`；这是本地 SDK `flutter_test` 已确认存在的公开方法。检查哪个 RenderObject/ModalBarrier/PointerListener 截获点击，再定位覆盖层或 GestureDetector。也可先写一个含 ReaderPage 的针对性 widget 测试（需 mock 平台通道）缩短回归周期。
2. 修好后验证空白点击隐藏/显示工具栏；确认系统栏也按预期变化。Android 原生实现见 `MainActivity.kt`；Dart 接口 `lib/core/reader_system_ui.dart`。
3. 删除临时诊断打印，保留回归断言；顺序运行两个模拟器集成测试。
4. 核验 Wakelock 原生状态、真实文件选择导入（UTF-8/GBK）、实际气泡位置/三主题等尚未人工核验的细节。原型双页视觉不阻塞阶段 2，双页实际实现归阶段 3。
5. 全部通过后更新 HANDOFF/验收记录，构建正常 `lib/main.dart` 应用并启动给用户体验。当前 APK 可能是 integration_test 入口，**不要直接把现存 app-debug.apk 当作最终体验包交付**。
6. 用户体验阶段 2 后再进入 EPUB/翻页/双页/真实翻译等阶段 3，不改成长期 TXT-only。

## 已修的问题

- 初版粘贴/位置持久化已实现，进度跳转改为立即入保存队列；常规滚动仍 250ms 防抖。
- “已复制” Snackbar 曾盖住进度条：现放在底部上方 120px，打开设置/离开阅读会隐藏。
- 搜索键盘遮挡书籍操作的测试问题：搜索完成 unfocus、滚动可收键盘；测试仅对最后书籍菜单 ensureVisible。不要对所有 tap 一概 ensureVisible，它会把设置列表滚到意外位置，导致 size 控件卸载。
- 代码格式化后 lint 提示已用 dart fix 修正，未关闭 lint 规则。

## 开发环境与命令

- Flutter 3.47.5 / Dart 3.13.4，路径 `/opt/homebrew/share/flutter`；Xcode 27；Android SDK `~/Library/Android/sdk`；JDK 25。
- iPhone 模拟器 ID：`144FF884-EC04-4E7F-9BE6-AFF8264E8699`。
- 安卓设备：`emulator-5554`，AVD `Reader_Phone`，API 36。
- `scripts/flutterw` 默认给子进程设置 HTTP(S) 大小写代理 `http://127.0.0.1:7897` 及 NO_PROXY。`READING_PROXY_URL=''` 会清除 HTTP/HTTPS/ALL_PROXY 两组变量，仅影响子进程，不改系统设置。
- 下载依赖用默认代理；设备测试先 pub get，之后关闭进程代理并 `--no-pub`。关闭代理后安卓曾成功跑完主流程，但后续仍有间歇 ADB/VM Service 断线或等待，**网络根因尚未完全确认**。
- **不要让同一个安卓设备的 run 和 test 同时运行**，它们会安装/停止同一个包。已有一次正常 run 与后续 test 重叠导致 DevFS 断开，不能据此判定应用崩溃。
- `flutter test -d` 清理可能卸载整个包；测试用临时业务库仍不能避免工具卸载。只在专用模拟器运行，勿用于已有真实书架的设备。
- iOS UI 宿主是 Device Hub (`com.apple.dt.Devices`)，不是旧 Simulator.app。CUA 可读 AX/截图，但坐标点击和原生 picker AX 有不稳定现象。继续 CUA 前按工具要求读 `cua.rewriteDocumentation()`，不要用其他技术绕过 UI 控制规定。
- 系统 curl TLS 可用；此机器 Python urllib 证书链失败，下载脚本已经改用 curl，未关闭证书验证。
- 写 Flutter 缓存、SDK、模拟器操作通常需要 exec_command `sandbox_permissions=require_escalated`，属于已授权开发工作。

```sh
cd /Users/tty/Desktop/Coding/Reading
python3 -m unittest discover -s tests -v
# 仅缺失资产时：
python3 scripts/fetch_assets.py
python3 dict_builder/build_ecdict.py

cd app
../scripts/flutterw pub get
../scripts/flutterw analyze
../scripts/flutterw test --reporter expanded
READING_PROXY_URL='' ../scripts/flutterw test integration_test/reading_flow_test.dart -d 144FF884-EC04-4E7F-9BE6-AFF8264E8699 --no-pub --reporter expanded
# 等上一个测试彻底退出后：
READING_PROXY_URL='' ../scripts/flutterw test integration_test/reading_flow_test.dart -d emulator-5554 --no-pub --reporter expanded
# 通过后构建正常入口并运行，务必等待结束后再做下一次安装：
READING_PROXY_URL='' ../scripts/flutterw run -d 144FF884-EC04-4E7F-9BE6-AFF8264E8699 --no-pub --no-resident
READING_PROXY_URL='' ../scripts/flutterw run -d emulator-5554 --no-pub --no-resident
```

## 最后一次运行与遗留文件

- 最后 iOS 集成测试 exec session `89857` 已失败退出，原因是上述右侧空白点击断言。
- 挂起的安卓测试 PID `96047` 已定向 SIGTERM；session `44775` 返回 `No tests ran` 后退出。不要重复杀未知进程。
- 旧安卓详细连接失败日志在 `artifacts/android-integration.log`（被 Git 忽略，含本地调试 URL）。
- 最新 8 项单元/组件测试和 analyze 的 exec sessions 已成功结束。
- `HANDOFF.md` 将链接本文件；续做先读本文件，不要把旧“阶段 2 开发中”当成没有源码。
- 当前没有真实用户导入书籍被要求迁移；模拟器里只有我们创建的示例/临时测试数据。别把后续用户数据当作可删除的测试数据。
