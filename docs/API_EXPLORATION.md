# 广工校园接口探索记录

状态：2026-11 整理。记录本项目已经接入或验证过的学校系统接口，供后续维护和适配使用。账号、密码、Cookie、ticket 不写入本文档。

参考：

- Goke jxfw 接口调研：`https://github.com/xihale/goke/blob/main/docs/jxfw-gdut-api.md`
- Goke 空教室实现：`app/src/main/java/app/goke/jxfw/JwcwxClient.kt`、`core/src/main/kotlin/app/goke/core/jxfw/JwcwxClassroom.kt`
- 本项目实现：`entry/src/main/ets/services/{jxfw,jwcwx,tzcs}/`

## 1. 统一认证 CAS

入口：

```text
https://authserver.gdut.edu.cn/authserver/login?service=<URL 编码后的业务系统地址>
```

所有业务系统共用同一套金智 CAS，差别只在 `service`：

| 系统 | service |
|---|---|
| 教务 jxfw | `https://jxfw.gdut.edu.cn/new/ssoLogin` |
| 教室查询 jwcwx | `http://jwcwx.gdut.edu.cn/login/cas` |
| 体测 tzcs | 独立 ASP.NET 登录，不走 CAS |

流程：

1. GET 登录页，解析：
   - `pwdEncryptSalt`：本次登录的 AES key（16 字符）；
   - `execution`：表单动态值；
   - `captchaSwitch` / `checkNeedCaptcha`：是否需要验证码。
2. 密码加密：
   - 明文 = `randomString(64) + password`；
   - `AES-128-CBC/PKCS7`，key = salt 的 UTF-8 字节，IV = `randomString(16)`；
   - Base64 输出。
3. POST 登录页，字段：
   `username`、`password`（密文）、`captcha`、`_eventId=submit`、`lt`、`cllt=userNameLogin`、`dllt=generalLogin`、`execution`。
4. 成功返回 302，`Location` 为业务系统带 ticket 的地址；手动跟随重定向，直到业务域下发 `JSESSIONID`。

实现注意：

- `@ohos.net.http` 的 POST body 必须放 `extraData`；
- `maxRedirects: 0` 遇到 302 可能抛 `2300047`，用 `headersReceive` 捕获 `Location` / `Set-Cookie` 后手动跟随；
- `response.cookies` 是 Netscape cookie-file 格式（制表符分隔），不是 `Set-Cookie` 文本；
- 手动跟随重定向时，遇到 `http://jwcwx.gdut.edu.cn` 要立即升级为 `https://`，否则在模拟器上会连接超时。
- `loginForService()` 会在进入目标域后继续跟随一次 `/login/cas`，用于绑定服务端 CAS 上下文；提前停止会得到“已登录但接口返回 -403”。

## 2. 教务 jxfw

基址：`https://jxfw.gdut.edu.cn`，认证 Cookie：`JSESSIONID`。

通用请求头：

```text
X-Requested-With: XMLHttpRequest
Accept: application/json, text/javascript, */*; q=0.01
Referer: <对应列表页>
```

### 2.1 课表

| 功能 | 方法 | 端点 | 说明 |
|---|---|---|---|
| 全学期课表 | GET | `/xsgrkbcx!xsAllKbList.action?xnxqdm=202601` | HTML 内嵌 `var kbxx = [...]` |
| 按周课表 | GET | `/xsgrkbcx!getKbRq.action?xnxqdm=202601&zc=13` | JSON `[[课程], [日期]]` |
| 考试安排 | POST | `/xsksap!getDataList.action` | `xnxqdm,page,rows,sort=zc,xq,jcdm2,order=asc` |
| 成绩 | POST | `/xskccjxx!getDataList.action` | `xnxqdm,page,rows=100,sort=xnxqdm,order=asc` |

字段与坑：

