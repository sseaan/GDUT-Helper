# CalDAV 课表镜像：协议实测与实现约定

> 调研时间：2026-11  
> 测试对象：自建的 Radicale 实例（测试文件每次跑完都已删除）。  
> 实现：`services/caldav/*`、`pages/profile/CalDavPage.ets`。

## 1. 目标

把当前学期课表**单向**镜像到用户自己的 CalDAV 日历（Radicale / Nextcloud）。
不读取远端事件、不做双向合并——教务同步是唯一数据源，双向只会制造冲突。

## 2. 平台约束

HarmonyOS `http.RequestMethod` 只有：

```
OPTIONS · GET · HEAD · POST · PUT · DELETE · TRACE · CONNECT
```

**没有 `PROPFIND` / `REPORT` / `MKCALENDAR` / `MKCOL`。**

所以：

- 不做服务发现（不从根路径找 principal / calendar-home）；
- 不创建日历集合（用户必须先在日历客户端里建好，再把集合地址复制进来）；
- 写入侧只需要 `PUT` / `DELETE` / `HEAD`，刚好够用。

## 3. Radicale 实测矩阵

| 请求 | 结果 | 结论 |
|---|---|---|
| `OPTIONS` | `200`，`DAV: 1,2,3,calendar-access` | 标准 CalDAV |
| `PROPFIND Depth:0`（`resourcetype`） | `207`，`<calendar/><collection/>` | 集合本身是日历 |
| `PROPFIND` 带 `current-user-principal` | `403` | 匿名会话下不能求 principal，别依赖它 |
| `PUT` 单 VEVENT（新） | `201` + `ETag` | OK |
| `PUT` 同一资源（无 `If-*`） | `204` | 覆盖幂等 |
| `PUT` 同一资源（`If-Match: *`） | `412` | 只认具体 ETag，不支持通配 |
| `PUT` 带错误 `If-Match` | `412` | 乐观锁可用 |
| **`PUT` 两个 VEVENT 的文档** | **`400`** | **一个资源只能一个组件** |
| **同 UID 写第二个资源** | **`409`** | **集合内 UID 必须唯一** |
| `DELETE` 已存在 / 不存在 | `200` / `404` | 404 视为已删除 |
| `GET` 集合里的资源 | `200 text/calendar` | 属性会被重排，内容保留 |
| `REPORT calendar-query` | `200` + `calendar-data` | 只能用于读回，本项目没用到 |

两条硬约束直接决定了实现形态：**拆成单事件资源** + **UID 加独立后缀**。

## 4. 实现约定

```text
uid        = <agendaId>@gdut-helper-caldav      # 和 ICS 导出的 @gdut-helper 区分
resource   = gdut-<stableHash(uid)>.ics         # 23 字符文件名，重推覆盖同一个
content    = 单 VEVENT + VTIMEZONE Asia/Shanghai，不带 METHOD
```

- **UID 后缀必须和导出的 ICS 不同**：用户若把导出的 ICS 导入同一日历，UID 冲突会让每次 PUT 都 409；
- **内容指纹**：`common/StableHash` 对「去掉 `DTSTAMP` 的正文」做 64 位哈希。
  不剔除时间戳的话每次构建都判定为变了，每次同步都是全量重推；
- **增量**：`filesDir/caldav_index.json` 记 `uid / name / hash`，只 PUT 新增或变化的，
  索引里有但当前学期不存在的逐条 DELETE；
- **顺序**：先 PUT 后 DELETE。中途失败时宁可远端短暂重复，也不要把日历删空；
- **并发 3**：首次约 400 个事件（25 门 × 16 周），并发 3 大约 20–40 秒；之后课表没变就是 0 次请求；
- **错误分类**：401/403 认证、404 集合不存在、409 UID 冲突、412 冲突、其它状态码 + 网络错误分开报。

## 5. 已知取舍

- 每个事件一个资源：Apple Calendar 里每节课都是独立条目，改一节不影响其它节，符合「镜像」语义；
  代价是对象数多、首次推送慢；
- 想要更少对象可以改成「每门课一个 RRULE 对象」（约 25 个 PUT），
  但单双周/停课要 EXDATE、调课要单独的 override 事件，语义成本高，放到二期；
- 不支持双向：RRULE/EXDATE/RECURRENCE-ID 展开与冲突合并的成本远高于收益。

## 6. 待补测

- [ ] 真机首推 ~388 个事件的耗时与失败率
- [ ] Nextcloud / Baikal 的兼容性（目前只在 Radicale 上验证）
- [ ] 服务器开启 Basic 认证后的 401 提示链路
