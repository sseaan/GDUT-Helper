# 广工门户与校园新闻接口调研

> 调研时间：2026-11-25  
> 调研方式：ego-lite 浏览器，使用已登录的统一认证会话实际访问并抓取 XHR。  
> 范围：校园新闻、校园卡余额、图书借阅、校园网余额。  
> 账号、Cookie、卡号、余额等个人数据不写入本文档；示例均为脱敏占位。  
> 1.1.0 实现：`services/portal/*`、`components/CampusDataCard.ets`、`pages/campus/*`。

## 1. 结论

| 功能 | 推荐数据源 | 数据形式 |
|---|---|---|
| 校园卡余额、卡号 | ehall 融合门户 `CUS_CARD_MYDATA` 卡片 | JSON |
| 图书借阅 | ehall `CUS_CARD_MYDATA` 卡片 | JSON |
| 校园网余额、剩余月数、状态 | ehall `CUS_CARD_MYDATA` 卡片 | JSON |
| 校园新闻、OA 通知、广工头条等 | ehall `CUS_CARD_MYNEWS` 卡片 | JSON |
| OA 通知简讯网原始页面 | `oas.gdut.edu.cn` Seeyon 门户 | HTML/JS，解析成本高 |

推荐只接入 **ehall 融合门户**：一个 CAS 会话即可拿到个人卡片和新闻，且都是结构化 JSON。  
OAS 通知简讯网保留为参考来源；ehall 的 `OA最新通知` 频道已经聚合了 OAS 通知，并直接给出 OAS 详情链接。

## 2. 登录与会话

### 2.1 ehall 统一认证入口

访问 `https://ehall.gdut.edu.cn/index.html#/` 未登录时会跳转：

```text
https://authserver.gdut.edu.cn/authserver/login?service=
  https%3A%2F%2Fehall.gdut.edu.cn%2Flogin%3FportalService%3D
  https%253A%252F%252Fehall.gdut.edu.cn%252Findex.html%2523%252F%23%2F
```

解码后的业务 `service`：

```text
https://ehall.gdut.edu.cn/login?portalService=https%3A%2F%2Fehall.gdut.edu.cn%2Findex.html%23%2F%23%2F
```

登录成功后访问 ehall 域需要携带的 Cookie：

| Cookie | 说明 |
|---|---|
| `WISCPSID` | ehall 主会话 Cookie，最重要的登录态 |
| `route` | 网关路由 Cookie，通常原样携带 |
| `COM.WISEDU.CASP.*` | 门户辅助 Cookie，按需保留 |

注意：

- 不要只判断 `JSESSIONID`。`authserver` 域也有 `JSESSIONID`，但 ehall 的会话标识是 `WISCPSID`。
- 现有 `CasLoginService.loginForService()` 可以复用，但登录完成判断应改为“目标域出现 `WISCPSID`”，而不是只看 `JSESSIONID`。
- Cookie 只放内存/系统安全存储，不写日志、不写普通 Preferences、不进入备份。

### 2.2 通用请求头

卡片接口实测请求：

```http
POST https://ehall.gdut.edu.cn/execCardMethod/{cardWid}/{cardId}
Content-Type: application/json
Accept: application/json, text/plain, */*
X-Requested-With: XMLHttpRequest
Referer: https://ehall.gdut.edu.cn/index.html
Cookie: WISCPSID=...; route=...
```

请求体是 JSON，`n` 是随机数，仅用于防缓存：

```json
{
  "cardId": "CUS_CARD_MYDATA",
  "cardWid": "7276243894285743",
  "method": "getPersonalDataList",
  "param": {
    "lang": "zh_CN",
    "platformType": 0
  },
  "n": "0.123456789"
}
```

响应统一信封：

```json
{
  "errcode": "0",
  "errmsg": "请求成功",
  "data": {}
}
```

注意 `errcode` 是字符串 `"0"`，不是数字。

### 2.3 会话预热（个人卡片详情必需）

CAS 登录得到的 `WISCPSID` 只能让卡片列表和新闻接口工作；**直接调用
`getPersonalDataDetail` 会返回 `{"errcode":"0","data":null}`**。  
实测必须先模拟融合门户启动流程：

