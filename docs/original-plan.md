# 极简外语阅读器（类 Linga）— 实施计划

## Context
你想做一个自己用的外语阅读 App，类似 Linga（Read & Learn Languages），核心要求三条：**画面极简舒服**、**翻译几乎零开支**、**不打断连贯阅读**。
- 点一下单词，释义直接出现在**单词旁边**（Linga 的问题是释义固定在屏幕最下方）。
- 长按选中整句并翻译。
- 格式：EPUB 必须，PDF 最好有，也要支持 TXT 和粘贴文本；主要读教材和小说。
- 需要生词本，多设备同步可选。
- 平台：**iPhone、Android 手机、iPad**（不做 Mac 版）。开发和调试在你的 Mac 上进行。

你没有开发经验：Claude Code 写几乎全部代码，你负责装环境、运行、试用、反馈问题。

当前环境：Apple M5 / 24GB / 300GB 可用，macOS 26.6，已装 Homebrew、git、Python；**未装** Xcode、Flutter、Android Studio。项目建在 `Desktop/Coding/Reading/`（目前只有一个空的 test.py）。

## 已确定的决策
| 项目 | 决定 |
|---|---|
| 框架 | Flutter：一套代码出 iPhone、iPad（同一个 iOS 工程）和 Android |
| 点词查词 | 全部用**下载到 App 内的词典**，不调用系统词典 |
| 词典 | 内置免费**英汉**（ECDICT）、内置免费**英英**（Wiktionary）、支持**导入 MDX**（牛津、朗文等，文件由你自己提供） |
| 释义档位（三档，设置里选默认档） | **极简**：词旁小气泡一行显示最常用的 2–3 个意思，如 tomorrow → 明天；未来（显示几个可调 1–3）。**简洁**：列出全部中文意思，不显示词性和音标。**完整**：音标、词性、全部释义、英英释义、例句、MDX 词典，可切换词典。点气泡会进入完整卡片 |
| 一词多义 | 按词典顺序取最常用的意思，不做语境判断；不贴合时点一下看完整释义 |
| 句子翻译 | 系统离线翻译：iPhone/iPad 用 Apple Translation，安卓用 Google ML Kit。免费、离线；按句缓存，同一句只翻一次 |
| UI 参考 | **Apple Books** 的排版、主题和设置面板，加上 **Linga** 的点词流程。区别是释义浮窗**贴在单词旁**：带小箭头，自动判断放在上方还是下方，不遮挡当前行 |
| 已定的默认值 | 左右翻页（iPad 横屏为双页）；浅色气泡；极简档 2 个意思；白色主题 + 跟随系统深色模式；iOS 用 Iowan Old Style，安卓用 Literata |

## 阅读设置（参考 Apple Books，全部可调）
- **字体**（默认跟随各平台官方阅读 App）：
  - **iPhone/iPad**：默认 **Iowan Old Style**，这是 Apple Books 的默认字体，系统自带，不用打包进 App。可选字体与 Apple Books 一致：Charter、Georgia、Palatino、Athelas、Seravek、San Francisco、New York（New York 在 Flutter 里能否调用，实现时再验证）。
  - **安卓**：苹果字体的授权不允许在安卓上使用，所以默认用 **Literata**（Google Play 图书的默认阅读字体，OFL 协议，可打包进 App）。另可选 Source Serif、EB Garamond、Atkinson Hyperlegible 和系统字体。
  - 中文释义：iOS 用苹方，安卓用 Noto Sans CJK（都是系统字体）。
- **字号**：滑杆调节，另有粗体开关；浮窗字号单独可调。
- **间距**：行距、字间距、段间距、页边距；两端对齐或左对齐。
- **主题**：白色、纸张（米黄）、安静（灰）、夜间（深色）；可设为跟随系统深色模式自动切换，浮窗和工具栏也跟着主题变色。
- **翻页方式**：上下滚动（适合教材），或左右翻页（适合小说，Apple Books 的默认方式）。
- **iPad 横屏 = 双页**（照 Apple Books）：横屏宽屏时自动左右两栏，像打开的书，两栏之间有中缝，外侧留适当页边。单栏拉满横屏的话，一行会超过 150 个字母，眼睛换行很累；只保留一个窄栏又会像 v1 原型那样两边空出一大块。横屏的翻页方式和竖屏分开记忆：横屏默认双页，竖屏按你的设置。
- 所有设置实时预览、自动保存；每本书也可以单独记住设置。