- `zcs`、`jcdm2` 是乱序逗号串，需要 split → 数字排序；兼容 `01-04` 区间写法。
- 全学期用 `jxcdmcs`（多教室逗号分隔），按周用 `jxcdmc`。
- `teaxms` 可能带 `[主讲]` / `[辅讲]` 后缀。
- 按周行没有 `kcrwdm`，跨周同步只能按（课程名、星期、节次）匹配。
- `tkbz` 不能作为调课标记。
- 开学日取按周接口 `data[1]` 中 `xqmc === "1"` 的 `rq`。
- 成绩 `rows` 中 `xf`、`zcj`、`cjjd` 可能是数字或字符串；缓考、未出分、被替代占位需要排除。

### 2.2 成绩

```text
POST /xskccjxx!getDataList.action
Content-Type: application/x-www-form-urlencoded; charset=UTF-8
xnxqdm=<term>&jhlxdm=&page=1&rows=100&sort=xnxqdm&order=asc
```

`GradeService` 最多拉 10 页并按 `term|code|name` 去重；GPA 只统计有绩点且通过（绩点 > 0 或分数 ≥ 60）的课程。

## 3. 空教室 jwcwx

基址：`https://jwcwx.gdut.edu.cn`。认证与 jxfw 共用 CAS，但需要单独建立 jwcwx 的 `JSESSIONID`。

### 3.1 登录链路

```text
GET  https://authserver.gdut.edu.cn/authserver/login?service=http%3A%2F%2Fjwcwx.gdut.edu.cn%2Flogin%2Fcas
POST 同一地址（加密表单）
302  http://jwcwx.gdut.edu.cn/login/cas?ticket=ST-...
     ↑ 必须立即改成 https:// 再请求
302  /login/cas
     ↑ 再请求一次，绑定 LoginController 的服务端用户上下文
GET  /free-class-room/buildingData?jwCode=
     ↑ code=0 视为登录成功
```

关键点：

- 只跟随到 ticket 回调就停止，接口会返回 `{"code":-403,"message":"您无权请求该资源，请先登录"}`；
- 必须完成 `/login/cas` 的后续请求（即使该请求返回 500 页面，只要已拿到 `JSESSIONID` 即可）；
- `buildingData` 请求需要 `X-Requested-With: XMLHttpRequest`，否则可能拿到登录 HTML。

### 3.2 教学楼

```text
GET /free-class-room/buildingData?jwCode=
X-Requested-With: XMLHttpRequest
```

返回：

```json
{
  "code": 0,
  "message": "成功",
  "data": [
    {
      "jzwbh": "05",
      "jzwdm": "0005",
      "jzwmc": "教学三号楼(城)",
      "szxqdm": "1",
      "xqmc": "大学城校区"
    }
  ]
}
```

| 字段 | 含义 |
|---|---|
| `jzwdm` | 教学楼代码，后续接口使用 |
| `jzwbh` | 楼栋编号 |
| `jzwmc` | 楼名 |
| `szxqdm` / `xqmc` | 校区代码 / 校区名 |

### 3.3 教室列表

```text
GET /free-class-room/classroom/{jzwdm}?jwCode=
Accept: text/html
```

返回 HTML 表格，解析规则：

- 每行 `<tr>`；
- 教室名在 `<th class="js">...</th>`；
- 教室代码在任意 `<td>` 的 `class="qk-{roomCode}-..."`；
- 容量在 `data-rnrs="223"`；
- 同一教室可能在多个节次单元格重复出现，按 `roomCode` 去重。

输出：`{ code, name, capacity }`。

### 3.4 当天占用

```text
GET /free-class-room/classroomUsedData?jwCode=&jzwdm=0005&rq=2026-11-24
X-Requested-With: XMLHttpRequest
```

返回：

```json
{
  "code": 0,
  "data": [
    {
      "dm": "3404218",
      "jcdm": "020304",
      "jcdm2": "02,03,04",
      "jxcddm": "011030201",
      "jxcdmc": "教3-201",
      "kcmc": "电影与深层心理学",
      "teaxms": "田老师",
      "jxbmc": "教学班482",
      "sknrjj": "五、好莱坞电影的批判性读解",
      "xq": "1",
      "zc": "8",
      "sytype": "1",
      "rs": 108
    }
  ]
}
```

