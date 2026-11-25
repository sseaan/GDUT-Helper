# 脱敏 fixture 说明

本目录保存广工教务、体测和空教室接口的**脱敏响应样例**，用于解析器单元测试和协议回归。M0 阶段只固化样例，不包含真实账号、Cookie、成绩或课表。

## 文件

| 文件 | 来源端点/页面 | 用途 |
| --- | --- | --- |
| `jxfw-all-kb.sample.html` | `GET /xsgrkbcx!xsAllKbList.action` | 全学期课表 `kbxx` 解析；覆盖乱序周次、多教室、教师后缀 |
| `jxfw-week.sample.json` | `GET /xsgrkbcx!getKbRq.action?xnxqdm=...&zc=...` | 按周课表 `[[课程],[日期]]` 解析与开学日推导 |
| `jxfw-exams.sample.json` | `POST /xsksap!getDataList.action` | 考试安排解析与稳定 ID |
| `jxfw-grades.sample.json` | `POST /xskccjxx!getDataList.action` | 成绩解析及 GPA 排除规则（缓考、未出分） |
| `tzcs-score.sample.html` | 师生云体测学年成绩页 | 体测 HTML 表格、BMI 合并行、总分/等级解析 |
| `jwcwx-buildings.sample.json` | `GET /free-class-room/buildingData` | 教学楼列表 |
| `jwcwx-rooms.sample.html` | `GET /free-class-room/classroom/{code}` | 教室列表与容量 |
| `jwcwx-occupancy.sample.json` | `GET /free-class-room/classroomUsedData` | 教室占用、节次与占用类型 |

## 脱敏规则

- 姓名统一改为“张老师/李老师/测试学生”等虚构值；
- 学号统一为 `3124000000` 一类虚构值；
- 不包含真实 Cookie、JSESSIONID、CASTGC、密码、验证码或请求头；
- 课程、成绩、教室和考试数据均为构造值，只保留真实接口的字段结构和边界情况；
- 新增 fixture 时必须确认不含个人身份信息，并在本文件登记来源与覆盖场景。

## 后续使用

M1 引入本地单元测试框架（hypium）后，解析器测试应直接消费这些文件：

```text
fixture → Parser → 领域对象 → 断言
```

解析器不得依赖 UI、网络或数据库；真实网络响应先经脱敏再进入仓库。后续如果接口字段发生变化，先更新 fixture 和测试，再修改解析器。