## 基础功能清单（对照 Apple Books 和 Linga，防止遗漏）
`[2]`、`[3]` 等表示在第几阶段做；标「可选」的可以砍掉。

**书架与导入**
- 从文件 App 或文件管理器导入 `[2]`；从其他 App「共享 / 用…打开」直接导入 `[3]`；粘贴文本新建 `[2]`
- 书架显示封面（EPUB 取自带封面，TXT 自动生成文字封面）、书名、作者、阅读进度百分比 `[2–3]`
- 按最近阅读排序，搜索书名，删除书，修改书名 `[2]`
- 打开 App 时可选直接回到上次读的书 `[3]`

**阅读页基础**
- **目录**：列出章节，点击跳转，高亮当前章节 `[3]`（TXT 自动识别「Chapter 1」这类标题生成目录 `[2]`）
- **进度**：底部显示百分比或页码、本章剩余页数；拖动进度条跳转 `[2–3]`
- **记住位置**：精确到段落，重开 App 回到原处 `[2]`
- **返回上一位置**：通过目录、链接或搜索跳转后，一键返回刚才读的地方 `[3]`
- **书签**：添加、列表、跳转 `[3]`
- **书内搜索**：搜索一个词，列出所有出现位置并能跳转 `[3]`
- **沉浸模式**：隐藏系统状态栏和工具栏；点屏幕中央呼出工具栏 `[2]`
- **阅读时屏幕不熄灭** `[2]`；横竖屏锁定 `[3]`
- **图片**：点击放大，可双指缩放 `[3]`
- **EPUB 脚注 / 注释**：点击脚注编号，就地弹出注释内容，不跳走（教材常用）`[3]`
- **书内链接跳转** `[3]`
- **iPad 横屏双页**（像 Apple Books）`[3]` 可选
- **安卓音量键翻页** `[3]` 可选
- 高亮划线 + 笔记 `[5]` 可选

**点击手势规则**（避免点词和翻页冲突）
- 点在单词上：查词；点空白处或屏幕中央：呼出或收起工具栏。
- 翻页模式下，左右滑动翻页；点击屏幕最左、最右的窄边也能翻页，窄边范围不包含文字区域。
- 长按：选句；长按后拖动：调整选区范围。

**查词与翻译**
- 复制单词或句子 `[2]`
- 词典查不到时显示提示，同时用系统翻译翻这个词作为兜底 `[3]`
- 查词历史（最近查过的词）`[3]`
- 选多个词（短语）：长按后拖动选区，再翻译 `[3]`
- 朗读 `[5]` 可选

**生词本**
- 列表显示单词、释义和原句；可按时间或书名筛选；支持搜索和删除 `[3]`
- 点击原句跳回书中原来的位置 `[3]`
- 导出 CSV `[3]`

**设置与系统**
- **首次启动引导**：选择学习语言 → 下载词典 → 下载系统翻译语言包 `[3]`
- **词典管理**：下载、删除、排序，显示占用空间 `[3]`
- **存储管理**：清除翻译缓存 `[3]`
- **备份与恢复**：把书架、生词本、进度导出成一个文件，换机时导入；做同步之前的保底方案 `[3]`
- 界面为中文 `[2]`；App 图标和启动画面 `[3]`
- **关于页**：列出开源数据和字体的协议与致谢（ECDICT、Wiktionary、各字体的协议都要求署名）`[3]`
- **TXT 编码自动识别**（UTF-8、GBK 等），避免乱码 `[2]`
- **不支持的文件给出明确提示**：带 DRM 的 EPUB、扫描版 PDF 等 `[3–4]`

