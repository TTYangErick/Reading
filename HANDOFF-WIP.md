# Reading 最新小步骤交接

更新：2026-10-02。本轮起点 `8eca9f2`，用户已提供真实 EPUB 路径；输入缺口已关闭。应用逻辑无变化，新增本地检查工具和专项兼容性报告。

## Current Goal

检查用户提供的一本真实 EPUB：对照原文件与 Reading 生产解析结果，验证章节/目录/图片并记录明确缺陷；本轮不实现后续兼容性修复。

## Completed

- 已读取用户指定《Harry Potter and the Chamber of Secrets》EPUB；原文件未修改、未纳入 Git。18 章正文均存在，3,178 个文字块按顺序与独立源文件抽取结果一致。
- 新增 `app/tool/inspect_epub.dart`：调用生产解析器输出结构、文字 CRC32 和 JSON 往返结果，不输出正文。
- 新增 `docs/real-epub-compatibility.md`：记录输入路径/SHA、验证方法、通过项、限制和复现入口。
- 确认两项问题：Reading 静默跳过 SVG 包裹的 JPEG 封面；原 NCX 自身漏了第 15 章，正文不缺失，不能误报为解析器丢章。
- 复制原 EPUB 至现有安卓模拟器 Downloads/reading-real-book.epub，SHA-256 核对一致。用户对正常导入、第 1/9/18 章阅读、点词释义保持、返回书架重开位置回复“全部正常”，原生验收已关闭。

## Verification

- ZIP CRC 通过；EPUB 2.0，425,499 bytes，29 项，20 个 spine 文档；18 个正文章节。
- 生产解析成功：3,179 块（文字 3,178 + 图片 1）；独立 Python ZIP/XML 规范化 p/h1/pre 逐块 CRC32 对照全数、全顺序一致。
- 原 NCX 17 项与解析目录标题/顺序/目标全数一致；第 15 章正文在块 2451（源标题拼作 CAPTER FIFTEEN ARAGOG），原目录缺该项。
- JSON 编码/解码相同；单次本机解析 127 ms，仅此书/本机，不是手机性能验收。
- 新工具格式检查、定向静态分析通过；原创 EPUB 3 夹具冒烟检查通过（目录/图片/表格/目标/JSON）。分析器第一次受沙箱缓存写入限制失败，正常提权重试通过。
- 安卓文件传输与 SHA 核验通过；原生导入、第 1/9/18 章、点词保持、重开位置获用户“全部正常”确认，按用户实测通过记录，不冒称代理自动 UI 验收。
- 无应用逻辑改动，未重跑应用全量测试/双平台构建。既有 28/28 测试和构建结论仍属 `18fae5b` 检查点。

## Current Project State

阶段 2 主体和阶段 3 EPUB 基础版已实现。原创 EPUB 样本在安卓/iPhone 两端均已用户实测通过（目录、图片/表格、词义停留、返回重开位置）。本轮真实小说解析核验通过并明确记录缺陷，安卓原生阅读已用户实测通过；真实教材表格/大书性能/iPad 设备仍未验证。

未实现：左右翻页、必做 iPad 横屏双页、脚注跳转、系统真实翻译、生词本、书签/正文搜索、备份等。阶段 2 部分视觉/TXT 原生导入验收仍保留。

本轮没有运行中的 build/test/attach/下载服务；没有改写用户业务数据库。旧临时下载端口 8765 已于上一轮关闭，不要再向用户发送旧链接或清理历史 PID。当前本书只传到安卓；原样本仍保留。

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
- 最近构建产物：`app/build/ios/iphonesimulator/Runner.app` 和 `app/build/app/outputs/flutter-apk/app-debug.apk`；都是 EPUB 基础版。升级前后 iPhone 比对资料在忽略的 `artifacts/epub-upgrade-state.json`。
- 本次新增独立诊断工具和记录，未改应用逻辑；后续应用改动按需执行：

```sh
cd /Users/tty/Desktop/Coding/Reading/app
../scripts/flutterw analyze
READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded
../scripts/flutterw build ios --simulator --debug --no-pub
../scripts/flutterw build apk --debug --no-pub
```


