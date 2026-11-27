# 图书馆系统（OPAC）接口调研

> 调研时间：2026-11-25  
> 调研方式：ego-lite 已登录 OPAC 会话，抓取 XHR 并核对前端 JS。  
> 账号、JWT、姓名、借阅记录、罚款金额等个人数据不写入本文档。  
> 1.1.0 实现：`services/library/*`、`pages/library/*`；首页入口为校园页图书馆网格卡。

## 1. 系统概览

| 项目 | 值 |
|---|---|
| 地址 | `https://opac.gdut.edu.cn` |
| 前端 | Vue/React SPA，Hash 路由，`#/Home`、`#/personalCenter` |
| 厂商 | 图星软件 / 超星 |
| 登录方式 | 统一认证 CAS 为主（`unifieAuthen=1`） |
| 分组 | `groupCode = 800555` |
| 语言头 | `x-lang: CHI`、`content-language: zh_CN` |

实测 `findConfig`：

```json
{
  "normalLogin": "0",
  "passportLogin": "0",
  "unifieAuthen": "1",
  "defaultLogin": "1",
  "unifieAuthenLoginUrl": "https://opac.gdut.edu.cn/sso-cas/cas/gdut/init?refer=..."
}
```

因此 App 不应引导用户使用图书馆独立密码，优先复用统一认证。

## 2. 登录与会话

### 2.1 CAS 统一认证

OPAC 的 CAS service：

```text
https://opac.gdut.edu.cn/sso-cas/cas/index/gdut
```

入口初始化 URL（会 302 到 `authserver.gdut.edu.cn`）：

```text
https://opac.gdut.edu.cn/sso-cas/cas/gdut/init
  ?refer=https%3A%2F%2Fopac.gdut.edu.cn%2Ffind%2Fsso%2Flogin%2Fgdut%2F0%3FpageType%3D0%26navigation%3D1
```

CAS 登录完成后，OPAC 最终会得到两个 Cookie：

| Cookie | 说明 |
|---|---|
| `jwt` | OPAC API Token（敏感） |
| `jwtHeader` | Token 对应的请求头名，实测为 `jwtOpacAuth` |

**注意：`jwt` 不是 CAS 回调直接 `Set-Cookie` 的。** 实测完整链路：

```text
1. GET /sso-cas/cas/gdut/init?refer=...
   -> 先拿到 mycasinfo / appFlag / JSESSIONID
2. CAS 登录，回调 /sso-cas/cas/index/gdut?ticket=...
   -> 302 到 /sso-cas/cas/index/gdut
3. 该页 200 HTML 内包含 passport2.chaoxing.com/api/v2/casreceive...
   -> 请求超星 passport2
4. passport2 200 HTML 内包含
   https://opac.gdut.edu.cn/find/sso/login/gdut/0?...&data=...&time=...&enc=...
5. 请求该 URL -> 302 到
   https://opac.gdut.edu.cn/#/Home?jwt=<jwt>&jwtHeader=jwtOpacAuth
   jwt 在 Location/前端 hash 中，不在 Set-Cookie 里
6. 原生端解析 URL 中的 jwt / jwtHeader，合成为 Cookie
   jwt=<jwt>; jwtHeader=jwtOpacAuth
```

因此原生登录必须：

- 先 bootstrap `init` URL，保留 `mycasinfo` / `appFlag`；
- 跟随 passport2 与 `/find/sso/login` 两段 HTML/302；
- 从最终 Location/hash 解析 `jwt` / `jwtHeader`，而不是只检查 Cookie。

`CasLoginService.loginForService` 已实现这条 handoff，调用方式：

```text
loginForService(username, password,
  'https://opac.gdut.edu.cn/sso-cas/cas/index/gdut',
  'jwt',
  OPAC_INIT_URL)
```

若设备/网络环境导致 CAS 链路异常，图书馆页仍提供 WebView 统一认证兜底：
登录完成后从 WebView URL 的 hash 或 Cookie 读取 `jwt`，写入 `LibrarySession`。

之后 OPAC API 请求需要：

