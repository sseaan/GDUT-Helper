# 工大助手（GDUT Helper）开发记录

> 本文合并了原 `PLAN.md` 与 M0–M6 阶段性文档，作为后续开发、发版和长期维护的统一入口。
> 应用名：**工大助手**；包名：`com.gduthelper.app`；当前版本：**1.1.0**。
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

### 当前发版状态

已完成：

- 应用名称、Logo、关于页、Q 群、AGPL-3.0 信息；
- 版本 `1.1.0`；
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
├── common/                           # 主题、标题栏、调色板、导航回调
├── components/                       # 课程 Sheet、底栏图标、圆形按钮
├── data/
│   ├── Database.ets                  # RDB v4
│   └── TimetableRepository.ets       # 学期/课程/异常/事件/墓碑
├── domain/
│   ├── agenda/AgendaEngine.ets       # 统一 Agenda
│   ├── model/                        # 数据模型、节次、SyncPlan
│   └── timetable/TimetableEngine.ets # 周次、展开、冲突
├── pages/                            # 五个 Tab 与二级页面
├── services/
│   ├── backup/                       # JSON v2 备份/恢复/清空
│   ├── importexport/                 # ICS/XLSX
│   ├── jxfw/                         # CAS、课表、成绩
│   ├── jwcwx/                        # 空教室
│   ├── tzcs/                         # 体测
│   ├── reminder/                     # ReminderAgent
│   ├── calendar/                     # 系统日历
│   ├── sync/                         # 同步策略与设置
│   └── widget/                       # 卡片快照
├── state/                            # TimetableState、外观、显示设置
└── resources/                        # 中文文案、图标、卡片配置
```

## 4. 数据层

RDB 名称：`gdut_helper.db`，当前 schema v4。

表：

- `semesters`：学期、开学日、总周数、教务学期代码、当前学期；
- `periods`：每学期 1–12 节时间；
- `courses`：课程、星期、节次、周次、颜色、授课内容、来源；
- `course_exceptions`：单周停课/调课，`source=MANUAL/SYNC`；
- `events`：日程/考试，`external_id` 去重；
- `course_tombstones`：用户删除的导入课程，防止同步复活。

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
- 课程内容 `sknrjj` 可选显示；
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
- 原生校园数据卡片：校园卡余额、图书借阅、校园网余额/状态，读取 ehall `CUS_CARD_MYDATA`；
- 校园新闻默认读取通知简讯网 `OA最新简讯`，完整页提供最新简讯/校内通知/公示公告/招标公告；
- 通知简讯列表接口不返回封面图，按需抓取 OAS 详情页正文首图做缩略图/大图；
- 校园数据卡片使用系统语义色，顶部跟随主题色，位于四张服务卡片下方；
- 新闻详情使用 App 内 WebView，详情页提供“在浏览器打开”原生按钮。

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

- 主题模式：跟随系统/浅色/深色；
- 主题色：鸿蒙蓝 / 广工红 / Goke绿（`#CDEBE3`，浅色表面自动使用深色前景）；
- 沉浸光感、光感强度（跟随系统/精致/柔和/流畅）、智感握姿开关；
- 关于页：Logo、版本、项目主页、QQ 群 `1103357499`、AGPL-3.0、致谢；
- 应用名统一为“工大助手”，根目录 `logo.png` 同步应用图标和关于页。

## 6. 接口与网络适配

详细端点、字段和样例见 [`docs/API_EXPLORATION.md`](docs/API_EXPLORATION.md)。
融合门户/校园新闻的卡片接口调研见 [`docs/PORTAL_DATA.md`](docs/PORTAL_DATA.md)。
图书馆 OPAC 的接口调研见 [`docs/LIBRARY_API.md`](docs/LIBRARY_API.md)。
界面/图标/沉浸光感的设计基线见 [`docs/DESIGN.md`](docs/DESIGN.md)。

关键适配：

- POST body 必须放 `extraData`；
- 302 用 `headersReceive` 捕获后手动跟随；
- `response.cookies` 为 Netscape cookie-file 格式；
- jwcwx 的 `http://` ticket 回调必须升级为 `https://`；
- CAS ticket 后还要请求 `/login/cas` 绑定服务端上下文，否则 `-403`；
- 统一错误分类：NETWORK/CREDENTIALS/CAPTCHA/SESSION/PROTOCOL。

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

### 已知阻塞

- **签名**：本地签名使用 DevEco 自动生成的调试证书，更换账号需在 DevEco 重新生成 Profile，证书持有者信息不写入仓库，详见 [`docs/SIGNING.md`](docs/SIGNING.md)。
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
- [x] 版本 `1.1.0`
- [x] 根目录 Logo 同步
- [x] 关于页/QQ 群/协议
- [x] 移除演示课程、自检页和测试文案
- [x] Debug HAP 构建
- [x] Release HAP 构建
- [x] 模拟器功能回归
- [x] 真机基础回归（登录/同步/课表/空教室/系统日历/卡片）
- [ ] DevEco 签名切换 Sseaan
- [ ] 真机通知权益/代理提醒复测
- [ ] 真实 XLSX 导入验证
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

- 外部接口变化只改 `services/{jxfw,jwcwx,tzcs}`，页面不直接拼请求；
- 新 UI 遵循 `common/Theme.ets` 语义色和 4vp 网格；
- 列表 `ForEach` key 必须包含影响内容的状态，避免跨月/跨日复用旧节点；
- 卡片数据通过快照文件传递，不使用主应用内存；
- 导入/恢复先预览，失败不污染数据库；
- 新增迁移必须提升 RDB/备份 schema 版本并保留旧版本读取路径；
- 不提交 `.sign/`、账号、Cookie、测试密码和真实成绩导出。
