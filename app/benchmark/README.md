# 首次分页宿主诊断

按需运行，不属于默认 `test/` 全量测试；不安装设备、不打开用户书籍、不改生产分页代码。它提供同环境相对诊断，不是移动设备性能验收。当前任务和后续决策只维护在 [PLAN](../../PLAN.md)。

在 `app/` 目录：

```sh
../scripts/flutterw --version
READING_PROXY_URL='' READING_BENCHMARK_OUTPUT=../artifacts/pagination-baseline.json \
  ../scripts/flutterw test --no-pub benchmark/pagination_benchmark.dart --reporter expanded
```

默认3轮，可用 `--dart-define=BENCHMARK_RUNS=5` 设置1–10轮。报告路径可省略；逐样本JSON仍输出到日志。`artifacts/` 已忽略，不提交个人环境测量输出。比较前后版本时保持字体、样本版本、窗口、引擎及运行模式相同，不与并行构建/其他基准争用机器；计时不作硬阈值测试。

## 测量范围

- 固定样本版本1，打包Literata，默认ReaderStyle显式选该字体；手机内容视口390×700，双页每栏575×762（1194宽、44中缝）。均不模拟系统安全区，不使用不同平台默认字体来比较快慢。
- short：2章、每章100个355 UTF-16单元普通段落。novel：16章；double-novel：32章。mixed以novel为基础加80个图片块、8个不同资源路径和80张8行3列表格；PNG已在内存，640×480，每份2369字节。
- long-paragraphs与near-limit-paragraphs保留novel的正文章节/词量，分别将每50/100个段落以换行组合，形成17,799/35,599单元的长块。后者仍低于现有单段拒绝上限；组合改变段间距与物理页数，不用于页数等价断言。
- 先预热字体/引擎，轮转样本顺序；每次重新解码JSON并调用真实 `loadPaginationImageSizes` / `BookPaginator.paginateAsync`，阶段分别计时。这里“未缓存”指没有现成BookPagination，不代表冷启动、冷磁盘或引擎完全无内部缓存。
- 布局完成后用默认PaginationCache独立测写入和等值新源字符串的查询，明确记录是否接纳。缓存查询耗时不包含源读取/解码、锚点查找或首帧绘制；miss不能当作快速重开。
- 16ms真实Timer记录分页期间宿主事件循环最大间隔，含系统调度/GC；结束时计入最后未完成间隔。短任务可能没有心跳，间隔小于16ms不代表延迟或高帧率；报告不是Flutter帧耗时。
- 单段探针保留优化前TextPaginator的调用作为归因参考，分别计量layout、line metrics、grapheme边界、getPositionForOffset、getLineBoundary和簇起点二分查找；不替代生产管线，探针各阶段不能机械相加等同整书耗时。
- 每个实际分页样本计时外检查文字/图注范围连续完整、图片可用与数量、表格行不重复/不缺失、章节起页、抽样源锚点和JSON不变。
- 不覆盖：SQLite/磁盘、EPUB导入、路由动画、正文Widget构建/栅格、真实图像解码显示、首次词典解压和峰值内存。混排预检很快不代表真实大图磁盘读取也很快。

## 2026-10-08 优化前基线（历史测量，非当前验收状态）

生产源码基线a85835b；Flutter3.47.5 / engine af7e796e16 / Dart3.13.4，macOS26.6.1，Flutter test/JIT，3轮中位数，单位ms。36次实际管线和18次单段探针均完成；下表显示分页耗时，未将缓存查询混入。

| 样本 | 手机 | 双页每栏 | 默认缓存接纳（手机/双页） |
|---|---:|---:|---|
| short | 18.1 | 12.0 | 是/是 |
| novel | 132.9 | 96.1 | 是/是 |
| double-novel | 268.0 | 195.5 | 否/是 |
| mixed | 161.8 | 119.2 | 是/是 |
| long-paragraphs | 582.6 | 281.8 | 是/是 |
| near-limit-paragraphs | 1148.3 | 544.8 | 是/是 |

