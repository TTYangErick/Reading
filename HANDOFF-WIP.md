# Reading 最新小步骤交接

更新：2026-10-02。本轮起点 `7cb9967`，工作区核对干净，应用源码无变化。本轮仅完成之前因 limit 留下的安卓构建核验和交接同步。

## Current Goal

补完 SVG 栅格封面修复的安卓 debug 构建，关闭该修复的工程验证记录；不展开脚注、分页或设备安装。

## Completed

- 使用 `scripts/flutterw` 默认代理正常构建 Android debug APK，构建退出码 0。
- 新 APK 已包含 `7cb9967` 的 SVG 封面修复；两端构建验证至此完成。没有更新或卸载模拟器应用，没有改动书架。
- 产物证据保存于忽略目录 `artifacts/svg-android-build.json`，包含来源提交、命令、大小、SHA-256、未安装标记及工具链警告。
- 同步主交接、计划与两份 EPUB 验收文档；下一轮唯一任务设为脚注链接/锚点解析模型。

## Verification

- **本轮新增**：在 `app/` 执行 `../scripts/flutterw build apk --debug --no-pub` 成功，Gradle assembleDebug 16.8s；session 71469 已结束。
- APK：`app/build/app/outputs/flutter-apk/app-debug.apk`，247,039,777 bytes；SHA-256 `87fab7708d785d1e9fca5a01981952c1a031f7baaae9e86d07b222036c7ec79f`。
- 构建出现 Java native-access 和 SDK XML 版本提示，均非阻断；本轮没有为警告更改环境或依赖。
- **沿用上一轮证据，未重复执行**：`7cb9967` 的 32/32 宿主测试、静态分析、iOS 模拟器 debug 构建通过；真实书 3,178 个文字块保持原顺序，提取两张图片，17 项目录目标正确 +1，JSON 往返一致。
- Git 核对应用源码/测试与 `7cb9967` 一致。本轮只有文档变更，按规则不重跑已通过且不受影响的测试/iOS 构建。
- **未验证**：新封面的原生视觉；两端模拟器已安装 App 未更新。历史用户“全部正常”指修复前真实书阅读，不是这次新封面验收。

## Current Project State

阶段 2 主体、阶段 3 EPUB 基础版已实现；SVG 简单单张栅格封面修复已通过解析/持久化测试、静态分析和双平台构建。旧库不重解析，原位置保留；新导入才增加封面块。

安卓真实小说基础阅读曾获用户实测通过；iPhone/安卓原创样本也通过。原 NCX 漏第 15 章未补全，正文不缺。iPhone 本真实书、真实教材、大书、iPad 设备未验收。iPad 仅通用工程/宽屏组件测试，左右翻页与横屏双页未实现。

当前无运行中的 build/test/attach/下载服务。原 EPUB 保留在用户 Downloads，安卓副本 `/sdcard/Download/reading-real-book.epub`。无数据库注入，不重新启动旧样本服务器。

## Key Decisions / Context

**工作方式调整**：此前 Next Step 混合多端验收、脚注和分页；依用户新要求改为一个周期一个目标，其余放入 Remaining Plan，防止额度/上下文中断时遗留大范围未验证修改。

- 保留 Flutter + Riverpod + drift 及 `BookParser`、`LanguageSupport`、`DictionaryProvider`、`Translator` 接口；新增 `EpubParser`，不另造第二套阅读/查词实现。
- `BookContent` 保存格式、标题、章节和内容块；图片只在导入时携带字节，持久化进入 `book_assets`，避免图片膨胀书架正文 JSON。`BookBlock` 兼容旧文本并增加图片路径/表格行；`BookChapter` 指向内容块索引。
- 图片固定显示高度以减少异步加载导致的位置跳动；位置仍精确到内容块，尚不是分页定位模型。
- 原计划按阶段 2 验收后进入阶段 3；用户于 2026-09-30 明确授权先开始 EPUB，10-01 要求继续，因此阶段 2 未验收项继续保留，但不阻塞 EPUB。最终左右翻页/iPad 双页要求没有取消。
- 现有 EPUB 基础版仍用滚动阅读，开发该版本时未并行扩展翻译和分页；教材范围保持文字、图片、简单表格，复杂固定版式/公式不扩大进来。
- 必须保留两处既有修复：`didChangeMetrics` 仅实际视窗几何变化才关闭气泡；长按复制在 `onLongPressEnd` 才打开面板，避免取消尚未结束的手势。iPhone 闪现问题已获用户确认解决。

