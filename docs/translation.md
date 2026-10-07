# 离线翻译契约

本文件是实现契约；进度与下一步只在 `../PLAN.md`。

- 入口：阅读器长按结束后的 `SentenceSheet`，以及两库确认未收录时的点词气泡（判定/展示见 `dictionaries.md`）。共用 `TranslationContent`；句子入口默认 English → 简体中文。保留原句与复制，底部面板自行滚动，不调整正文布局，不写书籍内容、阅读位置或脚注返回栈。
- `Translator` 提供 `engine/status/prepare/translate`。状态区分 ready、downloadRequired、unsupported、unavailable；失败使用 `TranslationFailure`，不把原文或模拟结果伪装成译文。
- `PlatformTranslator` 通过 `dev.reading/translation` 调用两端桥接。请求带唯一 id；native 同时只处理一个请求，其他返回 busy。准备超时 180 秒，其余 45 秒；超时按 id 取消结果传递、释放桥接占用，晚到回调忽略。Android SDK 已启动的模型下载可能继续，不能把关闭面板或 client.close 当作删除/撤销下载。
- iOS/iPadOS 18+ 真机：`LanguageAvailability` 检查；iOS 26+ 对已安装模型直接创建 `TranslationSession(installedSource:target:)`，无需原生模态加载页。模型下载与 iOS 18–25 兼容分支使用附着于当前控制器的透明 SwiftUI child host（不拦截触摸/辅助功能），提供 `translationTask` 生命周期与必要的系统语言下载许可；SwiftUI 提供的 session 不逃逸 task。加载/译文只显示在 Flutter 翻译区域；结束或超时取消直接 session / task，仅关闭 host 自身呈现的系统许可并移除 child，不关闭 Flutter 阅读器。模拟器及旧系统明确 unavailable，App 其他功能继续可用。无收费 API、无云端翻译回退。
- Android：`com.google.mlkit:translate:17.0.3`，English 为隐含语言，检查 Chinese 模型；只有用户点击准备按钮才调用 `downloadModelIfNeeded(requireWifi)`。译文来自 `Translator.translate`，完成/失败/超时释放 client。INTERNET 用于模型下载；SDK 自身服务通信不等于云端原文翻译。结果附官方 Google Translate 标识，面板“翻译说明”含来源与要求的声明。
- `CachedTranslator` 先查本地成功译文，再检查设备状态；缓存命中无需模型/网络。键为引擎版本 + from + to + 精确原句，不折叠空白。相同在途请求共享 future；失败、空结果不缓存。原句最多 4000、结果最多 16000 UTF-16 单元。
- 数据库 schema 4：仅新增 translations 表，最多 1000 项，按插入顺序淘汰。schema 1/2/3 迁移不改原数据；cache 与书籍生命周期独立。书架“更多 → 翻译缓存”显示条数并确认清理。UI 通过 `CachedTranslator.clearCache()` 增加缓存代次并串行执行写入；旧在途结果仍可返回原调用者，但不会重新写入缓存，新请求也不复用旧代次的 future。清理失败可重试，不污染后续写入队列。仅逻辑删除 translations，不执行 VACUUM 或移除语言模型，也不宣称立即缩小数据库文件。引擎升级需调整 engine key；系统模型版本无稳定可用标识，已有缓存不会随系统模型自动刷新。
- 自动化中的 TestTranslator 仅为测试替身，不进入产品。构建成功不能证明模型下载或翻译质量；真实引擎体验需单独验收，结果仅记录在 PLAN.md。

参考：[Apple Translation](https://developer.apple.com/documentation/translation/)、[Apple WWDC24 平台限制](https://developer.apple.com/videos/play/wwdc2024/10117/)、[ML Kit Android](https://developers.google.com/ml-kit/language/translation/android)、[Google Translate](https://cloud.google.com/translate)、[来源标识要求](https://developers.google.com/ml-kit/language/translation/translation-terms)。

## 拖动选区与短语

- 长按不拖动：保留原整句翻译/复制，松手后打开面板；按住时整句高亮。长按后移动超过8逻辑像素：以起始词为固定端，按Flutter文字引擎词边界调整另一端，支持向前、向后和同段跨行；拖动中实时高亮，松手后才请求一次当前范围的翻译。
- 调整过的选区使用“选中的文字 / 复制文字”，原句流程仍显示“选中的句子 / 复制句子”。使用现有英译中设备模型、缓存、失败重试和下载入口；现有4000 UTF-16单位翻译限制不变，过长仍可复制。原文按源UTF-16连续范围截取，不拼接视觉行、不改存储位置、不会根据翻译结果修改正文。
- 首版限当前可见的同一源段落、图注或表格单元格；支持滚动/单页/双页/补充脚注。分页传入当前片段可见起止，拖动命中检查同时遵守祖先裁剪区域；越过中缝、进入另一页/另一段/另一单元格时保留最后有效范围，不选择页外隐藏文本。不做跨段/跨页、自动滚动或自动翻页；松手后直接打开现有翻译面板，不提供额外选区手柄。
- 长按开始关闭旧单词气泡；普通点词、再次点击只关闭释义、链接、滑动翻页和原阅读操作保持。手势取消、源文字/排版样式/可见范围/窗口尺寸/文字缩放改变时取消当前选区，不触发翻译。拖动本身不请求词典/翻译或保存位置；已调整选区在双页右页也不改变正文保存锚点。
- 实现边界：ReaderParagraph本地临时手势状态与可选onSelection回调，PagedReader仅传可见源范围和回调，ReaderPage复用SentenceSheet；不加英语ASCII分词规则、数据库字段或原生桥。源范围与布局引擎边界分离，V1支持英语学习的边界保持。

- 共享翻译视图在原文变化时清空旧显示并增加请求代次，旧完成结果只可进入原精确键缓存，不能覆盖新原文；销毁后忽略UI回调。下载等待后先检查视图仍有效，再启动翻译。展开气泡不重启同一请求，原句子面板的文字顺序/复制入口保持。

## 阅读与离线准备指南

- 指南进入时仅调用既有Translator.status(en, zh-Hans)，不发起翻译或模型下载。ready/downloadRequired/unsupported/unavailable及读取异常分别显示；只有downloadRequired时提供用户主动下载按钮。
- 按钮复用CachedTranslator.prepare与既有平台下载许可/Wi-Fi要求，禁止重复点击；完成后重新status，不能把prepare完成或旧译文缓存当成模型就绪。错误可重试，状态可刷新；返回前台重新检查。
- 关闭指南不继续翻译、不更新已销毁UI；SDK已开始的下载可能继续。指南没有演示译文、不写translations或查词历史、不宣称替身测试验证真实下载。V1只提供en→zh-Hans，不改变句子面板/词典miss翻译流程。
- 指南说明可用未翻译过的新句在断网下验证实际模型，已有缓存显示成功不足以验证离线新句能力。Apple不可用提示沿现有iOS18+真机边界；Android不显示不相关的Apple系统要求。