- 各组合的JSON解码中位数约0.16–2.06ms；内存图片预检约0.05–0.32ms。已接纳的缓存查询约0.005–0.073ms，仅表示查找本身。double-novel手机布局因默认留存预算拒绝，没有取消资源限制来美化结果。
- 手机单段探针：17,799单元/550行的getLineBoundary批量查询中位数14.1ms，layout2.2ms；35,599单元/1100行分别53.6ms与11.9ms。后者getPositionForOffset约1.85ms、grapheme约0.60ms、簇查找约0.073ms，支持优先检查逐行getLineBoundary的成本，而不是先改JSON或提高缓存上限。
- near-limit手机管线每轮最大心跳间隔的中位数90.3ms。这证明本宿主上的协作让出无法避免所有长间隔，不能直接换算为手机FPS，也未证明就是用户那本书的唯一原因。
- 结果支持下一步验证长段行边界查询的等价优化；是否有效须以同基准及Unicode/章节/位置回归证明，不能通过截短原文或拆坏段落换取速度。

## 2026-10-08 行边界优化后（历史测量）

沿用上述样本、引擎、3轮中位数与独立运行方式；生产改动只在pagination.dart。再次完成36次管线和18次旧调用归因探针；优化后真实耗时读管线字段，旧探针保留用于比较，不代表新算法还调用每行getLineBoundary。

| 样本 | 手机：优化前→后 ms | 双页每栏：优化前→后 ms |
|---|---:|---:|
| novel | 132.9→133.3 | 96.1→97.7 |
| mixed | 161.8→156.6 | 119.2→121.5 |
| long-paragraphs | 582.6→118.6 | 281.8→83.3 |
| near-limit-paragraphs | 1148.3→235.4 | 544.8→174.8 |

- 所有12个样本/尺寸组合的物理页数与缓存接纳结果相同；普通/短段及混排总耗时变化在约±4%内，不据此声称普通段落明显提速或退化。长段耗时下降约68–80%。near-limit手机最大宿主心跳间隔中位数90.3→30.1ms；仍不是帧率验收，也并未消除全部长间隔。
- 新增line_boundaries_test.dart以原TextPainter行边界与绘制几何作对照，覆盖72组固定文字/方向/样式/临界与种子混合字符组合。测试发现空行前含双向控制字符时，直接二分会与旧行合并不同；最终空行及相邻行沿用旧查询，保留源偏移和几何。测试不调用新的二分函数充当自己的预期。
- 优化未改变单段拒绝限制、缓存预算、数据JSON或渲染完整段落的规则。大书缓存拒绝和首次完整分页仍是已知限制，后续是否调整须另作资源/内存评估。

## GBK 测试运行时诊断

`gbk_runtime_probe.dart` / `gbk_runtime_probe_test.dart` 是按需运行的最小对照，不计量性能、不属于常规测试。两入口执行同一固定输入的编码、解码、GBK/UTF-8 TXT解析，不加载应用数据库、UI或词典；每个阶段先输出标记，原生崩溃时可从最后一行确定进度。它只覆盖这个输入和首次编码入口，不能证明所有GBK路径或运行时均无问题。

在app目录执行（`dart`应来自同一Flutter SDK）：

```sh
dart --version
../scripts/flutterw --version
dart --packages=.dart_tool/package_config.json benchmark/gbk_runtime_probe.dart
READING_PROXY_URL='' ../scripts/flutterw test benchmark/gbk_runtime_probe_test.dart --no-pub --reporter expanded
# 最小输入未复现后，按需对比原应用依赖组合
READING_PROXY_URL='' ../scripts/flutterw test test/core_test.dart test/import_inbox_test.dart test/file_import_test.dart --no-pub --reporter expanded
```

采样前固定次数，每次独立启动进程，保留全部日志/退出码和源码revision、SDK/engine/Dart、OS/架构；不要在同一进程内循环codec当作多次冷启动。失败时先停止并保存最后阶段、Dart错误栈或macOS `~/Library/Logs/DiagnosticReports/flutter_tester-*.ips`；比较报告中的触发线程、镜像UUID与本机引擎，而非只比较“SIGSEGV”字样。产物放忽略的artifacts，当前结果与未关闭风险只记PLAN。最小输入通过后仍可能依赖完整测试组合、加载时序或其他输入；必要时仅补一次原配置全量并用`--reporter json`保存逐项事件，失败后先采证，不重跑到绿。仍未复现也不关闭间歇崩溃，不以关闭断言、串行全量或盲目更新依赖掩盖问题。