```text
GET /index.html
GET /base/getPortalConfig
GET /getLoginUser?_t=<timestamp>
GET /getLoginUserAndGuest?_t=<timestamp>
GET /getPageView?_t=<timestamp>&pageCode=&originalUrl=https%253A%252F%252Fehall.gdut.edu.cn%252Findex.html%2523%252F&lang=zh_CN
POST /minos-stata/collect/collectData      # 可选，用于取得 gwroute-minos-stata
```

其中 `/getPageView` 是触发个人数据上下文的关键：实测在它之前调用详情一直为
`data:null`，调用后同一 Cookie 的详情立即返回完整卡片。  
建议只按域名携带 cookie：不要把 `authserver` 的 `JSESSIONID` / `CASTGC` 发给
`ehall.gdut.edu.cn`；`route` 也必须使用 ehall 域的 `route`，并按同名 cookie
去重（优先更具体的域名）。

## 3. 个人卡片：校园卡、图书借阅、校园网

### 3.1 卡片标识

| 字段 | 值 |
|---|---|
| `cardId` | `CUS_CARD_MYDATA` |
| `cardWid` | `7276243894285743` |
| 卡片名称 | 个人事务 / 个人数据 |

### 3.2 获取卡片元数据

```http
POST /execCardMethod/7276243894285743/CUS_CARD_MYDATA
```

```json
{
  "cardId": "CUS_CARD_MYDATA",
  "cardWid": "7276243894285743",
  "method": "getPersonalDataList",
  "param": {
    "lang": "zh_CN",
    "platformType": 0
  },
  "n": "0.123456789"
}
```

返回 `data` 数组，每一项是一张个人卡片：

```json
{
  "wid": "卡片数据 ID",
  "title": "校园卡",
  "iconUrl": "图标 URL",
  "mainInfo": "您的余额：【YE】元",
  "subInfo": "您卡号：【KH】",
  "linkUrl": null,
  "needRetrieve": 1,
  "isEmail": 0,
  "accessTime": null,
  "extraInfo": ""
}
```

字段说明：

| 字段 | 说明 |
|---|---|
| `wid` | 后续 `getPersonalDataDetail` 的入参 |
| `title` | 卡片标题：`校园卡` / `图书借阅` / `校园网续费` / `校园邮箱` |
| `mainInfo` | 第一行展示文案，含 `【YE】`、`【KH】` 等占位符 |
| `subInfo` | 第二行展示文案 |
| `linkUrl` | 点击卡片可跳转的外部地址 |
| `needRetrieve` | `1` 表示需要再调详情接口；`0` 表示列表值已可用 |
| `isEmail` | `1` 表示邮箱绑定类卡片，本项目暂不需要 |

实测卡片（值因账号而异，以下均为占位）：

| 标题 | `wid` | `linkUrl` |
|---|---|---|
| 校园卡 | `fed7ccb8145041111139100024955cc7` | `null` |
| 校园网续费 | `c4a97088b9dcc25c2c62e78c2a98315e` | `https://selfmanager.gdut.edu.cn/sso_login` |
| 图书借阅 | `7fa9469233e1dc5892b9fb61db7e79d5` | `https://opac.gdut.edu.cn` |
| 校园邮箱 | `c404059df7533306355dd2046cedc70f` | 绑定邮箱，暂不接入 |

> `wid` 可能随门户配置变化，代码应优先按 `title` 匹配，`wid` 只作为已实测的兜底。

### 3.3 获取卡片详情

对 `needRetrieve = 1` 的卡片逐个调用：

```http
POST /execCardMethod/7276243894285743/CUS_CARD_MYDATA
```

```json
{
  "cardId": "CUS_CARD_MYDATA",
  "cardWid": "7276243894285743",
  "method": "getPersonalDataDetail",
  "param": {
    "wid": "fed7ccb8145041111139100024955cc7",
    "extraInfo": "",
    "lang": "zh_CN",
    "platformType": 0
  },
  "n": "0.123456789"
}
```

返回：

