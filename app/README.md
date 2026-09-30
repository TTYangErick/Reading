# Reading Flutter App

当前实现阶段 2：英语 TXT／粘贴导入、书架、本地查词、滚动阅读、样式和段落位置保存。
完整执行状态和验收结果见上层 `HANDOFF.md`；原计划见 `../docs/original-plan.md`。

## 重建与运行

从 Reading 根目录执行：

```sh
python3 scripts/fetch_assets.py
python3 dict_builder/build_ecdict.py
cd app
../scripts/flutterw pub get
READING_PROXY_URL='' ../scripts/flutterw run --no-pub
```

词典 CSV 与生成的 SQLite 不纳入 Git；`dict_builder/source.json` 固定 ECDICT 版本及 SHA-256，`assets/dictionaries/manifest.json` 记录数据库版本、行数、校验值。字体文件及许可证已纳入 Git。无需付费 API 或联网查词。

`scripts/flutterw` 默认只给子进程配置本地代理 `127.0.0.1:7897`。可通过 `READING_PROXY_URL` 覆盖；设为空字符串可关闭。它不改变系统网络设置。

本机实测：下载依赖时需代理；安卓调试曾有间歇断连，代理并未被证实为唯一原因。最终双平台集成测试采用先正常 `pub get`，再用 `READING_PROXY_URL=''` 运行或执行设备集成测试的方式通过。空值会清除该子进程的大小写 HTTP/HTTPS/ALL_PROXY。Gradle 保留已有的下载代理配置。

## 验证

```sh
# Reading 根目录
python3 -m unittest discover -s tests -v
# app 目录
../scripts/flutterw analyze
../scripts/flutterw test --reporter expanded
READING_PROXY_URL='' ../scripts/flutterw test integration_test/reading_flow_test.dart -d <设备ID> --no-pub --reporter expanded
../scripts/flutterw build ios --simulator --debug
../scripts/flutterw build apk --debug
```

集成测试的业务数据使用临时数据库，但 `flutter test -d` 工具会重装/卸载测试应用：仅在专用模拟器运行，勿在已有真实书架的设备运行。测试覆盖真实词典、粘贴导入、气泡与复制、即时设置、跳转、销毁并重建 App/数据库后的位置恢复、书名搜索/修改/删除。

## 代码与数据

- `lib/book`：可替换 BookParser，UTF-8/GBK TXT 解析和章节检测。
- `lib/text`：LanguageSupport，英文点词范围、句子范围及候选词。
- `lib/dict`：DictionaryProvider，只读 SQLite ECDICT；词形与释义顺序查询。
- `lib/db`：drift 业务数据库，书架/正文/段落索引/设置；不修改词典包。
- `lib/reader`：懒加载段落、字形矩形定位、气泡、阅读设置。
- `lib/core`：Riverpod 依赖、平台沉浸模式。
- `lib/translate`：Translator 扩展接口。阶段 3 接入真实系统翻译，目前没有模拟译文。

数据仅保存在 App 的 Application Support 目录。卸载 App 会清除本地书架；跨设备备份在阶段 3 实施。

当前 TXT 单文件上限 20 MB。阅读位置精确到段落。滚动阅读是阶段 2 的中间形态；EPUB、翻页、iPad 双页、词汇本和翻译按阶段 3 继续完成。