## 可行性与难度（★ 越多越难）
- 基础阅读器 ★｜字体、字号、间距、主题、夜间模式 ★～★★｜TXT / 小说 EPUB ★★｜教材 EPUB（表格、图片）★★★
- 点词 + 词形还原 ★★｜词旁气泡 / 浮窗 ★★｜极简、简洁、完整三档 ★★｜ECDICT、Wiktionary ★★
- 导入 MDX ★★★☆（原因见下）｜长按选句 + 系统翻译 ★★｜生词本 ★★｜iPad 大屏适配 ★★
- 翻页模式 ★★★｜PDF 点词 ★★★★｜WebDAV 同步 ★★★｜其他欧洲语言 ★★★｜日语 ★★★★

**为什么 MDX 不是「下载导入就好」**：
1. MDX 是没有公开规范的私有格式（逆向出来的），有多个版本、多种压缩方式，部分文件还加了密。需要专门的解析库，已有开源 Dart 实现可用，例如 `dict_reader`，实现时再验证。
2. 词条内容是 HTML，要依赖配套的 CSS、JS 和 .mdd 资源文件（图片、发音）才显示得好。每个做词典的人排版都不一样，要在小气泡里显示得好看，需要额外处理。
3. 极简和简洁档需要从 HTML 里抽出简短释义，每本词典的结构不同，没办法统一提取。
4. MDX 里没有词形表（went→go），需要借用 ECDICT 的词形表做还原。

所以 MDX 词典的做法是：**完整档用 WebView 按原词典排版显示**；极简和简洁档仍然使用 ECDICT 的释义。

**需要你知道的限制**：
- 免费 Apple ID 装到 iPhone、iPad 上的 App 7 天后需要重新安装，付 $99/年可以免掉（一个账号覆盖所有苹果设备）。安卓直接装 APK，没有这个问题。
- Apple Translation 在 iOS 模拟器里不能用，句子翻译要在 iPhone/iPad 真机上测试；其他功能都可以在模拟器里开发。
- 安卓手机如果没有 Google 服务，ML Kit 可能下载不了翻译模型。到时候再加一个云翻译免费额度作为兜底。

## 技术方案
- **自己写阅读器排版，不用 WebView**：EPUB/TXT 解析后转成统一的内容模型（标题、段落、图片、列表、简单表格），忽略出版商的 CSS，统一用舒服的排版渲染。三端观感一致，点词命中也最可控。
- **点词命中**：每个段落是一个 `Text.rich`，由 `RenderParagraph.getPositionForOffset` 拿到字符位置，再用自写的分词器扩展成单词。词形还原查 `forms` 表，查词查 SQLite 索引，耗时 <5ms。
- **气泡定位**：取单词的矩形区域（`getBoxesForSelection`），用 Overlay 放在它的上方或下方；滚动或点击其他地方时消失。
- **释义分档**：生成词典包时预先拆好每条释义，存成 `senses(headword, pos, rank, gloss_zh)`。极简取前 N 条并去重，简洁取全部释义但不带词性，完整读取整条词条。三档查询都在本地完成，速度一样快。
- **排版与翻页**：统一的 `ReaderStyle`（字体、字号、各种间距、主题色）驱动所有渲染。滚动模式用 `ListView`；翻页模式先用 `TextPainter` 按屏幕尺寸预先分页，再用 `PageView` 展示，字号或屏幕尺寸变化时重新分页。
- **词典包**：每本词典一个 SQLite 文件，结构为 `entries(headword, pos, phonetic, full_gloss, freq)` + `senses` + `forms(form→lemma)`。由 Python 脚本生成，托管在 GitHub Releases，App 内按需下载。MDX 从本地文件导入，建立索引后使用。
- **存储**：drift（SQLite），存书架、阅读进度、生词本、翻译缓存和词典设置。**状态管理**：Riverpod。
- **主要依赖**：`epubx`、`html`、`file_picker`、`drift`、`sqlite3_flutter_libs`、`google_mlkit_translation`（仅安卓）、`archive`、`flutter_riverpod`、`webview_flutter`（MDX 全文显示）、`dict_reader`（MDX 解析，待验证），后期加 `pdfrx`。
- **Apple Translation**：在 `ios/` 下写一个小的 Swift 插件，通过 MethodChannel 暴露 `translate(text, from, to)`；首次使用时由系统提示下载语言包。
- **手机与 iPad 布局**：手机竖屏单栏，气泡宽度受屏幕限制，自动避开屏幕边缘。iPad 正文限制最大行宽（约 65 个字符），不会拉满整个屏幕；横屏时左右留白更多，也可选开侧边的生词本。

