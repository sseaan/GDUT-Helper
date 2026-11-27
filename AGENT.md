# 工大助手（GDUT Helper）开发记录

> 本文合并了原 `PLAN.md` 与 M0–M6 阶段性文档，作为后续开发、发版和长期维护的统一入口。
> 应用名：**工大助手**；包名：`com.gduthelper.app`；当前版本：**1.2.0**。
> 最低兼容：HarmonyOS 6.1.0(23)；当前测试环境：Mate 80 Pro Max 模拟器 / SGT-AL10 真机（API 26）。

## 1. 项目目标

工大助手是广东工业大学学生的本地优先校园助手：

- 原生登录教务，导入课表、考试和开学日期；
- 本地保存课表、日程、提醒和系统日历；
- 查询成绩/GPA、体测成绩和空教室；
- 支持 JSON 备份恢复、ICS 导出、ICS/XLSX 导入；
- 不依赖自建服务端，不在线同步账号数据。

核心原则：

1. 本地数据优先，网络失败不破坏已有数据；
2. 账号密码只进入系统安全存储；
3. 教务/体测/空教室接口与页面解耦；
4. 导入先预览、再确认，失败可回滚；
5. 测试数据和演示数据不进入正式版本。

## 2. 里程碑摘要

| 阶段 | 状态 | 主要结果 |
|---|---|---|
| M0 环境验证 | 完成 | Stage 工程、HDS、RDB、卡片、文件选择器、构建与签名基线 |
| M1 本地课表 | 完成 | 学期/课程/异常 RDB、周次引擎、课程编辑、五 Tab UI |
| M2 教务同步 | 完成 | 原生 CAS、自动重登、全量/按周同步、考试、墓碑、幂等 |
| M3 日历/提醒/卡片 | 核心完成 | Agenda、手动日程、系统日历、三张卡片、AutoSync |
| M4 校园服务 | 完成 | 成绩/GPA、体测 WebView 登录、空教室真实数据与缓存 |
| M5 数据迁移 | 完成 | JSON 备份恢复、ICS/XLSX 导入、数据与备份页面 |
| M6 维护/发版 | 1.1.0 发布准备 | 主题色/材质档位、本地通知、ICS 导出、unsigned CI、发版文档 |
| M7 选课助手 | 功能完成，待真实选课时段验证 | 课程查询、冲突预检、抢课队列、定时提交、运行日志 |
| M8 校园服务增强 | 真机验收通过 | 扫码入口、馆藏检索与书目详情、电费查询（Beta）、CalDAV 课表镜像、校园数据卡片改版 |

### 当前发版状态

> M8（扫码、馆藏检索、电费查询、CalDAV、校园数据卡片改版）已真机验收通过，
> 版本号已升到 `1.2.0 / 1002000`；发版产物仍是 **unsigned HAP**，不切换签名证书。

已完成：

- 应用名称、Logo、关于页、Q 群、AGPL-3.0 信息；
- 版本 `1.2.0`；
- 主要更新：三套主题色与光感强度、图书馆 OPAC、校园数据/新闻、ICS 导出、本地通知、unsigned HAP CI；
- Debug/Release HAP 构建；
- 模拟器完整功能回归；
- 真机登录、全量同步、课表、空教室、系统日历、今日卡片验证。

仍受外部条件阻塞：

- 真机签名需要切换到 **Sseaan** 的华为开发者账号/Profile；
- 代理提醒需要 Profile 开通 `reminder_capability`，当前真机返回 `1700002`；
- 真实 XLSX 文件尚未做端到端验证；
- 真机全量回归（通知、横竖屏、生命周期、卡片尺寸）仍需设备。

## 3. 工程结构

