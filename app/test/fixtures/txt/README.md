# TXT 验收样本

这些短文由本项目为测试编写，不含用户书籍。两个正常样本正文相同，编码不同，均为 CRLF 换行：

| 文件 | 编码/内容 | 预期 |
| --- | --- | --- |
| `utf8-bom.txt` | UTF-8，含 BOM，117 bytes | 4 段正文、2 个章节，无乱码和多余空段 |
| `gbk.txt` | GBK，103 bytes | 与 UTF-8 版本正文一致 |
| `empty.txt` | 0 bytes | 提示文本为空，不新增书籍 |
| `binary.txt` | 含 NUL 的非普通文本 | 提示另存为 UTF-8 或 GBK，不新增书籍 |

正常样本正文：

```text
Chapter 1
Tomorrow is another day. The children went to school.
第二章 新的开始
中文与 English。
```

不要用编辑器自动转换 `gbk.txt` 或移除 `utf8-bom.txt` 的 BOM；它们是编码回归样本。

SHA-256：

```text
utf8-bom.txt 437dd6ecf64aa7f204b6a6e8cbc8023ca41d9617013a5524f655e554e2ee0712
gbk.txt     ef72a9e438ae1d3cdc835a469ca04496fdc322266a113e56484a97adc45dcfc8
```

`test/file_import_test.dart` 用真实文件读取、正式解析器与 SQLite 验证导入流程，替代了原生文件选择对话框和亮屏通道。它不能代替在 iOS Files／安卓文件管理器中实际选中文件的人工验收。

完整人工验收步骤见项目根目录 `docs/phase-2-acceptance.md`。
