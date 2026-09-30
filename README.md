# Reading

Flutter 离线点词阅读器，支持 iPhone、iPad 和安卓。

- 正式 App：`app/`
- 原网页原型：`prototype/reader.html`（保留未改）
- 当前执行计划：`PLAN.md`
- 最新交接与验收记录：`HANDOFF.md`
- 完整原计划存档：`docs/original-plan.md`
- 工程运行、重建词典与测试：[app/README.md](app/README.md)

## 当前体验

打开模拟器中的 Reading，点右上角 `+`，选择 TXT 文件、粘贴文本或先读一段示例。点击英文单词显示本地释义，点击气泡展开；长按正文可复制整句；`Aa` 调整字体、主题与释义档位。阅读进度和样式会保存在本机。

目前支持 TXT 与 EPUB 2/3 滚动阅读、目录、图片和简单表格；EPUB 原生导入和真实教材仍待体验验收。左右翻页、iPad 横屏双页、句子翻译、生词本和备份按阶段 3 继续实现。