```text
entry/src/main/ets/
├── ability/EntryAbility.ets          # 主 Ability、前台刷新、主题恢复
├── auto/AutoSyncAbility.ets          # WorkScheduler 自动同步
├── card/                             # 卡片 ExtensionAbility 与三张卡片
├── common/                           # 主题、标题栏、调色板、导航回调、ISBN/URL 识别
├── components/                       # 课程 Sheet、底栏图标、圆形按钮
├── data/
│   ├── Database.ets                  # RDB v5
│   └── TimetableRepository.ets       # 学期/课程/异常/事件/墓碑
├── domain/
│   ├── agenda/AgendaEngine.ets       # 统一 Agenda
│   ├── model/                        # 数据模型、节次、SyncPlan
│   └── timetable/TimetableEngine.ets # 周次、展开、冲突
├── pages/                            # 五个 Tab 与二级页面
├── services/
│   ├── backup/                       # JSON v2 备份/恢复/清空（schema v5）
│   ├── importexport/                 # ICS/XLSX
│   ├── jxfw/                         # CAS、课表、成绩
│   ├── jwcwx/                        # 空教室
│   ├── caldav/                       # 课表镜像到自建 CalDAV（Radicale 等）
│   ├── electric/                     # 电精灵电表查询（Beta，第三方接口）
│   ├── library/                      # OPAC：借阅、馆藏检索
│   ├── scan/                         # 系统扫码器封装与结果分类
│   ├── tzcs/                         # 体测
│   ├── reminder/                     # ReminderAgent
│   ├── calendar/                     # 系统日历
│   ├── selection/                    # 选课：客户端、解析、时钟、引擎、持久化
│   ├── sync/                         # 同步策略与设置
│   └── widget/                       # 卡片快照
├── state/                            # TimetableState、SelectionState、外观、显示设置
└── resources/                        # 中文文案、图标、卡片配置
```

## 4. 数据层

RDB 名称：`gdut_helper.db`，当前 schema v5。

表：

- `semesters`：学期、开学日、总周数、教务学期代码、当前学期；
- `periods`：每学期 1–12 节时间；
- `courses`：课程、星期、节次、周次、颜色、授课内容、来源；
- `course_exceptions`：单周停课/调课，`source=MANUAL/SYNC`；
- `events`：日程/考试，`external_id` 去重；
- `course_tombstones`：用户删除的导入课程，防止同步复活；
- `selection_task`：选课任务（单行，id=1）：开始时间、间隔、优先模式、自动重试、成功后同步；
- `selection_queue`：抢课队列，`kcrwdm` 唯一，保存位置、状态、尝试次数；
- `selection_logs`：运行日志，保留最近 600 条。

课程来源：

- `MANUAL`：手动课程；
- `IMPORT`：教务同步课程；
- `XLSX`：文件导入课程。

确定性课程 ID：

```text
jxfw:<term>:<kcrwdm>-<weekday>-<start>-<end>
```

必须包含时段，否则同一课程任务的多时段会被合并。

## 5. 功能实现

### 5.1 教务登录与同步

- 原生 CAS 登录，不使用 WebView；
- 密码 AES-128-CBC/PKCS7 加密；
- 账号密码存 Asset Store（`gdut_helper_jxfw_account`）；
- 登录后从 `xjkpxx`/欢迎页抓取学生姓名，失败时可在“我的”手动编辑；
- 同步页直接选择当前学期及前后各一学期，预览后自动创建/切换本地学期，无需先手动建学期；
- 会话失效自动登录并重试；
- 全量同步分 `preview` / `apply`，预览不写库；
- 二次同步幂等；用户删除的导入课程写墓碑；
- 按周同步按“课程名 + 星期 + 节次”匹配，保留手动停课/调课；
- 课程内容 `sknrjj` 可选显示；授课内容只在「按周课表」接口稳定返回，
  全量同步依次抓 本周 → 下周 → 上周 → 第 1 周，按课程名+星期+节次（可退让到重叠/同名唯一）匹配，
  取第一个非空值；本周内容变化时同步更新本地 `content`；
- 课程详情 Sheet 始终显示「授课内容」字段，教务没给内容时显示“教务未提供”；
- 颜色按课程名排序分配 12 色。

### 5.2 课表/日历

- 周一至周日网格，1–12 节；
- 周切换按钮 30×30，内容整体下移；
- 已结束课程淡灰显示（课表、今日、日历统一判断）；
- 课程展示名去掉末尾的 `（1）` 等班级序号，存储名保持不变以稳定同步匹配；
- 课程 Sheet：X 关闭、编辑、停课、调课、补课；
- 日历月/周视图，月视图课程蓝点、考试红点；
- 月视图 `ForEach` key 含月份/日期/数据数量，避免跨月复用旧格子；
- Agenda 统一课程、考试、日程。

### 5.3 成绩、体测、空教室