项目根目录 `/Users/tty/Desktop/Coding/Reading`；正式工程 `app/`；原型 `prototype/reader.html` 只作视觉参考，含模拟数据。

| 入口 | 续做要点 |
|---|---|
| `app/lib/book/book.dart` | `BookParser`/`ParserRegistry`、`BookContent`、`BookBlock`、`BookChapter`，保持旧 JSON 兼容 |
| `app/lib/book/epub.dart` | `EpubParser.parse`、`_Epub.read`/`addChapter`、`_Blocks.walk`：容器/OPF、资源、目录与内容提取 |
| `app/lib/library/library.dart` | `parseImportedFile`、`importFile`：系统选择、后台解析、入库与打开书籍 |
| `app/lib/db/database.dart` | schema 2；`addBook`/`asset`/`deleteBook`、`savePosition`；图片和正文一起事务保存 |
| `app/lib/reader/reader.dart` | `renderBlock`、`contents`、`jump`、`lookup`、`ReaderParagraph`，包含气泡和长按回归修复 |
| `app/test/epub_test.dart` | EPUB 2/3、错误文件、资源、旧库迁移/关闭重开等回归 |
| `app/test/file_import_test.dart` | 真实文件→解析→数据库→阅读，但替代原生选择对话框；不能当作原生 E2E |
| `docs/epub-acceptance.md`、`docs/phase-2-acceptance.md` | 已验证范围及未关闭的人工验收 |
| `scripts/make_epub_fixture.py` | 重建 `app/test/fixtures/epub/` 原创样本，不依赖网络 |

- Flutter 3.47.5/Dart 3.13.4；使用 `scripts/flutterw`，默认代理 `http://127.0.0.1:7897`，仅影响子进程。下载/构建保留默认代理；设备调试 `READING_PROXY_URL=''` 清除两组代理，使用支持的 `--no-pub`。代理未被证明是历史设备断连的唯一原因。
- iPhone UDID `144FF884-EC04-4E7F-9BE6-AFF8264E8699`，bundle `dev.reading.readingApp`；UI 宿主 Device Hub `com.apple.dt.Devices`。
- Android SDK `/Users/tty/Library/Android/sdk`，设备 `emulator-5554`，包名 `dev.reading.reading_app`；样本 `/sdcard/Download/reading-lesson.epub`。不要并行对同设备 run/test。
- 真实 ECDICT 数据库在 `app/assets/dictionaries/ecdict.sqlite`（Git 忽略）；不要删除后直接构建。仅缺失时用 `scripts/fetch_assets.py` 和 `dict_builder/build_ecdict.py` 重建。770,611 词条；不是原型示例词典。
- 最近构建产物：`app/build/ios/iphonesimulator/Runner.app` 已含本轮 SVG 修复；`app/build/app/outputs/flutter-apk/app-debug.apk` 本轮已构建，包含 SVG 修复。两端已安装 App 都未更新。升级前后 iPhone 比对资料在忽略的 `artifacts/epub-upgrade-state.json`。
- 解析器在 `7cb9967` 修复，测试/分析已通过；本轮仅补安卓构建，两端构建均通过。复查命令：

```sh
cd /Users/tty/Desktop/Coding/Reading/app
../scripts/flutterw analyze
READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded
../scripts/flutterw build ios --simulator --debug --no-pub
../scripts/flutterw build apk --debug --no-pub
```


真实书籍核验上下文：
- 用户原文件完整路径、SHA 和统计见 `docs/real-epub-compatibility.md`；不要再次索要路径或扫描私人目录。
- 本地证据在 Git 忽略的 `artifacts/real-epub-audit.json` 和 `artifacts/real-epub-comparison.json`；后者含源文件逐块校验结论。它们无正文。
- 诊断工具执行：在 `app/` 下 `dart run tool/inspect_epub.dart '<报告中的原文件路径>'`；定向检查 `dart analyze tool/inspect_epub.dart`。工具只诊断，不修改书籍。
- 安卓文件 `/sdcard/Download/reading-real-book.epub`，SHA `b552446064088e5b955327d1fd9434f9db6b36d740bfdb6d940c6a514884a63a`。
- 小说没有表格，不将本次验证描述为真实教材验收完成。


