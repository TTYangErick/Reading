# 真实 EPUB 兼容性检查：Harry Potter and the Chamber of Secrets

检查日期：2026-10-02。应用检查点 `18fae5b`，本轮没有修改解析器或阅读器。输入是用户指定的本地文件，仅本地读取、复制到现有本地安卓模拟器供正常导入；原书未修改，未收入 Git。

## 输入与方法

- 原文件：`/Users/tty/Downloads/Harry Potter and the Chamber of Secrets (Harry Potter  the Chamber of Secrets) (z-library.sk, 1lib.sk, z-lib.sk).epub`
- 大小：425,499 bytes；SHA-256：`b552446064088e5b955327d1fd9434f9db6b36d740bfdb6d940c6a514884a63a`。
- EPUB 2.0；29 个 ZIP 项，展开总计 836,263 bytes；`content.opf` 的 spine 含 20 个 XHTML 文档（封面/前置内容及 18 章）。ZIP CRC 检查通过。
- 实际调用生产 `EpubParser.parse`；独立以 Python 标准库读取 ZIP/XML，按 spine 收集非空 p/h1/pre 的规范化文字，以顺序及逐块 UTF-8 CRC32 对照解析结果。CRC32 只作兼容性比较指纹，不作安全摘要。原文不写入报告或测试夹具。
- 本地证据：忽略目录 `artifacts/real-epub-audit.json`、`artifacts/real-epub-comparison.json`。可重复运行 `app/tool/inspect_epub.dart`，仅输出结构、标题及文字校验值，不输出正文。

```sh
cd /Users/tty/Desktop/Coding/Reading/app
dart run tool/inspect_epub.dart '/Users/tty/Downloads/Harry Potter and the Chamber of Secrets (Harry Potter  the Chamber of Secrets) (z-library.sk, 1lib.sk, z-lib.sk).epub'
```

## 已验证

| 项目 | 结果 / 边界 |
|---|---|
| 解析 | 成功，3,179 个内容块，其中 3,178 个文字块和 1 张图片 |
| 正文完整与顺序 | 独立抽取的全部 3,178 个文字块，规范化后逐块 CRC32 与 Reading 相同且顺序一致；18 章正文均存在。这不验证原排版/斜体等样式 |
| 目录 | NCX 自带 17 项；解析出的标题、顺序、目标块全部与原 NCX 一致，无越界目标 |
| 第 15 章 | 正文位于块 2451；源标题拼为 `CAPTER FIFTEEN ARAGOG`，原 NCX 没有该项。是原书目录缺项，不能报告为解析器丢失正文 |
| 普通图片 | `Cover.jpg` 124,594 bytes 被正确提取；包内另外的 SVG 包裹封面未提取，见下方缺陷 |
| 持久化格式 | 生成 JSON 581,857 bytes，编码/解码后完全一致；不等于原生数据库/退出恢复验收 |
| 耗时 | 本机 Dart 单次解析 127 ms，仅这份小书的一次结果，不代表手机或大书性能 |
| 检查工具 | 格式检查与 `dart analyze tool/inspect_epub.dart` 通过；用原创 EPUB 3 夹具核验 3 项目录、1 图片、1 表格、有效目标和 JSON 往返，全部通过 |
| 安卓传输 | `/sdcard/Download/reading-real-book.epub` 与原文件 SHA-256 完全一致；传输不等于导入验收 |

本轮只新增本地诊断工具和文档，未改应用逻辑，因此没有重复双平台构建或把历史 28/28 测试当成本轮重新执行。

## 初次检查确认的限制与问题（修复进展见下方）

1. **初次检查的 Reading 缺陷（现已修复解析，尚未设备验收）：SVG 内嵌栅格封面静默丢失。** `titlepage.xhtml` 使用 `<svg><image xlink:href="cover_image.jpg" ... /></svg>`。包内 JPEG 存在（100,523 bytes），`_Blocks.walk` 只处理 HTML `img`，忽略 SVG `image` 且不显示占位。这份书仍有另一张普通封面可显示，但不能将其计为全部图片支持。建议下一次修复仅支持从简单 SVG 图片包装中提取本地 PNG/JPEG 等既有支持格式，并复用路径/大小/CRC/外部资源安全限制；不引入通用 SVG 执行或渲染。
2. **源书问题：NCX 漏第 15 章。** Reading 当前仅在目录完全为空时回退到正文标题，因此忠实保留了不完整目录。正文仍可滚动阅读到第 15 章。若后续要补全目录，需单独设计去重/顺序/目标规则，不能只为这本书硬编码章节号或拼写修正。
3. **没有表格。** 本文件不能新增简单表格兼容性证据；表格的既有依据仍是原创样本测试和两端用户实测。它是小说，不能代替真实教材测试。
4. SVG、原书 CSS/内嵌字体精确排版、图片放大、脚注交互和分页等既有限制没有因本次检查消失。

## 原生阅读：安卓用户实测通过

用户在现有安卓 Reading 通过“添加书籍 → 导入 EPUB / TXT”选择 Downloads 的 `reading-real-book.epub`，检查第 1、9、18 章、普通英文词释义保持和返回书架重开位置，对这一整组检查明确回复“全部正常”。上述项目按用户实测通过记录，不冒称代理自动原生 UI 验收。界面工具不能绑定独立安卓模拟器的限制仍在，但不再阻塞本项结论。

未向业务数据库注入正文，未在用户模拟器执行可能卸载应用的 `flutter test -d`。iPhone 本书原生导入、iPad/真机、大书/内存、精确排版均未验证。

## SVG 封面修复进度（2026-10-02）

- `_Blocks.addSvgImage` 支持直接单 image 与可选纯文本 title/desc，识别 `href` / namespaced `xlink:href`；复用 `addImage` 与既有路径、格式、解压上限及 CRC 校验。复杂 SVG 显示占位，不作通用 SVG 渲染，无新增依赖。
- 新增 4 项回归先在旧代码失败、修复后通过；全量宿主 32/32 通过，`flutter analyze` 无问题，iOS 模拟器 debug 构建通过。用户提醒 limit 后优先保存，安卓构建未执行。
- 本书重新解析得到 3,180 块、2 张图片；`cover_image.jpg` 100,523 bytes 和 `Cover.jpg` 124,594 bytes 均提取。3,178 个文字块及顺序与旧指纹完全一致；17 个目录目标统一 +1 正确，JSON 往返一致。新第 15 章索引 2452；原 NCX 缺项未修补。
- 证据在忽略的 `artifacts/real-epub-audit-svg-fixed.json`；修复前证据保留。单次本机解析 125 ms，不外推设备性能。
- 未自动重解析旧书，旧书位置不变；新导入才包含新图片。两端已安装 App 未更新，旧安卓 APK 不含本次修复，封面原生视觉尚未验收。上方用户“全部正常”是修复前的阅读验收。
- 下一轮只完成安卓构建及工程交付记录，之后再进入脚注解析模型。
