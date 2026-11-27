# 选课（抢课）功能可行性评估

> 评估对象：[GDUTMeow/gdut-course-grabber](https://github.com/GDUTMeow/gdut-course-grabber)（AGPL-3.0，Python + FastAPI + 网页 UI）
> 评估目标：在工大助手中以原生方式集成"选课/抢课"，判断可行性与落地路径。
> 结论时间：2026-11，协议实测环境 `jxfw.gdut.edu.cn`。

## 1. 结论

**协议层完全可行，平台层存在硬约束，产品形态必须收敛为"前台守着抢"。**

| 维度 | 判断 | 说明 |
|---|---|---|
| 接口可得性 | ✅ 可行 | 选课接口与现有课表/成绩同域同会话，无额外加密/CSRF 参数 |
| 与现有架构契合 | ✅ 高 | 复用 `JxfwClient` 会话、自动重登、错误分类、CAS 登录、RDB、通知 |
| 准点执行 | ⚠️ 受限 | 后台无合法的"精确定时长任务"，只能前台 + 常亮 + 短时任务兜底 |
| 实现成本 | 🟡 中 | 约 7–9 人日可交付 v1（公选课） |
| 合规/风控 | ⚠️ 中高 | 高频请求可能触发教务风控；应用市场对"抢课脚本"审核敏感 |
| 许可证 | ✅ 兼容 | 上游与本项目均为 AGPL-3.0；建议按协议重写而非复制代码 |

**推荐 v1 范围：本科公选课（`xsxklist` 模块）的查询 + 冲突预检 + 定时单线程抢课 + 前台保活 + 结果通知**；不做后台静默抢课、不做多账号、不做并发轰炸。

## 2. 上游方案拆解

### 2.1 协议（实测可用，未登录返回 200 + CAS 登录页）

| 功能 | 方法 | 端点 | 关键参数 |
|---|---|---|---|
| 可选课程列表 | POST | `/xsxklist!getDataList.action` | `sort=kcrwdm&order=asc&page=<n>&rows=<n>`，可选 `searchKey=kcmc&searchValue=<kw>`；`Referer: /xsxklist!xsmhxsxk.action` |
| 节次详情 | GET | `/xsxklist!getJxrlDataList.action?kcrwdm=<id>` | `Referer: /xsxklist!viewJxrl.action?kcrwdm=<id>` |
| **提交选课** | POST | `/xsxklist!getAdd.action` | `kcrwdm=<id>&kcmc=<name>`；`Referer: /xskjcjxx!kjcjList.action` |

响应：

- 列表：`{ rows: [...] }`，字段 `kcrwdm/kcmc/teaxm/kcflmc/jxbrs(已选)/pkrs(容量)`
- 节次：数组，字段 `jxbmc/xnxqmc/jxhjmc/zdgnqmc/zdjxcdmc/teaxms/zc/xq/jcdm2`
- 选课：**纯文本** `"1"` 表示成功，否则返回中文原因

### 2.2 失败语义（必须逐一映射为可展示状态）

| 返回文案 | 语义 | 处理策略 |
|---|---|---|
| `当前不是选课时间` | 未开选/已结束 | 终止任务，提示改时间 |
| `选课人数超出` | 满员 | 继续轮询（正常竞争态） |
| `上课时间有冲突` | 与已选课程冲突 | 终止该门，提示冲突 |
| `您已经选了该门课程` | 已选上 | 视为成功 |
| `超出选课要求门数` | 学分/门数上限 | 终止任务 |
| 未匹配的其他文案 | 未知 | 记录原文，继续或降级为人工 |

> 未登录时接口返回 **HTTP 200 + 登录页 HTML**（含 `使用统一认证中心登录`），不是 302。项目现有 `JxfwClient.ensureSession()` 已能识别该特征并触发 CAS 自动重登 —— 这一点是集成的关键前提，已验证成立。

### 2.3 抢课循环（上游语义）

- 单线程顺序提交，每轮之间 `delay`（默认 0.5s，前端强制 ≥0.5s）
- `priority_mode`：优先模式只死磕队首课程，否则按队列顺序列表循环
- `retry`：网络类失败重试，满员/冲突按策略跳过或继续
- 状态：`IDLE / WAITING(倒计时) / RUNNING`，支持随时取消
- 登录方式已在 2026-09 迁移为统一认证（issue #19/#22），与工大助手的 CAS 方案一致

## 3. HarmonyOS 平台约束（决定性因素）

| 能力 | 约束 | 能否用于抢课 |
|---|---|---|
| `workScheduler`（延迟任务） | 按应用活跃分组最小间隔 2/4/24/48 小时，单次 ≤2 分钟，**不保证准点** | ❌ 不可用于 12:00:00 |
| 短时任务 `requestSuspendDelay` | 需前台或 `onBackground` 申请；同时最多 3 个；单次 ≤3 分钟，单日配额约 10 分钟 | ✅ 可做"切后台后 3 分钟内收尾" |
| 长时任务 `startBackgroundRunning` | 类型必须与真实业务一致，且通知栏常驻；`TASK_KEEPING` 需受限权限 `KEEP_BACKGROUND_RUNNING_SYSTEM`（ACL）且仅部分设备 | ❌ 抢课没有合法类型，冒充会被系统校验拒绝（9900005） |
| 代理提醒 `reminderAgentManager` | 只负责提醒，不执行业务；本项目真机 Profile 暂无权益 | 🟡 仅用于"选课开始前喊用户回来" |
| 屏幕常亮 `window.setWindowKeepScreenOn` | 无需权限 | ✅ 抢课期间常亮 |

**推论**：HarmonyOS NEXT 无法做到"锁屏/后台自动抢课"。功能必须设计成：用户提前在 App 内布置任务 → 到点前被提醒 → 打开 App 保持前台 → App 准点发射请求。任何宣称后台静默抢课的方案都会在真机被挂起或直接不合法。

## 4. 与现有工程的契合度

可直接复用（无需改动或极小改动）：

| 现有资产 | 复用点 |
|---|---|
| `services/jxfw/CasLoginService` | CAS 登录、`autoLogin()`、CookieJar（含 Netscape 格式） |
| `services/jxfw/JxfwSession` | `JSESSIONID` 内存会话 |
| `services/jxfw/JxfwClient.request()` | POST/`extraData`、Referer、会话失效自动重登、错误分类 |
| `services/jxfw/JxfwModels` | `JxfwError/JxfwErrorKind`（NETWORK/CREDENTIALS/CAPTCHA/SESSION/PROTOCOL/SMS） |
| `domain/timetable/TimetableEngine` | 冲突预检、周次展开 |
| `services/sync/TimetableSyncService` | 抢课成功后一键同步课表 |
| `services/notification/LocalNotificationService` | 结果通知 |
| `services/reminder/*` | 开选前提醒（受 Profile 权益限制） |
| `data/Database` + `TimetableRepository` | schema 版本化迁移范式 |
| `services/backup/BackupService` | 备份 v3 增量字段 |

需要改动：

- `entry/src/main/ets/services/jxfw/JxfwClient.ets`：新增 3 个端点方法（见 §5）
- `data/Database.ets`：`DATABASE_VERSION` 4 → 5，新增选课相关表
- `services/backup/BackupService.ets`：`SCHEMA_VERSION` 4 → 5，导出/恢复选课队列
- `pages/Index.ets`：`routeMap` 增加 `selection` / `selection-task`
- `pages/campus/CampusPage.ets`：服务卡片增加"选课"入口（或课表页 FAB）
- `module.json5`：无需新权限（`INTERNET` 已有）
- `docs/PRIVACY.md`、`docs/API_EXPLORATION.md`：补充说明

## 5. 推荐实现

### 5.1 目录与文件

```text
entry/src/main/ets/
├── services/selection/
│   ├── SelectionModels.ets       # 课程、节次、任务、结果、错误枚举
│   ├── SelectionParser.ets       # getDataList / getJxrlDataList / getAdd 文本解析
│   ├── SelectionClient.ets       # 端点封装，复用 JxfwClient.request
│   ├── SelectionClock.ets        # 服务器时间偏移校准 + sleepUntil
│   ├── SelectionEngine.ets       # 抢课状态机（单线程循环、限速、优先级）
│   ├── SelectionRepository.ets   # 任务/队列/日志持久化（RDB v5）
│   └── SelectionService.ets      # 对外门面：arm/start/stop/recover
├── pages/selection/
│   ├── SelectionPage.ets         # 课程列表、搜索、详情、加入队列
│   └── SelectionTaskPage.ets     # 队列排序、开始时间、间隔、运行日志
└── state/SelectionState.ets      # AppStorage 运行态（供角标/可观测）
```

`JxfwClient` 新增（3 处小改，`allowRetry` 逻辑沿用）：

```ts
fetchSelectionCourses(page: number, rows: number, keyword: string): Promise<string>
fetchSelectionLessons(kcrwdm: number): Promise<string>
submitSelection(kcrwdm: number, kcmc: string): Promise<string>  // 返回原文，由 Parser 判定
```

### 5.2 数据层（RDB v5）

```sql
CREATE TABLE IF NOT EXISTS selection_tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  term_code TEXT NOT NULL,
  start_at INTEGER NOT NULL,        -- 毫秒时间戳
  interval_ms INTEGER NOT NULL,     -- 最小 300
  priority_mode INTEGER NOT NULL,   -- 0 列表循环 / 1 单曲循环
  auto_retry INTEGER NOT NULL,
  status TEXT NOT NULL,             -- IDLE/ARMED/RUNNING/DONE/PARTIAL/STOPPED/FAILED
  server_offset_ms INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER, updated_at INTEGER
);
CREATE TABLE IF NOT EXISTS selection_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL,
  kcrwdm INTEGER NOT NULL,
  kcmc TEXT NOT NULL,
  teacher TEXT, category TEXT,
  capacity INTEGER, chosen INTEGER,
  position INTEGER NOT NULL,
  state TEXT NOT NULL,              -- PENDING/SUCCESS/FULL/CONFLICT/ERROR/SKIPPED
  last_message TEXT, attempts INTEGER DEFAULT 0,
  updated_at INTEGER
);
CREATE TABLE IF NOT EXISTS selection_logs (   -- 可只保留最近 500 条
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL, at INTEGER NOT NULL,
  kcrwdm INTEGER, result TEXT, message TEXT, rtt_ms INTEGER
);
```

- 进程被杀后可恢复：启动时把 `RUNNING` 且已过开始时间的任务标为 `INTERRUPTED`，UI 提示"任务已中断"
- 备份 v5：导出 `selection_tasks` + `selection_queue`（不含 Cookie/密码/日志）
- 清空数据：一并删除选课表

### 5.3 准点执行

```ts
// 1) 偏移校准：T-30s 用一次轻量请求测 RTT + 读响应头 date
//    offset = serverDate + rtt/2 - localNow   （失败则用人工偏移，默认 0）
// 2) 分段等待，末段忙等，避免 setTimeout 漂移
static async sleepUntil(targetMs: number): Promise<void> {
  for (;;) {
    const remain = targetMs - Date.now();
    if (remain <= 0) return;
    if (remain > 1500) {
      await SelectionClock.sleep(remain - 1000);      // 粗粒度
    } else if (remain > 60) {
      await SelectionClock.sleep(Math.min(remain - 40, 50)); // 细粒度
    } else {
      while (Date.now() < targetMs) { /* busy ≤60ms */ }     // 收尾
      return;
    }
  }
}
```

要点：

- 用 `Date.now()` 反复重算剩余时间，而不是一次性 `setTimeout(差值)`（ArkTS 定时器不保证毫秒级且会累积漂移）
- 末段忙等 ≤60ms，避免卡 UI；如需更长可放到 Worker
- 抢课前 1 秒发一次轻量 GET 预热连接（`Connection: keep-alive` 已确认），缩短首字节时间；`@ohos.net.http` 每次 `createHttp()` 对应一次任务、需 `destroy()`，连接复用是否生效需真机实测
- 允许用户在"高级"里手动填服务器偏移（±2000ms），兜底时钟不同步

### 5.4 抢课状态机

```text
IDLE ──arm()──▶ ARMED ──到点──▶ RUNNING ──队列空/终止条件──▶ DONE|PARTIAL
                   │                │
                   └──stop()────────┴──▶ STOPPED
RUNNING ──会话失效且重登失败 / 未知协议 / 风控──▶ FAILED(需人工)
```

单轮逻辑（对应上游 `_select_courses`）：

1. 取队首（或按顺序遍历，受 `priority_mode` 控制）
2. `submitSelection()`
3. 结果分类：`SUCCESS / ALREADY / FULL / CONFLICT / NOT_TIME / LIMIT / UNKNOWN / SESSION`
4. `SUCCESS|ALREADY` → 出队 + 通知 + 可选自动同步课表
5. `FULL` → 保留队列，`await sleep(intervalMs)`
6. `CONFLICT / LIMIT` → 出队并告警（不再浪费请求）
7. `NOT_TIME` → 冷却 5–30s 后重试，连续 3 次则终止并提示
8. `SESSION` → 调 `CasLoginService.autoLogin()` 一次；再失败则 `FAILED`
9. `UNKNOWN` → 记原文；连续 5 次一致则终止（防死循环打爆教务）

限速与自我保护：

- `interval_ms` 下限 300ms（UI 默认 500ms，与上游一致）
- 单任务最大请求数（如 3000）与最大运行时长（如 30 分钟）硬上限
- 仅在 Wi-Fi（可选开关），避免流量 + 弱网放大
- 期间禁止并发同步；`selection` 运行时给其他教务请求加互斥锁

### 5.5 前台保活组合

```text
arm 时：
  window.getLastWindow(ctx).setWindowKeepScreenOn(true)
  页面常驻"抢课进行中"，退栈需二次确认
onBackground 时：
  backgroundTaskManager.requestSuspendDelay('grab', cb)   // 最多保 3 分钟
  同时发本地通知"抢课任务在后台仅能继续 3 分钟"
onForeground：
  cancelSuspendDelay()
到点前 1 分钟：
  LocalNotificationService / ReminderService 提醒
```

不做长时任务伪装（违反 Background Tasks Kit 集成规范，且系统会校验失败）。

### 5.6 UX 流程

```text
校园页 → 选课
  ├─ 未登录 → 复用 CAS 登录（与同步页一致）
  ├─ 课程列表：搜索(课程名) / 分页 / 余量着色（已满灰、将满黄、充足绿）
  ├─ 点课程 → 节次 Sheet → 与本地课表冲突预检（冲突红条，仍允许加入但提示）
  ├─ 加入队列 → 底部"抢课队列(n)"
  └─ 队列页
       ├─ 排序（拖动）、单门移除、优先级开关
       ├─ 开始时间（可选"立即"）、间隔、自动重试
       ├─ 倒计时卡片 + 服务器偏移状态（已校准/未校准）
       └─ 运行：实时日志（时间、课程、耗时 ms、结果）+ 停止按钮
成功后：
  Toast + 通知 + "同步课表"按钮（走 TimetableSyncService.fullSync）
```

文案与定位：入口叫"选课助手"，说明"仅在选课开放时段使用；本工具按固定间隔顺序提交，不做并发请求"。这是审核与校方观感的关键。

## 6. 风险与缓解

| 风险 | 等级 | 缓解 |
|---|---|---|
| 高频请求触发教务风控/封号 | 高 | 间隔下限 300ms、单任务上限、连续未知结果熔断、Wi-Fi 限定、明确免责声明 |
| 应用市场判定"抢课脚本"违规 | 高 | 定位"选课辅助"、不做并发、不做多账号、不做后台静默、仅校内选课场景；必要时把"自动提交"作为可选开关，默认只做查询+提醒+一键提交 |
| 后台被挂起导致错过时间 | 高 | 前台常亮 + 短时任务 + 开始前提醒；UI 明确"需保持 App 打开" |
| 用户在浏览器登录导致 JSESSIONID 互踢 | 中 | 抢课前检测会话；提示"抢课期间勿在其它设备登录教务" |
| 接口随教务升级变动 | 中 | 解析层集中在 `SelectionParser`，失败给出"教务接口可能已变更"提示 |
| 校规/学术诚信争议 | 中 | README/关于页写明"选课结果与风险由用户承担，请遵守学校选课规定" |
| 纯文本成功判定被改 | 低 | 解析器兼容 `"1"` 与 JSON `{success:true}` 两种形态 |
| 上游 AGPL 代码复制 | 低 | 本项目同为 AGPL-3.0；建议按协议自行实现，署名校验逻辑即可 |

## 7. 工作量（1 人）

| 阶段 | 内容 | 人日 |
|---|---|---|
| P1 协议层 | Client/Parser/错误分类 + mock 联调 | 1.0–1.5 |
| P2 数据层 | RDB v5、Repository、备份 v5、清空 | 0.5–1.0 |
| P3 引擎 | 时钟校准、状态机、限速、熔断、恢复 | 1.5–2.0 |
| P4 UI | 列表/详情/队列/运行日志/倒计时 | 2.0–2.5 |
| P5 生命周期 | 常亮、短时任务、通知、提醒 | 0.5–1.0 |
| P6 测试 | mock 服务器、模拟器、真机选课时段 | 1.5–2.0 |
| 合计 | | **7–9** |

分两期交付更稳：

- **v1.2（辅助版）**：P1+P2+P4 的"查询 + 冲突预检 + 倒计时 + 提醒 + 一键手动提交" → 3–4 人日，风险最低，可先上架
- **v1.3（自动版）**：P3+P5 的自动循环 → 再加 4–5 人日，视 v1.2 使用反馈决定

## 8. 验证方案

**Mock 服务器**（本地 Node/Python，模拟 jxfw）：

1. 未登录 → 返回登录页 HTML（验证会话检测与自动重登）
2. 返回 `1` / `选课人数超出` / `上课时间有冲突` / `当前不是选课时间` / `超出选课要求门数` / 未知文案
3. 随机 200–800ms 延迟，验证限速与超时
4. 中途返回登录页 HTML，验证 `SESSION` 分支

**真机（SGT-AL10）**：

- 非选课时段真实调用：应稳定返回 `当前不是选课时间`（等价于选择接口连通性验证）
- 时间校准：对比响应头 `date` 与本机，偏移应 <500ms
- 前台锁屏/切后台：验证 3 分钟短时任务行为与中断提示
- 低电量模式、弱网、飞行模式切换
- 进程杀后台重启：任务状态恢复为 INTERRUPTED 且不自动续跑

## 9. 待真实账号确认的开放问题

1. 选课模块是否只在"选课批次"开放时可见；是否需要额外轮次参数（`xkbat` 之类）
2. 除公选课（`xsxklist`）外，是否覆盖专业选修/体育选课；研究生系统是否同构
3. 是否有验证码/滑块/短信二次校验（`JxfwClient` 已能识别短信验证页，但选课链路未验证）
4. 一次 `getAdd` 的最坏响应时间（决定间隔下限能否压到 300ms）
5. `@ohos.net.http` 是否跨 `createHttp()` 复用 TCP/TLS 连接（决定预热策略收益）
6. 教务是否有并发/频率限制（连续 300ms 请求 5 分钟是否被限）

## 10. 明确不做

- 后台/锁屏静默抢课（平台不允许，也不做长时任务伪装）
- 多账号、代理 IP、并发轰炸、自动绕过风控/验证码
- 代抢、任务共享、云端下发课程列表
- 任何绕过学校选课规则的"占位/退课再抢"策略

## 11. 实现落地（已完成 v1）

实际交付的代码结构与本文评估一致：

| 文件 | 作用 |
|---|---|
| `services/selection/SelectionModels.ets` | 课程/节次/队列/任务/运行快照与常量 |
| `services/selection/SelectionParser.ets` | `getDataList`/`getJxrlDataList`/`getAdd` 解析与错误分类 |
| `services/selection/SelectionClock.ets` | 响应头 `Date` 校准、分段休眠、末段忙等 |
| `services/selection/SelectionEngine.ets` | 静态单例抢课循环、限速、熔断、通知、常亮、短时任务 |
| `services/selection/SelectionRepository.ets` | RDB v5 三张表读写 |
| `services/selection/SelectionService.ets` | 页面门面：列表、详情、冲突预检、队列、启动 |
| `pages/selection/SelectionPage.ets` | 课程列表 + 搜索 + 详情 Sheet（含冲突） |
| `pages/selection/SelectionTaskPage.ets` | 队列排序、参数、倒计时、开始/停止、日志 |
| `state/SelectionState.ets` | 队列 revision，驱动页面刷新 |
| `services/jxfw/JxfwClient.ets` | 新增 `fetchSelectionCourses` / `fetchSelectionLessons` / `submitSelection` |
| `data/Database.ets` | `migrateV5`：`selection_task` / `selection_queue` / `selection_logs` |
| `services/backup/*` | schema v5：选课任务与队列随备份导出/恢复 |

运行约束（与 §3 一致）：

- 引擎要求前台 + 屏幕常亮；退后台只申请 3 分钟短时任务，超时进程被挂起；
- 单线程顺序提交，间隔下限 300ms，单次运行上限 30 分钟 / 2400 次；
- 连续 20 次「不是选课时间」、8 次网络失败、6 次未知结果、会话失效或超出选课门数时终止并通知；
- 进程被杀后重启，遗留的 ARMED/RUNNING 会被标记为 STOPPED。

## 12. 落地建议

1. 先做 §8 的 mock + 非选课时段真机探测，确认接口连通与错误文案（0.5 人日，风险前置）
2. 按 v1.2「辅助版」交付，把"自动提交"作为第二期开关
3. 代码按协议重写，不搬运上游 Python；在 README 致谢处标注思路来源
4. 若因审核顾虑暂不上架，可作为"实验性功能"在设置页以显式开关打开，并默认关闭
