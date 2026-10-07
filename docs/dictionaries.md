# 离线词典契约

状态、验证结果与下一步只维护在 `../PLAN.md`。

## 学习语言边界

- V1只支持英语学习。中文界面、英汉/英英释义选择与英语句子译为中文均保持；这些不是学习语言切换。未来可能扩展其他学习语言，V1不提供选择器或其他语言数据。
- LanguageSupport隔离分词、断句与词形候选，DictionaryProvider隔离查询；英语规则留在英语实现和数据构建中。通用阅读、位置、书签及业务存储不依赖ASCII英文单词边界。语言默认入口如需整理，采用现有接口的最小注入，不构建多语言框架。
- lang/dict_id及翻译缓存语言对保留真实语义；旧英语记录未来仍按en解释。扩展时保持学习语言与glossLanguage（当前英语词汇释义语言）的概念分离。V1不为假设的新语言先改schema或现有UI。

## 数据和重建

- ECDICT 英汉保留独立 MIT 数据库与原有 manifest/source lock，中文词义排序不改。
- Wiktionary 英英来自 [Kaikki 原始 Wiktextract 数据](https://kaikki.org/dictionary/rawdata.html)，按顶层 `lang_code=en` 筛选。原始 gzip、生成 SQLite/gzip 均不提交 Git；固定快照和生成包的大小、SHA-256、版本及条数在 `dict_builder/wiktionary-source.json` 与 `app/assets/dictionaries/wiktionary-manifest.json`。
- `scripts/fetch_wiktionary.py` 下载并严格校验固定快照，`dict_builder/build_wiktionary.py` 流式处理、不把整个 JSONL 载入内存。下载地址会更新；源校验不符时拒绝自动更新。保留原始快照才能离线重复构建；更新版本必须重新核对并明确修改 source lock。
- 每个原始词性/词源记录独立入库，不覆盖同词条的其他词性；释义顺序、父子释义链、标签/限定语、IPA、词形引用保留。仅采用 `type=example` 且无 ref/source/author/title 等第三方出处的用法示例；跳过 quotation，不打包图片/音频/原引文。
- 英英数据库按 **CC BY-SA 4.0** 作为独立派生数据库提供。来源词条 URL、Wiktionary contributors、变更说明和许可在完整气泡及“开源许可与致谢”可查看。参见 [Wiktionary 版权说明](https://en.wiktionary.org/wiki/Wiktionary:Copyrights)、[Wikimedia 再利用条款](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use#7._Licensing_of_Content)、[许可证](https://creativecommons.org/licenses/by-sa/4.0/)。这与 ECDICT/应用代码的授权分别处理。

## 查询和显示

- `DictionaryProvider` 保持同步 `lookup/close`，词典 SQLite 独立于业务库。`CombinedDictionary` 组合 ECDICT 与 `WiktionaryDictionary`；后者使用独立只读 SQLite，失败时保留英汉并在完整档提示英英不可用。
- 完整卡片可收藏当前显示语言的释义及原句，极简/简洁气泡不增加收藏控件。生词快照保存在业务库 schema 5 独立表，契约见 `vocabulary.md`；收藏不改词库或正文进度。
- Wiktionary 优先精确拼写的真实词义（保留 May/may 区别）；没有实义或只有 form_of/alt_of 时沿数据内词形引用查询。最多访问 16 个候选、每次最多 8 条引用，循环和缺失目标终止。多个歧义目标采用长度/字典序的确定性顺序，不声称按上下文消歧。
- `reading` 等自身有实义的屈折词保留本条；`went` 等纯词形条目可显示原形。英汉与英英的原形可能不同，英英单独标示，中文释义不因英英解析而替换。
- 阅读设置提供主释义（英汉/英英）与展开行为（保持当前方式/查看另一种语言）。缺省为英汉 + 保持当前方式：原中文气泡和完整卡片的布局、内容顺序与手势不变，包括完整卡片已有的 Wiktionary 追加区域。
- 气泡打开（含词典加载中）时，点气泡外的正文单词、链接或空白只关闭当前释义并清除选词，不在同一次点击查询新词或打开脚注；下一次点击恢复查询/跳转。气泡内部展开、语言切换与关闭按钮不变；滑动翻页/滚动及长按句子沿用既有行为。
- 气泡显示最多 24 条英英释义、每条最多 2 个例句，超出释义数明确提示并提供来源。数据库保留其余数据。默认兼容路径中，既有 ECDICT 英文 definition 在没有 Wiktionary 释义时保留，不标为 Wiktionary；可选单语言卡片不把它混入中文或冒充英英词库。
- 英英主释义直接在极简/简洁气泡显示英文；极简取设置的前 1–3 条，简洁最多 24 条，不附音标/词性/例句，超限有提示。英文换行/滚动沿用受限气泡，不扩大正文预留区。
- 跨语言展开可选英英→英汉或英汉→英英；可选路径的完整卡片只显示一个词典，并提供英英/英汉切换。该切换仅作用当前选词，选新词/关闭/改相关设置时重置；同一拼写的另一次正文查词也重置。默认中文路径不加切换控件。
- 完整档直接显示主语言，禁用但保留“点击气泡展开”的设置值。缺词或不可用分别提示，另一词库有结果时允许主动查看，不自动切换或触发机器翻译。两库都成功确认未收录时采用下述独立兜底。头词、音标、来源跟随当前词典；默认路径保持原有兼容行为。
- `ReaderStyle` JSON version 1 增加 `glossLanguage`（enZh/enEn）与 `glossExpansion`（current/otherLanguage）；缺失/未知值回落 enZh/current。沿用全局 readerStyle 与单书 books.style 保存机制，业务 schema 不变。多词选区、MDX、联网查词、生词本和词典下载管理不在本模块。

## 安装与验证边界

- 书架“更多 → 词典管理”提供只读信息页。ECDICT / Wiktionary 分别展示来源版本、许可、内置词包大小、当前本地文件大小与四态（已就绪/内置待准备/暂不可用/无法读取）；刷新重新检查，两库异常独立处理。
- `DictionaryCatalog` 只读取 manifest、当前 SHA 命名的文件长度，并以只读 SQLite 检查 schema/必要字段。管理页不初始化 `CombinedDictionary`，不读取完整词包、不解压/下载/修复/删除，不访问业务数据库。书架移除预加载，词库准备由首次点词触发，沿用既有加载提示及查询接口。
- 内置词包大小取 manifest（英英为 gzip 大小）；本地占用为当前版本文件的实际字节数，缺失为 0、读取失败为未知，不包含旧文件、业务库或系统安装压缩开销。就绪状态不是全库哈希或完整性认证；不代表已完成低内存真机验收。页面目前没有词库导入、更新或删除入口。
- 英英词库内置 gzip SQLite；首次使用按 64 KiB 输入分块解压至临时文件，检查大小后原子改名。英汉词库直接复制内置未压缩 SQLite，经临时文件改名。两者以词库校验值命名本地文件；打开时检查 schema，英英另查必要字段。资产源校验在构建时完成，运行时不重复扫描整库。
- 首次仍需读取压缩资产，尚不能把主机测试当作低内存真机性能验证。没有无限自动删除历史词库，也不清除阅读库或翻译模型。
- Python tests 覆盖语言过滤、词性/释义顺序、引用示例排除、词形、确定性和坏输入；Dart tests 覆盖查询、循环/词形、ECDICT 保留、来源显示与三档气泡。真实词包另行检查 integrity/counts/抽词和延迟；所有真实数字记录在 PLAN 与 manifest。

## 未收录词的翻译兜底

- `DictionaryProvider.lookup` 的 null 只表示查询成功但未收录，查询不可用应抛出异常。CombinedDictionary仅两库均成功返回null才返回null；英英加载/查询错误且英汉也无词条时抛出错误，不能当miss。英汉已有词条时仍保留词条及英英不可用提示。
- Reader仅在词典完成、无错误、entry为null时接入机器翻译。只缺所选语言、另一库有词条，或ECDICT有英文definition/空释义记录，仍沿用词条路径，不强行切换或翻译。
- 真实miss在原受限气泡自动尝试现有en→zh-Hans离线翻译/成功缓存，标注“词典未收录 · 英译中机器翻译”，包括英英主释义用户；不会将机器译文冒充英英定义或改动设置。紧凑档最多三行，点气泡展开全文、复制原词与翻译说明；原正文分配不变。Android成功译文保留Google来源标识。
- 无模型时提示用户点击“下载语言模型并翻译”；失败提供原有重试/不可用状态。气泡以每次lookup代次隔离，关闭/换词/重排后晚到结果不重开气泡、不覆盖当前词、不改正文或返回栈。模型下载已启动可能继续，但已关闭的界面不会在下载完成后继续启动翻译；已经启动的成功翻译可按原文精确键入缓存。
- `TranslationContent`与SentenceSheet共用翻译生命周期、错误处理、下载与来源说明；CachedTranslator缓存、限制和清理规则不变。机器结果不构造DictionaryEntry，无生词收藏按钮、不写vocabulary；本模块不添加查词历史、数据表或新语言配置。

- 查询成功（含确认未收录）且当前气泡仍有效时，原词按history.md进入最近查词历史；不复制释义或自动收藏。历史入口重新查询当前词典，沿用全局主释义语言与本契约的缺词兜底。

## 首次使用引导

- 书架“开始英语阅读”卡片可跳过，“更多 → 阅读与离线准备”可随时重开；只支持当前V1英语学习，不新增语言选择或改变英汉/英英设置。
- 指南复用DictionaryCatalog检查各词库的ready/notPrepared/unavailable/unknown状态，可进入现有词典管理查看大小和许可；不会初始化CombinedDictionary、读取大词包或解压词库。首次点词的既有准备流程不变。
- settings键readingGuideSeenV1=1只在明确“暂时跳过”或“先去阅读”时写入。新旧安装缺此键均显示可跳过卡片，不强制跳转；查看/系统返回不自动标记，写入失败保留重试且不阻碍阅读。读取设置失败时卡片隐藏，常驻菜单仍可进入。
- 设置随既有整库备份恢复；旧备份无标志时卡片再次可见，恢复后刷新对应provider。不改变schema或ReaderStyle，也不把“已看引导”解释为词典/翻译模型已准备。
