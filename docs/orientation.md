# 阅读方向

入口：阅读设置 → 阅读方向。手机尺寸显示器可选跟随系统（默认）、竖屏、横屏。方向偏好适用于所有书籍，与“仅应用于这本书”的排版样式开关无关；不会新增顶部/底部控件或改变单/双页布局规则。

## 生效范围与位置

- 仅在ReaderPage阅读会话内向系统请求方向；嵌套正文引用/脚注持有独立会话，关闭某层不会解除下层阅读的设置。最后一个阅读页面销毁后请求恢复系统方向；阅读中的设置、查词、图片查看、目录等辅助页面沿用该会话。
- 请求串行执行，尚未执行的过期请求丢弃；正在执行的请求结束后再执行最新请求或退出重置，避免快速切换/退出留下旧方向。读取偏好较晚完成也不能重新锁定已退出页面。系统调用错误不阻断阅读，在阅读设置中给出重试。
- 旋转沿用既有窗口尺寸、分页重算及源锚点恢复；不把页码存为位置，不改正文JSON、源锚点或每书样式。仅方向设置不主动写入书籍位置；窗口变化后的正常进度保存仍由阅读器负责。

## 平台边界

- 以FlutterView实际显示器的逻辑短边判断，V1仅对小于600逻辑像素的iOS/Android显示器请求锁定。窗口尺寸不能冒充显示器尺寸：平板分屏缩成窄窗口仍显示“跟随系统”的说明，不提供无效选择；已有偏好保留，回到支持的显示器再应用。
- 这是保守的V1产品边界：iPad多任务开启时Flutter不保证方向锁定；本应用target API36，新版Android大屏会忽略方向限制。旧Android平板即使可能支持，也先统一跟随系统。不新增UIRequiresFullScreen，不禁用分屏、不设置大屏兼容性豁免；双页和窗口自适应保持原行为。用户可使用系统旋转锁定。
- 系统请求成功不等于物理旋转已完成，OS/设备策略仍可能影响实际行为；自动化只验证请求与生命周期，真实旋转、系统锁定、前后台和折叠/外接显示器行为须真机验证。官方依据：[Flutter setPreferredOrientations](https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html)、[Android方向与窗口适配](https://developer.android.com/develop/adaptive-apps/guides/app-orientation-aspect-ratio-resizability)。

## 存储、兼容与模块

- settings键`readingOrientationV1`，值`system`/`portrait`/`landscape`。缺失、未知值回退跟随系统；保存失败保留原偏好，保存中禁用重复操作。关闭设置面板不取消已开始的保存。
- 现有备份按普通settings记录包含此键；旧备份缺项回退跟随系统。整库恢复刷新偏好，不会在书架锁定方向；下次阅读才应用。无schema或备份版本迁移。
- `app/lib/orientation/orientation.dart`负责偏好、会话与系统请求；`settings.dart`负责设置UI。ReaderPage仅装配scope与设置组件，原ReaderSettings仍可独立使用。自动回归见orientation_test.dart、reader_links_test.dart、backup_test.dart及既有paged_reader_test.dart旋转/位置测试；当前验收状态只见PLAN.md。
