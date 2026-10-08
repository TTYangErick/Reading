# Reading 历史小步骤交接

> 历史快照，已停止维护。以下“当前/最新/下一步”和操作要求仅代表当时，不是现行指令。当前状态唯一见 [PLAN.md](PLAN.md)，执行规则见 [AGENTS.md](AGENTS.md)；不要按本文恢复或同步更新。

更新：2026-10-02；本轮起点 `a1288b2`。当前只实现正文脚注链接/锚点解析模型；不接 UI。本轮代码已完成，38/38 测试、静态分析及 iOS/安卓构建均通过；未安装到模拟器，UI 未接入。

## Current Goal

建立向后兼容的脚注文字链接、来源范围和目标位置模型；解析章内/跨连续阅读章节的链接及返回引用，不改变正文顺序或已保存进度。

## Completed

- `app/lib/book/book.dart` 新增 `BookPosition`、`BookLink`、`BookLinkKind`、`BookLinkStatus`；`BookContent` 增加 links/anchors 的可选 JSON 字段，旧 TXT/EPUB 缺字段默认为空，数据库 schema 仍为 2。
- `app/lib/book/epub.dart` 新增链接采集、规范化文字偏移映射、全文解析后目标解析。支持普通文字 `<a href>`、noteref/backlink 标记、章内/跨章 ID、URI 解码路径；不联网。
- 缺目标不回退到章节首；未载入的独立页面明确 unavailableDocument；外链/错误链接保留文字与状态，不执行且不阻断导入。重复 ID 首个优先，末尾空锚点不跳进下一章。
- 新增原创 `app/test/epub_links_test.dart` 6 项测试和实现边界说明 `docs/epub-links.md`。
- 保留旧 EPUB 的文字/图片/表格和词典阅读流程，没有更改阅读器 UI 或业务数据库存量内容。

## Verification

- 38/38 全部宿主测试通过（session 62701）；涵盖旧 32 项及新增 6 项链接测试：EPUB 2/3、表情/空白偏移、脚注返回、缺失/外链/错误/非连续目标、重复 ID、跨块范围、旧 JSON、数据库关闭重开。
- `flutter analyze` 无问题（session 51142）；格式与 `git diff --check` 通过。
- iOS 模拟器 debug 构建通过（session 6130 已结束，Xcode 9.8s）。安卓 debug 构建也通过（session 17940 已结束，Gradle 8.1s；仅有此前记录过的 Java native-access 警告）。
- 真实书 `artifacts/real-epub-audit-links.json` 对照 `real-epub-audit-svg-fixed.json`：3,180 块、文字指纹顺序、17 目录、2 图片完全一致，JSON 往返通过。不是脚注真实书/设备交互验收。
- 本轮未安装新构建、未在用户设备运行 `flutter test -d`；原生脚注 UI 未实现/未验证，封面新版本视觉也仍待验收。

## Current Project State

阶段 2 主体、阶段 3 EPUB 基础版和简单 SVG 栅格封面修复已实现。正文链接数据已实现且通过宿主验证，尚没有任何链接点击/返回交互。独立脚注页未载入；需要下一步骤补充，不能声称完整脚注功能。

用户已确认旧版安卓真实小说第 1/9/18 章、查词和重开正常，两端原创样本也通过；这不证明本轮脚注或新封面设备显示通过。原书 NCX 漏第 15 章，正文不缺，目录补全未做。

iPad 仅通用工程和宽屏组件测试，左右翻页/必做横屏双页/iPad 设备验收未完成。真实翻译、生词本、书签/搜索、备份等未完成。

当前无运行中的构建/测试/下载/调试任务，无数据库注入。两端已安装 App 未覆盖更新，旧书不重解析，位置保留。

## Key Decisions / Context

