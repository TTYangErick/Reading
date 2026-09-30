# Reading 最新小步骤交接

更新：2026-10-01。安卓原生 EPUB 样本验收已获用户确认“四项全部正常”，本轮关闭此项。开工 HEAD `cac2ed4` 且工作区干净；应用功能检查点仍为 `18fae5b`，没有应用代码改动。

## Current Goal

收齐安卓 `reading-lesson.epub` 原生导入的四项用户实测结果，关闭该验收项并交接下一步。本轮不展开 iPhone、脚注或分页。

## Completed

- 已读取最新交接、项目规则、整体计划和专项验收记录，核对源码导入入口仍允许 TXT/EPUB。
- 只读核实 `emulator-5554` 在线，`dev.reading.reading_app` 已安装且进程存在，样本在 Downloads（2695 bytes）。宿主/设备 SHA-256 一致。
- CUA 重新枚举仍未列出模拟器；通过实际进程路径以及 `Android Emulator` 名称连接均返回 `Invalid app`。可连接 Android Studio，已观察到 Device Manager 中 Reader Phone 在线。
- 用户针对完整四项操作明确回复“四项全部正常”：系统选择导入、图片/表格、Tomorrow 气泡停留、Second lesson 跳转后返回书架重开恢复。已同步专项验收表、主交接及执行计划。

## Verification

- 前一轮环境检查通过：设备在线、应用包/进程存在；本地与安卓样本 SHA-256 均为 `724fb95af485d48e53d306fe0930702f1eb3450adb17e638b94fc8b469c72928`。没有重装、清空、修改应用数据或启动会卸载 App 的测试。
- 前一轮 CUA 直接观察到 Device Manager 的 Reader Phone（Android 16/API 36）在线。原生导入行为由本轮用户实测确认，非代理自动 UI 验证。
- 本轮用户实测通过：系统选择器实际导入、图片/表格、Tomorrow 释义停留几秒不消失、Second lesson 跳转及返回书架重开仍在第二章。证据为用户对四项验收问题的原话“四项全部正常”，覆盖这一份样本，不外推到所有 EPUB。
- 本轮只更新验收文档，检查八项结构、状态一致性与差异；不重跑此前已通过的 28 项应用测试/构建。

## Current Project State

**已验证（检查点 18fae5b）**：28/28 宿主测试通过；静态分析无问题；iOS/Android debug 构建通过。组件测试覆盖手机 430×1000、平板横屏 1180×820 的导入、图片、表格点词、目录和重开位置。iPhone 升级前后核对原有 1 本书的 ID、位置、样式及设置均保留；CUA 看到了新导入入口。Android 覆盖安装返回 Success，样本已传入下载目录，应用已启动。

**本轮新增验证**：安卓原生 EPUB 样本四项流程用户实测通过。

**未经验证**：iPhone 从原生文件选择器实际选取 EPUB 的端到端流程、用户真实教材/大书兼容性、iPad 模拟器和真机。平板尺寸组件测试不等同于 iPad 设备验收。阶段 2 原生 TXT 导入及部分气泡/主题/系统栏视觉验收仍保留。

**尚未完成**：左右翻页、必做 iPad 横屏双页、脚注跳转、真实句子翻译、生词本、书签/正文搜索、备份等阶段 3 后续功能。

安卓此项验收已关闭，没有待答的安卓验收问题。本轮未启动 build/test/attach，未操作设备或书架；只有交接/验收文档更新。下一轮用 Git 状态核对，不依赖历史 PID。

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
- 本次仅改交接文档，不需要重跑下面应用检查；后续应用改动按需执行：

```sh
cd /Users/tty/Desktop/Coding/Reading/app
../scripts/flutterw analyze
READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded
../scripts/flutterw build ios --simulator --debug --no-pub
../scripts/flutterw build apk --debug --no-pub
```

## Known Issues / Risks

