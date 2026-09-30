# 原创 EPUB 验收样本

根目录执行 `python3 scripts/make_epub_fixture.py` 可重新生成两份确定性样本。

- `lesson-epub2.epub`：EPUB 2 NCX 嵌套目录。
- `lesson-epub3.epub`：EPUB 3 nav 嵌套目录。
- 两者均包含两个章节（manifest 故意倒序，spine 正序）、带空格的图片路径、原创三条蓝色柱状图、简单词汇表及 50 段正文，支持验证位置恢复。
- 这些是结构验收样本，不是完整教材兼容性证据。当前测试未使用外部 EPUB 校验器。