```json
{
  "errcode": "0",
  "errmsg": "请求成功",
  "data": {
    "wid": "fed7ccb8145041111139100024955cc7",
    "title": "校园卡",
    "mainInfo": "您的余额：0元",
    "subInfo": "您卡号：******",
    "linkUrl": null,
    "needRetrieve": 0,
    "accessTime": "2026-11-25T10:02:48.710+00:00",
    "extraInfo": ""
  }
}
```

### 3.4 三项业务的数据约定

#### 校园卡

- `mainInfo`：`您的余额：{金额}元`
- `subInfo`：`您卡号：{卡号}`
- `linkUrl`：`null`
- 建议展示：主行显示余额，副行显示卡号；卡号建议只显示后 4 位。
- 结构化解析（可选）：

```text
/您的余额：([0-9.]+)元/
/您卡号：(.+)$/
```

#### 校园网余额

- `mainInfo`：`余额: {金额}元`
- `subInfo`：`剩余月数: {月数}个， 状态: {状态}`
- `linkUrl`：`https://selfmanager.gdut.edu.cn/sso_login`
- 结构化解析（可选）：

```text
/余额:\s*([0-9.]+)元/
/剩余月数:\s*(\d+)个/
/状态:\s*(\S+)/
```

#### 图书借阅

- `mainInfo`：当前账号无借阅时返回 `-`；有借阅时的实际文案尚未取得非空样本。
- `subInfo`：`即将到期{n}本；超期未还{n}本`；无数据时占位符可能未替换，例如 `即将到期-本；超期未还-本`。
- `linkUrl`：`https://opac.gdut.edu.cn`
- 建议：**直接展示 `mainInfo` / `subInfo` 原文**，不要强依赖数字解析；非空样本取得后再补解析规则。
- 后续验证项：有在借图书时 `mainInfo` 是否返回借阅数量、`subInfo` 占位符是否被替换。

### 3.5 推荐调用流程

```text
1. 使用 ehall CAS 会话请求 getPersonalDataList
2. 按 title 匹配 校园卡 / 校园网续费 / 图书借阅
3. 对 needRetrieve = 1 的卡片并发调用 getPersonalDataDetail
4. 用 mainInfo / subInfo 渲染卡片；可选解析出余额与卡号
5. 卡片点击：
   - 图书借阅 -> linkUrl (opac.gdut.edu.cn)
   - 校园网续费 -> linkUrl (selfmanager.gdut.edu.cn/sso_login)
   - 校园卡 -> 无链接，可打开明细 Sheet
```

### 3.6 缓存建议

- 余额、借阅、网络状态：内存缓存 5–15 分钟，进入“我的/校园”或下拉刷新时再请求。
- 不建议后台高频轮询；接口没有明显的实时性要求。
- `accessTime` 可作为“数据更新时间”展示，但它是 UTC ISO 时间。
- 门户数据不要写入现有 JSON 备份，避免把余额、卡号写入备份文件。

## 4. 校园新闻

### 4.1 卡片标识

| 字段 | 值 |
|---|---|
| `cardId` | `CUS_CARD_MYNEWS` |
| `cardWid` | `7631867210332992` |
| 实测 | 同一个 `cardWid` 可以查询所有频道 |

请求：

```http
POST /execCardMethod/7631867210332992/CUS_CARD_MYNEWS
```

```json
{
  "cardId": "CUS_CARD_MYNEWS",
  "cardWid": "7631867210332992",
  "method": "getChannelNews",
  "param": {
    "channelIds": "1623945854407286785",
    "pageNumber": 1,
    "lang": "zh_CN",
    "platformType": 0
  },
  "n": "0.123456789"
}
```

`channelIds` 支持逗号分隔多个频道；分页从 `pageNumber = 1` 开始，实测每页固定 6 条。

### 4.2 频道 ID

| 频道 | channelId | 实测总量 |
|---|---|---:|
| 广工头条 | `1623945854407286785` | 47 |
| 广工新闻 | `1623946401407442945` | 473 |
| 媒体广工 | `1623947527526559746` | 546 |
| 学术动态 | `1623963557499117569` | 98 |
| OA最新通知 | `1750414748292165634` | 45124 |
| OA最新公告 | `1740368235659382786` | 35076 |
| OA最新简讯 | `1750415095823806466` | 67892 |
| OA招标公告 | `1750415322458963969` | 8157 |

