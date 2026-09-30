# Reading 阶段交接：EPUB 基础阅读

更新：2026-10-01。功能检查点：`18fae5b`。本次仅补齐交接规范与文档，以下应用验证均来自该功能检查点，未重新运行。开始续做先读本文件，再读 `PLAN.md`；原需求在 `docs/original-plan.md`。

## 1. 本阶段目标

让 Reading 从 TXT 阅读扩展到可重排 EPUB：导入 → 原目录 → 文字/图片/简单表格 → 离线点词 → 保存和恢复阅读位置，同时保留已有书架、设置和气泡修复。本模块是阶段 3 的一部分，不代表阶段 3 完成。

## 2. 已完成内容

- EPUB 2 NCX / EPUB 3 nav 目录、嵌套层级、章节 ID 跳转；正文遵循 spine 顺序，缺目录时回退标题。
- 导入入口同时支持 EPUB/TXT；后台解析、元数据书名、书架持久化和滚动阅读已接通。
- 包内 PNG/JPEG/GIF/WebP 图片、简单表格及横向滚动；正文和表格复用真实 ECDICT 查词与复制。
- 数据库 schema 1→2：独立图片 BLOB、事务导入/删除，兼容旧 TXT JSON、位置和样式。
- 原创 EPUB 2/3 样本、解析/迁移/阅读交互回归及专项验收记录已保存；两端模拟器均正常覆盖升级。

## 3. 当前状态

**已验证（检查点 18fae5b）**：28/28 宿主测试通过；静态分析无问题；iOS/Android debug 构建通过。组件测试覆盖手机 430×1000、平板横屏 1180×820 的导入、图片、表格点词、目录和重开位置。iPhone 升级前后核对原有 1 本书的 ID、位置、样式及设置均保留；CUA 看到了新导入入口。Android 覆盖安装返回 Success，样本已传入下载目录，应用已启动。

**未经验证**：从原生文件选择器实际选取 EPUB 的端到端流程、用户真实教材/大书兼容性、iPad 模拟器和真机。平板尺寸组件测试不等同于 iPad 设备验收。阶段 2 原生 TXT 导入及部分气泡/主题/系统栏视觉验收仍保留。

**尚未完成**：左右翻页、必做 iPad 横屏双页、脚注跳转、真实句子翻译、生词本、书签/正文搜索、备份等阶段 3 后续功能。

**本次文档任务**：七项总结规则已写入 `AGENTS.md`，本文件已按规则整理；没有改动应用代码。功能测试/构建/attach 均已结束，无待接管运行会话；提交状态以 `git status --short` 和 `git log -2 --oneline` 为准。

## 4. 关键实现/决策及原因

- 保留 Flutter + Riverpod + drift 及 `BookParser`、`LanguageSupport`、`DictionaryProvider`、`Translator` 接口；新增 `EpubParser`，不另造第二套阅读/查词实现。
- `BookContent` 保存格式、标题、章节和内容块；图片只在导入时携带字节，持久化进入 `book_assets`，避免图片膨胀书架正文 JSON。`BookBlock` 兼容旧文本并增加图片路径/表格行；`BookChapter` 指向内容块索引。
- 图片固定显示高度以减少异步加载导致的位置跳动；位置仍精确到内容块，尚不是分页定位模型。
- 原计划按阶段 2 验收后进入阶段 3；用户于 2026-09-30 明确授权先开始 EPUB，10-01 要求继续，因此阶段 2 未验收项继续保留，但不阻塞 EPUB。最终左右翻页/iPad 双页要求没有取消。
- 本轮仍用滚动阅读，不并行扩展翻译和分页；教材范围保持文字、图片、简单表格，复杂固定版式/公式不扩大进来。
- 必须保留两处既有修复：`didChangeMetrics` 仅实际视窗几何变化才关闭气泡；长按复制在 `onLongPressEnd` 才打开面板，避免取消尚未结束的手势。iPhone 闪现问题已获用户确认解决。

## 5. 已知问题与风险

- Android CUA 只能绑定 Android Studio 欢迎窗；AX 点击 More Actions 无变化，坐标备用操作返回 `noWindowsAvailable`，原生导入因此未验收。不要绕过 CUA 使用 adb input 或其他 UI 自动化。
- iPhone 最后一次观察已回到旧书正文，可能用户正在体验；继续操作前先看当前界面，勿盲目沿用历史元素索引。
- 当前章节按 UTF-8 解码；SVG、原书 CSS/内嵌字体精确排版、图片放大未实现；合并单元格/嵌套表格明确降级成按行文本。固定版式和 DRM 拒绝导入，不能宣称全格式教材支持。
- 限额：EPUB 50 MB、单资源解压 20 MB、声明总解压 150 MB、10,000 文件；实际流式解压限制、CRC 和路径检查已实现。真实大书性能/内存尚未验收；查词 <5ms/翻译 <1s 仍是目标，不是全面达标结论。
- 不在已有用户书架的模拟器运行 `flutter test -d`，该工具可能卸载 App。正常覆盖安装保留数据；iOS 安装后容器 UUID 会变，必须重新查询，不能据旧路径消失判断丢书。
- 安卓安装曾因额度不足而无法完成自动审批；用户要求继续后正常审批重试成功，此阻塞已解除。以后模块结束即更新交接，不等额度耗尽。

## 6. 下一步（按依赖顺序）

1. **先完成原生导入验收**：用 CUA 重新观察安卓模拟器窗口；若可操作，在 Reading → 添加书籍 → 导入 EPUB / TXT → Downloads 选 `reading-lesson.epub`，核对图片、表格点词、嵌套目录及离开重开位置。若仍无法操作窗口，保留明确阻塞，请用户执行这条路径反馈，不以组件测试代替。iPhone 同样需实际选择一份 EPUB。
2. **再检查真实教材**：获得用户要读的 EPUB 后，先用 `EpubParser.parse` 检查章节/资源/目录，再实际阅读同一文件。若发现不支持格式，记录具体资源与现象；添加最小回归再修复，不覆盖原书或默默跳过内容。
3. **补脚注能力**：检查 `app/lib/book/epub.dart` 的 `_Blocks.walk` 和非线性章节处理；先设计向后兼容的链接/锚点及脚注内容结构（当前模型不保存链接），再接入阅读器跳转/返回原位置；补章节内及跨章脚注回归。脚注是后续范围，当前不标完成。
4. **进入翻页/iPad 双页**：以 `BookContent` 内容块为基础，先定义能随字号/方向重新分页的位置映射，再替换或扩展 `ReaderPage` 滚动呈现；验证文字、图片、表格不遗漏/重复及退出恢复。分页稳定后加入 iPad 横屏双页，并在 iPad 模拟器/真机验收；不得只把两列文字称作完成双页。
5. 每完成上述一个独立模块，按本文件七项结构更新状态与后续依赖；同步 `HANDOFF.md`/`PLAN.md`，运行该代码改动需要的验证并记录实际结果。

## 7. 继续工作所需上下文

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