- 成绩：分页拉取、学期/类别筛选、GPA 汇总、缓存；
- 体测：WebView 官方登录 + 抓取 Cookie + 原生成绩页；
- 空教室：
  - 校区/教学楼搜索与选择；
  - 周次/日期/节次筛选；
  - 教学楼、教室、占用缓存；
  - 点击教室打开周课表 Sheet；
  - 灰色空闲、淡蓝课程、红色个人占用；
  - 番禺/揭阳校区可见；
  - jwcwx 字段 null-safe。

### 5.4 校园页
- 校园页只保留校园新闻与服务卡片：成绩、体测、空教室、更多服务（2×2）；
- 「更多服务」页：顶部为校园数据卡片，下面是选课助手、图书馆卡片（与成绩/空教室同一 `serviceCard` 样式）；
- 选课入口受功能设置里的「选课助手」开关控制（`selectionEnabled`，默认开）；
- 原生校园数据卡片：校园卡余额、图书借阅、校园网余额/状态，读取 ehall `CUS_CARD_MYDATA`；
- 校园新闻默认读取通知简讯网 `OA最新简讯`，完整页提供最新简讯/校内通知/公示公告/招标公告；
- 通知简讯列表接口不返回封面图，按需抓取 OAS 详情页正文首图做缩略图/大图；
- 校园数据卡片：三列数字（校园卡/图书借阅/校园网），一层卡片底 + 两条细分隔线，
  标题行坐在页面背景上（可点刷新/登录）；数值用正文色、占位值用三级色，不用装饰色条；
- 新闻详情使用 App 内 WebView，详情页提供“在浏览器打开”原生按钮。

### 5.4.1 选课助手

- 入口：校园页 →「更多服务」→「选课助手」，两个页面：选课列表（`selection`）、抢课任务（`selection-task`）；
- 列表：`xsxklist!getDataList.action` 分页 + 课程名搜索，显示容量/已选/余量；
- 详情 Sheet：`xsxklist!getJxrlDataList.action` 按（星期, 节次, 地点）归并周次，并用 `expandWeek` 与本地课表做冲突预检；
- 队列：去重、排序、移除；`kcrwdm` 为提交键；
- 抢课引擎（`SelectionEngine`）：静态单例 + AppStorage 快照，页面退出不影响运行；
  - 用响应头 `Date` 做服务器时钟校准（3 次采样取最小 RTT），按服务器时间到点触发；
  - 分段休眠 + 末段 60ms 忙等，避免 `setTimeout` 漂移；
  - 单线程顺序提交，间隔下限 300ms；按返回文案分类：满员继续、冲突/超限终止该门、已选视为成功、
    连续 20 次“不是选课时间”终止、连续 8 次网络失败终止、连续 6 次未知结果终止；
  - 硬上限：单次 30 分钟 / 2400 次请求；
  - 运行中保持屏幕常亮（`setWindowKeepScreenOn`），退后台申请短时任务（单次 ≤3 分钟）；
  - 成功后本地通知，可选自动 `TimetableSyncService.fullSync`；
  - 进程被杀后由 `SelectionRepository.markInterrupted` 把 ARMED/RUNNING 收敛为 STOPPED。
- 不实现：后台/锁屏静默抢课（HarmonyOS 无合法的精确定时长任务）、多账号、并发请求。

### 5.4.2 图书馆与扫码

图书馆：

- `LibraryPage`（`library`）：顶部常驻搜索栏（书名/作者/ISBN）+ 当前借阅与可借额度；
  借阅部分走 CAS → `jwt` 会话，搜索栏走匿名公开目录，不登录也能用；
- 搜索栏输入后点「检索」（或回车）→ `library-search` 带关键字入栈，进去直接出结果；
- `LibrarySearchPage`（`library-search`）：馆藏检索，五字段切换（全部/书名/作者/索书号/ISBN）+ 排序菜单 + 无限滚动 + 最近检索；
- `LibraryBookPage`（`library-book`）：题录 + 摘要 + 按馆藏地分组的册信息；书目对象由路由参数传入，不再重拉；
- 检索与册信息走 OPAC 公开目录（`/find/unify/search`、`/find/physical/groupitems`），
  **不需要统一认证会话**，所以不登录也能查书；借阅列表仍需登录；
