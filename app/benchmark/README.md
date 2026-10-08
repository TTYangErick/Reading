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
- 单段探针对照TextPaginator当前调用，分别计量layout、line metrics、grapheme边界、getPositionForOffset、getLineBoundary和簇起点二分查找；不替代生产管线，探针各阶段不能机械相加等同整书耗时。
- 每个实际分页样本计时外检查文字/图注范围连续完整、图片可用与数量、表格行不重复/不缺失、章节起页、抽样源锚点和JSON不变。
- 不覆盖：SQLite/磁盘、EPUB导入、路由动画、正文Widget构建/栅格、真实图像解码显示、首次词典解压和峰值内存。混排预检很快不代表真实大图磁盘读取也很快。

## 2026-10-08 基线（历史测量，非当前验收状态）

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