```http
jwtOpacAuth: <jwt Cookie 的值>
groupCode: 800555
x-lang: CHI
content-language: zh_CN
mappingPath: <当前 SPA 路由去掉斜杠，通常为空>
Content-Type: application/json;charset=UTF-8
```

> 不要把 `jwt` 写入日志、普通 Preferences 或备份。  
> 原生 App 可以复用 `CasLoginService.loginForService()`，service 传上面的
> `https://opac.gdut.edu.cn/sso-cas/cas/index/gdut`，目标 Cookie 建议检查 `jwt`。

### 2.2 普通账号登录（备选）

前端仍保留账号密码登录：

```http
POST https://opac.gdut.edu.cn/oga/login
Content-Type: application/json;charset=UTF-8
```

请求字段：

```json
{
  "username": "图书馆账号",
  "mappingPath": "",
  "password": "DES-ECB-PKCS7(password, key='Libstar_%$#tx501') hex",
  "verifyCode": "验证码",
  "nextpath": "/personalCenter",
  "codeKey": "验证码 codeKey",
  "loginSystem": 1
}
```

密码加密：

- DES / ECB / PKCS7；
- key 为字符串 `Libstar_%$#tx501`；
- 前端输出 `ciphertext.toString()` 的 hex。

成功响应返回 `data.jwtHeader` 与 `data.jwt`，前端写入 sessionStorage 和 Cookie。  
由于广工当前配置为统一认证，**不建议主流程使用账号密码登录**。

### 2.3 会话探测与失效

```http
GET https://opac.gdut.edu.cn/oga/userinfo
```

成功返回用户信息；401/会话失效时前端会清除 `jwt`、`jwtHeader`、`userInfo` 并弹出登录。  
`userInfo` 字段包含：

```text
userId, primaryId, name, picUrl, jobDesc, jobType, unit, department,
position, gender, email, address, phone, postalCode, birthDate,
status, regDate, expirationDate, libCode, groupCode, collegeYear,
collegeClass, collegeDept, emailCheckFlag, mobileCheckFlag ...
```

App 只应取展示所需字段（如姓名、单位/学院、借阅额度），不要全量落库。

## 3. 我的借阅

### 3.1 当前借阅

```http
POST https://opac.gdut.edu.cn/find/loanInfo/loanList
Content-Type: application/json
```

请求：

```json
{
  "page": 1,
  "rows": 10,
  "searchType": 1,
  "searchContent": "",
  "sortType": 0,
  "startDate": null,
  "endDate": null
}
```

实测响应（当前账号无借阅）：

```json
{
  "success": true,
  "message": "操作成功",
  "errCode": 200,
  "errorCode": null,
  "data": {
    "searchResult": [],
    "loanNum": 30,
    "numFound": 0
  }
}
```

字段：

| 字段 | 说明 |
|---|---|
| `searchResult` | 借阅记录数组；空数组表示当前无借阅 |
| `loanNum` | 当前剩余可借阅数量（额度） |
| `numFound` | 记录总数 |

> 非空借阅记录的具体字段尚未取得样本（当前账号 0 条），
> 预计包含题名、条码、借阅日、应还日、续借次数、馆藏地等，需用有借阅的账号补测。

### 3.2 借阅历史

```http
POST https://opac.gdut.edu.cn/find/loanInfo/loanHistoryList
```

请求结构与 `loanList` 基本一致，可带日期范围。  
另有导出：

```text
GET /find/loanInfo/exportLoanList
GET /find/loanInfo/exportLoanHistoryList
```

### 3.3 续借

```http
POST https://opac.gdut.edu.cn/find/lendbook/reNew
```

前端通过 `renewBook` 调用；具体请求字段需在有借阅记录时抓取。  
预计需要记录 ID/条码列表，待补测。

### 3.4 欠款/账户

```text
GET /find/account/getTotalMoney      # 当前欠款
POST /find/account/getAccountDel     # 账户明细
POST /find/account/precreate         # 创建支付订单
GET  /find/account/payStatus         # 支付状态
```

## 4. 检索与馆藏

已在前端 JS 中确认的主要接口：