- 检索请求体的 `docCode` 必须是 `[null]`，`["2"]` 会返回 0 条；字段集不完整会被服务端当作会话问题（`errCode 9999`）；
- 排序只用 `relevance` / `title_sort` / `publishYear`：`publishTime` 直接返 0 条，`onlyOnShelf` 传布尔值也返 0 条；
- 检索结果在 `LibraryClient` 里做 5 分钟内存缓存（最多 8 条），不落盘。

扫码：

- 入口：「我的」tab 标题栏右侧的扫码图标（`sys.symbol.barcode_viewfinder`），由 `Index.rootTitleBar()` 在 `currentTab === 4` 时注入；
- **不能把控件画在标题栏高度范围内**：HDS 标题栏是带系统材质 + 渐变模糊的覆盖层，内容放进去会被糊掉；
  也不能画在紧贴标题栏的内容区，会变成孤立悬浮块；只能进 HDS 的 `menu` 槽位；
- **`menu` 必须每次下发**（`common/TitleBarOptions.immersiveTitleBar`）：HDS 对 titleBar 选项做增量应用，
  不下发 `menu` 时会保留上一个 tab 的动作，导致图标漏到其他页面并遮住内容；空数组也会清掉；
- `ScanService` 调 `scanBarcode.startScanForResult()` 系统默认 UI：**不申请 `CAMERA` 权限**，应用不接触摄像头帧；
- `ScanDispatcher` 分三类：`http(s)`/`www.` → 系统浏览器；校验位通过的 ISBN-10/13 → `library-search`；
  其余 → 弹窗提供「复制 / 在浏览器搜索 / 取消」；
- ISBN 校验、URL 识别集中在 `common/Identifiers.ets`，无 UI 依赖，可直接用 node 跑用例；
- 模拟器无相机，扫码只能在真机验证；无 ScanBarcode syscap 时返回「当前设备不支持扫码」。

### 5.4.3 电费查询（Beta）

- 数据源是电表服务商站点 `bd.bdfairy.cn`（电精灵）；Beta 阶段，接口可能随时调整，读数仅供参考；
- 开关 `electricityEnabled` 默认关闭，在「功能设置 → 校园」里开启，开启前弹免责声明，取消则回滚开关；
- 卡片在「更多服务」第二位，带 Beta 角标，受开关控制；页面 Beta 标记与校区标签同行右对齐
  （标题栏是材质覆盖层，放进去会被糊掉，所以不进标题栏）；
- 链路全部走免登录会话（`connect.sid`）：

```text
POST /selectarea          # 选校，同时下发 connect.sid；band="1" 或 data=selectmeter 表示会话已绑房
POST /phonejcbd           # 已绑房时先解绑，否则 /selectmeter 常回错误页
POST /selectmeter         # {comAddress, hidType:"电表"} → {url:"/meter_main"}
GET  /meter_main          # 读数页（HTML），读 const yffye = ref('17.07')
GET  /electricbill        # 月账单（可选），读 billData 里的 ydl/ydje
```

- 三个校区 areaId：`54` 大学城/东风路/龙洞、`136` 番禺、`128` 揭阳；
- **校区选错不会报错，而是 `/meter_main` 直接挂住**（实测同一表号：136 约 2s 返回，54 二十余秒零字节）。
  因此 `PowerPage` 先按当前校区查，超时/失败后自动回退其余校区，命中后把校区一起记住并提示已切换；
- 表号在**发起请求前**就落盘，查询失败也不会丢；读数解析对真实页面验证过（`yffye/zye/bzdye/zydl/dbzt/cbsj`）；
- 月账单页的 `billData` 要定位到 `billData = ref({...})` 赋值语句，模板里还有 `{{ billData.qcdl }}`；
  站点给的是上一个结算月（11 月查到的 `month` 是 `2026-10`），所以卡片标题用「月账单」而不是「本月用电」；
- **不要先访问 `GET /?id=`**：那一步 302 到微信 OAuth，`maxRedirects: 0` 在设备上可能直接抛
  `2300047`，跟随又会卡在微信域名；实测 `POST /selectarea` 自己就下发 `connect.sid`，入口请求整段省略；
- Cookie 手写维护：`HttpRequest.enableAutoCookie()` 是 API 26 的能力，项目最低兼容 API 23；
  `response.cookies` 是 Netscape 格式，为空时退回 `Set-Cookie` 响应头，按 domain 过滤后自己拼 `Cookie` 头；
  没有 Cookie 时 `/meter_main` 返回 HTTP 500 + `errorApp`，所以这一步不能省；
