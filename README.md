# 工大助手

一款专为广工学生打造的功能聚合 App，可以在鸿蒙系统上快速、便捷地获取校园信息。

## 当前状态

**1.0.0 发版准备**：工大助手已完成教务同步、成绩/GPA、体测、空教室、课表/日历、提醒与系统日历、桌面卡片、数据备份/恢复和 ICS/XLSX 导入。当前版本重点在真机回归和导入格式兼容。

- 教务：原生 CAS 登录、自动重登、全量/按周同步、课程异常与删除墓碑
- 校园：成绩/GPA、体测 WebView 登录、空教室校区/楼栋/周次查询
- 本地：课表、日历、考试、提醒、系统日历、桌面卡片
- 数据：JSON 备份恢复、ICS/XLSX 导入、本地数据清空
- 平台：HarmonyOS 6.1.0(23) 及以上，当前测试环境 API 26

- 开发记录与计划：[`AGENT.md`](AGENT.md)
- 隐私说明：[`docs/PRIVACY.md`](docs/PRIVACY.md)
- 签名配置：[`docs/SIGNING.md`](docs/SIGNING.md)
- 接口探索记录：[`docs/API_EXPLORATION.md`](docs/API_EXPLORATION.md)

## 构建

依赖 DevEco Studio 26.0.1（内置 HarmonyOS SDK API 26 Beta1、hvigor 与 JBR）：

```bash
./scripts/build-debug.sh          # Debug
./scripts/build-debug.sh release  # Release
```

产物位于 `entry/build/default/outputs/default/`：`entry-default-signed.hap`（已配置自动签名）或 `entry-default-unsigned.hap`。

首次克隆后需在 DevEco Studio 的“项目结构 > 签名配置”中启用自动生成签名；未配置签名时仍可构建 unsigned HAP，但无法安装到真机。

## 目录

- `entry/`：HarmonyOS 主模块（ArkTS / ArkUI）
- `entry/src/main/ets/pages/`：HDS 应用壳层与今日/课表/日历/校园/我的/空教室页面
- `entry/src/main/ets/components/`：底栏图标、圆形图标按钮等通用组件
- `entry/src/test/fixtures/`：脱敏教务、体测、空教室响应样例
- `docs/`：接口调研、隐私说明和签名配置
