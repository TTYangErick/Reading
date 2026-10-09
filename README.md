# Reading

Flutter 离线点词阅读器，支持 iPhone、iPad 和安卓。

- 正式 App：`app/`
- 原网页原型：`prototype/reader.html`（保留未改）
- 当前执行计划：`PLAN.md`
- 当前状态与下一步：仅维护 `PLAN.md`，HANDOFF 文件为历史快照
- 完整原计划存档：`docs/original-plan.md`
- 工程运行、重建词典与测试：[app/README.md](app/README.md)

## 当前体验

打开 Reading，点右上角 `+`，选择 EPUB/TXT 文件、粘贴文本或先读一段示例。点击英文单词显示本地释义，点击气泡展开；长按正文可复制整句或查看离线翻译；按住后拖动可跨正文段落和双页选择文字，分页时在阅读区域外缘停留可继续翻页选择，松手翻译或复制所选文字；阅读设置调整字体、主题与释义档位。阅读进度和样式会保存在本机。

目前支持 TXT 与 EPUB 2/3、单页/双页分页、目录、脚注、图片和简单表格。手机与 iPad 分页均采用紧凑阅读区，底部仅显示章节/页码，滑动翻页；点击空白或底部信息打开阅读操作。当前验收范围和剩余验证统一见 [PLAN.md](PLAN.md)。

本地查词组合 ECDICT 英汉与 Wiktionary 英英：默认中文气泡和展开方式保持原样；阅读设置可选择英英主释义，以及英英→英汉或英汉→英英的跨语言展开。完整卡片可查看用法示例和来源许可。词包随应用提供，查词不联网；数据来源、重建与显示范围见 [词典契约](docs/dictionaries.md)。

句子翻译已接 Apple Translation（iOS/iPadOS 18+ 真机）与 Android 的 Google Translate / ML Kit 设备端模型，并缓存成功译文。首次需下载模型；平台验收范围见 PLAN.md。书架“更多 → 翻译缓存”可查看条数并清理译文，语言模型和阅读位置保留。Android 翻译来源：[Google Translate](https://cloud.google.com/translate)。实现和限制见 [翻译契约](docs/translation.md)。生词本支持收藏、原句回跳和 CSV 导出；阅读操作提供书签与书内搜索。书架“更多 → 备份与恢复”可保存单文件备份，并在预检与确认后整库恢复；范围与限额见 [备份契约](docs/backup.md)。剩余范围与验收见 `PLAN.md`。