- 读数是服务端渲染的 Vue 模板，没有 JSON 接口，`ElectricParser` 只抽 `ref('...')` 与 `billData` 的键值对；
  站点改模板就会解析失败，页面给「没读到读数」而不是静默显示空值；
- **无效表号在该站点上通常表现为无响应**，所以超时压到 6s/12s、只重试一次，文案提示「表号可能有误」；
- 明文 HTTP：`networkSecurity.isCleartextPermitted()` 默认允许，项目已有 tzcs 走 `http://` 的先例；
- 隐私：只在本机记上次的校区与表号（`electric_settings`），**余额不落盘、不进备份**。

### 5.4.4 CalDAV 日历同步

- 单向镜像：把当前学期课表推到用户自己的 CalDAV 集合（Radicale / Nextcloud），入口在「数据与备份」；
- **一个事件一个资源**：Radicale 要求「一个资源一个组件」，整学期一个 ICS（多 VEVENT）会被 **400** 拒掉；
- 资源名 `gdut-<stableHash(uid)>.ics`，UID 后缀用 `@gdut-helper-caldav`，
  与 ICS 导出的 `@gdut-helper` 区分开——否则用户把导出的 ICS 导入同一日历时，UID 冲突会让每次 PUT 都 409；
- 本地索引 `filesDir/caldav_index.json`（`uid / name / hash`）：
  - 只推新增和内容变化的，没变化的一次请求都不发；
  - 已消失的事件按索引逐条 DELETE，换学期/删课自然收敛；
- 指纹 `common/StableHash` 基于去掉 `DTSTAMP` 的正文，否则每次构建都会判定为「变了」而全量重推；
- 并发 3 个 PUT；**先上传后删除**，中途失败时宁可短暂重复，也不要把远端日历删空；
- 平台限制：`http.RequestMethod` 没有 `PROPFIND / REPORT / MKCALENDAR`，所以不做发现、不建日历，
  地址由用户从日历客户端复制；写入侧只需要 `PUT / DELETE / HEAD`，够用；
- 触发：设置页「立即推送」+ 教务全量同步成功后自动（`CalDavSyncService.pushIfEnabled`，失败静默）；
- 隐私：集合地址/用户名/开关进 Preferences，密码只进 Asset Store，推送到哪由用户自己填。

### 5.5 提醒、系统日历、卡片

- ReminderAgent 课程提前 10 分钟、考试提前 30 分钟，最多 24 条；
- 失败回滚开关并提示改用系统日历；
- 即时本地通知：`LocalNotificationService` 使用 `notificationManager`，同步完成时推送，不依赖代理提醒能力；
- 系统日历写入未来 21 天事件，最多 80 条，ID 去重；标题为课程/日程名，备注为 `地点 · 教师 · GDUT Helper`；
- 三张卡片：今日课程、下一节课、本周课表；
- 卡片进程读取 `filesDir/widget_today.json`；
- 卡片必须使用 `@LocalStorageProp`；
- `TodayCardAbility.onUpdateForm` 重新生成快照，解决日期/数据不更新。

### 5.5 数据迁移

JSON v2：

- SHA-256 checksum；
- v1 兼容；
- 包含学期、节次、课程、异常、事件、墓碑、成绩/体测缓存、偏好；
- 不含密码、Cookie、Token、验证码、系统日历映射；
- 恢复前预览；RDB 事务失败回滚；恢复后清理旧系统日历/提醒。

ICS：

- VEVENT、折行、DTSTART/DTEND、LOCATION、DESCRIPTION、UID；
- `STATUS:CANCELLED` 跳过；`DURATION` 支持；
- UID 去重；导入事件 `source=ICS`；
- 导出：当前学期展开为 ICS，含课程/考试/日程，Asia/Shanghai，VALARM；

XLSX：

- zlib 解压；
- sharedStrings + sheet 解析；
- 课程名/星期/节次/周次/教室/教师表头；
- 单双周、区间、连续节次合并；
- 15MB/5000 行保护；
- 导入课程 `source=XLSX`，不参与教务同步清理。

清空本地数据：

- 删除学期、课程、异常、事件、墓碑、成绩/体测/空教室缓存、卡片快照；
- 清理系统日历和提醒；
- 保留登录账号、外观/显示偏好和权限状态。

