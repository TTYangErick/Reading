# Reading

中文交流。用户没有开发经验；工程工作由代理完成，用户负责体验反馈和真机操作。

开始任务时读取 `PLAN.md`、`HANDOFF.md`；需要完整需求时参考 `docs/original-plan.md`。原计划中的旧环境描述与本地状态冲突时，以 HANDOFF 和实际验证为准。

- 平台：Flutter iPhone、iPad、Android；不增加 macOS 产品。
- 保留 `prototype/reader.html` 作为视觉与交互参考，不将模拟数据当作真实能力。
- 首先完成阶段 2，再由用户体验验收后进入阶段 3。EPUB 是必需的后续功能；iPad 横屏双页必须实现。
- 教材范围：文字、图片、简单表格；公式与复杂固定版式暂不在范围内。
- 本地词典查词，无网络请求或收费 API；英汉阶段 2，Wiktionary、系统句子翻译阶段 3。
- 使用 Riverpod、drift，维护可替换的解析、语言、词典、翻译接口。
- 使用 `scripts/flutterw` 执行 Flutter 命令，它只给当前进程设置代理，不修改系统配置。
- 功能完成后运行相关测试、`flutter analyze`、iOS 模拟器和 Android 构建；记录真实结果和未通过项。
- 大词典源文件、生成数据库、编译产物不提交 Git。保留可重建脚本、来源版本、校验值和许可证。
- 每次交付更新 HANDOFF：完成内容、命令、测试证据、剩余问题。不要把尚未验收的阶段标成完成。