- 项目 `/Users/tty/Desktop/Coding/Reading`，Flutter 工程 `app/`；需求 `PLAN.md` / `docs/original-plan.md`，最新模型详解 `docs/epub-links.md`。原型仅作视觉参考，不当真实功能。
- **本轮拆分决定**：原先拟模型之后直接做 UI；独立脚注页（linear=no 或非 spine 文档）涉及补充内容存储和跨文档位置，为保持单步规模，本轮仅建正文链接模型并明确 unavailableDocument。下一轮先完成补充脚注页解析，再做 UI，不将遗漏包装成完成。
- `BookPosition(block,offset)` 使用最终文字 UTF-16 偏移；`BookLink` 的 source block/start/end 是半开区间；仅 status=resolved 时 target 非空。`targetKey` 为规范化包内 path 加可选 #decoded-id。全量 anchors 进入 JSON，旧数据缺省为空。
- `_NormalizedText` 对 raw 非空白片段保存映射，用二分定位范围，链接跨块时拆成各块范围。`_Blocks` activeLinks/closedLinks/rawAnchors 收集标记；`_Epub.resolveLink` 在连续正文解析完后解析目标。
- 重复 ID：同文档首个胜出；不同文档同 ID 隔离。脚注链接缺 fragment 目标绝不使用章节 fallback；目录原有 fallback 规则保留。
- 外部 URI（包括 javascript）、data 链接不执行/不联网；UI 以后只能按明确状态处理，不能对 external 自动调用系统打开。错误转义/路径越界/查询参数为 invalid。
- 媒体/简单表格沿用原实现，表格内/图片链接和 `<a name>` 旧锚点本轮未捕获；正文仍保留，不把这些列为支持。
- 保留 Flutter/Riverpod/drift；`BookParser`/`LanguageSupport`/`DictionaryProvider`/`Translator` 接口不变。正文/元数据进 books JSON，图片进 book_assets。旧书不自动重解析；无 schema 升级。
- 必须保留 iPhone 气泡修复（didChangeMetrics 仅真实几何变化关闭）及长按复制 onLongPressEnd 才开面板，避免重现手势取消。
- `scripts/flutterw` 默认两组代理 `http://127.0.0.1:7897`；设备 run/test 用 `READING_PROXY_URL=''` 并支持时 --no-pub。构建使用默认代理，SDK/工具缓存可能需正常提权。
- 检查命令（在 app 下）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded`；`../scripts/flutterw analyze`；`../scripts/flutterw build ios --simulator --debug --no-pub`；`../scripts/flutterw build apk --debug --no-pub`。
- 真实词典 `app/assets/dictionaries/ecdict.sqlite` Git 忽略，770,611 词条；不要删除/无故重建。缺失时才用 scripts/fetch_assets.py 与 dict_builder/build_ecdict.py。
- iPhone UDID `144FF884-EC04-4E7F-9BE6-AFF8264E8699`，bundle `dev.reading.readingApp`，UI 宿主 `com.apple.dt.Devices`；安卓 `emulator-5554` / `dev.reading.reading_app`，SDK `/Users/tty/Library/Android/sdk`。
- 两端构建输出 `app/build/ios/iphonesimulator/Runner.app` / `app/build/app/outputs/flutter-apk/app-debug.apk`；最新构建状态见 Verification，已安装版本不会自动更新。
- 用户真实书路径/SHA 在 `docs/real-epub-compatibility.md`，安卓副本 `/sdcard/Download/reading-real-book.epub`，不要再次索要路径、修改原书或加入 Git。旧本地样本服务 8765 已停止。

## Known Issues / Risks

- linear=no/非 spine 的独立脚注页只标 unavailableDocument，不含目标文字；表格内链接、图片链接、旧 name 锚点未支持。需要逐步补齐，不能把本轮模型称作完整脚注支持。
- 当前链接都不会在 UI 中响应；阅读器仅有原有点词行为。真实书脚注类型/复杂 CSS 隐藏脚注等兼容性未验证。
- 新封面视觉未验收；简单 SVG 栅格包装已支持，通用 SVG 不支持。两端旧书保持旧解析结果，新导入才用新模型。
- 安卓 CUA 无法绑定独立模拟器，历史设备验收由用户协助。不在用户书架设备执行 flutter test -d（可能卸载），正常覆盖安装后 iOS 容器 UUID 会变，应重新查询。
- 原 NCX 缺第 15 章未补全；原书排版、复杂表格/公式/固定版式不扩张。查词/翻译性能目标不是已全面达标结论。

## Next Step

**唯一优先步骤：支持独立存放、非连续阅读的脚注页解析与存储，仍不接 UI。**

1. 读 `docs/epub-links.md` 与 book.dart/epub.dart。扩展位置标识和补充文档数据容器，使正文块索引不因脚注页面载入而改变；兼容当前 links/anchors JSON 和更旧无链接 JSON。
2. 仅解析 manifest 中被正文链接引用的本地 XHTML/HTML（含 linear=no），保持原 spine/目录/阅读进度不变；按现有限额限制资源，避免循环引用/重复加载/无限递归，不访问外部 URI。
3. 以原创样本验证跳入独立脚注目标和脚注返回正文、链式/循环引用边界、缺文件/目标、持久化重开及已有正文逐块不变；不要只改状态而不保存真实脚注内容。
4. 完成测试/分析/必要构建后写交接；下一轮再做正文链接点击、脚注展示与返回。若规模超出周期继续拆分，不提前做分页。

## Remaining Plan

1. 独立脚注模型/解析完成后再接 UI 跳转及返回（含点词手势兼容和位置恢复）；name 锚点/表格链接/目录缺项补全按必要性单独排队。新封面正常覆盖升级后另行导入一份验收，保留旧书。
2. 分页依次定位/文字分页、图片表格、手机翻页与恢复；然后 iPad 横屏双页与设备验收。
3. 阶段 3 真实翻译/缓存、Wiktionary、生词本/导出、书签/搜索、备份、真机；阶段 2 剩余视觉/TXT 原生导入验收保留。
4. 阶段 4 MDX/MDD/PDF、阶段 5 可选同步/多语言尚未开始。
