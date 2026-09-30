# Reading 临时交接快照（自动化通过，待体验验收）

更新：2026-09-30。用户要求在额度用尽前保存，并总结当前成果。

## 第一结论

不要从头开始。正式 Flutter App 和真实词典已经写好。此前「长按复制后空白点击」回归已修复，双平台集成测试通过。随后用户实测发现 iPhone 点词气泡闪现，现已定位修复并获用户确认。最新 17 项单元/组件测试及静态分析通过，双平台 debug 构建通过；本次气泡修复未重跑会卸载用户书架的设备集成测试。当前进入阶段 2 体验验收；原生文件选择导入、系统栏实际外观与部分视觉项目还未验收，不能把阶段 2 标为全部验收完成。阶段 3 尚未开始。

## 最新完成节点：导入回归与 iPhone 气泡修复

- 用户要求预留额度记录；额度曾从约 30% 降到 14%。上次直接 attach 因自动审批额度不足未执行，用户随后要求继续，本轮执行已恢复。
- **用户发现并确认解决的故障**：iPhone 每次点词后约 30–60ms 释义消失。通过正常应用的原生日志，调用栈明确为 `_ReaderPageState.didChangeMetrics → dismiss`。原代码对任何屏幕参数通知无条件关闭；现捕获查词时的 size/DPR/padding/insets，仅实际几何变化才关闭。临时诊断代码已移除。
- 用户在热更新后明确回复「现在正常了」。17 项完整测试通过；回归覆盖重复 metrics 通知和 3 秒停留不关闭、真实 resize 关闭旧锚点；静态分析通过。
- **持久安装已完成**：正常 iOS debug 构建成功，`simctl install` 覆盖升级，重新启动 Reading PID `71858`。升级前后核对同一个书籍 ID，现有 1 本书保留。模拟器升级会更换数据容器 UUID，不能因旧路径消失就认定丢数据；需重新 `simctl get_app_container`。
- Android 最新正常 debug APK 构建成功（38.3s），位于 `app/build/app/outputs/flutter-apk/app-debug.apk`。本次没有重装安卓模拟器，它仍是上次运行版本；以后体验安卓时先以正常入口更新。
- **TXT 导入新增 8 项回归**：真实 UTF-8 BOM/GBK 文件走正式读取、compute 解析、SQLite、阅读页、返回书架；另测取消、空文件、NUL 内容、读失败、超过 20MB、选择器异常，以及失败后重试。替代了原生对话框，不能宣称原生文件选择 E2E 完成。
- 样本 `app/test/fixtures/txt/`，说明含编码及校验值。人工验收表 `docs/phase-2-acceptance.md`。原生文件选择和部分视觉仍待核验。
- 用户询问 EPUB 是否开始，已明确答复：**尚未开始，阶段 3 必做**，保留文字/图片/简单表格、最终翻页、必做 iPad 双页等原计划。
- 所有本轮测试/构建/attach 会话均已结束。attach 用 `d` 分离，不用 `q` 终止用户应用。

## 当前准确下一步（优先于下面历史记录）

1. 不再重复重跑已通过检查。继续核验阶段 2 的实际系统文件选择导入和气泡/主题/系统栏外观。不要在用户已开始体验的模拟器执行 `flutter test -d`，它可能卸载 App。
2. 打开 Reading 可直接继续阅读现有示例，修复已持久安装。收集用户对阶段 2 的体验反馈；可测试真机型号/版本仍未提供。
3. 阶段 2 体验确认后正式进入阶段 3，优先 EPUB 文字/图片/简单表格与目录，之后按原计划推进翻页/双页/真实句子翻译；不改成长期 TXT-only。
4. 继续重要节点立即更新本文件，保留额度用于记录、提交和明确剩余项。

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
- `flutter test --reporter expanded`：17 项通过（UTF-8/BOM/GBK、章节/空文件、英文范围/句子、样式、数据库真实关闭重开、完整 ECDICT、三档/展开/未命中、窄屏长气泡/角落几何、长按松开再弹复制面板、空白切换工具栏、重复 metrics 保持气泡、真实文件导入和失败后重试）。最新共 17/17 通过。
- `flutter analyze`：最终代码 No issues found（5.6s）。临时手势/区域诊断输出已移除。
- iOS 模拟器 debug 构建成功；Android debug APK 构建成功。
- **前一检查点（501cafd）的沉浸和原生亮屏集成测试，本轮未在用户体验设备重跑**：iPhone 18 Pro（20s）和 Android API 36（25s）均 `All tests passed`：粘贴 → 真词典查词 → 展开 → 复制句子 → 即时设置 → 空白隐藏/恢复工具栏 → 进度 51% → 销毁并重建 App 和数据库 → 恢复段落/粗体 → 书名修改/搜索/删除。另已通过 `WakelockPlus.enabled` 核验阅读时原生亮屏开启、返回书架关闭。
- 查词是本地 SQLite；最终 1000 次 debug 模拟器查询：iOS p95 0.168 ms / max 9.050 ms；Android p95 1.014 ms / max 51.144 ms。本轮宿主 p95 0.223 ms / max 0.593 ms。机器负载/调试会造成波动，不能把每次 `<5ms` 目标宣称已全部达成，也不能用模拟器代替真机性能验收。
- CUA 在 iOS 已实际看到书架、文字封面、正文排版、系统 TXT 文件选择器（空 Recents）。字体/排版基本可显示。**没有完成从原生选择器选一份实际 TXT 的端到端验收，也没有完成气泡截图视觉验收**。不要把解析测试等同于原生文件选择测试。

