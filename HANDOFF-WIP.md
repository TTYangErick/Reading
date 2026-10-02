# Reading 最新小步骤交接

更新：2026-10-02。用户先确认 iPhone 样本“可以进入正文”，随后回复“三项全部正常”；iPhone 当前样本完整验收已关闭。起点 `403ed2e`，工作区干净，应用代码无变化。

## Current Goal

关闭 iPhone 原生 EPUB 样本验收：确认导入、图片/表格、Tomorrow 释义保持、Second lesson 跳转与重开位置；不展开后续功能。

## Completed

- 用户从提供的样本下载链接完成操作后明确回复“可以进入正文”，记录为 iPhone 原生导入用户实测通过。
- 已核对并停止任务的临时 Python 样本服务器 PID 86345；验证回环端口 8765 已关闭，原下载地址现在不再提供服务。
- 用户对剩余三项明确回复“三项全部正常”：图片/表格正常、表格 Tomorrow 释义停留、Second lesson 跳转后返回书架重开仍在第二章。专项验收、主交接和计划同步关闭此项。

## Verification

- 用户实测：iPhone 原生 EPUB 导入成功并进入正文。来源为用户原话“可以进入正文”，不冒称代理自动 UI 验收。
- 终端直接验证：停止前监听 PID 与交接一致，终止该进程后端口 8765 已关闭。Reading 与已保存样本不受影响。
- 用户实测：图片/表格、释义保持、目录与重开位置三项通过，证据为对明确三项操作问题的答复“三项全部正常”。结论仅覆盖这份样本和当前 iPhone 模拟器，不外推所有教材或真机。
- 本轮仅变更记录并清理临时服务，不重跑此前已通过的应用测试/构建。

## Current Project State

**已验证（检查点 18fae5b）**：28/28 宿主测试通过；静态分析无问题；iOS/Android debug 构建通过。组件测试覆盖手机 430×1000、平板横屏 1180×820 的导入、图片、表格点词、目录和重开位置。iPhone 升级前后核对原有 1 本书的 ID、位置、样式及设置均保留；CUA 看到了新导入入口。Android 覆盖安装返回 Success，样本已传入下载目录，应用已启动。

**历史用户实测**：安卓原生 EPUB 样本四项流程通过（2026-10-01）。

**本轮新增用户实测**：iPhone 原生 EPUB 导入、图片/表格、气泡停留、目录及重开位置全部通过；与安卓一样按用户实测记录。

**未经验证**：用户真实教材/大书兼容性、iPad 模拟器和真机。平板尺寸组件测试不等同于 iPad 设备验收。阶段 2 原生 TXT 导入及部分气泡/主题/系统栏视觉验收仍保留。

**尚未完成**：左右翻页、必做 iPad 横屏双页、脚注跳转、真实句子翻译、生词本、书签/正文搜索、备份等阶段 3 后续功能。

安卓及 iPhone 当前样本验收均已关闭。当前无运行中的 build/test/attach/样本下载服务；不应再要求用户点击旧下载链接或重复导入。文档修改会单独提交。

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

**唯一优先步骤：对一份用户实际要读的 EPUB 做兼容性检查，产出具体通过项/缺陷记录。**

- 目前没有用户提供的真实教材路径。下一轮先请用户提供本机 `.epub` 完整路径（无需反复找旧源码或环境配置）；确认该文件可读后再开始，不擅自扫描无关私人目录或用原创样本替代真实教材。
- 对这一份文件检查 `EpubParser.parse` 的章节顺序、目录目标、图片资源和简单表格；将解析结果与书内 OPF/spine/内容对照，再在正常应用阅读代表性章节。不得覆盖原书或直接注入业务数据库代替导入。
- 输出一份针对该文件的兼容性记录，明确已验证/缺陷/未验证；若发现问题，保留最小复现和涉及文件/资源，本轮不顺带大改解析器，下一轮唯一任务才是优先缺陷的修复与回归。
- 若没有真实 EPUB 输入，本步标为等待路径，不把样本通过说成真实教材通过；与用户确认后续单步调整，勿未经说明就转入多个模块。
- 临时下载服务已停，端口 8765 已关闭，无需再清理 PID 86345。需要新传输服务时重新核实环境，不沿用历史 PID。

## Remaining Plan

整体产品计划见 `PLAN.md` 和 `docs/original-plan.md`；以下是待排入后续周期的队列，不是本轮行动清单。

1. 安卓及 iPhone 原生样本验收均已用户实测通过；该阶段不再重复执行，除非后续相关代码变化需要回归。
2. 获得用户真实 EPUB 后，独立核对一份教材的章节、目录、图片和简单表格；具体兼容性缺陷逐个修复/回归。未提供文件时记录输入缺口，不阻塞其他已授权独立工作。
3. 脚注先完成向后兼容的链接/锚点解析模型和样本测试；下一周期再做阅读器跳转/返回及交互回归。
4. 分页先做可验证的位置映射与文字分页；后续分别接入图片/表格分页、手机翻页界面与恢复；基础稳定后独立完成 iPad 横屏双页，再做 iPad 设备验收。进入每一模块前按实际规模继续拆分。
5. 阶段 3 其余：真实翻译/缓存、Wiktionary、生词本/导出、书签/正文搜索、备份、真机验收；到达对应阶段再拆成可独立验证的小步骤。阶段 2 剩余视觉/TXT 原生导入项目保持待验收。
6. 阶段 4 MDX/MDD、PDF；阶段 5 可选同步、多语言，均未开始。保留原计划，不在当前周期展开。