校园页的“校园新闻”使用 **通知简讯网的最新简讯**，即 `OA最新简讯`
（`1750415095823806466`），不使用 `广工头条`。  
`OA最新通知` / `OA最新公告` / `OA招标公告` 可作为通知公文网的分类入口；
`广工头条`、`广工新闻`、`媒体广工`、`学术动态` 仍可用于官网新闻，但不在校园页默认展示。

### 4.3 返回结构

```json
{
  "errcode": "0",
  "errmsg": "请求成功",
  "data": {
    "datas": {
      "data": [
        {
          "title": "新闻标题2026-11-25",
          "channelName": "广工头条",
          "columnName": "GDUT/官网通知新闻/",
          "pubTime": "2026/11/25",
          "picUrl": null,
          "newDisplay": false,
          "day": "25",
          "month": "11",
          "isTop": 0,
          "contents": "正文或摘要，可能为 null",
          "abstractVal": null,
          "url": "https://www.gdut.edu.cn/info/...",
          "author": "学校官网",
          "wid": "新闻唯一 ID",
          "read": false,
          "enableRead": false
        }
      ],
      "pageNumber": 1,
      "pageSize": 6,
      "totalSize": 47,
      "errcode": "0",
      "errmsg": "请求成功",
      "traceId": null
    },
    "configInfo": {
      "newsTotal": 6,
      "newsColumns": 1,
      "newsShowSubscribe": 1,
      "showMore": 0,
      "newsDisplay": { "dateFormat": 2, "type": 2 }
    }
  }
}
```

字段说明：

| 字段 | 说明 |
|---|---|
| `title` | 标题，部分标题自带日期后缀 |
| `channelName` | 频道名 |
| `pubTime` | 发布时间字符串 `YYYY/MM/DD` |
| `picUrl` | 封面图，可能为 `null`；可能是 authserver 签名图片 |
| `isTop` | 是否置顶，`0/1` |
| `contents` | 广工头条/广工新闻可能带正文/摘要；OA 通知通常为 `null` |
| `url` | 详情外链；OA 通知指向 `oas.gdut.edu.cn/seeyon/newsData.do?...`，校园新闻指向 `www.gdut.edu.cn` |
| `wid` | 新闻唯一 ID，可用于去重 |
| `newDisplay` | 是否显示“新”标记 |
| `read` / `enableRead` | 门户已读状态；原生 App 可忽略 |
| `pageNumber` / `pageSize` / `totalSize` | 分页信息 |

### 4.4 频道配置接口（可选）

如果不想硬编码频道 ID，可调用：

```http
POST /execCardMethod/7631867210332992/CUS_CARD_MYNEWS
```

```json
{
  "cardId": "CUS_CARD_MYNEWS",
  "cardWid": "7631867210332992",
  "method": "getConfiguredChannel",
  "param": { "lang": "zh_CN", "platformType": 0 },
  "n": "0.123456789"
}
```

返回频道树，例如：

```json
{
  "id": "1623945854407286785",
  "name": "广工头条",
  "parentId": "1613074944376836097",
  "isChannel": true,
  "isFixed": true,
  "sort": 5
}
```

`getSubscribedChannels` 返回当前卡片已订阅频道，可用于“我的订阅”类 UI。

### 4.5 展示建议

- 首页/校园页新闻列表：显示 `title`、`channelName`、`pubTime`，有 `picUrl` 时展示缩略图。
- 点击：用系统浏览器或内置 WebView 打开 `url`；OA 通知需要 OAS 登录态，若未登录会跳统一认证。
- 分页：`pageNumber` 递增；每页 6 条，`totalSize` 可能很大（OA 通知 4.5 万条），只按需加载。
- 去重：优先用 `wid`，其次 `url`。
- 缓存：列表缓存 3–5 分钟；不要一次拉取全部。