### 5.6 外观与关于

- 功能设置：课表授课内容、本地通知、测试通知、校园数据、校园新闻、选课助手；
- 主题模式：跟随系统/浅色/深色；
- 主题色：鸿蒙蓝 / 广工红 / Goke绿（`#CDEBE3`，浅色表面自动使用深色前景）；
- 沉浸光感、光感强度（跟随系统/精致/柔和/流畅）、智感握姿开关；
- 关于页：Logo、版本、项目主页、QQ 群 `1103357499`、AGPL-3.0、致谢；
- 应用名统一为“工大助手”，根目录 `logo.png` 同步应用图标和关于页。

## 6. 接口与网络适配

详细端点、字段和样例见 [`docs/API_EXPLORATION.md`](docs/API_EXPLORATION.md)。
融合门户/校园新闻的卡片接口调研见 [`docs/PORTAL_DATA.md`](docs/PORTAL_DATA.md)。
图书馆 OPAC 的接口调研见 [`docs/LIBRARY_API.md`](docs/LIBRARY_API.md)。
电精灵电表查询的链路与坑见 [`docs/ELECTRICITY.md`](docs/ELECTRICITY.md)。
CalDAV / Radicale 的实测矩阵与实现约定见 [`docs/CALDAV.md`](docs/CALDAV.md)。
界面/图标/沉浸光感的设计基线见 [`docs/DESIGN.md`](docs/DESIGN.md)。

关键适配：

- POST body 必须放 `extraData`；
- 302 用 `headersReceive` 捕获后手动跟随；
- `response.cookies` 为 Netscape cookie-file 格式；
- jwcwx 的 `http://` ticket 回调必须升级为 `https://`；
- CAS ticket 后还要请求 `/login/cas` 绑定服务端上下文，否则 `-403`；
- 统一错误分类：NETWORK/CREDENTIALS/CAPTCHA/SESSION/PROTOCOL；
- 选课接口未登录同样返回 200 + 登录页，需按页面内容判定会话失效；
- 第三方站点可能只支持明文 `http://`（电精灵），默认允许，但要在隐私声明里写明；
- CalDAV 写入只依赖 `PUT`/`DELETE`/`HEAD`：`PROPFIND`/`REPORT`/`MKCALENDAR` 平台没有；
- Radicale 一个资源只允许一个组件、集合内 UID 唯一，整学期一个 ICS 会被 400 拒掉；
- 门户一次会话要 4 跳（列表 + 3 张详情卡），详情卡并发取，首屏先用缓存铺一屏。

## 7. 测试记录

### 模拟器

- 学期、课表、日历、空教室、成绩、体测、备份页面；
- `Life.ics`：2 个事件预览并成功导入；
- JSON 导出、v1 恢复、v2 校验；
- 12 月日历日期/星期、考试红点；
- 番禺校区 19 间教室；
- 清空数据成功；
- 课程卡 X 关闭、周切换、已结束课程淡灰。

### 真机 SGT-AL10

- 全新安装、创建学期；
- 教务登录成功；
- 全量同步 25 门课程、4 场考试；
- 二次同步 `+0 / 更新 0 / 移除 0`；
- 今日/课表/空教室真实数据；
- 系统日历写入 `[GDUT]` 事件；
- 今日卡片添加到桌面；
- 进程重启后首次同步自动登录。

### M8 回归（真机验收通过）

- 我的页标题栏扫码：URL → 浏览器、ISBN → 馆藏检索、其它文本 → 复制/搜索弹窗；
- 馆藏检索：五个字段、排序菜单、无限滚动、最近检索、书目详情按馆藏地分组；
- 电费查询：番禺校区 `areaId 136` 真实表号查询成功，余额/账单/抄表时间解析正确，
  跨校区自动回退与表号记忆正常；
- CalDAV：Radicale 单事件资源建/改/删、增量推送、清空远端；
- 校园数据卡片：三列数字随数据刷新（不再卡在首帧 `--`）。

### 已知阻塞

- **签名**：发版产物是 **unsigned HAP**，不再切换签名证书；本地签名使用 DevEco 自动生成的调试证书，仅用于侧载调试，
  不随发布包分发，详见 [`docs/SIGNING.md`](docs/SIGNING.md)。