## 预留接口（方便以后加功能、换实现）
原则：每类可替换的能力先定义一个小的抽象接口（Dart `abstract interface class`），第一版只写一两个实现，统一在一个 registry 里登记。以后加词典、翻译源、格式、语言或同步，只需要新增实现并登记，不用改阅读器和界面。测试时也可以直接换成假实现。

| 接口 | 作用 | 第一版实现 | 以后可加 |
|---|---|---|---|
| `BookParser` | 文件 → 统一内容模型 `BookContent`，按扩展名在 registry 里选用 | TXT、EPUB | MOBI、FB2、网页文章 |
| `PagedDocument` | 按页渲染的文档（原页面 + 带坐标的文字层） | —（先只定接口） | PDF（pdfrx）、扫描件 OCR |
| `LanguageSupport` | 某种语言的分词（点击位置 → 单词范围）、断句、词形还原候选 | 英语 | 法、德、西、日 |
| `DictionaryProvider` | `lookup(word)` → 词条，`senses(word, tier)` → 分档释义；自带元信息（名称、语言、是否提供短释义） | SQLite 词典包（ECDICT、Wiktionary） | MDX、其他格式 |
| `Translator` | `translate(text, from, to)`、`isAvailable`、`prepare(语言对)`；外面统一包一层缓存，并可配置多个翻译源依次兜底 | Apple Translation、ML Kit | 云翻译免费额度、AI 翻译 |
| `WordAction` / `SentenceAction` | 卡片上的按钮（名称、图标、何时显示、点击后做什么） | 加入生词本、复制 | 朗读（TTS）、AI 解释、查网页词典 |
| `VocabExporter` | 生词本导出 | CSV | Anki .apkg |
| `SyncBackend` | `push()` / `pull()` 生词本、进度、书籍 | —（先只定接口） | 坚果云 WebDAV、iCloud |

数据层也提前为以后做准备：
- **数据库**：用 drift 的 schema 版本和迁移机制，以后加字段不丢数据。所有需要同步的表都带 UUID 主键和 `updatedAt` 时间戳（为同步准备）；生词带 `lang` 和 `dictId` 字段（为多语言准备）。
- **词典包**：`manifest.json` 带 `schemaVersion`；App 遇到看不懂的新格式时提示更新，不会崩溃。
- **样式和主题**：`ReaderStyle`、主题列表、字体列表都是纯数据，加一个主题或一款字体只需加一条配置。
- **设置**：有类型的设置存储，每项都有默认值，并带版本号。

## 目录结构（`Desktop/Coding/Reading/`）
```
Reading/
  prototype/reader.html        阶段 1 的可点击 UI 原型
  app/                         Flutter 工程
    lib/
      library/                 书架、导入（文件 / 粘贴）
      book/                    content_model, epub_parser, txt_parser, (pdf/ 后期)
      reader/                  reader_page, paragraph_view（点击命中）, paginator（翻页）,
                               word_bubble（极简/简洁）, word_card（完整）, sentence_card,
                               settings_panel, reader_style, themes
      text/                    word_tokenizer, sentence_splitter
      dict/                    dict_pack_manager, dict_lookup, lemmatizer, mdx_importer
      translate/               translator 接口, apple_translator, mlkit_translator, translation_cache
      vocab/                   生词本 + 导出 CSV（可导入 Anki）
      db/                      drift 数据库
    assets/fonts/              内置的开源阅读字体
    ios/Runner/                AppleTranslatorPlugin.swift
    （每个目录里的接口文件和 registry 放在一起，例如 dict/dictionary_provider.dart + dict/dictionary_registry.dart；
      同步接口放在 sync/sync_backend.dart，actions 接口放在 reader/actions.dart）
    test/                      分词、断句、词形还原、查词的单元测试 + 用假实现测试各接口
  dict_builder/                build_ecdict.py, build_wiktionary_en.py, manifest.json
```