SVG 修复实现决定（7cb9967）：
- 这是栅格图片提取，不是 SVG 渲染。仅允许直接单 image 和纯文本 title/desc；尺寸由既有阅读器图片布局处理，不复刻 SVG 坐标/原 CSS。没有引入新依赖。
- HTML 包将 `xlink:href` 存为 `dom.AttributeName`，不能简单用字符串 key 读取，见 `addSvgImage`。
- 复用 `addImage` → `_Epub.resolve/data` 保持路径限制、解压上限与 CRC；外链只生成占位，不发请求。
- 不重解析旧库，不做位置迁移。新导入产生新内容块索引；本书新第 15 章在 2452，历史报告 2451 对应旧解析版本。
- 新证据 `artifacts/real-epub-audit-svg-fixed.json`；修复前 `real-epub-audit.json` 保留作对照，不覆盖。原书/正文不入 Git。

## Known Issues / Risks

- 简单 SVG 本地栅格包装已解决；通用 SVG、嵌套组、多图组合、精确 CSS/字体/滤镜仍不支持，以占位显示。不是完整 SVG 能力。
- 旧书不会自动补封面；正常安装新版后需另行导入一份才能检查新提取结果，不应为验收删除用户旧书和进度。
- 原 NCX 漏第 15 章，正文不缺；目录补全需独立设计去重/顺序，不能硬编码本书。
- 安卓 CUA 无法绑定独立模拟器；用户此前可协助验收。iPhone/iPad/真机本次新封面视觉未验证。
- 分页/双页、脚注交互、真实翻译、生词本、书签/搜索/备份仍未完成；阶段 2 部分视觉/TXT 原生导入验收保留。
- 构建的 Java/SDK XML 兼容提示已记录，当前不阻塞；将来工具链升级时再统一处理，不为通过的构建扩张本轮工作。

## Next Step

**唯一优先步骤：实现脚注链接/锚点解析与向后兼容的数据模型，不接阅读器 UI。**

1. 读取 `app/lib/book/book.dart` 的 `BookContent`/`BookBlock` JSON 与 `app/lib/book/epub.dart` 的 `_Epub.targets`、`_Blocks.walk`。先限定支持的行内文本链接、章内/跨章目标和返回链接表示，不提前实现跳转界面。
2. 定义链接文本范围和目标位置，保留 EPUB ID/路径映射；空白规范化后链接偏移必须匹配最终正文。旧 TXT/EPUB JSON 缺少新字段时正常读取。
3. 用原创 EPUB 2/3 夹具验证章内/跨章脚注、返回链接、空白/行内标签、缺失目标、外链和重复 ID；外链不联网。兼顾 `linear=no` 脚注资源可能未进入正文的问题，先记录/限定支持方式，不悄悄丢失目标或改动原章节顺序。
4. 运行针对模型、解析器、旧书读取的测试及必要分析/构建，明确脚注 UI 未实现；若模型范围过大先拆小并保存，不同轮展开跳转、返回、分页。

## Remaining Plan

1. 脚注模型/解析之后，下一独立周期接阅读器跳转及返回并回归位置恢复。目录缺项补全独立排队；新版封面视觉在正常覆盖升级后另行导入一份验收，保留旧书/进度。
2. 分页依次位置映射/文字分页、图片表格、手机翻页与恢复；随后必做 iPad 横屏双页，再独立模拟器/真机验收。
3. 阶段 3 其余：真实翻译/缓存、Wiktionary、生词本/导出、书签/正文搜索、备份、真机；阶段 2 剩余视觉/TXT 原生导入验收保留。
4. 阶段 4 MDX/MDD/PDF、阶段 5 可选同步/多语言均未开始。总体计划见 `PLAN.md` / `docs/original-plan.md`。