| 功能 | 方法 | 端点 |
|---|---|---|
| 首页书目列表 | GET/POST | `/find/index/bookList` |
| 搜索联想 | GET | `/find/index/searchAssociative` |
| 书目检索 | POST | `/find/unify/search` |
| 高级检索 | POST | `/find/unify/advancedSearch` |
| 检索模板 | GET | `/find/unify/getUnifyReruestBody` |
| 书目详情 | GET | `/find/searchResultDetail/getDetail` |
| 馆藏信息 | POST | `/find/searchResultDetail/getCatalog` |
| 册信息（条码/状态） | POST | `/find/physical/groupitems` |
| 按馆藏地分组 | POST | `/find/physical/groupItemsByLibCode` |
| 借阅分析 | GET | `/find/searchResultDetail/getLoanAnalysis` |
| 热门借阅 | POST | `/find/bookList/recordHotBookList` |
| 新书列表 | GET | `/find/books/popularBooks` |
| 电子书 | GET | `/find/searchResultDetail/getDuxiuEBook` |

### 4.1 公开目录：检索与馆藏**不需要登录**

实测（2026-11，curl 匿名请求 + 浏览器内核对）`/find/unify/search` 与
`/find/physical/groupitems` 都不要求 `jwt`，也不需要任何 Cookie：

```http
POST https://opac.gdut.edu.cn/find/unify/search
Content-Type: application/json;charset=UTF-8
groupCode: 800555
x-lang: CHI
content-language: zh_CN
mappingPath:
Referer: https://opac.gdut.edu.cn/
```

```json
{
  "docCode": [null],
  "litCode": [],
  "searchField": "keyWord",
  "searchFieldContent": "线性代数",
  "matchMode": "2",
  "resourceType": [], "subject": [], "discode1": [], "publisher": [],
  "libCode": [], "locationId": [], "eCollectionIds": [], "neweCollectionIds": [],
  "curLocationId": [], "campusId": [], "kindNo": [], "collectionName": [],
  "author": [], "langCode": [], "countryCode": [],
  "publishBegin": null, "publishEnd": null,
  "coreInclude": [], "ddType": [], "verifyStatus": [], "group": [],
  "sortField": "relevance", "sortClause": "asc",
  "page": 1, "rows": 20,
  "onlyOnShelf": null, "searchItems": null,
  "newCoreInclude": [], "customSub": [], "customSub0": [],
  "indexSearch": 1
}
```

两个必须注意的坑：

- **`docCode` 必须是 `[null]`**。写成 `["2"]` 服务端仍返回 `success: true`，但结果恒为 0 条；
- **缺字段会被当成会话问题**：body 只带 `searchWord` 之类的自造字段时，服务端返回
  `{"success":false,"errCode":9999,"message":"系统访问中断，请稍后再试！"}`，
  很容易误判为“需要登录”。按上面的完整字段集发送即可匿名检索。

`searchField` 支持：`keyWord`（任意词）、`title`、`author`、`isbn`、`callNo`（实测五个字段均可用）。
`rows` 实测 50 可用；翻页用 `page` 递增，同一组条件翻页结果稳定。

排序（`sortField` 实测）：

| 值 | 效果 |
|---|---|
| `relevance` | 相关度（默认） |
| `title_sort` | 题名序 |
| `publishYear` | 出版年序 |
| `in_date` | 入藏时间 |
| `publishTime` | **无效**，服务端直接返 0 条 |

`sortClause` 在 `publishYear` 上不生效（asc/desc 同序），在 `title_sort` 上生效；UI 只对外暴露字段，不暴露方向。
`onlyOnShelf` 传 `true/false` 会让 `data.numFound` 变成 `null` 且结果为 0，**不要用**。

响应：

```json
{
  "success": true, "errCode": 200,
  "data": {
    "numFound": 2718,
    "searchResult": [{
      "recordId": 1218412,
      "title": "线性代数. 第2版",
      "author": "…", "publisher": "…", "publishYear": "2019",
      "isbn": "978-7-04-039689-8", "isbns": ["…"],
      "callNoOne": "O151.2/98",
      "physicalCount": 3, "onShelfCountI": 3,
      "adstract": "…", "docCode": 1
    }],
    "facetResult": {}, "hlResult": {}, "levelResultList": []
  }
}
```

