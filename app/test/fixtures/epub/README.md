# 原创 EPUB 验收样本

根目录执行 `python3 scripts/make_epub_fixture.py` 可重新生成两份确定性样本。

- `lesson-epub2.epub`：EPUB 2 NCX 嵌套目录。
- `lesson-epub3.epub`：EPUB 3 nav 嵌套目录。
- 两者均包含两个章节（manifest 故意倒序，spine 正序）、带空格的图片路径、原创三条蓝色柱状图、简单词汇表及 50 段正文，支持验证位置恢复。
- 这些是结构验收样本，不是完整教材兼容性证据。当前测试未使用外部 EPUB 校验器。

书架集中验收样本由 `python3 scripts/make_shelf_fixture.py` 从上述EPUB3原创正文生成，固定ZIP时间与顺序，可重复重建：

| 文件 | 新导入后的预期 |
|---|---|
| `shelf-cover.epub` | `Reading shelf — cover`，显示 `Reading Sample Author` 和棕色边框/展开书本的竖版封面 |
| `shelf-missing.epub` | 同一作者，图片引用缺失，沿用文字封面且能阅读 |
| `shelf-broken.epub` | 同一作者，ZIP与CRC有效但图片不可解码，沿用文字封面且能阅读 |

三者正文、目录和源锚点与lesson-epub3相同；新增封面不插入正文。缺图/坏图样本是故意制造的可选资源问题，不用于宣称EPUB格式验证通过。新元数据需新导入，已有书架不会自动补齐。它们只用于功能/布局，不能代替真实长书性能样本；工程回归见 `epub_metadata_test.dart`，原生待验状态仅见上层PLAN。