本轮新增上下文：
- 用户原文件完整路径、SHA 和统计见 `docs/real-epub-compatibility.md`；不要再次索要路径或扫描私人目录。
- 本地证据在 Git 忽略的 `artifacts/real-epub-audit.json` 和 `artifacts/real-epub-comparison.json`；后者含源文件逐块校验结论。它们无正文。
- 诊断工具执行：在 `app/` 下 `dart run tool/inspect_epub.dart '<报告中的原文件路径>'`；定向检查 `dart analyze tool/inspect_epub.dart`。工具只诊断，不修改书籍。
- 安卓文件 `/sdcard/Download/reading-real-book.epub`，SHA `b552446064088e5b955327d1fd9434f9db6b36d740bfdb6d940c6a514884a63a`。
- 本轮没有架构变更。小说没有表格，不将本次验证描述为真实教材验收完成。

## Known Issues / Risks

- `_Blocks.walk` 处理 `img` 而不处理 SVG 的 `image`；本书 `titlepage.xhtml` 的本地 `cover_image.jpg` 被静默略过。另一张 `Cover.jpg` 正常提取，不能据此宣称全部图片通过。
- 原 NCX 漏第 15 章；Reader 当前使用原目录，仅无目录时才从标题生成。补全不完整目录需独立步骤，避免错误去重或硬编码本书。
- 独立安卓模拟器不能被当前 CUA 绑定；本书验收已由用户实测完成。iPhone 本书、iPad/真机仍未验证，不扩张结论。
- EPUB 仍不支持 SVG 通用渲染、精确 CSS/字体、脚注交互/图片放大；固定版式/DRM 拒绝；章节按 UTF-8 解码。复杂表格明确降级。
- 不在已有用户书架设备执行 `flutter test -d`，可能卸载 App。正常覆盖安装后 iOS 容器 UUID 会改变，查询新路径，不误判丢书。

## Next Step

**唯一优先步骤：修复简单 SVG 包装中的本地栅格封面遗漏。**

- 入口 `app/lib/book/epub.dart` 的 `_Blocks.walk`，当前只处理 HTML `img`；本书 `titlepage.xhtml` 中 `<svg><image xlink:href="cover_image.jpg" ... /></svg>` 的 JPEG 被静默跳过。
- 先在 `app/test/epub_test.dart` 用原创小 JPEG/PNG 构建最小夹具；实现对简单 SVG 图片包装的本地图片提取，兼容 `href`/`xlink:href`。复用已有路径解析、格式白名单、资源大小/CRC 验证，外链不联网；对不支持的 SVG 给出清晰降级，不实现通用 SVG 渲染或脚本执行。
- 回归验证原创夹具、本地资源/外链/缺图/路径越界、书籍保存与旧 EPUB/TXT；再运行 `tool/inspect_epub.dart` 检查本书两张图片均入资源且正文顺序不变。图片新增将改变块索引，重新导入的新书可采用新索引，不能重解析旧库导致已保存位置错位。
- 应用改动按 AGENTS 执行适当测试、静态分析和双平台构建；如果范围超出周期，保存未完成项。仅此修复，不同轮展开目录补全、脚注或分页。
- 本书安卓原生验收已用户确认“全部正常”，无需再次索要路径或重做现有基础检查；图片修复后才做受影响的专项视觉回归。

## Remaining Plan

1. 本书原生验收已关闭；下一轮单独修复 SVG 中仅包裹本地栅格图片时的图片提取，补原创回归样本及路径/外链检查；不做通用 SVG 渲染。原目录缺项自动补全另列待处理，不与封面修复捆绑。
2. 脚注先链接/锚点解析模型和样本测试，再下一周期做阅读器跳转/返回。
3. 分页依次位置映射/文字分页、图片表格、手机翻页与恢复；再必做 iPad 横屏双页和独立设备验收。
4. 阶段 3 其余：真实翻译/缓存、Wiktionary、生词本/导出、书签/正文搜索、备份、真机验收。阶段 2 剩余视觉/TXT 原生导入验收保留。
5. 阶段 4 MDX/MDD/PDF；阶段 5 可选同步、多语言未开始。完整产品计划见 `PLAN.md` / `docs/original-plan.md`。