### 4.6 通知简讯的封面图

`OA最新简讯`（`1750415095823806466`）的 `picUrl` 实测为 `null`，但 OAS
文章详情页正文里有图片。若要在 App 中显示封面/缩略图，可对文章 `url`
做一次轻量 HTML 抓取：

1. GET `url`（OAS 详情页游客可访问，无需 OAS 登录）；
2. 取正文第一个 `<img>`，跳过 `/skin/`、`news_logo`、`icon` 等站点图标；
3. 相对地址补 `https://oas.gdut.edu.cn`；
4. 缓存文章 URL → 图片 URL，避免重复请求。

不建议抓取 OAS `newsIndex` 列表页：游客访问实测返回 0 条，且需要 OAS
登录态；列表仍用 ehall `getChannelNews`，仅对封面缺失的文章补抓详情首图。
文章正文本身不做原生解析，点击后使用 App 内 WebView 打开，并在 WebView
页面提供“在浏览器打开”原生按钮。

## 5. OAS 通知简讯网

### 5.1 入口与页面

```text
https://oas.gdut.edu.cn/seeyon/main.do?method=main&loginPortal=1&portalId=-7779029842361826066
```

标题：`广东工业大学 通知简讯网`  
实测游客可访问通知/公告/简讯列表，不需要 OAS 登录；个人化内容才需要登录。

顶部空间：

- 首页
- 校内通知
- 公示公告
- 校内简讯
- 招标公告
- 学校公文

### 5.2 页面数据来源

门户初始化会请求：

```text
GET /seeyon/main.do?method=vPortalData&showName=1&random=...&portalId=-7779029842361826066
    &themeId=2200000003&mls=1200000003
    &fsid=497038097197843112
    &fspath=/seeyon/before_login/497038097197843112.psml
    &fstype=40&menuSource=
```

返回 JavaScript，核心变量：

- `vPortal.space`：顶部空间列表；
- `vPortal.spacesSummary[spaceId]`：空间布局和 section 配置；
- `vPortal.currentUser`：游客时为 `seeyon-guest`。

首页 `spaceId = 497038097197843112` 的 section 实测：

| 区块 | sectionBeanId | section id | 备注 |
|---|---|---|---|
| 图片横幅 | `bannerImageSection` | `4365217254563725994` | 轮播图 |
| 数据查询 | `bul2Section` | `-2035285724217915191` | 校内查询入口 |
| 最新通知 | `newsSection` | `8463576657325868697` | `sl` base64 为“最新通知” |
| 最新简讯 | `newsSection` | `-7400282370687679688` | `sl` base64 为“最新简讯” |
| 最新公告 | `newsSection` | `35672547838805983` | `sl` base64 为“最新公告” |
| 招标公告 | `newsSection` | `-3929440816328915277` | |

`vPortal.spacesSummary` 里的 section 只给出布局信息；门户实际列表可能是服务端直接渲染到 HTML 中。  
部分 section 会通过：

```text
POST /seeyon/ajax.do?method=ajaxAction&managerName=sectionManager&managerMethod=doProjection
```

携带 `arguments`（URL 编码 JSON，包含 `sectionBeanId`、`entityId`、`spaceId`、`panelId` 等）返回 `Data.rows`。  
该接口依赖具体门户布局的 `entityId` / `panelId`，不适合作为 App 的稳定接口。

### 5.3 详情与列表链接

详情链接格式：

```text
https://oas.gdut.edu.cn/seeyon/newsData.do?method=newsView&newsId={newsId}
```

列表“更多”链接格式（实测招标公告/结果）：

```text
https://oas.gdut.edu.cn/seeyon/newsData.do?method=newsIndex&boardId={boardId}
```

### 5.4 建议

- 校园新闻功能**不要直接解析 OAS 门户 HTML**：Seeyon 页面结构复杂，列表可能是服务端渲染，section 接口依赖布局 ID。
- 需要 OA 通知时，直接用 ehall `CUS_CARD_MYNEWS` 的 `OA最新通知` 频道：
  - 返回标题、日期、作者、OAS 详情链接；
  - 与 OAS 通知简讯网内容一致；
  - 不需要单独维护 OAS 登录态。