## 分阶段实施
**阶段 0：装环境（你操作，我给逐步指引）**
Xcode（App Store，含 iOS 模拟器）、`brew install --cask flutter`、Android Studio（带 SDK 和模拟器），然后跑 `flutter doctor` 直到全绿，并在 iPhone 模拟器和安卓模拟器上各跑通一个示例 App。

**阶段 1：UI 原型（先定手感，再写 App）**
- 写一个单文件 `Reading/prototype/reader.html`，发布为私有 Artifact 后把链接给你。你在 Mac 浏览器或手机浏览器里直接点着试。
- **示例内容**：《傲慢与偏见》第一章开头（公有领域）。里面的单词由一份内嵌的小词典支撑（约 150 词，格式模仿 ECDICT：音标、词性、中文释义、英英释义）；每个句子附一份预先写好的中文译文，模拟系统翻译的效果。原型里未收录的词显示「原型未收录」。
- **设备切换**：顶部可切换 iPhone、安卓手机、iPad 竖屏、iPad 横屏四种画框尺寸，同一套交互在不同屏幕上的效果一目了然。
- **点词**：
  - 单词出现淡色底，气泡带小箭头贴在词的上方（空间不够就放到下方），并自动避开屏幕边缘；
  - 极简、简洁、完整三档可切换，极简档显示的意思个数可在 1–3 之间调；
  - 点气泡展开完整卡片，卡片上的 ☆ 按钮可以加入生词本；
  - 点空白处或滚动时，气泡消失。
- **长按**（约 0.45 秒）：整句高亮，句子旁出现译文卡片。
- **设置面板**（仿 Apple Books 的「Aa」按钮，从底部弹出）：
  - 字体：Literata、Source Serif 4、EB Garamond、Atkinson Hyperlegible（Google Fonts 加载）和系统字体；
  - 字号、粗体、行距、字间距、段间距、页边距、两端对齐；
  - 主题：白色、纸张、安静、夜间，以及「跟随系统」；
  - 滚动 / 左右翻页（原型里的翻页用 CSS 分栏模拟）；
  - 释义档位；行间注音的对比方案开关（查过的词在上方行间留一行小字）。
- **生词本**：原型里只是一个简单的列表面板，用来确认入口放在哪里、长什么样。
- **工具栏**：点屏幕中央呼出，包含返回书架、目录（示例章节列表）、书签、书内搜索入口、设置，以及底部的进度条和页码。主要看布局和手感，不一定每个都能用。
- **书架页**：几本示例书的封面网格和阅读进度，点击进入阅读页。
- 设置用 localStorage 记住（读写都包 try/catch）。
- 你试用后提意见，我改到满意为止，然后把最终的颜色、字号、间距整理成 App 的 `ReaderStyle` 和主题常量。

**阶段 1.1：原型第 2 版（根据第 1 版的反馈）**
- 已发布的原型：https://claude.ai/artifact/JUPZxgJRbLpgbG53rCxb3U，源文件 `Reading/prototype/reader.html`，更新后发布到同一个链接。
- **iPad 横屏改成双页**：翻页方式拆成 `modePortrait` 和 `modeLandscape` 两个设置，默认都是 `page`（左右翻页）。在 `layout()` 里按屏幕方向（`W>H`）取对应的设置；横屏宽屏（`W>=900`）走 `paginate()` 已有的两栏逻辑，页边距和中缝的最小值改为约 44px。设置面板的翻页方式在横屏时显示「双页 / 上下滚动」，竖屏时显示「左右翻页 / 上下滚动」。
- **默认字体改为 Iowan Old Style**：字体列表改成与 Apple Books 一致（Iowan、Charter、Georgia、Palatino、Athelas、Seravek、San Francisco、New York），并保留 Literata，标注「安卓默认」。原型在 Mac/iPhone 的 Safari 里能显示这些苹果字体；在其他浏览器里会退回相近字体。
- **气泡改成浅色**：极简、简洁气泡和句子卡片、完整卡片统一用 `--surface` 底色，加细描边和柔和阴影，文字用 `--ink`，小箭头同色。在安静、夜间主题下，`--surface` 本身就是比页面稍亮的深灰，不会出现刺眼的白块。`--tip-bg` / `--tip-ink` 只留给 toast 使用。
- **其余默认值确认不变**：极简档显示 2 个意思；主题为白色 + 跟随系统深色模式。
- **设置存储升级**：localStorage 的键改为 `rp.settings.v2`，否则你浏览器里 v1 存下的旧设置（Literata 字体、滚动模式）会盖掉新的默认值。
- 改完后重新发布到同一个链接，并用 JavaScriptCore 做一次语法检查。