| 字段 | 说明 |
|---|---|
| `numFound` | 命中总数，用于分页 |
| `searchResult[].recordId` | 书目记录号，馆藏查询的入参 |
| `searchResult[].callNoOne` | 索书号 |
| `searchResult[].physicalCount` | 馆藏册数 |
| `searchResult[].onShelfCountI` | 在架册数 |
| `searchResult[].adstract` | 摘要（原文拼写如此） |

### 4.2 册信息（馆藏地/条码/状态）

```http
POST https://opac.gdut.edu.cn/find/physical/groupitems
```

```json
{ "recordId": 677239, "page": 1, "rows": 50 }
```

`data` 为册数组：

```json
{
  "itemId": 4213032,
  "callNo": "TP311.561/M17",
  "barcode": "A3398537",
  "locationName": "龙洞自然科学借阅室",
  "curLocationName": "龙洞自然科学借阅室",
  "libName": "广东工业大学",
  "processType": "在架",
  "itemPolicyName": "普通",
  "circAttr": "--",
  "inDate": "2017-05-02",
  "vol": "", "year": ""
}
```

`processType` 实测取值只有两类：`在架`、`借出-应还日期:YYYY-MM-DD`，
判断可借优先看它，`circAttr` 在该校数据里恒为 `--`。

### 4.3 已接入范围

`services/library/LibraryClient.ets`：

- `fetchOverview()`：当前借阅 + 可借额度（**需要**登录态）；
- `searchBooks(query, page)`：书目检索（公开目录，匿名，不依赖 `jwt`），带 5 分钟内存缓存；
  关键字是合法 ISBN 且字段为命草时自动改走 `isbn`；
- `fetchHoldings(recordId)`：册信息（同上）。

界面：

- `pages/library/LibraryPage.ets`：当前借阅 + 「馆藏检索」入口；
- `pages/library/LibrarySearchPage.ets`：字段切换（全部/书名/作者/索书号/ISBN）、
  排序菜单、无限滚动、最近检索（Preferences）、空/错态；“在浏览器打开”降级；
- `pages/library/LibraryBookPage.ets`：题录 + 摘要（可展开）+ 按馆藏地分组的册信息；
  册信息由检索页通过路由参数传入（检索结果已含题录字段，不再多拉一次）。

扫码入口：我的页标题栏 → 扫到 ISBN → 直接进 `library-search`。

仍未接入：续借、预约/委托、欠款支付、借阅历史分页、电子书跳转、书目聚类筛选（`facetResult`）。

## 5. 推荐接入方案

```text
统一认证 CAS
  -> init 预热（mycasinfo / appFlag）
  -> service = https://opac.gdut.edu.cn/sso-cas/cas/index/gdut
  -> passport2 -> /find/sso/login -> 解析 hash 中的 jwt / jwtHeader
  -> GET /oga/userinfo
  -> POST /find/loanInfo/loanList
  -> 渲染：当前借阅、可借额度、到期日、欠款
```

建议新增：

```text
services/library/LibrarySession.ets    # jwt / jwtHeader（内存）
services/library/LibraryClient.ets     # OPAC 请求与 401 重登
services/library/LibraryModels.ets     # LoanRecord / UserSummary
services/library/LibraryService.ets    # 查询、缓存、到期提醒
```

### 缓存与提醒

- 借阅列表缓存 10–30 分钟；
- 到期前 3 天生成本地提醒/系统日历事件（可复用现有 ReminderService）；
- 欠款金额只在用户主动打开时刷新；
- 退出统一认证时清空 LibrarySession。

### 隐私

- JWT 只放内存/系统安全存储，不写日志、不写普通 Preferences、不进入备份；
- 借阅记录不导出到备份；
- 不采集完整身份证、手机号等无关字段。

## 6. 待补测

- [ ] 有借阅记录时 `loanList.searchResult` 的完整字段。
- [ ] `reNew` 请求体与成功/失败返回。
- [ ] `loanHistoryList` 的日期筛选字段与分页。
- [ ] OPAC CAS 登录后 `jwt` 的具体过期时间与刷新策略。
- [ ] 欠款/支付接口是否需要二次密码或短信。
- [ ] 图书到期提醒的时区与“应还日”字段格式。