- 只有在 ehall 新闻接口不可用时，才考虑用 OAS `main.do?method=main...` HTML + DOM/正则解析作为降级。

## 6. 接入建议（HarmonyOS）

> 展示层已于 M8 改版：校园卡 / 图书借阅 / 校园网三项改成「三列数字」卡片，
> 金额统一 `¥12.00`、借阅副标题「到期 0 · 超期 0」、校园网副标题不再展示「正常」。


### 6.1 服务划分

建议新增：

```text
services/portal/PortalClient.ets     # CAS/eCookie、execCardMethod 通用 POST
services/portal/PortalModels.ets     # 卡片、新闻、余额模型
services/portal/PortalParser.ets     # mainInfo/subInfo 解析
services/portal/PortalService.ets    # 个人卡片 + 新闻业务编排
pages/portal/CampusNewsPage.ets      # 校园新闻列表/详情
pages/portal/PortalCardsPage.ets     # 校园卡/图书/网络卡片
```

### 6.2 推荐接口调用顺序

```text
登录 ehall（CAS）
  -> getPersonalDataList
  -> 并发 getPersonalDataDetail(校园卡/图书借阅/校园网续费)
  -> 渲染三张卡片

校园新闻
  -> getChannelNews(channelIds=广工头条/广工新闻/媒体广工/学术动态, pageNumber=1)
  -> 点击 url 打开详情
  -> 上拉加载 pageNumber+1
```

### 6.3 错误处理

- HTTP 302 到 `authserver.gdut.edu.cn` / 登录页：会话失效，重新 CAS 登录并重试一次。
- `errcode != "0"`：展示 `errmsg`，不要清空已有缓存。
- 网络失败：保留上次缓存，提示“数据可能不是最新”。
- 个人卡片详情单张失败：其余卡片正常展示，失败卡片显示“暂不可用”。

### 6.4 隐私

- 不记录 Cookie、`WISCPSID`、卡号、余额到日志。
- 卡号展示建议脱敏，例如 `******1234`。
- 门户余额、借阅数据不进入 JSON 备份。
- 新闻列表可缓存标题/链接，但不要缓存带签名的图片 URL 过期参数。

## 7. 待验证项

- [ ] 图书借阅非空数据：`mainInfo` / `subInfo` 占位符替换后的真实文案。
- [ ] 校园卡余额在真实消费后是否实时更新，缓存多久合理。
- [ ] 校园网余额接口是否需要额外权限或仅校内网络可用。
- [ ] OAS 首页“最新通知/最新简讯”是否有稳定列表接口；目前建议走 ehall 新闻频道。
- [ ] ehall 会话过期时接口的准确响应（302、HTML 登录页或 JSON 错误码）。
- [ ] 新闻图片 `picUrl` 的签名有效期。

## 8. 参考命令（调试用）

在已登录的 ego-lite 环境中，可直接用 `page.fetch` 验证：

```js
const r = await page.fetch(
  "https://ehall.gdut.edu.cn/execCardMethod/7276243894285743/CUS_CARD_MYDATA",
  {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Requested-With": "XMLHttpRequest"
    },
    body: JSON.stringify({
      cardId: "CUS_CARD_MYDATA",
      cardWid: "7276243894285743",
      method: "getPersonalDataList",
      param: { lang: "zh_CN", platformType: 0 },
      n: String(Math.random())
    })
  }
);
console.log(r.status, r.body);
```

新闻：

```js
const r = await page.fetch(
  "https://ehall.gdut.edu.cn/execCardMethod/7631867210332992/CUS_CARD_MYNEWS",
  {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "X-Requested-With": "XMLHttpRequest"
    },
    body: JSON.stringify({
      cardId: "CUS_CARD_MYNEWS",
      cardWid: "7631867210332992",
      method: "getChannelNews",
      param: {
        channelIds: "1623945854407286785",
        pageNumber: 1,
        lang: "zh_CN",
        platformType: 0
      },
      n: String(Math.random())
    })
  }
);
console.log(r.status, r.body);
```