**原型之后还需要你看的（可选，不影响往下做）**：在 iPad 横屏双页下点词，看气泡位置是否舒服；在 Mac 的 Safari 里看 Iowan 字体的效果。

**阶段 2：模拟器上的英语 MVP**（开发时以 iPhone 模拟器为主，同时在安卓模拟器上检查）
- 用 Flutter 创建工程，支持 TXT 和粘贴导入，实现内容模型和滚动阅读器。
- 按原型实现完整的阅读设置：字体、字号、间距、四种主题、跟随系统夜间模式。
- 用 `build_ecdict.py` 生成英汉词典包（含 `senses` 表），实现点词 → 气泡（三档）→ 点击展开完整卡片，并记住阅读进度。
- 完成「基础功能清单」里所有标 `[2]` 的项。

**阶段 3：EPUB + 长按翻译 + 生词本 + 英英词典 + 上设备**
- EPUB 解析（目录、章节、图片、简单表格）。
- 断句、长按选句（可拖动调整范围），接入 Apple Translation 插件和 ML Kit，并做翻译缓存。
- 生词本：记录单词、原型、释义、原句、书名和日期，可导出 CSV。
- 用 Wiktionary 生成英英词典包，在完整档中显示；设置里可调整词典顺序。
- 翻页模式（左右翻页），可与滚动模式切换。
- 完成「基础功能清单」里所有标 `[3]` 的项（目录、书签、搜索、脚注、备份等）。
- 装到 iPhone、iPad（Xcode 签名）和安卓手机（APK）上，完成 iPad 横屏和大屏适配。

**阶段 4：MDX 导入 + PDF**
- MDX 导入：选择文件 → 解析 → 建立索引；完整档用 WebView 按原排版显示，同时加载 .mdd 资源。
- PDF：用 `pdfrx` 渲染原始页面，读取带坐标的文字层，实现点词和长按选句，命中处叠加高亮。

**阶段 5（可选）**
坚果云 WebDAV 同步生词本、进度和书籍；法语、德语等其他语言的词典包。

## 验证方式
- **单元测试**（`flutter test`）：
  - 分词（撇号、连字符）
  - 断句（Mr.、e.g. 等缩写，引号）
  - 词形还原（went→go、studies→study）
  - 三档释义提取（极简：tomorrow→明天；未来；简洁：不含词性）
  - 分页：换字号后页数正确，没有丢字或重复
  - 用常用词表检查词典命中率
- **手动端到端**：`flutter run`（iPhone 模拟器或真机），导入一本英文 EPUB 小说：
  - 点词后气泡立刻贴着单词出现，不遮挡当前行；
  - 三档切换正常，点气泡能展开完整卡片；
  - 改字体、字号、主题后立即生效，系统切到深色后夜间模式自动启用；
  - 长按选中整句，首次翻译 <1s，再次长按直接命中缓存；
  - 重开 App 回到原来的阅读位置；
  - 目录跳转后能「返回上一位置」，书签和书内搜索能正确跳转，点脚注就地弹出；
  - 翻页模式下，点词不会误触翻页，点边缘不会误触查词；
  - 逐项勾完「基础功能清单」中本阶段的项；
  - 生词本里有刚加入的词和原句。
- **各平台**：
  - iPhone/iPad 真机：确认系统翻译语言包的下载提示正常，iPad 横竖屏布局都舒服；
  - 安卓：确认 ML Kit 模型能下载；
  - 断网测试：飞行模式下点词和长按翻译都能用（语言包已下载的前提下）。
