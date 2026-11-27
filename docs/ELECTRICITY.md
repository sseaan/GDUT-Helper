# 电精灵（bd.bdfairy.cn）电表查询接口调研

> 调研时间：2026-11  
> 调研方式：curl 直接打站点 + 真机核对；本文不含任何真实表号、余额和房间号。  
> 实现：`services/electric/*`、`pages/electric/PowerPage.ets`（Beta，默认关闭）。

## 1. 是什么

学校宿舍电费由第三方「电精灵」（`bd.bdfairy.cn`，微信 H5）提供，**免登录**即可按表号查余额。
站点是服务端渲染的 Vue 页面，没有 JSON 接口，读数写在 `const yffye = ref('17.07')` 这类表达式里。

## 2. 校区与 areaId

| areaId | 覆盖范围 | 站点档位 |
|---|---|---|
| `54` | 大学城东西区 / 东风路 / 龙洞 | full（余额 + 账单 + 明细） |
| `136` | 番禺 | full |
| `128` | 揭阳 | full |

`areaName` 需要与站点注册表一致（`广东工业大学(大学城东西区/东风路/龙洞校区)` 等），
只影响站点侧展示。

## 3. 链路

```text
POST /selectarea    {"areaId","areaName"}      → {"data":"login","band":""}，同时下发 connect.sid
POST /phonejcbd     {}                          → 可选：会话已绑房时先解绑
POST /selectmeter   {"comAddress","hidType":"电表","room":""} → {"url":"/meter_main"}
GET  /meter_main                                → HTML，读 ref('...')
GET  /electricbill                              → HTML，读 billData 与 month
```

请求头：微信 UA + `X-Requested-With: com.tencent.mm` + `Origin`/`Referer`，`Content-Type: application/json`。

**不要先访问 `GET /?id={areaId}`**：那一步 302 到微信 OAuth，`maxRedirects: 0` 在设备上可能直接抛
`2300047`，跟随又会卡在微信域名；实测 `/selectarea` 自己就会 `Set-Cookie`，入口请求整段省略。

## 4. 读数页字段

| key | 含义 |
|---|---|
| `yffye` | 预付费余额（元） |
| `bzye` / `bzdye` | 补助余额 |
| `zye` | 总余额 |
| `zydl` | 累计电量（度） |
| `dbzt` | 闸位状态（如「合闸」） |
| `cbsj` | 抄表时间 |
| `roomaddr` | 房间号（可能渲染成字符串 `undefined`） |

解析只抽 `(?:const|let|var) X = ref('v')`，`ref(JSON.parse('...'))` 这类不会被误抓；
`undefined`/`null`/空串在 `ElectricParser.clean()` 里统一清空。

月账单页面板：`billData = ref({qcdl:"..", qmdl:"..", ydl:"..", ydje:".."})`，
必须定位到**赋值语句**（模板里还有 `{{ billData.qcdl }}`）；`month` 是上一个结算月，
11 月查到的是 `2026-10`，所以界面标题用「月账单」而不是「本月用电」。

## 5. 实测踩到的坑

1. **校区选错不会报错，而是挂住**：同一表号在 `136` 约 2s 返回，在 `54` 二十余秒零字节。
   客户端必须按「当前校区 → 其余校区」回退，并把命中的校区记住。
2. **无效表号同样表现为无响应**，不是优雅的 `empty`；读超时压到 6s/8s，
   文案提示「表号可能有误，也可能站点暂时不可用」。
3. **会话绑定态**：`/selectarea` 会回 `band:"1"` 或 `data:"selectmeter"`，说明会话已被标记绑房，
   此时 `/selectmeter` 常返回错误页，需要先 `POST /phonejcbd` 再选校。
4. **明文 HTTP**：`https://bd.bdfairy.cn` 不可达，只能走 `http://`。
   `@ohos.net.networkSecurity.isCleartextPermitted()` 默认允许，项目里 tzcs 也是 `http://`。
5. **Cookie**：`HttpRequest.enableAutoCookie()` 是 API 26 的能力，项目最低兼容 API 23，
   所以手写 cookie jar：读 `response.cookies`（Netscape 格式），为空时退回 `Set-Cookie` 响应头，
   按 domain 过滤后自己拼 `Cookie` 头。没有 Cookie 时 `/meter_main` 返回 `500 + errorApp`。

## 6. 待补测

- [ ] 日用电明细（`POST /electricdetail`，表单编码）
- [ ] 楼栋 → 楼层 → 房间 → 表号 级联（`/getB`、`/login`）在广工是否稳定
- [ ] 站点模板改版后的解析降级路径