- 当前 Android CUA 可读取 Android Studio/Device Manager，但不能绑定独立模拟器（两种入口均 `Invalid app`）；用户确认窗口可见。旧的 `noWindowsAvailable` 是前轮记录，当前不能仅凭它推断设备未显示。已通过用户协助完成本次样本验收；工具限制仍在，但不再阻塞这项验收结论。不绕过 CUA。
- iPhone 最后一次观察已回到旧书正文，可能用户正在体验；继续操作前先看当前界面，勿盲目沿用历史元素索引。
- 当前章节按 UTF-8 解码；SVG、原书 CSS/内嵌字体精确排版、图片放大未实现；合并单元格/嵌套表格明确降级成按行文本。固定版式和 DRM 拒绝导入，不能宣称全格式教材支持。
- 限额：EPUB 50 MB、单资源解压 20 MB、声明总解压 150 MB、10,000 文件；实际流式解压限制、CRC 和路径检查已实现。真实大书性能/内存尚未验收；查词 <5ms/翻译 <1s 仍是目标，不是全面达标结论。
- 不在已有用户书架的模拟器运行 `flutter test -d`，该工具可能卸载 App。正常覆盖安装保留数据；iOS 安装后容器 UUID 会变，必须重新查询，不能据旧路径消失判断丢书。
- 安卓安装曾因额度不足而无法完成自动审批；用户要求继续后正常审批重试成功，此阻塞已解除。以后模块结束即更新交接，不等额度耗尽。

## Next Step

**唯一优先步骤：完成 iPhone 正常应用的一份 EPUB 原生导入验收，并记录真实结果。**

- 先读本交接、核对 Git 与 `docs/epub-acceptance.md`，通过 CUA 观察 Device Hub 当前 iPhone 状态。设备 UDID 和 bundle 见 Key Decisions / Context；有用户书架，禁止卸载或运行 `flutter test -d`。
- 先确认 iPhone 的 Files 能访问样本；安卓 Downloads 的文件不会自动出现在 iPhone。宿主样本为 `/Users/tty/Desktop/Coding/Reading/app/test/fixtures/epub/lesson-epub3.epub`。如 Files 内没有样本，使用正常文件传输路径准备，必要时请求用户协助保存到 Files；未准备好时记录准确阻塞，不虚构已经传入。
- 在 Reading → 添加书籍 → 导入 EPUB / TXT，用系统选择器选这份样本。核对正文、图片/表格、Tomorrow 气泡保持；目录选择 Second lesson，返回书架后重开仍在第二章。
- 四项均确认后更新专项验收表与八项交接，区分代理直接观察和用户反馈；若失败，保存具体步骤/现象作为下一轮修复依据。结束该周期，不顺带开始真实教材、脚注或分页。

## Remaining Plan

整体产品计划见 `PLAN.md` 和 `docs/original-plan.md`；以下是待排入后续周期的队列，不是本轮行动清单。

1. 安卓原生样本验收已通过；下一周期独立执行 iPhone 原生 EPUB 导入验收；记录选择器、阅读与重开结果。
2. 获得用户真实 EPUB 后，独立核对一份教材的章节、目录、图片和简单表格；具体兼容性缺陷逐个修复/回归。未提供文件时记录输入缺口，不阻塞其他已授权独立工作。
3. 脚注先完成向后兼容的链接/锚点解析模型和样本测试；下一周期再做阅读器跳转/返回及交互回归。
4. 分页先做可验证的位置映射与文字分页；后续分别接入图片/表格分页、手机翻页界面与恢复；基础稳定后独立完成 iPad 横屏双页，再做 iPad 设备验收。进入每一模块前按实际规模继续拆分。
5. 阶段 3 其余：真实翻译/缓存、Wiktionary、生词本/导出、书签/正文搜索、备份、真机验收；到达对应阶段再拆成可独立验证的小步骤。阶段 2 剩余视觉/TXT 原生导入项目保持待验收。
6. 阶段 4 MDX/MDD、PDF；阶段 5 可选同步、多语言，均未开始。保留原计划，不在当前周期展开。
