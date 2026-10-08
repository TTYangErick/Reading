# 外部文件导入契约

Reading 支持 EPUB 2/3 和 TXT；现有书架文件选择、粘贴文本入口保持。正文/脚注/目录/资源和源位置规则沿用 [阅读契约](epub-links.md)，存储无需迁移。

## 系统入口

- iPhone/iPad：注册 EPUB `org.idpf.epub-container` 与 TXT `public.plain-text` 文档类型，接收文件 App 或其他提供文件的 App 的“用 Reading 打开”。SceneDelegate 覆盖冷启动与已运行时的文件 URL；关闭 Flutter 默认深链接路由，避免文件路径成为页面路由。使用 security-scoped 访问与 NSFileCoordinator，只读复制，不修改原文件。
- Android：接收 `ACTION_VIEW` 的 `content://` EPUB/TXT 和 `ACTION_SEND` 单文件（EXTRA_STREAM 或单项 ClipData）。分享 MIME 为 EPUB、纯文本或通用二进制；二进制仍须文件名是 `.epub`/`.txt`。打开入口仅声明 EPUB/纯文本，避免抢占所有二进制文件。缺扩展名时，仅可信的已知 MIME 可补扩展名；明确不支持的扩展名不会被 MIME 覆盖。拒绝 `file://`，不增加存储权限。冷启动与 onNewIntent 都接入，Activity 恢复不重复接收旧 Intent。
- 首版不包含 iOS Share Extension、批量文件、分享网页/网络下载或纯文字 EXTRA_TEXT；纯文字沿用粘贴入口。来源 App 必须交付可读取的文件和必要权限；系统是否显示入口取决于它交付的类型。

## 交互与数据边界

收到文件后只显示书架待导入卡片，包含文件名、“导入”和“忽略”。接收中不可导入；接收失败/不支持/超限展示说明并可忽略。用户确认导入后才解析并事务入库，成功清理私有临时副本并打开新书。解析/入库失败不插入部分书籍，副本保留供用户忽略或重试。

正在阅读、查看设置或操作备份时不会自动跳转、弹出导入对话框或写入书库；返回书架再处理。确认导入后至打开的书返回期间，共用 importing 状态锁住书架操作，避免重复导入或进入备份恢复。接收另一本书不会改当前书的正文位置、样式或返回栈。相同文件再次主动分享是独立请求；同一请求的重复桥接通知不会生成第二份卡片或自动入库。首版不按书籍内容去重。

待处理文件与临时副本只在当前进程保存；不纳入备份，进程结束/系统回收后可重新分享。下次进程启动清理自有暂存目录，不触碰书库、用户原文件或系统词库。临时目录亦可能被系统清理，此时提示重新分享。

开启启动续读时，已有待导入项优先，自动导航前刷新快照；平台状态暂无法确认也留在书架。导航已完成后到达的文件继续等待，不跳走。细节见 [启动契约](startup.md)。

## 资源限制

- 最多4份正在复制/等待确认的文件，以及1条合并的队列已满提示。忽略正在复制的文件会标记取消，但复制任务退出前继续占用名额，避免通过反复取消制造无界工作队列。
- TXT最多20MiB、EPUB最多50MiB。原生复制先检查来源声明长度，再按64KiB块核对实际累计字节；来源未知/不实长度也不能绕过限制。Flutter解析前再按流检查实际大小；复用原解析器的压缩包、正文、图片等限制。
- 原生串行执行文件IO，不在界面线程读取整本书；Flutter在compute执行读取和解析。安全文件名仅用于显示/选解析器，暂存路径使用随机ID，不拼接外部路径或文件名。
- 忽略、成功、复制失败会尽力删除自有副本；复制取消会在读取块之间检查并清理。来源提供器自身阻塞时，取消要等其读操作返回，不承诺系统提供器超时。队列容量仍受限，未做后台下载/跨进程可靠投递。

## 桥接接口与验证

`dev.reading/imports`：`pending` 返回快照数组 `{id,name,ready,path?,error?}`；`release(id)` 释放；原生 `changed` 通知 Flutter 重新拉取快照。错误码 `unsupported/tooLarge/unreadable/queueFull` 由 Flutter映射成提示。路径仅指向应用自有暂存文件。Flutter拉取使用版本防止旧异步快照覆盖新状态；无手机插件的宿主保持原有导入可用。

`app/test/import_inbox_test.dart` 验证快照/通知、乱序、释放失败、销毁、宿主缺插件、状态操作与实际大小限制；`external_import_flow_test.dart` 使用实际文件、compute、内存SQLite和阅读/备份页面验证确认、忽略、坏文件与等待行为。EPUB结果与原解析器的正文JSON、脚注链接和资源逐一比较；既有 `file_import_test.dart` 继续覆盖文件选择入口。

宿主模拟消息与两端构建不能证明系统真实投递及权限生命周期。集中真机验收须分别验证：冷启动/已打开书架/阅读中接收、文件提供器授权、忽略/超限/失败后再分享，核对旧书与位置。待验状态只维护在 [PLAN](../PLAN.md)。

平台依据：[Android接收分享](https://developer.android.com/develop/ui/compose/sharing/receive)、[Apple Scene URL回调](https://developer.apple.com/documentation/uikit/uiscenedelegate/scene(_:openurlcontexts:))、[Apple原位打开文档](https://developer.apple.com/documentation/bundleresources/information-property-list/lssupportsopeningdocumentsinplace)。
