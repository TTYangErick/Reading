# Reading 交接与执行状态

更新：2026-10-02

## 已确认

- 项目在 `/Users/tty/Desktop/Coding/Reading`；原型在 `prototype/reader.html`。
- 历史会话：`~/.claude/projects/-Users-tty-Desktop-Coding/e2bedabc-fa2a-465f-a15f-b8a641e84793.jsonl`；相关记忆位于同目录的 memory/。
- 原计划存档 `docs/original-plan.md`，当前执行范围 `PLAN.md`。
- 原型为 v2，标题仍写 v1；297 词条，847 次示例单词全部命中；语法及抽样词形还原检查通过。
- Flutter 3.47.5 / Dart 3.13.4、Xcode 27.0、CocoaPods 1.17.0、Android SDK 已就绪。
- 2026-09-30 指定 HTTP(S)_PROXY 和 NO_PROXY 后，flutter doctor 显示 No issues found。
- Xcode 模拟器窗口是 DeviceHub；现有 iPhone 18 Pro 与 Android Reader_Phone 模拟器。
- 旧临时 hello_check 仅 Flutter 示例，不是 Reading App；iOS/安卓示例曾构建运行成功。
- Reading 开始接手时无 Git 仓库，仅原型和空 test.py；没有丢失的正式业务代码。

## 当前工作

阶段 2 主体代码与真实 ECDICT 已完成，用户确认 iPhone 气泡闪现已修复。阶段 3 的 EPUB 基础版本已接通：EPUB 2/3 文字、图片、简单表格、嵌套目录、离线点词和位置保存。基础版本曾通过 28 项宿主测试及双平台构建，并覆盖升级两端模拟器、核对 iPhone 数据保留。后续 SVG 修复已通过 32 项测试、静态分析与双平台构建，但修复版尚未覆盖安装。

安卓原生 EPUB 样本导入、图片/表格、气泡停留、目录及重开位置已获用户“四项全部正常”确认；iPhone 同样已确认能进入正文且其余三项全部正常，两端当前 EPUB 样本验收关闭；真实 EPUB 教材和部分视觉项目仍待验收。iPad 当前只有通用工程及平板横屏组件测试；iPad 设备验收、左右翻页/横屏双页、翻译、生词本等尚未完成。

**最新准确断点、成果、失败现象与下一步命令请先读 [HANDOFF-WIP.md](HANDOFF-WIP.md)。** 用户要求每轮只完成一个可验证的小步骤，完成后立即按八项结构总结，接近限制或中断前再次更新。安卓该项验收已关闭；两端样本均已通过，用户提供的真实小说已完成逐块解析/目录对照，缺陷见 [真实 EPUB 报告](docs/real-epub-compatibility.md)；安卓原生阅读已获用户“全部正常”确认；SVG 封面修复已实现，32/32 宿主测试、静态分析及双平台构建通过，安卓构建本轮补齐；唯一下一步是脚注链接/锚点解析模型。两端已安装 App 尚未更新，新封面原生视觉未验收；其余步骤列入整体计划。最新规则见 `AGENTS.md`。

## 环境

使用 `./scripts/flutterw`。设备调试可用 `READING_PROXY_URL=''` 清除该进程代理（下载依赖仍使用默认代理）；安卓连接仍有间歇不稳定，详见临时快照。本地代理 `127.0.0.1:7897` 须可用；NO_PROXY 包含 localhost,127.0.0.1,::1。Gradle 用户配置已单独使用相同代理。

## 未关闭

- 用户可测试的 iPhone/iPad/Android 型号、系统版本尚未提供；不阻塞阶段 2。
- 原型 UI 自动化的页面状态与截图不一致，未声称通过双页/气泡视觉验收。
- 系统翻译、语言模型下载、Wiktionary、MDX、PDF 未实现；在后续阶段处理。
- 教材范围已确认：文字、图片、简单表格。

## 参考

- Apple Translation: https://developer.apple.com/documentation/translation/translating-text-within-your-app
- ML Kit 模型安装方式: https://developers.google.com/ml-kit/tips/installation-paths
- ECDICT: https://github.com/skywind3000/ECDICT
