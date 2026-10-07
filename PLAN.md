# Reading — Canonical Plan

## Current Summary

更新：2026-10-08。项目：`/Users/tty/Desktop/Coding/Reading`；正式工程：`app/`。

**交付节奏（2026-10-07用户更新）。** 不必每个模块安装iPad真机；先做实现/自动化/模拟器验证，合适节点再集中真机交付/验收。历史模块真机尚未安装作为待办保留，不阻塞后续开发，不重复要求连接。

**规则 / Git。** 本文件为唯一 canonical plan；HANDOFF / HANDOFF-WIP 为历史快照，不另建计划。main / f3a3d5a，大量前序未提交修改保留，暂存为空；不暂存/提交/推送。

**V1语言边界（用户最新要求）。** V1只支持英语学习；现有中文UI、英汉/英英释义和en→zh-Hans句子翻译保持。学习语言与界面语言/释义语言是不同概念。未来V2可能扩展其他学习语言，但本轮不实现语言选择、多语词包、额外翻译语言对或通用多语言框架，也不因此改动已验收UI。

**当前目标。** V1发布准备核查与最小补齐：图标/启动页、名称版本、权限许可和构建签名边界；用户确认先用现有棕色风格的简洁书本图标。不安装设备，不自动发布或创建签名密钥。

**已接受的行为。** 用户2026-10-06反馈已在iPad检查上一CSV交付并要求下一项，记录iPad CSV体验通过，不扩展为其他设备或所有历史待验项。 用户此前已确认章节另起页/重开位置、点其他词与中缝只关闭释义、Apple 大加载弹窗移除以及 iPad 断网新句翻译均无问题。按这些范围记录通过，不扩展为 iPhone 真机、首次模型下载许可、iOS 18 兼容分支或低内存设备验收。英英主释义/跨语言展开此前已确认。

**实现与下一步。** V1发布准备工程核查完成：书本图标/浅深启动页、名称版本/权限许可/签名边界已核对；analyze、Android ARM64 Release205.6MB、iOS模拟器构建及APK签名校验通过。没有安装设备或正式发布。下一步为大书首次分页耗时定位，先建立宿主可复现基线；真机Profile与集中体验仍待用户恢复安装。上轮引导最终270/270通过，一次GBK依赖初始化异常未复现，原因未定。

**现有能力 / 接口。** TXT/EPUB、图片/简单表格、正文/补充脚注、单/双页、源锚点保存、ECDICT/Wiktionary 和 Apple/ML Kit 真实翻译已实现。业务 schema 7新增查词历史表，schema6书签/schema5生词表保留，PageAnchor v1、ReaderStyle v1及既有业务表保持不变。章节按现有 contents 另起下一物理页，双页左右均可；手机上边距20/平板32，底部40薄信息。阅读器共享行为见 docs/epub-links.md；词典、翻译、生词、书签契约分别 docs/dictionaries.md、docs/translation.md、docs/vocabulary.md、docs/bookmarks.md，书内搜索见 docs/search.md，备份格式与恢复契约见 docs/backup.md。

**上一检查点证据。** 章节模块全量142/142、分析、真机/模拟器/Android 构建通过，四设备覆盖安装及数据对照通过；这是前轮证据，不代替当前新增模块测试。iPad 真机签名 Team 已配置，设备开启开发者模式；原生 UI 自动化历史不可用，体验由用户验收。

**风险 / 未完成。** 生词列表首版全量读取后本地筛选，大规模记录性能未验证；CSV其他平台及原句回跳原生体验待反馈；大规模CSV导出内存峰值未验证。备份首版32MiB数据/64MiB文件限制与接近限额的内存峰值仍需真机体验；Wiktionary 119MB压缩包/320MB本地库首次准备的低内存性能、大书/真实教材范围测试、iPhone真机仍保留。词典来源地址可能变化，重建需固定SHA原始快照。本地状态检查不等价全库完整性认证；管理页只显示当前版本文件，不统计旧副本或系统安装压缩开销。安装对照发现iPhone模拟器脚注样本保存位置变化，原因未独立确定，详情见前一词典管理模块；上轮跳转面板修复、生词本升级及本轮原句回跳的四设备旧数据对照均一致。

**最少恢复。** 先读摘要、当前模块及git status/暂存与未暂存diff。下一步入口reader/{paged_reader,book_pagination,pagination,pagination_cache}.dart和现有分页测试，先区分源解码/图片预检/文字布局/缓存命中耗时；不安装设备、不改位置格式，保留全部前序修改。图标资源入口scripts/generate_app_icons.swift，重建命令和签名边界见app/README.md。

## 当前模块：V1发布准备核查（工程与构建完成，未安装设备）

