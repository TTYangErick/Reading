# Reading 最新小步骤交接

更新：2026-10-02。本轮起点 `577577c`；目标仅 SVG 包裹本地栅格封面的兼容修复。代码已修复，测试/分析及 iOS 构建通过。用户提醒接近 limit，主动收口保存；安卓构建未执行，不开始后续模块。

## Current Goal

修复简单 SVG 图片包装被静默跳过的问题，保留现有图片安全加载、正文顺序、目录定位和已保存的书架数据。本轮不做目录补全、脚注或分页。

## Completed

- `app/lib/book/epub.dart`：抽取 `_Blocks.addImage`，让普通 `img` 和 SVG 图片复用同一个本地资源加载流程。
- 新增 `_Blocks.addSvgImage`：支持 SVG 直接包含一张栅格 `image` 及可选纯文本 title/desc，兼容 `href` 和 namespaced `xlink:href`（`href` 优先）。保留 SVG 与 image 的 ID 目录定位。
- 对多图、矢量路径、脚本/foreignObject、变换/滤镜/蒙版等非简单包装输出一条可见占位，不做部分 SVG 渲染、不执行内容、不联网。SVG 自身按独立块处理，避免前后正文混在一起。
- 新增 4 个回归测试，覆盖两类链接、图像/前后段落顺序、目录锚点、资源入库/读取、缺图、外链/data URI、越界路径、复杂图形降级。
- 重新解析用户真实 EPUB：两张 JPEG 均被提取；3,178 个文字块与修复前逐块一致；17 项目录目标均正确偏移一块。

## Verification

- 红灯验证：4 个新增 SVG 测试在旧代码全部失败，确实复现遗漏及无占位；修复后 `test/epub_test.dart` 13/13 通过。
- 全部宿主测试：32/32 通过（含 EPUB/TXT 导入、图片/表格、点词与重开、旧 JSON/数据库迁移及边界检查）。未运行设备测试，未卸载 App。
- `flutter analyze`：No issues found；格式检查与 `git diff --check` 通过。
- 用户真实书：3,180 块 = 3,178 文字 + 2 图片；`cover_image.jpg` 100,523 bytes、`Cover.jpg` 124,594 bytes。文字指纹及顺序与历史核验完全相同；全部目录块索引比旧版 +1，JSON 往返一致，无越界目标。本机单次解析 125 ms，不外推手机性能。
- iOS 模拟器 debug 构建已通过（session 65843 已结束，Xcode build 9.9s），产物 `app/build/ios/iphonesimulator/Runner.app`。安卓 debug 构建尚未执行；用户提醒 limit 后优先保存，旧 APK 仍是修复前版本。
- 尚未把新构建覆盖安装到模拟器；本次封面的原生视觉专项验收未做。此前真实书安卓“全部正常”和两端样本验收属于修复前版本，不能冒充本次封面视觉结果。

## Current Project State

阶段 2 主体、阶段 3 EPUB 基础版已实现。本轮 SVG 单张栅格封面兼容已实现且解析/持久化回归通过；设备端新封面视觉尚未验证。修复不改数据库 schema 或存量正文，旧书位置保持原样；只有新导入书会提取新增封面。

用户真实小说安卓普通导入/阅读/点词/重开曾用户实测通过；原 NCX 缺第 15 章仍保留。iPhone 这本书、真实教材、大书/iPad 设备均未验收。iPad 只有通用工程和宽屏组件测试，左右翻页及必做横屏双页未实现。

当前没有运行中的 build/test/attach/下载服务，无业务数据库注入。原 EPUB 在用户 Downloads，安卓副本 `/sdcard/Download/reading-real-book.epub`。旧服务器 8765 已停止，勿重复清理历史 PID。

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
- 最近构建产物：`app/build/ios/iphonesimulator/Runner.app` 已含本轮 SVG 修复；`app/build/app/outputs/flutter-apk/app-debug.apk` 仍是旧 EPUB 基础版。两端已安装 App 都未更新。升级前后 iPhone 比对资料在忽略的 `artifacts/epub-upgrade-state.json`。
- 本轮修改解析器，测试/分析通过；构建结果见 Verification（iOS 通过、Android 待执行）。复查命令：

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


本轮实现决定：
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

## Next Step

**唯一优先步骤：完成本轮 SVG 修复的安卓构建核验并关闭工程交付记录。**

1. 读取本交接，确认工作区与本轮提交一致。32/32 测试、静态分析和 iOS 构建已有通过证据，无新修改/故障时无需重跑。
2. 在 `/Users/tty/Desktop/Coding/Reading/app` 执行 `../scripts/flutterw build apk --debug --no-pub`（默认代理；SDK/Gradle 缓存写入需正常提权）。成功产物 `build/app/outputs/flutter-apk/app-debug.apk`，记录实际结果。
3. 成功后更新交接/计划为双平台构建通过；下一轮唯一任务再设为脚注链接/锚点解析模型。若失败，只定位本次构建失败，不展开脚注或分页；保存具体错误和恢复命令。
4. 新封面原生视觉仍待验收，构建不等于已安装或已实测。后续正常覆盖升级后另行导入一份检查，保留旧书/进度；不要在用户设备运行 `flutter test -d`。

## Remaining Plan

1. 当前先补安卓构建；随后脚注先模型/解析（`book.dart` 向后兼容的链接范围/目标结构，`epub.dart` 章内/跨章锚点与空白规范化位置测试），再下一周期接阅读器跳转与返回；原目录缺项补全独立排队。新版 SVG 封面原生视觉在正常升级后补验收，旧书不自动重解析。
2. 分页依次位置映射/文字分页、图片表格、手机翻页与恢复；随后 iPad 横屏双页，再独立模拟器/真机验收。
3. 阶段 3 其余：真实翻译/缓存、Wiktionary、生词本/导出、书签/正文搜索、备份、真机；保留阶段 2 未关闭验收。
4. 阶段 4 MDX/MDD/PDF，阶段 5 可选同步/多语言未开始。总体需求见 `PLAN.md` 和 `docs/original-plan.md`。