| 字段 | 含义 |
|---|---|
| `dm` | 占用记录 ID |
| `jxcddm` | 教室代码，必须与教室列表的 `qk-` 代码对应 |
| `jxcdmc` | 教室名（借用/考试时可能为空） |
| `jcdm2` | 节次列表，优先使用，如 `02,03,04` |
| `jcdm` | 节次原始串，回退时按两位切分 |
| `kcmc` | 课程名（借用/考试可能为空） |
| `sknrjj` | 授课内容 / 借用原因 |
| `teaxms` | 教师 / 借用人 / 监考 |
| `rs` | 人数 |
| `sytype` | 1 课程、2 借用、3 锁定、4 考试、其他未知 |

解析后得到 `periods: number[]`，页面据此计算每间教室 1–12 节的空闲状态。

### 3.5 错误与会话

- `-403 您无权请求该资源，请先登录`：CAS 登录未完成上下文绑定，重新执行完整 ticket + `/login/cas` 链路；
- 302 到 `/login` 或 `authserver`：会话失效，需要重新 CAS；
- 其他 `code != 0`：接口层错误，按返回 `message` 展示；
- 建议 `登录 → 拉数据`，不长期保活；多端登录会互相踢掉 `JSESSIONID`。

## 4. 体测 tzcs

基址：`http://tzcs.gdut.edu.cn`，独立 ASP.NET 平台，不使用 CAS。

### 4.1 登录页

```text
GET /Src/PlatForm/user/Login_m.aspx?Mode=2&SchoolCode=84223B2F7B9F3A91A2F9913135761855
```

表单隐藏字段：

- `__VIEWSTATE`
- `__EVENTVALIDATION`
- `hidSchoolNo=13010`
- `hidCode=...`
- `hidRole=2`
- `drpRole=2`

可见字段：`username`、`password`、`vercode`、`BtnSubmit=登 入`。

密码加密：

- key = `SHA256(hidSchoolNo)` 前 16 字节；
- IV = `hidCode` 前 16 字节；
- `AES-128-CBC/PKCS7` → Base64。

验证码：

```text
GET /Src/PlatForm/user/GetCheckCode.aspx
```

返回 GIF 图片。验证码与登录 POST 必须使用同一个 `ASP.NET_SessionId`。

成功跳转：

```js
location.href = '../Personal/Index.aspx'
```

### 4.2 成绩页

| 功能 | 端点 |
|---|---|
| 当前学年 | `/Src/PlatForm/PHTest/PHTest_StudentScore.aspx` |
| 历史学年 | `/Src/PlatForm/PHTest/PHTest_StudentScore_H.aspx?DataYear=<year>` |

页面按测试项目表格输出：项目名、实测值、得分、等级、分值；解析时排除空项、性别不适用项（男生 1000 米/引体向上，女生 800 米/仰卧起坐/往返跑）和“标准分”等汇总行。

### 4.3 当前实现选择

App 内使用 WebView 打开官方登录页，用户手动完成验证码；登录成功跳转 `Personal` 后读取 Cookie，再用原生 HTTP 拉取成绩页。这样避免 ASP.NET 验证码会话不一致，也兼容页面改版。

## 5. HarmonyOS 适配要点

- 所有 POST 表单 body 使用 `extraData`；
- 302 需要 `headersReceive` 捕获，不能依赖 `maxRedirects` 自动跟随；
- `response.cookies` 需要同时兼容 Netscape cookie-file 与 `Set-Cookie`；
- 请求业务域前把 `http://jwcwx.gdut.edu.cn` 升级成 `https://`；
- CAS 登录后必须继续完成服务端的 ticket 回调，不能只拿 cookie 就返回；
- 会话失效统一抛 `SESSION`，由客户端自动重新登录并重试一次；
- 不要把密码、Cookie、ticket 写入日志或仓库。