## 本轮解决的阻塞：沉浸空白点击

- 失败可追溯到先前的长按复制，设置关闭只是暴露问题的位置。命中测试证实点击到了阅读区，手势日志只出现 VerticalDrag，没有外层 Tap 参与；并非设置覆盖层或左右屏幕边缘。
- `ReaderParagraph` 原先在 `onLongPressStart` 直接 push 复制面板；当前在开始时记录句子位置，`onLongPressEnd` 松开后才打开，取消时清空位置。Flutter Navigator 在打开路由时会取消尚未结束的指针；此改法避免面板出现时仍有按压中的手势。
- 同样的完整集成测试由失败变为双平台通过，原失败断言保留。尚未证明旧问题在正常发行应用中一定出现；不要将测试绑定的问题过度宣传为所有用户设备的故障。
- 新增 `app/test/reader_interaction_test.dart`，覆盖真实词典点词/展开/关闭、长按松开才弹面板、复制后和字号/粗体设置后的空白切换。
- 小范围测试发现字体下拉菜单在窄屏测试字体下溢出 41px，已通过 `isExpanded: true` 修复。
- 日志 `artifacts/immersive-diagnostic.log` 为本机诊断记录（Git 忽略），最终版本移除了这些诊断输出。

## 精确下一步

1. iPhone 已覆盖升级本轮气泡修复并启动，书架核对保留；安卓最新 APK 已构建但模拟器未更新，后续用正常入口升级。
2. 通过 CUA 实际导入 UTF-8/GBK TXT 文件，核验系统文件选择器到书架的端到端路径；解析器和粘贴路径已经通过。当前 CUA 对 Device Hub 返回 `noWindowsAvailable`，这属于界面自动化受限，不是 Flutter 构建失败；不要用其他 UI 自动化技术绕过。
3. 视觉核验词旁气泡在边缘、各主题/字体、沉浸系统状态栏的实际隐藏与恢复。自动化目前核验工具栏，不等同系统栏像素验收。
4. 让用户体验阶段 2；可提供 iPhone/iPad/安卓型号和系统版本，安排真机安装。无需用户重装环境、寻找旧源码或做工程调试。
5. 用户体验验收阶段 2 后继续 EPUB/翻页/必做 iPad 双页/真实翻译等阶段 3，不能长期停在 TXT-only。

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

- 17 项测试 session `45482` 通过；目标手势回归 `27321` 通过；analyze `48669` 通过。
- iOS build `90461` 成功；覆盖安装 `64836` 成功；正常应用新进程 `71858`。升级后的应用数据根目录需通过 `simctl get_app_container` 动态查询。
- Android build `19163` 成功；未安装到当前安卓模拟器，不要误称已更新。
- attach `15934` 已用 `d` 分离结束。直接依赖 mDNS 的 attach 曾挂起；可从 `simctl spawn <ID> log show --last 15m --predicate 'process == "Runner" AND eventMessage CONTAINS "VM service"'` 找当前 VM URL，再 `READING_PROXY_URL='' ../scripts/flutterw attach -d <ID> --debug-url <URL>`。URL 重启会变，勿复用历史端口。
- attach 的控制台没有转发本轮 debugPrint；实际诊断从 iOS 原生日志读取（查询 Runner + 调用栈方法名）。别因 attach 输出空白就断言用户没有点击。
- 两个 Runner 进程可能同时存在：旧 `dev.reader.helloCheck` 和正式 `dev.reading.readingApp`，需按 bundle identifier 核对。勿杀未知进程。
- CUA 当前已恢复读取 Device Hub 窗口；先前间歇超时/noWindowsAvailable 仍需留意。不要用不可用的 macOS `cua.computer.launch_app`。
- 本轮用户已经开始体验 iPhone，后续按有用户数据的环境对待；不再把模拟器视为可随意清空。
- 最新阶段验收表见 `docs/phase-2-acceptance.md`，样本目录说明见 `app/test/fixtures/txt/README.md`。