- **代理提醒**：当前 Debug Profile 未开通代理提醒权益，`publishReminder` 返回 `1700002` / `notification not allowed`；系统日历提醒可用。
- **真实 XLSX**：解析器已实现，缺少真实文件端到端验证。
- **真机全量回归**：通知、横竖屏、生命周期、卡片尺寸、文件选择器仍需真机。

### GitHub Actions

- `.github/workflows/build-unsigned.yml`：push/PR/手动触发；
- 使用 `ErBWs/setup-ohos@v2` 安装 HarmonyOS SDK；
- CI 中移除 `signingConfig`，构建 unsigned HAP 并上传 Artifact；
- 不注入证书/密码；ArtiFact 为 unsigned HAP，侧载前需用本地 DevEco/自动签名重新签名，直接 `hdc install` 会报 `9568332`。

## 8. 发版检查清单

- [x] 应用名“工大助手”
- [x] 版本 `1.2.0`
- [x] 根目录 Logo 同步
- [x] 关于页/QQ 群/协议
- [x] 移除演示课程、自检页和测试文案
- [x] Debug HAP 构建
- [x] Release HAP 构建
- [x] 模拟器功能回归
- [x] 真机基础回归（登录/同步/课表/空教室/系统日历/卡片）
- [ ] 真机通知权益/代理提醒复测
- [ ] 真实 XLSX 导入验证
- [ ] 真实选课时段验证选课列表 / 提交 / 错误文案（当前仅在非选课时间验证过连通性）
- [x] 真机验证扫码：系统扫码 UI、我的页标题栏图标位置、其他 tab 不再出现图标、ISBN→馆藏、URL→浏览器、其他→弹窗
- [x] 真机验证馆藏检索：字段切换、排序菜单、无限滚动、最近检索、书目详情分组、在浏览器打开
- [x] 真机验证电费查询：开关免责弹窗、卡片显隐、真实表号读数解析、跨校区回退
- [x] 真机验证 CalDAV：增量推送、清空远端、错误文案
- [ ] CalDAV 首推 ~388 个事件的耗时（并发 3）与 Nextcloud/Baikal 兼容性
- [ ] 电费查询的无效表号超时体验（当前 3 校区回退约 24s）
- [ ] 真机横竖屏/生命周期/文件选择器全量回归
- [ ] 最终 Release 签名包与隐私说明发布

构建命令：

```bash
./scripts/build-debug.sh          # Debug
./scripts/build-debug.sh release  # Release
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`。

## 9. 隐私与安全

- 密码只存系统 Asset Store；
- 密码、Cookie、Token、验证码不进入日志、RDB、Preferences 或备份；
- 文件通过系统选择器访问，不申请宽泛存储权限；
- 备份不含系统日历映射和登录凭据；
- 详细说明见 [`docs/PRIVACY.md`](docs/PRIVACY.md)。

## 10. 维护约定

- 外部接口变化只改 `services/{jxfw,jwcwx,tzcs,selection}`，页面不直接拼请求；
- 新 UI 遵循 `common/Theme.ets` 语义色和 4vp 网格；
- 列表 `ForEach` key 必须包含影响内容的状态，避免跨月/跨日复用旧节点；
- 课程/日程列表用 `common/RenderKey.contentSignature()` 把名称、地点、教师、节次、颜色、已结束状态拼进 key，
  否则编辑课程后列表沿用旧节点不刷新；
- 卡片数据通过快照文件传递，不使用主应用内存；
- 导入/恢复先预览，失败不污染数据库；
- 新增迁移必须提升 RDB/备份 schema 版本并保留旧版本读取路径；
- **多参数 `@Builder` 是按值传递**，参数变化不会触发重绘：异步到达的数据一律用独立组件的 `@Prop`，
  否则界面会卡在首帧的占位值（`--`）；
- HDS 标题栏对 `titleBar` 选项做增量应用：**`menu` 每次都要下发**（空数组即清空），
  否则上一个 tab 的动作会漏到其它页面；标题栏是带材质的覆盖层，别把控件画进它的高度范围；
- 镜像类数据（余额、电表读数、邮件类内容）不落盘、不进备份；只允许保存「地址/账号/上次状态」，
  密码统一进 Asset Store；
- 外部接口变化只改 `services/{jxfw,jwcwx,tzcs,selection,library,portal,electric,caldav}`。