- 用户确认V1先用简洁书本图标；替换Flutter默认图标，沿用#835C3E棕色、#FBFAF8纸白与书签色。scripts/generate_app_icons.swift在macOS用共享矢量几何生成iOS各尺寸不透明PNG、Android旧版PNG/自适应及单色图标、启动页素材，无外部图像依赖。
- Android旧版及Android12+启动背景、NormalTheme背景和iOS命名颜色随浅/深色匹配Flutter背景；启动页只显示书本，不添加人为延时或新启动路由。保留现有业务/数据库/阅读布局。
- 显示名Reading、版本0.2.0+1与许可页一致；Android dev.reading.reading_app、iOS dev.reading.readingApp标识保持，避免破坏覆盖升级。已有开源致谢和词典/字体许可入口不重复实现。
- Android已构建包权限仅INTERNET、ACCESS_NETWORK_STATE及本应用DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION，无相机/录音/广泛存储授权。iOS依赖含Flutter/file_picker/wakelock/package_info隐私清单；这只是资源检查，不等价已完成商店隐私申报或全部SDK合规审核。
- 发布边界：Android Release仍用debug签名，iOS仍Apple Development自动签名；保留现有本地优化测试用途，Gradle注释明确非商店分发签名。正式渠道/账号归属、上传密钥或分发证书、商店隐私声明/截图等须实际发布前确定，不为本轮生成密钥或更改标识。
- 验证：iOS全部图标尺寸匹配目录、PNG不透明RGB，Android XML/iOS storyboard解析通过，已目视检查生成图标；analyze无问题、git diff --check通过。Android ARM64 Release assembleRelease27.0s、205.6MB；iOS模拟器Xcode13.9s成功。新APK的签名验证、Reading显示名、0.2.0/versionCode1/仅arm64和上述权限再次核对通过。原Dart逻辑未改，上轮最终270/270为功能回归证据，本轮没有重复全量测试；不以编译成功代替原生启动视觉验收。
- 复现：根目录`swift scripts/generate_app_icons.swift`；app目录`../scripts/flutterw analyze --no-pub`、`../scripts/flutterw build apk --release --target-platform android-arm64 --split-per-abi -P force-version-code-ignoring-abi=true`、`../scripts/flutterw build ios --simulator --debug --no-pub`；SDK build-tools/36.0.0的apksigner verify和aapt dump permissions/badging核对APK。临时日志/tmp/reading-release-prep-{analyze,android,ios}.log，不作跨机器恢复前提。配置参考Android官方[启动页](https://developer.android.com/develop/ui/views/launch/splash-screen)与[自适应图标](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)。
- Workflow status：plan done（唯一PLAN与下一步骤对齐）；architecture not needed（原生资源和注释，不改业务/存储）；interface done（app/README重建命令/发布边界，启动素材说明）；engineering validation done（资源检查/分析/双构建/签名），启动视觉及正式分发 pending（设备延后、尚无正式渠道签名）；Git checkpoint not needed（用户要求不暂存/提交/推送，前序修改保留）；handoff done（证据/命令/唯一下一步明确）。全部构建已结束，无待续工程会话。

## 前一模块：英语首次使用与离线准备引导（工程与构建完成，未安装设备）

- 书架非强制卡片“开始英语阅读”，可进入指南或跳过；更多菜单“阅读与离线准备”随时可重开。未增加启动强制路由或学习语言选择，不改原阅读UI；新旧安装缺少标志时均显示可跳过卡片。
- 阅读指南解释导入/点词与英英选择/长按翻译/可见同段选区/翻页；分别复用DictionaryCatalog.inspect与Translator.status读取资源状态。只读取manifest/本地词库摘要，不初始化CombinedDictionary或加载大词包，不自动prepare/translate；原首次点词准备词库行为保持。
- 模型缺失时显式“下载语言模型”；复用现有prepare及平台许可/Wi-Fi要求，完成后再status确认。失败可重试，状态读取错误可刷新，不把失败/未知写成就绪；准备中防重复点击，关闭后只忽略页面回调、不继续翻译，SDK已开始的下载可能继续。恢复前台或词典管理返回后刷新状态。
- 持久化仅settings新增readingGuideSeenV1=1，由明确跳过/先去阅读写入；写失败保留重试/返回途径，不挡打开书。查看指南/系统返回不自动标记。沿既有备份settings整库语义，新备份带标志，旧备份缺标志则再次显示卡片；恢复后invalidate对应provider。schema7、ReaderStyle和原生桥不变。
- 工程验证：9项widget专项+1项备份兼容，最终全量270/270通过、analyze无问题、git diff --check通过。覆盖卡片跳过/旧设置/菜单重开/不提前检测资源、写入失败重试、状态错误刷新、用户主动下载及重新检查、失败与仍未就绪结果、关闭后的晚到完成、ready/unsupported/unavailable三状态320窄屏1.5倍字、新旧备份设置往返。原书架、导入、阅读与备份全量回归通过，未触发真实资源下载。
- 首轮全量269通过/1失败：既有core_test.dart的GBK映射初始化报List<dynamic>不是String，栈在gbk_codec静态Map；依赖锁文件无变化。单独core_test 6/6通过，随后完整270/270通过；未改GBK代码或断言，不将未复现称为已修复，若再次出现须检查依赖/Flutter测试运行时而非忽略。5项括号lint已清理。
- 构建：Android ARM64 Release assembleRelease21.5s、APK205.6MB；iOS模拟器debug Xcode12.1s成功。apksigner verify通过，version0.2.0/versionCode1/仅arm64，沿用开发签名。没有安装设备，不以替身测试证明真实模型已下载或新入口真机体验通过。
- 复现（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/reading_guide_test.dart --reporter expanded`，全量去掉路径；`../scripts/flutterw analyze --no-pub`；`../scripts/flutterw build apk --release --target-platform android-arm64 --split-per-abi -P force-version-code-ignoring-abi=true`；`../scripts/flutterw build ios --simulator --debug --no-pub`。临时日志/tmp/reading-guide-{tests,full,core-recheck,full-final,analyze,release,ios}.log，不作跨机器恢复前提。
- Workflow status：plan done（唯一PLAN结果和下一步骤已对齐）；architecture not needed（现有settings/Catalog/Translator，不增schema或原生接口）；interface done（docs/dictionaries.md、translation.md及app/README引导契约）；engineering validation done（最终270全量/分析/双构建/签名），真机体验 pending（按用户要求延后安装），一次GBK测试异常原因 pending（已复核未复现）；Git checkpoint not needed（未暂存/提交/推送，保留前序修改）；handoff done（入口/证据/边界/下一步齐全）。本轮全部测试、构建结束，无待续后台工程会话。

## 前一模块：图片点击放大与缩放（工程与构建完成，未安装设备）

- 正文分页/双页/滚动图片共用openImage与临时ReaderImageViewer路由；复用数据库已读取图片字节，不访问网络、不复制原文件或改书内布局。补充文档和生词原句阅读走相同入口。图注点词仍原行为。
- 有点词气泡时第一次点击图片只dismiss，下一次才打开；重复打开与非当前路由拦截。支持双指1–5倍、放大后拖动、双击2.5倍/还原、按钮放大/缩小/还原、关闭和系统返回。沿当前ReaderPalette；旋转查看页后重置图片变换，阅读页按原源锚点重排。
- 输入上限20MiB；先读图像描述信息，解码不主动放大小图，最长边4096、最多8Mi像素；大原图允许降采样，不承诺无限放大或原像素显示。缺失/坏图有可退出提示，描述器和buffer在finally释放，transform销毁。
- 本轮未改数据库/位置JSON/分页算法/原生桥，没有新依赖。原图片缩略图与图注空间不变；查看页不写正文位置，原阅读器生命周期仍按既有规则保存。
- 验证：最终7专项/全量260通过，analyze无问题，git diff --check通过。覆盖Android320/iPhone402/iPad1194分页、手机滚动及补充文档原句临时根；实际点词→点击图片只关闭、再次打开；按钮/双击/双指缩放与拖动；关闭/系统返回/快速重复点击，正文整数与精确位置不变；解码尺寸、空/坏/超限字节、可退出错误状态。首次测试重复tap的命中警告已改为同坐标真实点击，3项格式/导入lint已修复，无未解决失败。
- 构建：Android ARM64 Release assembleRelease21.5s，APK205.6MB，iOS模拟器debug Xcode12.1s成功；apksigner verify通过，包名dev.reading.reading_app/version0.2.0/versionCode1，仅arm64。沿用开发签名，优化包不等于正式商店发布包。本轮未安装任何设备，原生手势舒适度仍待集中体验。
- 复现（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/image_viewer_test.dart --reporter expanded`，全量去掉路径；`../scripts/flutterw analyze --no-pub`；`../scripts/flutterw build apk --release --target-platform android-arm64 --split-per-abi -P force-version-code-ignoring-abi=true`；`../scripts/flutterw build ios --simulator --debug --no-pub`。临时日志/tmp/reading-image-{tests,full,analyze,release,ios}.log不作跨机器恢复前提。产物app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk。
- Workflow status：plan done（唯一PLAN结果/下一模块对齐）；architecture not needed（复用资源与临时路由，无schema/原生变化）；interface done（epub-links.md图片查看契约、app/README入口）；engineering validation done（7专项/260全量/分析/双构建/签名），原生体验 pending（用户延后安装）；Git checkpoint not needed（未暂存/提交/推送，前序修改保留）；handoff done（范围/证据/边界/下一步明确）。本轮测试和构建全部结束，无待续工程会话。

## 前一模块：会话内分页缓存（工程与构建完成，未安装设备）

- 有界LRU复用完整BookPagination，最多3份/16MiB估算留存预算；精确源JSON与书ID/文档/几何排版参数作为键，不使用位置/时间戳判断内容版本。Book.contentSnapshot只附带已有DB字符串，不新增schema或序列化字段；未提供快照的临时Book不缓存。
- 命中在首帧直接显示按当前PageAnchor定位的正文，不再进入“正在分页”；主题/释义设置不重排。字号/方向/文字缩放等隔离，返回旧排版可以复用；源改变清掉当前计算状态。缺图结果不缓存。
- 缓存不留图片像素，超预算只跳过缓存而不阻断阅读。删除书籍/恢复成功/系统内存压力/数据库provider替换清理，generation避免在途旧结果回填。缓存预算不等于整个App内存上限；源JSON快照增加了活跃书架字符串留存，原有全量加载大书库的内存需后续实测。
- 当前专项覆盖精确内容/书/文档/几何隔离、LRU与容量/删除/内存压力、缺图拒绝、排版键与纯显示参数、反复解码重开首帧命中/最新锚点/字号/单双页窗口/源替换；上轮入场取消和原全量回归一并执行。
- 工程验证完成：5项新专项包含在全量253/253中，analyze无问题，git diff --check通过。初轮252项通过后追加缺图拒绝与方向切换测试；一项括号lint已修正。最终Android ARM64 Release assembleRelease21.5s、iOS模拟器debug Xcode12.0s成功；APK205.5MB，签名校验通过，包名/版本0.2.0/versionCode1不变，仅arm64-v8a。
- 用户最新决定：本轮仅工程与构建，未安装手机、iPad或模拟器，不请求重连。下一模块恢复图片放大；渐进分页与Profile实测留作性能后续，不宣称首次开大书已快或所有动画不卡。
- 复现（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded`、`../scripts/flutterw analyze --no-pub`、`../scripts/flutterw build apk --release --target-platform android-arm64 --split-per-abi -P force-version-code-ignoring-abi=true`、`../scripts/flutterw build ios --simulator --debug --no-pub`；日志/tmp/reading-pagination-cache-{tests,full,analyze,release,ios}.log为临时证据。交付包app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk，不能用旧Debug替代。
- Workflow status：plan done（唯一PLAN结果和下一模块已更新）；architecture done（共享有界会话缓存，保留原分页算法/源位置，无schema或原生修改）；interface done（epub-links.md缓存/清理契约）；engineering validation done（253全量/分析/双平台构建/签名），真机性能 pending（用户选择延后安装）；Git checkpoint not needed（未暂存/提交/推送，前序改动保留）；handoff done（恢复入口/命令/限制齐全）。所有本轮测试/构建命令已结束。

## 前一模块：开书入场动画性能（工程完成，Android真机待重连交付）

- 用户澄清卡顿集中在书架进入阅读页的滑入动画；openBook接收已解码Book后push，PagedReader原首帧即启动整书分页，与路由动画共用UI线程，是确定的工作重叠而非已测量的唯一掉帧原因。
- 修复：PagedReader等待路由正向动画完成后才读分页图片/计算布局；共享等待器及generation屏蔽过期配置；反向退出和dispose释放监听，不启动已退出路由的分页。保留原滑入动画、正文布局、源锚点和进度保存，不修改schema或词典逻辑。
- 验证：reader_entry_test.dart两项确认动画中零图片读取/无layout、完成后正常分页、中途pop不读取/无异常；全量248/248通过。analyze最初一项括号格式提示已修复，最终无问题；仅加括号不改测试行为。iOS模拟器debug Xcode13.3s成功，Android Release成功；未重复安装模拟器，真机用户体验pending。
- 打包：Debug通用包400.1MB；仅target-platform仍残留插件其他ABI，实际235MB；加split-per-abi后真正只有arm64-v8a，约205.5MB。包名dev.reading.reading_app/versionName0.2.0，使用-P force-version-code-ignoring-abi=true保持versionCode1，避免架构包自动升为2001影响后续升级。仍使用项目原debug签名证书（与已安装版一致），Release优化不等于已配置正式发布签名。
- 构建恢复：首次--no-pub Release因旧GeneratedPluginRegistrant残留integration_test引用失败；pub get --offline并让build执行pub插件生成后成功，pubspec.lock无变更。模式切换时若复现，重新生成插件元信息，不手改生成文件或删用户数据。签名校验用JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home。
- 当前手机ADB仅见模拟器，未覆盖安装。后续重连10ADA60Q6Z002SZ后先重新取得当前数据基线（用户可能已导入书），再adb install -r app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk；不得拿首次空库代替当前基线。Release不可依赖run-as读取，因此安装后保留数据需用可用只读方式/用户书架位置检查，不通过卸载或降级解决权限。
- 下一步先验证这份优化包的滑入体验，必要时用Profile采集帧耗时再改热区；整书重算、缓存、渐进显示尚未实现。不将延后分页说成降低总计算量或彻底解决掉帧。
- Workflow status：plan done（唯一PLAN调整当前目标）；architecture not needed（局部调度，不改数据/接口）；interface done（epub-links.md调度契约）；工程validation done（2专项/248全量/analyze/双平台构建），真机交付与帧耗时 pending（手机断开）；Git checkpoint not needed（不暂存/提交/推送）；handoff done（文件/构建命令/交付断点明确）。证据/tmp/reading-entry-{full,analyze,release-arm64,ios}.log，不作为跨机器恢复依赖。

## Android真机性能反馈与初步诊断（2026-10-07）

- 用户反馈每次开书“正在分页”、动画/交互卡顿，并询问约400MB体积。此次只做源码和APK结构分析，未修改代码或替换手机安装包，未采集真实帧时间。
- 已确认：PagedReader.layout仅活在当前State，重开需先读取当前文档图片尺寸，再完成整本文档BookPaginator.paginateAsync才显示正文；无跨打开分页缓存。paginateAsync仍在UI isolate执行TextPainter，按块/表格行检查8ms后让出事件循环，单块计算和最后索引构建不保证帧预算。配置比较使用完整style.encode，后续需区分排版参数与纯显示参数，避免无关设置触发重排。
- 已交付为Debug通用APK，压缩条目合计约370.6MiB（文件约382MiB含打包开销，约400MB十进制）；其中词典159.4MiB（Wiktionary113.5/ECDICT45.9）、三架构native169.8MiB、其他41.3MiB。Debug含kernel_blob/调试引擎及验证层，不代表优化后安装包体积；运行后词库展开/模型/书籍另占磁盘，不能混同内存。
- 后续建议先将真机性能列为优先修复候选：用arm64 Release核实交付体验与大小、Profile真机采集开书/分页/翻页帧耗时，再决定有界分页缓存与分段优先显示策略。不能承诺换Release即可全部修复，也不能直接把TextPainter搬到普通后台isolate。图片放大尚未开始；本次分析不等于已完成性能优化或新的真机验收。

## Android真机首次交付（2026-10-07）

- 用户要求安装到已连接手机；ADB确认V2301A / PD2301，Android16/API36，arm64兼容，安装前pm path无Reading。设备序列10ADA60Q6Z002SZ，仅后续用户授权设备操作时使用。
- 复用已验证最新app-debug.apk（0.2.0/versionCode1，minSdk24/targetSdk36，含查词历史和目录返回），正常adb install -r返回Success；am start -W返回Status: ok，已在前台。首次安装，不涉及旧库迁移；未清数据、卸载、注入样本或自动下载模型。
- 手机原生阅读/点词/模型下载及离线新句翻译待用户体验；不能沿用Android模拟器或iPad验收作为此手机通过。测试包交付不等于正式发布版本。本次无源码修改，不重复测试与构建；下一开发模块仍为图片点击放大/缩放，iPad真机集中交付安排不变。

## 前一模块：目录跳转返回（工程与三模拟器交付完成，真机集中交付待办）

- 只为普通正文根阅读器保存一个临时来处；首次目录跳转建立、连续目录跳转保留、返回后清除，不新增路由或持久化字段。正常离开/重开沿当前进度，不自动退回旧处。脚注/搜索页选目录仍结束临时浏览并让正文处理；生词临时根按原逻辑不写正文位置。
- 分页保留完整PageAnchor（含图注/表格行），滚动保存可见块及布局未变时的位置；字号/方向/模式改变后按源锚点或块重排，不承诺旧像素。新增返回入口在原操作面板/滚动工具栏，已有目录/设置/搜索/书签/进度控件保留，紧凑正文与底部信息高度不变。
- 验证：单页/双页/滚动、连续跳章、返回/再次跳章、字体/方向变化、图片表格锚点、脚注嵌套/选目录、生词原句隔离、当前进度保存/重开无旧返回点。专项/全量/分析/iOS模拟器与Android构建，模拟器保数据交付；本轮不要求真机安装。


- 工程验证：专项7项包含在全量246/246中，analyze无问题，git diff --check通过。三尺寸覆盖连续目录选择/返回/新返回点/当前进度与重开、原控件及正文高度不变；滚动半屏段落恢复误差小于2px；表格行完整锚点跨字号/方向变化保留；分页与滚动模式切换；脚注选目录回正文与生词临时根隔离。测试初稿的listener取值及面板点击位置已按实际测试接口修正，无未解决失败。
- 构建：iOS模拟器debug Xcode13.2s、Android assembleDebug10.2s通过。本轮未构建或安装iPad真机版本，遵循用户集中真机交付节奏；既有Java native-access警告未阻断构建。
- 交付：iPhone/iPad模拟器及Android正常覆盖安装并启动；schema7不变，原3/1/4本书及正文哈希/整数与精确位置/样式/资源/settings/译文/生词/书签/历史快照一致，Android仍6条译文。未卸载、清数据、test -d或注入样本。
- 待体验：普通正文打开目录选章节，再打开原阅读操作使用“返回目录跳转前”；连续选多个章节应返回首次来处，原设置/目录/搜索/书签/进度保留。滚动模式入口在原工具栏；返回点仅本次阅读有效，重开沿当前保存位置。原生体验与工程验证分开记录，不要求本轮连接真机。
- 证据/恢复：reader.dart rememberChapterOrigin/returnFromChapter/openChapter、paged_reader.dart jumpAnchor、test/chapter_return_test.dart、docs/epub-links.md及app/README.md。命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded`、`../scripts/flutterw analyze --no-pub`、`../scripts/flutterw build ios --simulator --debug --no-pub`、`../scripts/flutterw build apk --debug --no-pub`。临时日志/tmp/reading-chapter-return-{tests,full,analyze-final,ios-simulator,android}.log及/tmp/reading-{before,after}-chapter-return-sim-install.json不是跨机器恢复依赖。
- Workflow status：计划 done（唯一PLAN已对齐结果与下一模块）；架构 not needed（复用现有源锚点和阅读状态，不改schema/位置JSON/原生桥）；接口 done（docs/epub-links.md记录普通目录返回语义）；工程验证 done（7专项/246全量/分析/两构建/三模拟器保数据交付），原生体验 pending，iPad真机安装 pending（按用户要求集中安排，不阻塞后续）；Git checkpoint not needed（不暂存/提交/推送，前序修改保留）；handoff done（入口/证据/边界/唯一下一步齐全）。所有本轮测试、构建及安装命令已结束，无待续后台工程会话。

## 前一模块：查词历史（工程与三模拟器交付完成，真机集中交付待办）

- 范围：history/{history,history_page}.dart、db/database.dart、core/providers.dart、reader.dart点词完成、library.dart入口及backup两文件。查询成功（含确认未收录）且当前气泡仍有效时记录原词，加载失败/关闭前未完成不记；翻译是否成功不改变“查过”的事实。原词/语言精确去重，200条按查询顺序保留，无释义/来源句快照，不自动收藏。
- 接口：schema7只增lookup_history(lang,word,looked_up_at)，词长256、语言32、拒绝空白/控制字符；代次和写队列隔离清空/整库恢复与旧查询。历史详情复用WordBubble、当前全局释义语言设置和缺词翻译，不提供虚构来源/收藏。
- 备份：v1文件封装不变，schema7七表完整导出；schema6六表旧文件经预检补空历史，新库整库恢复会替换历史（含旧备份清空历史），确认页显式列数量。未知schema/漏表/历史超限/重复/坏字段拒绝。
- 验证：旧库迁移/旧表不变，重复/容量/Unicode/清空/失败队列及过时请求；历史UI搜索/空/错误/清空取消/重新查询/英英/缺词；阅读点击退出及位置回归；旧新备份和事务失败回滚；相关/全量测试、分析、三构建、四设备实际迁移对照。体验仍单独待用户反馈。
- 工程验证：最终全量239/239（含12项历史/9项备份）、analyze无问题、git diff --check通过。覆盖schema6→7旧六表保留、200条/精确去重/语言隔离/错误队列/清空与恢复旧代次、旧schema6及新schema7备份/坏记录/事务回滚、三尺寸历史入口/字面搜索/主释义/清空确认/查词与正文隔离、失败重试/窄屏大字号/未完成详情关闭。首轮修正测试异步等待；追加错误重试测试暴露refresh回调返回Future已修复，并将前序迁移测试的当前版本断言更新为7。
- 构建：真机release Xcode28.2s、模拟器16.4s、Android assembleDebug18.9s均通过，codesign --verify --deep --strict通过。Java native-access/SDK XML既有警告未阻断成功构建。
- 三模拟器已正常覆盖安装并启动，实际schema6→7，新增history为空；原3/1/4本书及内容/位置/样式/资源/settings/译文/生词/书签快照一致，Android仍6条译文。未卸载、清数据、test -d或向设备注入样本；破坏性清空/恢复仅在独立临时测试库验证。
- 真机待集中交付（用户已解除逐模块安装要求）：iPad UDID 00008142-000411691E20401C，devicectl显示available(paired)，读取appDataContainer时报CoreDevice4000 / connection reset by peer。本轮未取得新的真机安装前快照，也未安装；已通过异步问题请用户连线解锁。不可复用前轮fallback快照代替本轮基线。应用签名产物已备好，无代码变更时不必重构建。
- 待体验：书架更多→查词历史，先在正文查几个词，再检查列表/重复置顶/搜索/重新查询及全局英英偏好；点击气泡外只关闭、原阅读位置保持；清空先取消再确认，仅历史消失。备份恢复会替换历史，旧备份历史数量为0，仍需用户按实际需要确认，不用其设备做破坏性测试。安装与宿主测试不等价原生体验通过。
- 证据/恢复：history/{history,history_page}.dart、db/database.dart、reader.dart lookup、library.dart、backup两文件，契约docs/{history,backup,dictionaries}.md，test/history_test.dart。命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded`、`../scripts/flutterw analyze --no-pub`。日志/tmp/reading-history-{tests,full,analyze-final,ios-release,ios-simulator,android}.log；三模拟器/tmp/reading-{before,after}-history-sim-install.json。临时脚本/tmp/reading-check-history-data.py只读检查schema迁移/数据，不作为跨机器恢复依赖。
- Workflow status：计划 done（唯一PLAN已对齐结果和真机断点）；架构 done（独立有界历史、串行写入/代次、schema7迁移）；接口 done（history.md及备份旧新兼容/词典记录规则）；工程验证 done（239全量/分析/三构建/三模拟器实际迁移数据对照），iPad真机交付 pending（用户后续决定集中交付，不阻塞开发），原生体验 pending；Git checkpoint not needed（不暂存/提交/推送，前序修改保留）；handoff done（下述唯一下一步）。所有工程测试/构建/安装/启动命令已结束，无待续后台工程会话。


## 前一模块：未收录词翻译兜底（工程与四设备交付完成，体验待确认）

- 范围：dict/{dictionary,wiktionary}.dart明确null为确认未收录、异常不能降为miss；reader/{reader,bubble}.dart仅真实miss接入；抽取句子面板已有翻译内容供气泡复用，保留下载/缓存/失败重试/来源说明，不改schema/原生桥/语言设置。
- UX：未收录气泡自动尝试英译中，标注“词典未收录 · 机器翻译”；简档保持紧凑，展开可复制原词和查看说明，模型未下载时用户主动下载。另一词库有内容（包括只有ECDICT definition或空词条记录）时沿用词条，不自动翻译；词典异常维持错误提示。
- 验收：真实miss、两库/单库错误及单语言缺词隔离；下载显式、成功缓存、错误重试；关闭/换词/重排/旧异步不覆盖新气泡或正文位置；原句面板/默认英汉/英英展开回归；相关与全量测试、分析、三构建、可用设备保数据覆盖安装。原生舒适度单独待用户反馈。
- 实现完成：null契约/错误隔离、原气泡机器翻译、共享TranslationContent，保持句子面板顺序和复制。紧凑译文最多3行，展开保留原请求，复制原词；下载等待结束时已关闭/换源则不继续翻译，成功在途结果仍按既有缓存规则保留。
- 工程验证：专项9/9、原词典/句子回归30/30、全量227/227通过。专项使用测试翻译器，不代表新入口真实引擎质量验收。首轮测试修正了分页查找器、实际字体和初始保存等待，产品无需位置修复。分析初次2个测试代码提示已清理，最终analyze无问题；最终源码差异仅测试导入/括号整理，不改变全量测试所覆盖行为。git diff --check通过。
- 构建与交付：iPad真机release Xcode29.5s、模拟器18.2s、Android assembleDebug10.1s；codesign --verify --deep --strict通过。iPad真机与iPhone/iPad模拟器、Android均正常覆盖安装并启动；未卸载/清数据/test -d/注入。
- 数据对照：真机schema6不变、quick_check=ok；安装前后2书/18资源/1settings/18译文/1生词/0书签六表全部字段一致（18译文为本轮安装前已有，不沿用上轮15条基线）。三模拟器原3/1/4书及内容/位置/样式/资源/settings/译文/生词/书签快照一致，Android6译文。数据库结构/语言设置/原生桥不变。
- 待体验：遇到两库未收录词，应在原气泡显示标记明确的机器译文；点展开可看完整结果、复制原词与翻译说明，点击气泡外只关闭。已有词条仍按英汉/英英设置显示。首次缺模型仍由用户主动下载，机器结果可能不准确；测试替身和安装成功不能替代原生体验/翻译质量。iOS模拟器按既有能力提示不可用，不要求重新安装来解决平台限制。
- 最少恢复/证据：入口见Current Summary；专项命令（app/）`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/word_fallback_test.dart --reporter expanded`，全量去掉路径；`../scripts/flutterw analyze --no-pub`。临时日志/tmp/reading-fallback-{tests,regression,full,analyze-final,ios-release,ios-simulator,android}.log，模拟器/tmp/reading-{before,after}-fallback-sim-install.json，真机/tmp/reading-ipad-{before,after}-fallback.sqlite；临时文件不作为恢复前提。
- Workflow status：计划 done（唯一PLAN已对齐实际结果与下一模块）；架构 not needed（复用现有词典/翻译边界，无schema/原生接口变化）；接口 done（docs/dictionaries.md明确null/错误/兜底、docs/translation.md共享状态、README入口）；工程验证 done（9专项/30回归/227全量/分析/三构建/四设备数据对照），原生体验 pending（用户）；Git checkpoint not needed（不暂存/提交/推送，前序修改保留）；handoff done（结果/限制/恢复文件/唯一下一步齐全）。所有测试/构建/安装/启动命令均已结束，无待续工程会话。


## 前一模块：长按拖动选区（工程与四设备交付完成，体验待确认）

- 接入ReaderParagraph长按移动，源UTF-16范围/引擎词边界；PagedReader传可见源范围避免选到裁剪页外文字。拖动期间不请求翻译，松手复用SentenceSheet和CachedTranslator；旧无拖动句子/点词/点击退出/翻页保持。
- 相关入口reader/{paragraph,paged_reader,reader}.dart、translate/sentence_sheet.dart；不改schema、数据格式、语言配置或原生翻译桥。
- 专项8/8通过：实时高亮、左右与跨行、Unicode/组合符号、裁剪/双页中缝/图注/单元格/补充脚注、取消/字号重排、只翻译复制实际范围、无拖动句子行为与正文进度不变。随后移除逐帧整段盒子枚举（使用现有命中/裁剪检查）并加入Android/iOS平台变体；最终全量218/218通过；额度中断后仅清理2项冗余导入和1项测试括号提示，最终analyze无问题，三构建/四设备交付通过。


- 构建与交付：iPad真机release Xcode31.1s、模拟器18.3s、Android assembleDebug12.0s；codesign --verify --deep --strict通过。iPad真机及iPhone/iPad模拟器、Android正常覆盖安装并启动；没有卸载、清缓存、test -d或设备数据注入。
- 数据对照：真机schema6不变，安装前后2书/18资源/1settings/15译文/1生词/0书签六表全部字段一致，quick_check=ok；三模拟器原3/1/4书及内容/资源/位置/样式/settings/译文/生词/书签快照一致（Android6译文）。没有触发备份恢复或为了测试改写设备数据。
- 待体验：长按不松手→拖到同段另一词→松手，应翻译高亮的词组且能复制；反向拖、跨行、单/双页、图注/表格/脚注可体验；不拖动仍按旧整句处理。跨页/跨段、自动滚动和松手后的手柄未实现，不以本轮结果宣称这些能力。原生舒适度、边缘误触仍需用户反馈。
- 最少恢复：reader/{paragraph,paged_reader,reader}.dart、translate/sentence_sheet.dart、test/selection_test.dart；接口见docs/translation.md“拖动选区与短语”。专项命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/selection_test.dart --reporter expanded`；全量去掉路径。证据/tmp/reading-selection-{tests,full,analyze-final,ios-release,ios-simulator,android}.log、/tmp/reading-{before,after}-selection-sim-install.json、/tmp/reading-ipad-{before,after}-selection.sqlite；临时证据不作为跨机器恢复依赖。
- Workflow status：计划 done（唯一PLAN更新本轮/下一模块）；架构 not needed（复用段落、原翻译/缓存接口，无schema/依赖变化）；接口 done（docs/translation.md与README使用方式）；工程验证 done（8专项/218全量/最终分析/三构建/四设备数据对照），原生体验 pending（用户）；Git checkpoint not needed（不暂存/提交/推送，全部前序修改保留）；handoff done（边界/恢复入口/证据/下一步齐全）。本轮所有工程命令已结束，无待续构建或安装会话。

## 前一模块：备份与恢复（工程与四设备交付完成，体验待确认）

- 已确认：整库替换，无合并；恢复前文件校验、摘要与明确确认。包含六表全部字段与图片，保留UUID/位置/时间/语言/许可；不包含可重新下载词典与系统模型。
- 文件v1：20字节magic/版本/长度/CRC32头+UTF-8 JSON（图片base64），不压缩、不解包、不执行文件中SQL；最多64MB文件/32MB数据/500书/10000资源/50000记录/1000译文，限制JSON深度与结构。CRC只用于意外损坏检测，不是认证/加密。
- 路径：app/lib/backup/，library/library.dart入口，CachedTranslator.replaceCache隔离旧请求；复用现有drift事务和FilePicker，无新依赖/schema。
- 专项9/9通过：六表全字段往返与重开、EPUB2/3正文/补充/图片/链接、表格位置/图注与补充书签、旧JSON、空库/孤立生词、损坏/未知版本/资源缺失/重复/限额、真实SQL失败事务回滚、取消不改库、旧异步译文不污染；Android320/iPhone402/iPad1194界面的保存/取消/失败重试/预检摘要/替换/书架与设置刷新通过。上轮因额度导致自动审批未完成；本轮全量210/210已通过；最终analyze无问题（全量后仅移除一行未使用的测试导入）；三构建与四设备交付完成，真机安装/启动和数据对照已补齐。


- 构建/交付：真机release Xcode29.3s、模拟器17.8s、Android assembleDebug17.6s；codesign --verify --deep --strict通过。iPhone/iPad模拟器、Android正常覆盖安装与启动；schema6不变，原3/1/4本书的ID/内容/资源/整数与精确位置/样式/settings/译文/生词/书签快照一致（Android6译文）。没有卸载/清缓存/test -d/数据库注入，未在用户设备执行整库恢复。
- 真机交付：2026-10-07重新检查为connected，正常覆盖安装已验证签名的release产物并独立启动成功。安装前/启动后均检查无WAL/SHM，仅只读复制reading.sqlite；schema6不变，2书/18资源/1settings/15译文/1生词/0书签六表全部字段一致，quick_check=ok。没有卸载、清缓存、注入或执行整库恢复。此前连接阻塞已解除，无需重做已通过工程验证。
- 体验待确认：书架→更多→备份与恢复→保存备份；选择刚保存文件应看到正确数量摘要，取消应不改数据。需要实际恢复时由用户确认“替换并恢复”，随后检查书籍图片/位置/样式、生词及书签，不能把组件测试或安装成功当作该项已验收。首版容量限制与内存峰值见docs/backup.md。
- 证据/恢复：app/lib/backup/{backup,backup_page}.dart、test/backup_test.dart、docs/backup.md；library.dart入口与CachedTranslator.replaceCache；无新依赖/schema。日志/tmp/reading-backup-{tests,full,analyze-final,ios-release,ios-simulator,android}.log，三台快照/tmp/reading-{before,after}-backup-sim-install.json，真机快照/tmp/reading-ipad-{before,after}-backup.sqlite。专项命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/backup_test.dart --reporter expanded`；全量去掉路径。临时日志/快照不作为跨机器恢复依赖。
- Workflow status：计划 done（唯一PLAN记录实际交付/未完成项）；架构 done（固定版本单文件，事务恢复与旧译文隔离）；接口 done（docs/backup.md，README入口同步）；工程验证 done（9专项/210全量/最终分析/三构建/四设备数据对照），真机交付 done（安装与启动成功）、原生体验 pending；Git checkpoint not needed（不暂存/提交/推送，前序修改保留）；handoff done（入口/命令/证据/下一动作齐全）。测试、构建与安装命令均已结束，无待续后台工程会话。

## 前一模块：书内搜索（工程与交付完成，体验待确认）

- 搜索器独立于Flutter/数据库，不依赖EnglishLanguage或ASCII词边界；归一化大小写/连续空白时保持原始UTF-16位置映射，不跨源块/表格单元格拼接。文字匹配不代表新增学习语言支持。
- 已实现search/book_search.dart流式KMP源偏移映射、200字符单位查询/500结果/2000万扫描单位/10万片段限制与取消，search_page.dart输入/结果/无匹配/部分结果/失败重试；reader.dart复用reading-search+reading-link路由及独立高亮、目录/返回书架/真实backlink跨搜索层正确返回。窄屏滚动顶部控件统一44px宽，保留原按钮。
- 验证：专项9/9及全量201/201；全量后补空表格片段预算、巨大空白预览、部分无命中提示和搜索页退出沉浸态，最终专项9/9与analyze无问题。覆盖Unicode/空白/字面查询/大小写、结果与扫描上限、过时异步/取消/失败重试，Android320/iPhone402/iPad1194分页与320滚动正文/图注/宽表长单元格/脚注目标可见和高亮、返回结果查询保持、六业务表全字段不变、真实backlink/目录/返回书架。不将组件测试当作原生体验。


- 构建与交付：iPad真机release Xcode29.0s、模拟器17.7s、Android assembleDebug19.4s，codesign通过；四设备正常覆盖安装，无卸载/清缓存/设备test -d。三台模拟器启动成功；iPad自动启动遇Locked/CoreDevice10002，安装已成功，用户解锁手动打开即可，本轮无数据库迁移。
- 数据对照：真机schema6、2书/18资源/1settings/15译文/1生词/0书签六表全部字段完全一致，quick_check=ok；iPhone模拟器3书、iPad模拟器1书、Android4书/6译文的内容/资源/整数与精确位置/样式/settings/译文/生词/书签快照均一致。仅只读快照比较，未注入设备数据。
- 原生体验待验：阅读操作→书内搜索，输入当前书中的关键词或短语→点结果查看高亮；返回上一处应保留搜索内容与列表；回到原阅读处应恢复原位置。补验双页/滚动、键盘避让、搜索目标中的查词和原阅读设置。真实大书/低内存性能仍待专项体验，不能以宿主测试或安装成功代替。
- 恢复与证据：入口app/lib/search/{book_search,search_page}.dart、reader/reader.dart、test/book_search_test.dart；接口docs/search.md、docs/epub-links.md。专项命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/book_search_test.dart --reporter expanded`，全量去掉路径。日志/tmp/reading-search-{tests-final,full,analyze-final,ios-release,ios-simulator,android}.log；设备只读快照/tmp/reading-{before,after}-search-sim-install.json与/tmp/reading-ipad-{before,after}-search.sqlite。快照仅为本机临时证据，不是用户备份功能。
- Workflow status：计划 done（唯一PLAN记录交付和下一模块）；架构 done（独立只读搜索器，复用源坐标与临时导航，无schema/依赖变化）；接口 done（docs/search.md与epub-links.md）；工程验证 done（9专项/201全量/最终9专项/分析/三构建/四设备数据对照），原生体验 pending（用户，真机需解锁打开）；Git checkpoint not needed（用户要求不暂存/提交/推送，全部前序修改保留）；handoff done（恢复入口/证据/限制/下一动作齐全）。所有工程命令已结束，无待续测试或构建。

## 前一模块：书签基础闭环（工程与交付完成，体验待确认）

- 存储schema6新增bookmarks：UUID/book_id/规范PageAnchor v1 JSON/位置文字摘要/created_at/updated_at；同书同锚点幂等，不保存页码。书籍删除同事务清理，生词快照保留原规则。坏/失效锚点拒绝。
- 入口为阅读操作面板“书签”，滚动手机顶部同名按钮；书签面板支持添加当前位置、按时间列表、确认删除、空/错误重试。图注/表格行和补充文档命名空间使用原锚点格式。
- 跳转使用现有reading-link路由并传递完整锚点，保留阅读设置/目录/逐层返回/全部返回和16层限制；不写正文进度。
- 验证：bookmark_test.dart专项8/8，schema5文件实际升级/旧五表保留/并发去重/改名与删书隔离/关开，坏位置拒绝；Android320/iPhone402/iPad1194分页和iPhone滚动覆盖正文/补充脚注/长图注/表格续行可见、添加/删除取消与确认、原阅读进度保留、双页左页起点/字号/旋转/嵌套/重开，真实INSERT/DELETE/读取故障重试。全量192/192、analyze无问题、diff检查通过。旧迁移测试只更新最终schema预期5→6。本模块构建/保数据交付已完成；未在本轮展开全文搜索/备份/同步。

- 构建：iPad真机release Xcode27.9s、模拟器17.0s、Android assembleDebug10.6s，codesign通过。iPad覆盖安装成功，初次自动启动被Locked/CoreDevice10002拒绝；用户随后解锁打开，启动与迁移阻塞已解除。三台模拟器安装/启动/实际schema5→6完成，新增bookmarks均0，原3/1/4书及其内容/资源/整数和精确位置/样式/settings/译文/生词快照完全一致（Android6条译文）。真机首次启动后只读确认schema5→6、bookmarks表存在且0条，2书/18资源/1settings/15译文/1生词全部字段与升级前一致（含正文/阅读位置/样式/时间）；PRAGMA quick_check=ok。没有注入样本或修改设备数据库，用户“已打开”仅确认启动，不当作书签交互验收。
- 恢复入口：app/lib/bookmarks/{bookmark,bookmark_sheet}.dart、db/database.dart、reader/reader.dart的bookmarkPosition/bookmarks/openLink.linkAnchor，test/bookmark_test.dart；契约docs/bookmarks.md及docs/epub-links.md。测试命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/bookmark_test.dart --reporter expanded`；全量去掉路径。分析/三构建沿既有命令，无需因文档收尾重复。

- Workflow status：计划 done（唯一PLAN与下一步一致）；架构 done（独立bookmarks表，复用位置与临时路由）；接口 done（docs/bookmarks.md及epub-links.md）；工程验证 done（8专项/192全量/分析/三构建/四设备实际迁移保数据），真机启动/迁移 done（用户打开后只读确认），体验 pending（用户）；Git checkpoint not needed（未暂存/提交/推送，前序改动保留）；handoff done（状态与恢复命令齐全）。所有测试/构建/安装/启动命令已结束，无待续工程会话。
- 设备证据：/tmp/reading-{before,after}-bookmarks-sim-install.json、/tmp/reading-ipad-before-bookmarks.sqlite及/tmp/reading-ipad-opened-bookmarks.sqlite为升级前/首次启动后临时只读快照（after-bookmarks是此前未启动的schema5中间快照）；日志/tmp/reading-bookmarks-{tests,full,analyze,ios-release,ios-simulator,android}.log。真机UDID沿下方；`xcrun devicectl device info files --device <UDID> --domain-type appDataContainer --domain-identifier dev.reading.readingApp --subdirectory 'Library/Application Support'`先检查WAL，再copy from reading.sqlite和存在的WAL/SHM；仅比较，不注入/卸载/清缓存。用户阅读可能改变进度/时间，发现差异须如实记录。

## 前一模块：生词CSV导出（工程与交付完成，iPad体验通过）

- 入口vocab/vocabulary_page.dart；纯CSV编码独立于系统保存。UTF-8 BOM、CRLF记录分隔、双引号转义；可能被表格软件解释为公式的字段加单引号，原数据库不改。固定字段带来源/许可与稳定ID/位置，日期UTC ISO8601。
- 导出选择当前搜索/书籍筛选列表或全部，沿用当前时间排序；空列表/加载失败禁用，保存中防重复；取消不报成功，失败可重试。系统目标由用户选择，不自动分享/上传。
- 验证：vocabulary_export_test.dart新增6/6（编码往返、公式文本化；Android320/iPhone402/iPad1194布局、筛选/排序/全部、取消/失败/重试/重复点击/销毁安全、五业务表全字段不变；空/错误禁用）；全量184/184、analyze无问题、git diff --check通过。CSV导入、同步、备份不在本轮。

- 构建：iOS真机release Xcode28.3s、模拟器17.6s、Android assembleDebug17.9s，codesign校验通过。正常覆盖安装四设备成功；三台模拟器启动成功，真机因Locked/CoreDevice10002拒绝启动，解锁后手动打开即可，不需重装/改签名。
- 数据对照：真机schema5、2书/18资源/1settings/15译文/0生词所有字段一致；iPhone模拟器3书、iPad模拟器1书、Android4书/6译文的内容/资源/位置/样式/settings/缓存/生词相同（三台生词均0）。非空导出由专项测试验证，未注入设备样本；无卸载、清缓存、test -d。用户随后确认已使用iPad检查并要求下一项，记录该设备CSV体验通过；其他平台的系统保存未获用户确认。
- 体验：先收藏若干生词（含英汉/英英、多行释义）→书架更多→生词本→右上角导出→当前列表/全部→系统选择保存位置；打开CSV检查中文、多行内容和来源列，再取消一次确认无成功提示、原收藏仍在。普通阅读与查词UI不变。
- Workflow status：计划 done（唯一canonical plan已更新）；架构 done（纯VocabExporter编码接口+现有FilePicker，无新依赖/权限/schema）；接口 done（docs/vocabulary.md固定字段、编码/防护/保存语义）；工程验证 done（6专项/184全量/分析/三构建/四设备数据对照），原生体验 iPad done（用户已检查）、其他平台 pending；Git checkpoint not needed（不暂存/提交/推送，前序修改保留）；handoff done（结果/边界/命令/下一步已记录）。所有工程命令已结束，模拟器留运行，无待续后台构建。
- 文件：app/lib/vocab/export.dart、vocabulary_page.dart、app/test/vocabulary_export_test.dart、docs/vocabulary.md、本计划。复现（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/vocabulary_export_test.dart --reporter expanded`；全量去掉路径；`../scripts/flutterw analyze --no-pub`；三构建/安装沿既有命令。临时日志/tmp/reading-csv-{tests,full,analyze,ios-release,ios-simulator,android}.log；快照/tmp/reading-{before,after}-csv-sim-install.json、/tmp/reading-ipad-{before,after}-csv.sqlite不作恢复前提。

## 前一模块：生词原句回跳（工程与交付完成，体验待确认）

- 入口 vocab/vocabulary_page.dart 列表原句/查看原句按钮及详情。先读现有书籍，source.dart严格核对v1位置、正文/补充文档、块/UTF-16偏移/cell、原词及原句；失败保留收藏，不默默夹取到其他位置。
- ReaderPage.source是独立临时根路由，负责亮屏生命周期与设置持久化，但不会保存正文进度；其嵌套链接仍受16层限制。返回主入口为返回生词本，嵌套返回原句。目录浏览也使用临时正文链接页。分页图注使用caption锚点，表格使用tableRow+行号并显露目标列/长单元格偏移；不更改PageAnchor或生词JSON格式。
- 新增vocabulary_source_test.dart专项19/19：来源解析拒绝失效/坏数据；Android分页、iPhone分页、iPad双页、iPhone滚动各覆盖正文/补充脚注/图注/宽表长单元格，断言原词在屏内及关闭/生命周期后旧books全字段不变；嵌套链接/设置同步/目录临时浏览/返回生词本，快速点击只打开一次；删书/失效提示保留收藏。全量178/178、analyze无问题、git diff --check通过。CSV、同步、重新导入书的自动重绑定不在本轮。
- 构建：iOS真机release Xcode27.7s、模拟器17.1s、Android assembleDebug10.6s，codesign校验通过。四设备正常覆盖安装成功；三台模拟器启动成功，真机自动启动被锁屏拒绝（CoreDevice10002 / Locked），安装本身成功，解锁后手动打开即可。没有卸载、清缓存、数据库注入或test -d。
- 安装前后只读对照：真机schema5不变，2本书/18项资源/1项settings/15条translations/0条vocabulary全部字段一致；iPhone模拟器3本、iPad模拟器1本、Android4本，内容/资源/样式/整数与精确位置/settings/译文缓存/生词记录相同（Android6条译文，三台生词均0条）。非空生词定位/保留由专项测试验证，不伪称设备已有人工作品验收。临时证据/tmp/reading-{before,after}-source-sim-install.json、/tmp/reading-ipad-{before,after}-source.sqlite；日志/tmp/reading-vocabulary-source-{tests,full}.log和/tmp/reading-source-{ios-release,ios-simulator,android}.log不是恢复前提。
- Workflow status：计划 done（本摘要/当前模块与唯一下一步）；架构 done（复用临时阅读路由，来源严格验证，不改schema5或位置格式）；接口 done（docs/vocabulary.md、docs/epub-links.md）；工程验证 done（19专项/178全量/分析/三构建/四设备数据对照），原生体验 pending（用户）；Git checkpoint not needed（不暂存/提交/推送，保留全部前序修改）；handoff done（入口、证据、边界与下一步齐全）。测试/构建/安装命令均已结束，无待续后台工程任务。
- 复现命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/vocabulary_source_test.dart --reporter expanded`；全量去掉测试路径；`../scripts/flutterw analyze --no-pub`；构建与覆盖安装沿既有命令。体验入口：完整释义卡收藏→书架更多→生词本→点击原句或“在书中查看原句”，检查来源可见、原设置可用、返回列表筛选保留、原书进度不被临时查看覆盖。

## 前一模块：生词本基础闭环（工程与交付完成，体验待确认）

- 存储：schema5新增独立表；VocabularyDraft/记录与Repository负责快照保存/去重/查询/删除。位置为源BookPosition与可选表格cell，不保存临时页码。英汉默认只存ECDICT中文释义，英英选择存Wiktionary释义与来源/许可，不冒充句子翻译。
- UI：仅完整卡片添加星标，未收录/加载中不提供收藏；按钮显示保存中/已加入/失败可重试。书架更多→生词本显示最近收藏、原句、书名日期、来源；支持字词搜索/书名筛选/时间排序与删除确认、空/错误状态。
- 验收：旧库迁移保数据、关开后记录存在、重复收藏幂等、不同语言/上下文隔离、删除只影响目标生词；三平台完整卡片可存/简洁不增控件，表格与脚注原句正确，列表筛选/搜索/删除；分析/平台构建/正常覆盖安装。后续再做原句跳转与CSV。

- 新增 app/lib/vocab/{vocabulary,save_button,vocabulary_page}.dart 与 test/vocabulary_test.dart；db/database.dart迁移到5，reader/bubble.dart及reader.dart接入仅完整卡片星标，library.dart增加入口；docs/vocabulary.md记录稳定契约。
- 验证：专项8/8覆盖真实schema4文件迁移、旧四表逐字段保留、并发去重/多语言与上下文隔离、删书保留/删除隔离、关开重载、正文/脚注/表格/图注原句与位置，数据库INSERT/SELECT/DELETE实际故障与恢复重试；Android320/iPhone402/iPad1194收藏/切换语言，手机和平板书架入口/搜索/筛选/排序/详情/删除确认。全量159/159通过；旧schema3翻译测试仅更新最终schema预期为5，保留全部旧数据断言。analyze无问题、git diff --check通过。

- 构建：iOS真机release Xcode31.0s、模拟器17.7s、Android assembleDebug15.1s，签名校验通过；/tmp/reading-vocabulary-{tests,full,ios-release,ios-simulator,android}.log仅作临时证据。iPad第一次安装因断线CoreDevice4000失败，用户重连后正常覆盖安装与启动成功，无签名/应用数据改动。
- 当前交付：iPhone/iPad模拟器与Android均正常覆盖安装并启动，schema实际4→5；其原有3/1/4本书、图片、位置、样式、设置和译文缓存对照全部一致（Android6条译文）。没有卸载/清缓存/数据库注入/test -d。真机安装与启动成功，schema4→5，旧表全字段一致：2本书（正文/位置/样式/时间）、18项资源、1项settings、15条translations；新vocabulary表0行，没有注入样本。临时对照 /tmp/reading-{before,after}-vocabulary-sim-install.json 与 /tmp/reading-ipad-{before,after}-vocabulary.sqlite不是恢复前提。

- Workflow status：计划 done（本摘要/唯一当前模块与后续粗计划）；架构 done（独立生词快照表，复用drift/Riverpod和原查词路径，不添加额外服务架构）；接口 done（docs/vocabulary.md及词典契约）；工程验证 done（8专项/159全量/分析/三构建/四设备实际迁移与旧数据对照），原生体验 pending（用户）；Git checkpoint not needed（不暂存/提交/推送，保留前序全部未提交修改）；handoff done（文件/契约/命令/限制/下一步齐全）。所有构建/测试/安装/启动命令已结束，无待续后台工程任务，应用留在设备供体验。
- 复现命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/vocabulary_test.dart --reporter expanded`；全量去掉测试路径；`../scripts/flutterw analyze --no-pub`；`../scripts/flutterw build ios --release --no-pub` / `build ios --simulator --debug --no-pub` / `build apk --debug --no-pub`。升级后数据核对允许schema4→5，仅比较既有表；正常安装，不用旧二进制覆盖schema5数据库。

## 前一补修：跳转后保留完整阅读操作（工程与安装完成，体验待确认）

- 入口 reader.dart readingActions/settings/contents/leave；不改解析、存储格式、正文布局及原设置组件。返回功能是额外入口。
- 跳转页设置通过回调同步全部父阅读页，由正文统一持久化；单书/全局选择继承当前值。进度条只操作当前文档；目录明确选择正文章节会结束临时链接路由再定位正文；返回书架沿正文保存队列退出。
- 验证：新增 linked controls 三平台测试（Android320、iPhone402、iPad1194宽），覆盖原控件/设置持久化与嵌套同步/临时进度隔离/逐层及全部返回/目录正文章节定位/返回书架；滚动EPUB2/3测试追加设置、目录与滑条可见检查，以及单书/全局范围切换不改变脚注滚动位置。相关30/30、全量151/151、analyze无问题。最终构建：iOS真机release Xcode27.1s、模拟器17.8s、Android assembleDebug10.1s，codesign校验通过；临时日志 /tmp/reading-link-controls-{tests,full,ios-release,ios-simulator,android}.log 不作为恢复前提。


- 四设备正常覆盖安装完成；本轮安装前后数据一致：真机2本书/18项资源/1项settings/15条译文（全字段含位置）；iPhone模拟器3本、iPad模拟器1本、Android4本/6条译文（内容/资源/样式/整数和精确位置/设置/缓存均相同）。未卸载、清缓存、注入或test -d。真机 devicectl 独立启动成功。所有测试/构建/安装会话已结束，原有模拟器保持运行。临时对照 /tmp/reading-{before,after}-link-controls-sim-install.json 与 /tmp/reading-ipad-{before,after}-link-controls.sqlite。
- 变更文件：app/lib/reader/reader.dart、app/test/paged_reader_test.dart、app/test/reader_links_test.dart、docs/epub-links.md、本计划。格式/静态检查通过；本模块不改schema、内容JSON、原ReaderSettings组件和分页布局。测试命令（app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/paged_reader_test.dart test/reader_links_test.dart --reporter expanded`；全量去掉测试路径；构建/安装命令沿下方设备上下文。
- Workflow status：计划 done（唯一当前目标/下一步已更新）；架构 not needed（复用原设置/导航/持久化）；接口 done（docs/epub-links.md 描述跳转页控件、设置同步及目录语义）；工程验证 done（30专项/151全量/分析/三构建/四设备数据对照），体验 pending（用户）；Git checkpoint not needed（不暂存/提交/推送，全部前序修改保留）；handoff done（当前结果、路径、恢复命令、唯一下一步齐全）。

## 前一模块：词典管理基础页（工程已完成，体验待确认）

- 复用书架更多菜单和既有页面主题，iPhone/iPad/Android共用。展示本地已就绪、内置待准备、暂不可用、状态未能读取；两库独立检测，刷新可重试。
- 数据路径：两份 asset manifest → 固定哈希命名的本地词库 → 只读大小/schema/字段检查。包大小来自 manifest（英英为压缩包）；副本大小为实际当前文件。未知信息不写0或伪装可用，不读取巨大词包来生成摘要。
- 保留现有词典加载与查询接口，不写业务数据、不自动准备；记录既有词典来源版本与许可证，不发网络请求。书架移除原来的 ref.watch(dictionaryProvider) 预加载，首次点词沿现有接口准备；刷新立即失败的 Future 预先挂错误监听，仍由页面显示失败/重试。
- 当前验证：新专项 6/6（缺失/损坏/schema/异常隔离、只读字节不变、仅 JSON 资产读取、320 手机与1194平板/1.5倍文字/浅深色、刷新失败重试、业务数据不变/不初始化查词）；全量148/148，analyze无问题，git diff --check通过。真实 ECDICT schema 与两库 manifest 已核对。最终构建：iOS真机release Xcode28.4s、模拟器17.2s、Android assembleDebug16.4s；codesign --verify --deep --strict通过（需在可访问系统信任链的环境执行，沙箱内曾报CSSMERR_TP_NOT_TRUSTED，正常权限复核通过）。临时日志 /tmp/reading-dictionary-{management-tests,ios-release,ios-simulator,android}.log 不作为恢复前提。

- 交付：四设备正常覆盖安装成功。真机安装前后全字段只读对照一致：2本书（含正文/阅读位置/样式）、18项资源、1项settings、15条译文。iPad启动请求因锁屏被拒绝（Locked / CoreDevice10002）；新包安装成功，用户解锁后手动打开即可，不重装/改签名。三台模拟器对照：Android（4本书/6条译文）与iPad模拟器（1本书）全部相同；iPhone模拟器3本书的正文/资源/样式/settings/缓存一致，但脚注EPUB2样本的position 7→9，location null→block9/offset0精确锚点。安装间隔旧应用可运行，现有生命周期会保存位置，但未独立确定此次差异原因，不能声称该设备位置逐字不变，也不回写旧进度。只读快照 /tmp/reading-{before,after}-dictionary-management-sim-install.json 及 /tmp/reading-ipad-{before,after}-dictionary-management.sqlite 为辅助证据。没有卸载、注入数据库、清缓存或test -d。
- Workflow status：计划 done（本摘要/当前模块/后续粗计划）；架构 not needed（独立只读检查，查询与存储接口不变）；接口 done（docs/dictionaries.md）；工程验证 done（6专项/148全量/分析/三构建），原生体验 pending（用户确认）；Git checkpoint not needed（用户要求不暂存/提交/推送，保留全部前序修改）；handoff done（新文件、真实结果、风险和唯一下一步已记录）。
- 复现命令（在app/）：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/dictionary_management_test.dart --reporter expanded`；全量去掉测试路径；`../scripts/flutterw analyze --no-pub`；`../scripts/flutterw build ios --release --no-pub` / `build ios --simulator --debug --no-pub` / `build apk --debug --no-pub`。正常覆盖安装命令和设备ID沿用下方上下文，切勿test -d或卸载用户已有设备。
- 本轮新文件：app/lib/dict/catalog.dart、management_page.dart、app/test/dictionary_management_test.dart；集成改动：core/providers.dart、library/library.dart；契约：docs/dictionaries.md。不涉及schema/内容JSON/ReaderStyle变更。当前新页面未获用户验收，前轮验收不能替代。全部测试/构建/安装命令均已结束；Android Reader_Phone 模拟器进程保持运行供体验（本轮启动，无待完成工程命令）。Git暂存仍为空；本轮检测到额外未跟踪的 app/android/gradle/gradle-daemon-jvm.properties（标注updateDaemonJvm生成），不属于页面源码，保留未删除/未暂存。

以下模块保留当时工程证据；其中历史“体验pending”及旧设备状态以顶部最新验收范围为准，不重新打开已确认事项。

## 已完成模块：跨平台章节另起页（用户验收通过）

- 用户确认：下一物理页即可，双页左右均可；iPhone、iPad、Android 共用规则，不增加平台专属开关或强制左页。
- 实现入口：book.dart 的派生 chapterStarts 使用现有 contents（显式目录优先，缺目录用 heading），过滤越界并去重；book_pagination.dart 与 pagination.dart 在正文块进入章节前结束当前非空页。两套算法保持一致；补充 document 分页不使用正文目录，无空页注入。所有目录层级均视为阅读器可导航章节；有目录的普通非目录小标题保持连续，无目录旧 EPUB 仅有 heading、无法进一步区分标题级别，沿用当前目录回退语义。
- 位置/兼容：不修改内容 JSON 或 schema，不增删源块，PageAnchor 的正文块/UTF-16 偏移、图注/表格行照旧；旧已导入书重新排版即生效。滚动模式没有分页，不额外塞入整屏空白。完成条件：短章/重复目录/首章无空页、媒体起章、旧 JSON、正文/补充隔离、同步异步一致；iOS/Android 单页及 iPad 双页起章、重排/重开与脚注返回验证通过后交付。
- 验证：新增 7 项章节测试（iOS/Android 目录/旧 JSON/异步/重排两项，TXT/补充隔离一项，媒体一项，Android/iPhone/iPad 实际 reader 起页/旋转/重开三项）；旧间距测试明确区分非目录标题，UTF-8/GBK 导入测试改为翻至第二章后检查正文。导入专项 10/10；最终全量 **142/142**，analyze 无问题，git diff --check 通过。真机 release Xcode **28.1s**、模拟器 **18.0s**、Android assembleDebug **9.6s**，codesign 校验通过。历史 135 项结论不代替本轮。
- 安装/数据：iPad Pro 13-inch M5 真机、iPhone 18 Pro 模拟器、iPad Pro 11-inch M5 模拟器、Android emulator-5554 全部正常覆盖安装成功。安装前后只读逐项一致：模拟器分别 3/1/4 本书（正文/资源/样式/整数及精确位置/settings/缓存），Android 6 条译文；真机 2 本书、18 项资源、1 项 settings、14 条译文所有字段相同。无卸载/注入/清缓存/test -d。临时证据 /tmp/reading-{before,after}-chapter-sim-install.json 与 /tmp/reading-ipad-{before,after}-chapter-fix.sqlite，不作为接手依赖。iPad 自动启动被锁屏拒绝（CoreDevice 10002 / FBSOpenApplicationErrorDomain 7，Locked），安装本身成功；用户解锁后手动打开即可继续体验，不据此重装/改签名。不推断用户体验通过。所有构建/安装/启动命令已结束，无后台工具任务。
- Workflow status：计划 done（本模块是唯一当前步骤）；架构 done（共用派生章节边界，存储不变）；接口 done（docs/epub-links.md）；验证 done（142 全量/分析/三构建/四设备安装和数据对照），体验 pending（用户确认）；Git checkpoint not needed（不暂存/提交/推送，保留全部历史修改）；handoff done（当前结果、入口、规则、风险、下一步明确）。

## 已完成补修：双页中缝点击关闭（用户验收通过）

- 文件：`app/lib/reader/paged_reader.dart` 在 PageView 外加空白点击手势，调用既有 onBlank；不新增模态遮挡、不修改 44px 中缝或源位置。测试 `app/test/paged_reader_test.dart` 的 `outside word tap dismisses without lookup at Size(1194.0, 834.0)` 增加中缝中心/两侧边缘；修复前稳定失败（/tmp/reading-gutter-before.log），修复后 `paged_reader_test.dart` + `reader_gloss_language_test.dart` **17/17**（/tmp/reading-gutter-after.log），保留单/双页滑动、查词、展开及位置回归。
- 最终验证：17/17 相关回归、analyze 无问题、git diff --check 通过；真机 release Xcode 29.6s、模拟器 17.2s、Android assembleDebug 10.1s；codesign 校验通过。此前 135/135 全量是上一关闭规则版本的证据，本轮局部补修未重复全量。
- 交付：iPad 正常覆盖安装及 devicectl 独立启动均成功。安装前后 SQLite 对照：2 本书 ID/标题/正文/样式、18 项图片、1 项 settings、14 条译文一致；一本书在两次快照间 position 186→868、精确锚点及阅读时间同步改变（该间隔包含用户继续操作/等待），原因未独立核实，不冒称位置逐字不变，不回写旧进度。临时只读快照 `/tmp/reading-ipad-before-gutter-fix.sqlite` / `after` 不是恢复前提。没有卸载、注入或清缓存；模拟器/Android 本轮仅构建。
- Workflow status：计划 done（当前摘要/本节）；架构 not needed（局部点击补漏）；接口 done（沿用 onBlank）；验证 done（修复前复现、修复后 17 项、分析/构建/安装），体验 pending；Git checkpoint not needed（用户要求不暂存/提交/推送）；handoff done（入口、证据、下一步已记录）。不更新历史 HANDOFF 或创建新计划。所有构建/安装会话已结束。

## 前一模块：点词释义外部点击只关闭（用户验收通过）

- 用户要求：已打开单词释义时，点另一个词只是退出，回到无气泡/无选词状态；再次主动点词才查新词。
- 实现：reader.dart 的 lookup/openLink 遇到 selected 时 dismiss 并 return，阻止同一点击查询或跳转；底层常驻透明手势区域补足顶部空白，避免增删背景节点导致滚动组件重建。dismiss 的 generation 使未返回的旧请求不重新弹出卡片。没有遮挡全页的模态层，滑动/滚动/长按保持原行为，气泡内部交互不改。
- 定向验证 26/26：新增单页/双页两项，断言第二个词不会进入词典调用、同词/顶部空白关闭、关闭不改锚点、不打开工具栏、下次点击恢复查询、滑动仍翻页；扩展滚动与语言/脚注回归，验证先关闭再跳转、展开/语言切换及返回位置保持。全量 135/135（/tmp/reading-gloss-dismiss-full.log 为临时日志）；analyze 无问题、git diff --check 通过。真机 release Xcode 28.2s、模拟器 17.2s、Android assembleDebug 9.8s，签名校验通过。

- 真机交付：iPad 正常覆盖安装并 `devicectl device process launch` 成功。安装前后 SQLite 全字段有序对照：2 本书（含内容/整数与精确位置/样式）、18 项 book_assets、1 项 settings、14 条 translations 全部一致。没有卸载/数据注入/清缓存。临时只读快照 `/tmp/reading-ipad-before-dismiss-fix.sqlite` 与 `/tmp/reading-ipad-after-dismiss-fix.sqlite` 不作为恢复依赖。本轮模拟器与 Android 只构建、未重装；iPad 上运行的是最新修复版。
- Workflow status：计划 done（本摘要/本节是唯一当前步骤）；架构 not needed（局部点击分派）；接口 done（docs/dictionaries.md 更新交互契约）；验证 done（26 专项/135 全量、分析/构建/安装及数据核对），体验 pending（用户真机）；Git checkpoint not needed（遵循不暂存/提交/推送，保留既有修改）；handoff done（入口、证据、待验与下一步已记录）。所有工具构建/安装会话结束，Reading 留在 iPad 供用户验收。

## 前一模块：Apple 翻译重复弹窗修复（iPad 核心体验用户验收通过）

- 最新用户反馈：旧版原生大弹窗出现后会消失，译文成功显示在 Flutter 句子面板。由此确认该 iPad 真实句子翻译已运行成功；未确认断网新句或本次模型下载，不扩大验收范围。
- 修复：`ReadingTranslation.swift` 移除自建 `.formSheet` / ProgressView / 取消按钮。iOS 26+ 已安装模型直接使用 `TranslationSession(installedSource:target:)`，取消/超时调用 session.cancel；模型准备及 iOS 18–25 使用透明、非交互、辅助功能隐藏的 child UIHostingController。SwiftUI session 留在 translationTask 内；完成后异步拆除宿主，必要时只 dismiss 其系统许可，保持 request ID / busy / 晚回调隔离。Flutter 句子面板、缓存键、数据库、阅读布局不改；契约同步 docs/translation.md。iOS 18 分支运行和系统模型下载许可尚无真机验证。
- 本轮验证：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/translation_test.dart test/translation_cache_test.dart --reporter expanded` **12/12**；analyze 无问题；真机 release Xcode **10.2s**，模拟器 **16.6s**，Android assembleDebug **2.6s**。`codesign --verify --deep --strict` 通过。未把宿主测试当作 SwiftUI 原生生命周期验收，也未重复无关全量测试。
- 覆盖安装：`devicectl device install app` 成功。前后只读导出 SQLite：2 本书的 ID/标题/正文/样式、18 项图片资源、1 项 settings、12 条译文完全一致；其中一本书 position 151→161、location/阅读时间也变更，快照间用户可继续阅读，原因未独立确认，不能声称位置逐字不变，不回写旧快照。另一本书所有字段相同。临时快照 `/tmp/reading-ipad-before-overlay-fix.sqlite` / `after` 仅辅助证据，不作为跨机器恢复前提。
- 历史启动错误（现已解除）：安装后 `device process launch` 返回 CoreDevice 10002 / FBSOpenApplicationErrorDomain 3（invalid signature / inadequate entitlements / profile not explicitly trusted）。本地产物为 iPhoneOS arm64、Team 与 bundle entitlement 匹配；profile 包含此 iPad，有效至 2026-10-12，codesign 校验通过。已询问用户连回 Wi-Fi 并手动打开，后来已只读确认新安装路径 E1A59712… 的 Runner 进程运行（PID 922），启动阻塞解除；当时原因未独立确定，不据此更改证书、bundle ID 或卸载。该错误仅针对修复版此次启动，上一版真实翻译已获确认。

- 设备与签名（2026-10-05）：iPad Pro 13-inch（M5），iPadOS 26.6.2，UDID `00008142-000411691E20401C`；wired / paired，Developer Mode Enabled；Xcode 27.0（27A266a）。用户已完成账号/签名配置，`security find-identity -v -p codesigning` 确认 1 个有效 Apple Development identity，Runner 三个配置使用 Automatic / Team `ZBL5LT4AAN`，bundle ID 保持 `dev.reading.readingApp`。Xcode 同时将工程 objectVersion 改为 60；保留用户修改，未触碰证书或账号凭据。
- 前一安装轮构建证据：先前未签名 debug 真机编译 15.6s 通过；本次在 `app/` 执行 `../scripts/flutterw build ios --release --no-pub` 退出 0，Xcode 32.9s，产物 `app/build/ios/iphoneos/Runner.app`（265.8 MB，已替换之前 unsigned 产物）；`codesign --verify --deep --strict` 通过。release 可脱离 Flutter/Xcode 调试器运行。当时无应用逻辑改动；133/133 等历史证据仅对应各自范围，本次桥接修复另见上方验证。
- 前一安装轮安装/启动：先以 `devicectl device info apps --bundle-id dev.reading.readingApp --include-all-apps` 确认真机已有 0.2.0 (1)；只读容器检查 Documents 为空、无 sqlite。随后 `devicectl device install app --device <UDID> app/build/ios/iphoneos/Runner.app` 正常覆盖安装成功，`device process launch --device <UDID> dev.reading.readingApp` 成功。启动后只读确认 `Library/Application Support/reading.sqlite` 已生成、Runner 进程存在；这是启动证据，不是 UI 或翻译验收。没有卸载、数据库注入、清缓存或 test -d，三台模拟器本轮未重装。
- 恢复入口：`docs/translation.md`、`app/ios/Runner/ReadingTranslation.swift`、`app/lib/translate/sentence_sheet.dart` 与 `translator.dart`；签名在 `app/ios/Runner.xcodeproj/project.pbxproj`。如后续再次安装且书架已有内容，应重新读取数据库/位置作前后核对；不得沿用本次安装前“空数据库”结论。设备/签名阻塞已解除。
- 真机验收顺序：①联网长按英文句子，若提示缺模型，点击“下载语言模型并翻译”并完成系统许可；模型已安装则记录复用，不冒称本次验证下载。②关闭 Wi-Fi 和蜂窝网络，翻译从未请求过的新句，确认有合理中文，排除成功缓存伪装离线能力。③继续翻译另一新句，关闭/重开面板并重开 App，确认不持续 busy、缓存可用、正文位置不变。④按条件验证取消/重试；未出现系统下载或失败状态时如实记未覆盖，不删除共享模型制造条件。
- 可用原创样本：通过现有粘贴导入入口建临时书，三句分段：`The gardener left a blue umbrella beside the wooden gate.` / `Although the train arrived late, we reached the museum before noon.` / `Please put the unopened letter under the small brass lamp.` 第一段用于联网，第二、三段在断网后首次请求；若已经翻译过则换新句，勿清空用户缓存。
- 完成条件：至少一台符合系统要求的 Apple 真机实测通过；只记录该设备结果，不代替另一机型覆盖。前一版安装/独立启动/成功译文已确认；本次修复版已确认进程运行，无重复弹窗体验、模型下载及断网新句仍待用户验收；没有可用 iPhone。所有构建/安装命令已结束，无后台工具会话。
- Workflow status：计划 done（本节及摘要）；架构 done（沿用桥接，替换模态宿主）；接口 done（外部 channel/缓存不变，docs/translation.md 更新）；验证 pending（测试/构建/安装 done，新版启动 done、体验 pending）；Git checkpoint not needed（用户禁止自动暂存/提交/推送，暂存仍空）；handoff done（唯一下一步、入口、证据及阻塞已记录）。

## 已完成模块：独立脚注页解析与存储

- 只载入 manifest 中被文字链接引用的本地 XHTML/HTML（含普通 EPUB 2 链接），复用既有块、图片/表格及安全解压逻辑；不执行脚本，不下载资源。
- 补充页独立存储，正文 targets/目录/阅读进度不受补充块影响；旧书不重解析、不升级 schema。
- 去重广度遍历，自引用/别名/循环不重复加载；限额定义及拒绝行为见现有契约文档。
- 数据与存储完成条件、全量测试/分析及两端 debug 构建均已通过；该阶段未接 UI，现由下方交互模块接入。

本轮验证命令（在 `app/`，恢复时无需无条件重复）：

```sh
READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/reader_links_test.dart test/reader_interaction_test.dart --reporter expanded
READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded
../scripts/flutterw analyze
../scripts/flutterw build ios --simulator --debug --no-pub
../scripts/flutterw build apk --debug --no-pub
```

## 已完成交互模块：正文链接点击、脚注展示及返回

- 已实现独立链接阅读路由，正文与补充页均可定位；沿用阅读主题、字体、媒体及点词。命中链接优先于查词，长按松手后复制句子的行为不变。
- 原路由保留滚动状态；逐层返回、系统返回和全部关闭不改正文进度。来源目标精确匹配时 backlink 可跨层返回；其他 backlink 按真实目标打开。
- 不可跳转状态显示说明，不调用系统打开外链。重复点击被拦截，连续打开最多 16 层，始终可退出。
- 长段落目标在列表初次布局后按 UTF-16 偏移定位；文档末尾受滚动范围约束时确保可见，不强求置顶。
- 测试、分析、两端构建及文档核对均已完成；两端已安装，iPhone EPUB 3 核心交互、Android EPUB 2/3 及补充交互经用户验收通过，具体边界如下。

## 已完成设备验收：脚注核心流程（用户实测）

- 已生成独立原创样本 `footnotes-epub2.epub` / `footnotes-epub3.epub`，不覆盖基础样本。重建：`python3 scripts/make_footnote_fixture.py`。样本含同章脚注、linear=no 独立页、非 spine 嵌套页、普通 EPUB 2/语义 EPUB 3 返回链接、跨行标记、图片表格、缺失/外链、自引用及非零正文位置。
- 验证：在 `app/` 执行 `READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/footnote_fixture_test.dart --reporter expanded`，2/2 通过。验证两补充页不进正文、目录、精确返回来源、图片/表格及 JSON 往返。新增测试经 Dart 格式化及定向 `flutterw analyze test/footnote_fixture_test.dart`，无问题；两样本重建 SHA-256 一致，ZIP CRC/首项未压缩 mimetype 检查通过；`git diff --check` 通过。本轮应用代码不变，复用此前构建。
- iPhone 18 Pro 在线，已 `simctl install` 正常覆盖安装；安装前后只读 SQLite 核对原有两书 ID/标题/位置相同：示例节选位置 12、基础 EPUB 3 样本位置 3。安装后书架仍显示 2 本书、35%/5%。没有卸载、数据注入或 `flutter test -d`。
- 两份样本已在 iPhone 系统 Files Downloads。上轮工具点击系统选择器报 `noWindowsAvailable` 后交给用户；用户本轮确认已导入 EPUB 3，并完成目录进入、`[1]` 脚注、查词、嵌套返回及重开正文位置检查，均无问题。此为用户实测证据；其他场景尚无明确反馈。
- Android `emulator-5554` 在线，本轮 `adb -s emulator-5554 install -r app/build/app/outputs/flutter-apk/app-debug.apk` 返回 Success。安装前后 `reading.sqlite` SHA-256 完全相同：`3d13d012e51680a9701371c375463acf04b8321a6cc3926ea69cbb7e1352a9ab`；原有三书位置为示例节选 8、基础 EPUB 3 样本 0、真实小说 611，数据保留。两份脚注样本已 push 到 `/sdcard/Download/`，回读字节与仓库样本一致。临时只读核对副本已自动清理，无数据库注入或卸载。
- Android 界面工具只返回 Device Manager，故交用户手动验收。用户最新反馈：两份样本已导入，脚注、查词、嵌套/系统返回、重开位置、长按复制、同章 `[2]`、跨行 `[3]` 和图片表格均无问题。此为用户实测，不标为代理自动验收。
- 未明确反馈项保留：iPhone EPUB 2、长按/同章/跨行/图片表格等补充场景，以及两端缺失/外链提示；已有宿主测试覆盖相应逻辑。它们可在后续阅读器设备回归中补验，不作为分页基础算法工作的额外审批门槛。

## 已完成模块：稳定位置映射与文字分页基础

- `TextPaginator` 用 `TextPainter` 布局原段落；按实际行坐标取逻辑范围，保留原文空白/换行，按字素边界合并不可分割的带。不要恢复“以上一行 end 直接查下一行”的实现：本机引擎会排除行尾空白/换行，窄视口下字体回退的组合表情也可能产生重合范围。空文本用零宽字符测一个空行，输出原文偏移仍为 0。
- `TextPagination.pageForPosition` 复用正文/补充命名空间，块内二分查页；`pages[index].start` 给出稳定源位置。布局输出不可变，页码是临时派生结果；未改持久化、现有 reader 或默认滚动模式。
- 专项 10/10、全量 72/72、分析与双平台构建通过（见摘要）。额外实际选区落在对应裁剪带、RichText 总高度对照通过；不只检查拼回文字是否相同。
- 纯文字层仍同步测量并显式拒绝媒体；混合布局、协作调用、溢出 UI 和持久化现由后续模块接入。大书性能/渐进布局/缓存及 iPad 双页仍待完成。

本轮验证（`app/`，已结束）：
```sh
READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/pagination_test.dart --reporter expanded
READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded
../scripts/flutterw analyze
../scripts/flutterw build ios --simulator --debug --no-pub
../scripts/flutterw build apk --debug --no-pub
```

## 已完成模块：图片与简单表格分页基础

- `BookPaginator` 组合原文字算法，文字/图片/图注/表格行统一按顺序装页；纯文字页与旧算法逐项对照一致。`loadPaginationImageSizes` 仅读取目标文档去重资源的编码描述，释放资源，不解像素帧；测试已验证从 books JSON 重建内容后经数据库 BLOB 读取尺寸。
- 图片等比缩小不放大、缺失/坏图占位；图注可以续页，保留原文 offset。表格列宽 160、内边距 10，整行跨页不重复表头；超高行/宽表/单元格字形溢出显式标记，空表有占位，不丢内容。溢出内容现由 PagedReader 提供滚动/展开入口。
- `PageAnchor` 显式区分部分和表格行号，`pageForAnchor` 精确往返页起点；旧 `pageForPosition` 仍按真实源位置解释，图片/表格块起点语义不变。基础模块完成时尚未持久化，现已通过 schema 3 接入；内容 JSON 不变。
- 基础模块完成时验证：`READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/book_pagination_test.dart --reporter expanded` 11/11；全量 83/83；分析/双平台 debug 构建成功。当时 UI 尚未接入，本轮新增结果见下文。

## 已完成模块：手机分页阅读接入与位置保存（用户已验收）

- 手机单页 UI：阅读设置可选左右翻页，保留滚动默认；PagedReader 显示加载/回退状态、滑动/按钮/进度条、图文表格。按完整原段落测量和裁剪，复用抽出的 ReaderParagraph，词、链接和复制仍对应原文坐标。宽表横向、超高页纵向滚动；展开入口显示完整可选文字。
- 持久化：schema 3 只新增 location；PageAnchor version 1 保存块内偏移、图注或表格行。旧书、坏值、未知版本安全退回；旧整数块号保留。翻页保存页起点，精确跳转及重排保留源锚点，脚注不写正文进度，生命周期/退出按当前实际锚点保存。
- 响应性：paginateAsync 复用同步算法，在块/行边界协作让出并取消过期请求；图片尺寸先完成再布局。异常长单块回退滚动，不宣称已完成大书性能优化。
- 专项 8/8：旧 schema 2 真实 SQLite 迁移并关开、原文/资源/设置/进度保留、旧样式/坏锚点、同步/协作一致性及取消/限额；翻页、查词、松手后复制、字号/视口重排和重开；脚注原文点击/返回/进度隔离；表格续行恢复、横向/纵向滚动与展开；图片 BLOB 解码、图注查词及位置保存、坏图占位和超长段回退。全量 91/91、analyze、双平台 debug 构建通过（详见摘要）。
- 正常覆盖安装：iPhone simctl install 退出 0；Android adb install -r 返回 Success。只读元数据/内容和图片指纹对比无变化；iPhone 3 本、Android 4 本，原有阅读位置完整保留。没有代理启动新版或伪造原生验收。

本轮验证命令（均已结束）：
```sh
cd app
READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/paged_reader_test.dart --reporter expanded
READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded
../scripts/flutterw analyze
../scripts/flutterw build ios --simulator --debug --no-pub
../scripts/flutterw build apk --debug --no-pub
```

## 已完成工程：iPad 双页与紧凑阅读区（体验待反馈）

- 手机分页上一版用户验收通过；iPad 最初 UI 被用户明确要求调整，本轮以其 2026-10-04 最新布局要求为准。上方只保留正文自身章节标题，不显示额外书名/信息栏。
- 本轮实现双页组合、右页来源锚点、旋转/分屏回单页、方向模式分别保存；随后减少实际预留，将正文高度增加 154。底部章节/页码融入 40 自然边距，字号 11、现有墨色 45% 透明度，长章名省略但保留页码。没有固定大工具条，操作面板按需打开。
- 验证：全量 95/95；最后章节/字体调整后专项 12/12 与浅深色渲染通过；最终 analyze/iOS/Android 构建通过。旧 JSON、数据库迁移、正文/脚注位置和资源/循环限制在全量内通过。
- 三台模拟器已正常覆盖安装，安装前后书架、位置、内容及资源一致。iPad 保留用户已导入的示例节选。CUA 连接故障，未宣称本轮原生验收通过。
- 最终源码之外的临时截图脚本已删除；渲染图片仅在忽略的 artifacts 中保留。未暂存、提交或推送。

## 已完成工程：真实句子翻译与缓存（Android 用户验收通过，Apple 真机待验收）

- 长按结束后原句面板自动查缓存/翻译；缺少模型时需点击下载；译文可选中，复制原句入口保持。默认 en → zh-Hans，不做其他语言、云端兜底、词典 miss 回退或生词本。
- Apple 18+ 真机使用 SwiftUI translationTask 承载系统模型许可；Android 使用 ML Kit 17.0.3 / Wi-Fi 模型下载，来源标识和说明已补齐。平台不可用、失败、取消、超时可明确反馈，不产生假译文。
- schema 4 只增加 translations。缓存精确键/输入输出上限/1000 项 FIFO、native 生命周期、测试边界和官方引用见 `docs/translation.md`。文档是契约，不是第二份计划。
- 全量 102/102 后，最终增补翻译专项 8/8、analyze、iOS 模拟器/Android 最终构建通过；Swift 真机分支另行无签名编译通过。三个模拟器覆盖安装及前后数据只读对比通过。没有把单元测试中的 TestTranslator 当成设备模型验证。

## 已完成工程：翻译缓存管理

- 书架“更多 → 翻译缓存”：显示全引擎/语言对缓存条数，确认清理、取消、空状态与失败重试；schema 不变。
- 清理仅作用 translations，保留书籍/资源/位置/设置/词典/模型。`CachedTranslator.clearCache()` 增加代次并与缓存写入串行；旧在途结果仍可回给原调用者但不入库，新请求不会复用旧 future。失败不污染后续写入队列。契约见 `docs/translation.md`。
- 专项 12/12、书架/阅读回归 11/11、analyze、双端构建通过。三台正常覆盖安装成功，原书架/位置和 Android 4 条译文指纹一致。没有在用户设备主动清空缓存。
- 缓存管理为局部可恢复操作，自动化已覆盖关键交互和数据边界，不新增强制人工验收关卡。用户可随时反馈原生观感；Apple 真机翻译保留独立验收待办。

## 当前完成工程：Wiktionary 英英离线词典接入（体验待反馈）

- 选用 Kaikki raw-wiktextract-data.jsonl.gz，当前页面标注 dump 2026-09-02、提取 2026-10-03；旧 postprocessed 按语言包已弃用。原始包存 dict_builder/data（忽略），流式筛选 en，记录 SHA/版本/条数/大小。
- 英英数据独立 SQLite/许可证。保留释义、词性/标签、词形、原词条来源；例句仅保留明确为 example 的自编例句，不导入带引文的 quotation/第三方出处例句。UI 完整档展示英英和来源，简洁档原英汉不变；Wiktionary 独有词允许查出，缺包不阻断英汉。
- 测试构建的过滤/归并/词形/来源/确定性，真实词包覆盖与查词、气泡档位和 ECDICT 回归；analyze、双端构建、保数据覆盖安装。schema 4 与正文位置不变。
- 原始快照 2,981,058,381 bytes，SHA `3dac8a09e57827bef493e2e6b552fe917bf3b1fc55dee05c4e4a3702aff5dbdb`；1,389,727 个不同词条 / 1,491,593 条词性词源记录 / 1,785,991 条释义 / 920,682 条词形映射。SQLite 320,331,776 bytes，压缩资产 118,980,347 bytes；源锁与资产 manifest 已记录校验值。
- Python 构建测试 2/2；完整真实词包安装/重开、实际释义/例句/计数/完整性/英汉回归测试 2/2，合并全量 Flutter **113/113**，analyze 无问题。主机首次解压 1.29–1.80s、重开 <1ms，500 次组合查询 p95 235–236µs；这些不是低内存真机性能证据。
- iOS 模拟器构建 10.4s、Android 构建 14.9s 成功；源码资产/iOS bundle/APK 的完整压缩词库 SHA 一致。三个模拟器均正常覆盖安装，安装前后书籍/位置/资源/设置/译文缓存只读对比一致，没有自动启动或人工验收冒领。
- 首次仍需读取约 119 MB 压缩资产并保存约 320 MB 离线库，实际手机首次等待/内存需体验反馈。源包和生成库不提交；重建命令见 app/README.md，接口与许可边界见 docs/dictionaries.md。临时分段下载/预览产物均在忽略目录，生产资产来自完整快照。
- 原生体验仍待反馈：首次查词/展开/滚动、断网重开及阅读位置。语言交互要求已由下方已完成的释义选项模块实现，不再以本段旧固定排序 UI 作为下一轮目标。
- 下载/构建/安装进程均结束。未暂存/提交/推送。缓存/Apple 翻译/iPad/真实教材的未验收边界仍保留。

## 已完成工程：释义语言与可选跨语言展开（用户验收通过）

- 核心约束：默认英汉 UI 与交互优先；不为了英英调整中文布局、正文阅读区或强制改变展开方式。主释义与展开行为是独立选项，新增入口为阅读设置 → 点词释义；小气泡没有新增常驻按钮。

| 主释义 | 展开行为 | 极简/简洁首次点词 | 点击气泡后 |
|---|---|---|---|
| 英汉（默认） | 保持当前方式（默认） | 原中文气泡 | 原完整卡片：中文在前，保留已有英文/来源/复制/关闭 |
| 英汉 | 查看另一种语言 | 原中文气泡 | 英英完整卡片 |
| 英英 | 保持当前方式 | 英文释义气泡 | 英英完整卡片 |
| 英英 | 查看另一种语言 | 英文释义气泡 | 英汉完整卡片 |

- 仅可选路径的完整卡片显示紧凑语言切换；临时选择不入库，下次选词（含相同拼写的另一处）、关闭、修改相关设置时重置。默认中文路径不增加控件；其布局/字体/间距/内容顺序与原渲染基准一致。完整档直接显示主语言，禁用但保留跨语言展开设置值。
- 英英极简取 senses 的前 1–3 条；简洁最多 24 条，仅释义、可换行/受限滚动；完整最多 24 条/每条 2 例句及来源许可。明确区分未收录与不可用，另一词库有结果时可主动查看；不静默换语言或调用翻译。头词、音标与来源跟随当前词库。默认中文的原有兼容显示保留。
- 接口：`ReaderStyle` JSON version 1 新增 `glossLanguage`（enZh/enEn）和 `glossExpansion`（current/otherLanguage），缺失/未知值回落 enZh/current；沿用全局 readerStyle 与 books.style，不改 schema。WordBubble 持有仅当前卡片的临时语言，reader 按 lookupGeneration 区分实例；读取现有组合词典，不增加下载/解压/联网或新的查词等待。契约见 docs/dictionaries.md。
- 验证：全量 **131/131**（新增 18），analyze、两端构建、三端保数据覆盖安装通过；默认中文 12 组测试字体 + 12 组可读字体前后像素一致。临时宿主渲染脚本已从 app/test 移出，永久测试不依赖本机字体或临时基准文件。阅读器测试实际操作设置、重开、正文选词、脚注与返回；既有分页/翻译/资源限额回归在全量内通过。
- 用户最新反馈：阅读设置中的英英主释义与“查看另一种语言”展开方式没有问题，按此范围记录验收通过；未将其扩大为 Wiktionary 低内存首开、Apple 真机翻译等无反馈项目的验收。当前已转入手机分页留白修复。
- 保留限制：Wiktionary 压缩资产约 119 MB/解压约 320 MB，低内存真机首用未测；系统译文 Apple 真机仍待验。词典下载/删除管理、MDX、生词本、首次引导、翻译兜底及阅读器 UI 重设计不在本轮。

本轮验证命令（app/，均已结束）：
```sh
READING_PROXY_URL='' ../scripts/flutterw test --no-pub test/gloss_language_test.dart test/reader_gloss_language_test.dart --reporter expanded
READING_PROXY_URL='' ../scripts/flutterw test --no-pub --reporter expanded
../scripts/flutterw analyze
../scripts/flutterw build ios --simulator --debug --no-pub
../scripts/flutterw build apk --debug --no-pub
```

释义模块边界：工程检查已完成；用户已确认设置中的英英主释义与跨语言展开没有问题。其他未体验项目按摘要保留，不扩大验收范围。

## 当前完成工程：手机分页上下留白修复（观感待反馈）

- 用户截图来自手机分页：SafeArea 外额外保留顶部 76、底部 110，分页组件另占 40；隐藏工具栏没有释放固定高度。用户要求底部与 iPad 一致显示信息，不承担直接翻页。
- 手机分页现在使用紧凑阅读器，SafeArea 内顶部 20、底部 40 自然边距，正文净增 166 逻辑像素；iPad 顶部 32/底部 40 不变，手机滚动模式不变。无常驻头栏/左右箭头/大进度区，底部 11 号淡色章节与页码沿用 iPad 组件。日常翻页滑动；点击空白/底部信息打开临时操作面板，不直接改变页码。目录/设置/返回/进度定位、宽表翻页及内容展开仍可达。
- 自动验证：分页专项 14/14、全量 133/133、analyze、两端构建通过；两种手机安全区测试核对实际 PageView 上下界、BookPagination 内容高度、页数减少、面板不挤正文、查词避让、翻页/重开精确锚点。旧双页/媒体/脚注测试继续通过；默认查词内容与手势逻辑不改。
- 三台模拟器已正常覆盖安装，最新安装前后只读数据完全一致。没有自动启动或宣称原生视觉验收通过。无需重新导入书籍，重排后的页数可能减少，保存的原文锚点保持。
- 下一动作：用户检查 Android/iPhone 截图中的同一本书，确认顶部/底部边距、薄章节页码、滑动翻页和重开位置；释义选项的已确认结果保留。此边界不自动展开新功能。

Workflow status：当前手机分页修复工程完成；plan `done`（唯一 PLAN）；architecture/interface `done`（复用现有紧凑页码/临时面板，不改数据接口）；validation `done`（14 专项/133 全量、分析、双端构建、三端保数据安装），原生观感 `pending`；Git checkpoint `not needed`（用户要求不暂存/提交/推送）；handoff `done`（摘要、原因、尺寸与下一动作已更新）。

## 已完成里程碑（压缩）

| 成果 | 关键决策 / 验证边界 |
|---|---|
| 环境与原型 | Flutter/Dart、Xcode/Android 工具已就绪；`prototype/reader.html` 保留，模拟释义/翻译不算正式能力 |
| 阶段 2 主体 | Riverpod + drift；真实 ECDICT 770,611 词条；TXT/粘贴、书架、查词/三档气泡、设置/位置；部分人工验收未关闭 |
| EPUB 基础与真实书核验 | 两端原创样本用户实测通过；安卓真实小说阅读通过；小说无表格，不能替代真实教材验收；专项证据见 docs/epub-acceptance.md 与 docs/real-epub-compatibility.md |
| SVG 图片包装修复 | 共享本地图片读取路径；原型外的真实书两张图片均提取、文字不变；两端构建通过，新封面设备视觉待验收 |
| 正文脚注模型 `f3a3d5a` | 章内/跨连续章节链接、引用/返回语义、状态区分和旧 JSON 兼容；当时 38/38 测试、分析、双平台构建通过 |
| 独立脚注页（当前未提交） | 补充内容命名空间及返回目标、受限加载/循环去重；当时 52/52 测试、分析、双平台构建及真实小说正文不变对照通过 |
| 链接阅读交互（当前未提交） | 下划线点击、独立展示/定位、返回栈与正文进度隔离；60/60 测试、分析及双平台 debug 构建通过；iPhone EPUB 3 核心、Android EPUB 2/3 及补充交互用户实测通过 |
| 文字分页基础（当前未提交） | 原文位置映射、Unicode/换行/标题间距及重排；10 项专项、全量 72/72、分析/双平台 debug 构建通过；未接分页 UI/媒体/持久化 |
| 图片/表格分页基础（当前未提交） | 尺寸预读、等比图片/图注、整行表格、精确媒体锚点及显式溢出；当时 11 项专项、全量 83/83、分析/双平台 debug 构建通过 |
| 手机分页/精确保存（当前未提交） | 可选单页 UI、原文手势/重排恢复、schema 3 兼容迁移、协作排版/溢出回退；8 项专项、全量 91/91、分析/双端构建通过，已安装，用户验收通过 |
| iPad 双页/紧凑布局（当前未提交） | 双页/方向模式、正文高度 +154、薄章节页码；全量 95、专项 12、渲染/分析/双端构建通过，三端已安装，iPad 体验待验收 |
| 真实句子翻译/缓存（当前未提交） | Apple/ML Kit 原生接入、schema 4 成功缓存、句子面板；全量 102、最终专项 8、分析/构建/三端安装通过；Android 断网新句用户验收通过，Apple 真机待验收 |
| 翻译缓存管理（当前未提交） | 书架数量/清理、代次与队列防旧结果入库；23 项相关测试、分析/双端构建及三端保数据安装通过 |
| Wiktionary 英英（当前未提交） | 固定完整数据源、独立词库、组合查询/释义/例句/来源许可；Python 2、Flutter 全量 113、分析/双端构建与三端保数据安装通过，原生体验待反馈 |
| 释义语言选项（当前未提交） | 默认英汉保持，可选英英主释义/跨语言展开、全局/单书保存；24 组宿主渲染对照、全量 131、分析/双端构建/三端保数据安装通过，用户确认语言选项没有问题 |

## 语言扩展约束（V1英语，V2可能扩展）

- 当前评估：已有LanguageSupport（code/wordAt/sentenceAt/candidates）与EnglishLanguage、DictionaryProvider、带from/to参数的Translator；生词存lang/dict_id，译文缓存区分语言对；阅读源位置使用Unicode文字的UTF-16偏移，书签/进度无需英语规则。现有边界足够继续V1，不需要现在新增语言注册表/插件框架、配置矩阵或数据库字段迁移。
- 已识别耦合：reader.dart、paged_reader.dart和生词capture/resolve直接构造EnglishLanguage，生词capture写入en；词典模块内也有英语规则。后续涉及这些调用链时，优先复用现有LanguageSupport，通过单一V1默认配置/依赖入口注入并从code取数据语言，确保保存与回跳使用一致断句规则。此为局部整理原则，不在本轮做全库重构，不把去掉所有en字面值当目标；英语数据构建/词形规则留在英语模块合理。
- 通用UI、分页/跳转/书签/数据存取不新增英语分词或ASCII限定；书内搜索已采用源文字与位置映射，语言相关匹配规则保持可分离，避免归一化改变字符长度后直接套回原文偏移。V1只验证和宣称英语学习支持，不用未来日语/西语实现或数据来扩大范围。
- 学习语言、释义目标语言和应用UI语言分开理解；现有glossLanguage enZh/enEn仅表示英语词汇的释义选择，不能当未来学习语言选择器。已有英语数据需在未来升级时继续按en解释；按真实新增语言的需求再决定书籍语言元数据与兼容迁移，不提前加空泛字段。
- 未来扩展目标为增加语言模块/词典配置及设置选择，并尽量复用现有阅读/学习流程；不承诺任意语言只加一个下拉框就能完整支持。新语言仍需自身分词、词形、断句、词典数据与布局/翻译能力验证。首次使用引导V1只说明英语离线资源，不加入学习语言选择。原始计划里的多语言项属未来候选，无V1承诺。
- 此约束评估当时仅记录，无架构变更。随后书内搜索按上述边界实现，未增加英语耦合或多语言系统。下一开发动作见下方。

## 后续粗计划与依赖

- 当前唯一下一动作：大书首次分页耗时定位，先建立宿主可复现基线。入口app/lib/reader/{paged_reader,book_pagination,pagination,pagination_cache}.dart及现有分页测试；固定生成的长篇纯文本与含图片/表格样本、手机/双页尺寸，区分源解码、图片预检、文字布局和缓存命中路径，记录输入规模/环境/耗时，不用波动的硬时间阈值当单元测试。先证明瓶颈再选最小优化，不在这一定位步骤重写分页/持久化或承诺帧率；保持章节边界、源锚点与资源限制，相关分页回归验证结果。宿主耗时只作相对诊断，不能外推Android帧率；若无法可靠分离则明确保留待真机Profile，不要求立即安装。继续只维护本PLAN。图片/引导/入场与缓存/启动页真机体验、正式签名与隐私申报作为后续集中验收/分发项保留。
- 分页：手机早期分页功能已验收；本次手机紧凑边距调整待用户反馈，不能沿用旧验收结论。iPad 双页及紧凑 UI 工程完成、详细体验待确认。真实教材/大书性能及阶段 2 遗留验证仍保留。
- 阶段 3 其余：词典管理后续能力（导入/删除/更新需另定范围）、生词本原生体验补验（收藏/原句/CSV已交付）、备份原生体验，以及iPhone真机/iOS18兼容分支/低内存设备等尚未覆盖的验证。iPad与Android断网新句核心体验已确认；阶段2遗留验收不丢失。
- 2026-10-06原需求遗漏项复核（粗清单，不新增并行当前目标）：①书内搜索（工程/交付完成，体验待验）；②备份/恢复（工程与四设备交付完成，原生体验待确认）；③长按拖动调整选区/短语翻译（可见同段落基础闭环已交付，跨段跨页/手柄等未实现）；④词典miss系统翻译兜底（工程/四设备已交付）与查词历史（工程/三模拟器完成，真机集中交付待办）；⑤词典管理从只读状态/大小扩展到下载或导入、删除、更新、顺序（需先定来源及模型管理边界）；⑥书架EPUB封面/作者、外部共享导入、启动直回上次书选项；⑦图片点击放大/缩放（工程/构建完成，未安装验收）、应用横竖屏锁定（未实现）；⑧普通正文目录跳转的一键返回（工程/三模拟器交付完成，真机集中交付与体验待办）；⑨英语首次使用/离线准备引导（工程/构建完成，未安装验收）与图标/启动页发布检查（工程与构建完成，启动体验与正式分发待办，V1不做学习语言选择）。开源许可致谢页、翻译缓存清理已有实现，不重复列为缺失。以上原始阶段3细项此前在粗计划中压缩过度，现补齐；搜索、备份与选区基础闭环已交付，目录返回工程及三模拟器交付完成，图片放大和英语引导工程完成，发布准备工程核查完成，下一步骤首次分页耗时定位，真机集中交付；其他按依赖再排，不声称阶段3全部完成。
- 已有实现但验证不足另计：选区、备份、搜索与书签原生交互、生词原句回跳及部分前序布局详细体验；CSV仅iPad获确认。真实教材/复杂简单表格边界、大书性能、Wiktionary首次解压的低内存行为、iPhone真机/iOS18兼容分支/首次模型下载许可与不同Android设备覆盖不以宿主测试替代。脚注使用当前已接受的临时阅读返回方式，不因原始“就地弹出”措辞再复制另一套UI。
- 阶段 4：MDX/MDD、文字层 PDF；阶段 5 可选同步/多语言，均未开始。原需求细项仅必要时查 `docs/original-plan.md`，不在当前步骤展开。

## 必要运行上下文与边界

- 源码入口：`app/lib/library/library.dart` 导入/后台解析；`book/book.dart` 模型/解析接口；`book/epub.dart` EPUB；`db/database.dart` schema 7；`reader/reader.dart` 阅读/气泡；`text/language.dart`、`dict/dictionary.dart`、`translate/translator.dart` 分别是语言/词典/翻译接口。不要照原计划目录猜测不存在的 `app/lib/language/`。
- 本机已确认 Flutter 3.47.5/Dart 3.13.4。使用 `scripts/flutterw`：默认 HTTP/HTTPS 大小写代理 `http://127.0.0.1:7897`，NO_PROXY 本地地址；下载/构建保持默认。`READING_PROXY_URL=''` 清除代理，供本地设备调试/宿主测试，支持时加 --no-pub。工具链缓存写入可能需正常提权；Java native-access/SDK XML 警告历史未阻断成功构建，不为警告擅自重装环境。
- `app/assets/dictionaries/ecdict.sqlite` 是真实词典且 Git 忽略；不要删除或无故重建。只有缺失时才读 `scripts/fetch_assets.py` / `dict_builder/build_ecdict.py` 的恢复步骤。大型资产/原书/编译产物不提交。
- EPUB 整书限额保持：文件 50 MB、单资源解压 20 MB、声明总解压 150 MB、10,000 项；保留实际输出大小/CRC/路径检查。新增脚注限额及状态契约见 `docs/epub-links.md`。
- 两端输出：`app/build/ios/iphonesimulator/Runner.app`、`app/build/app/outputs/flutter-apk/app-debug.apk`。构建不自动更新设备。禁止在已有用户书架模拟器运行 `flutter test -d`（可能卸载 App）；正常覆盖安装保留数据，iOS 容器 UUID 会变，需要重新查询，不能按旧路径消失判定丢书。
- iPhone UDID `144FF884-EC04-4E7F-9BE6-AFF8264E8699`，bundle `dev.reading.readingApp`，UI 宿主 Device Hub `com.apple.dt.Devices`。Android `emulator-5554` / `dev.reading.reading_app`，SDK `/Users/tty/Library/Android/sdk`。设备运行状态需操作前重查；不要同设备并行 run/test。
- 安卓界面工具历史无法绑定独立模拟器，原验收借助用户；无新证据别重复同样失败绑定。iPhone 也曾有 noWindowsAvailable，先读当前 UI，失败后不盲目重试旧元素。不得用数据库注入代替原生导入验收。
- 真实书完整路径/SHA 在 `docs/real-epub-compatibility.md`，无需再次索要；安卓副本 `/sdcard/Download/reading-real-book.epub`。比对证据在忽略的 `artifacts/real-epub-audit-links.json` / `real-epub-audit-svg-fixed.json` / `real-epub-audit-supplements.json`；它们是辅助证据，不能依赖其跨机器存在。
- 本轮测试、分析和双平台构建已结束，无代理遗留运行任务。旧样本回环服务 8765 已停止，旧下载链接不可用，不重复清理历史 PID。现有模拟器可能仍由用户使用。可测试真机型号/系统未提供，只影响后续真机验收。
