# 工大助手设计规范

> 状态：**设计基线（已确认）**。本文作为工大助手的界面/材质/图标规范；未完成的迁移项在“实施阶段”中标注。  
> 参考：`FengHDSL/XJAU-Helper`（MIT License）。参考其 `MainView` / `MaterialCard` / `MaterialButton` / `IconCircleButton` / `MineView` 的实现与注释，不直接照搬业务代码。  
> 本文只固定“视觉与组件规则”，不改变业务数据流。

### 当前实现状态

- 已落地：校园服务网格卡高度 118vp、图书馆网格卡与“更多服务”宽入口对调、图书馆原生 OPAC 自动登录、自定义书本图标、底栏 `lightColor`/宽度、加号材质按钮、我的页图标去重、三套主题色、日期条高亮移动与 Tab 页面平移动效、光感强度档位、ICS 导出、本地通知与 unsigned HAP CI。
- 待后续：分类胶囊逐项材质化、卡片 `MaterialCard` 全量迁移。

## 1. 设计目标

- 原生 HarmonyOS 质感：悬浮底栏、沉浸光感、按压缩放/流光。
- 同一层级不重复使用同一种图标；每个入口有唯一语义。
- 卡片、按钮、分类栏只保留一层视觉，不出现“胶囊套胶囊”。
- 浅色/深色、壁纸/纯色背景都可读。
- 动效克制：切换、按压、流光有反馈，不影响阅读。

## 2. 设计 Token

| 项目 | 规范 |
|---|---|
| 页面左右边距 | 16vp |
| 卡片圆角 | 18–20vp |
| 卡片内边距 | 16vp |
| 行高 | 52–56vp |
| 图标尺寸 | 底栏 20vp；设置行 19–20vp；分类栏 16–18vp；FAB 24vp |
| 最小点击区域 | 40×40vp |
| 主色 | `brandColor`（`ThemeColor`，默认鸿蒙蓝） |
| 主色文字 | `AppTheme.ON_BRAND` |
| 次级文字 | `AppTheme.TEXT_SECONDARY` |
| 三级文字 | `AppTheme.TEXT_TERTIARY` |
| 卡片底 | `AppTheme.CARD_BG` 或系统材质 |
| 分隔线 | `AppTheme.DIVIDER` |
| 页面底 | `AppTheme.BG` |

图标风格：

- 线性图标统一 1.5–2px 视觉粗细，圆角端点；
- 选中态用主题色，未选中用 `TEXT_SECONDARY`；
- 同一张卡片/同一层级不出现重复图标；
- 同一概念在不同层级必须更换图形或使用不同填充状态（如“日历”用于当前学期，“同步箭头”用于系统日历同步）。

## 2.1 主题色与光感

| 名称 | 色值 | 说明 |
|---|---|---|
| 鸿蒙蓝 | `#0A59F7` | 默认 |
| 广工红 | `#C8102E` | 校色 |
| Goke绿 | `#CDEBE3` | 薄荷绿（浅色强调色，表面使用深色前景） |

- 入口：我的 → 外观 → 主题色；
- 光感强度：我的 → 外观 → 材质与动效 → 跟随系统/精致/柔和/流畅；
- 持久化键：`themeColorId`，保存在 `appearance_settings`；
- 运行时通过 `Index` 的 `@Provide('brandColor')` 下发，页面/组件用 `@Consume` 接收；
- 主题色变化立即作用于按钮、选中态、悬浮栏光效和强调文字；
- Goke绿为浅色表面色：`onBrandColor` 自动切为深色，`brandTextColor` 使用深薄荷绿保证白底可读；
- 半透明强调底使用 `ThemeColor.alpha(brandColor, alpha)` 派生，不写死蓝色；
- 光感强度：跟随系统 / 精致 / 柔和 / 流畅，映射到 `hdsMaterial.MaterialLevel`；
- `module.json5` 启用 `ohos.arkui.UIMaterial.state=enable`。

## 3. 沉浸光感实现规则

### 3.1 两类原生材质

1. **HDS 组件材质**：用于 `HdsTabs` 底栏、`HdsNavDestination` 标题栏/返回按钮。
   - `HdsTabs.barFloatingStyle.systemMaterialEffect`
   - `materialType: hdsMaterial.MaterialType.IMMERSIVE`（不支持时 `ADAPTIVE`）
   - `materialLevel: ADAPTIVE`
   - `lightColor: 主题色 28%–40% 透明度`
2. **自定义组件材质**：用于圆形加号按钮、分类胶囊、自定义卡片。
   - 用透明 `Toggle({ type: ToggleType.Button })` 作为材质承载层；
   - 叠加 `uiMaterial.ImmersiveMaterial`（静态 style，`applyShadow` 小按钮关闭）；
   - 内容（SymbolGlyph/Text/Image）作为兄弟节点叠在承载层之上，`hitTestBehavior(None)`；
   - **承载层和内容都不能有不透明底色或 `backgroundBlurStyle`**，否则会盖住材质。

### 3.2 降级

- 设备不支持 IMMERSIVE / 用户关闭沉浸光感：
  - 底栏/标题栏自动回落 `ADAPTIVE` 或无材质；
  - 自定义组件回落薄玻璃（半透明白/黑 + 轻磨砂 + 1px 淡亮边）；
  - 不能出现“材质消失后按钮不可见”。

### 3.3 反例

- 外层胶囊 + 内层胶囊；
- 材质层上再叠一层不透明 `backgroundColor`；
- 普通 `Button` 直接挂系统材质（真机可能不渲染）；
- 用 `backgroundBlurStyle` 模拟系统材质后又盖实色。

## 4. 悬浮底栏

参考 XJAU `MainView`：

```text
HdsTabs
  barPosition: End
  barOverlap: true
  barMode: Fixed
  animationDuration: 280ms（可关闭为 0；仅保留页面平移）
  barFloatingStyle:
    barWidth: 340 / 420 / 500 (small / medium / large)
    barSideMargin: 12
    barBottomMargin: 20（AppTheme.TAB_BAR_BOTTOM_MARGIN；PC/浮动窗口自动留白）
    adaptToHandedness: true
    lightColor: 主题色 (深色 40% / 浅色 28%)
    systemMaterialEffect: IMMERSIVE + ADAPTIVE
```

Tab 项：

- 图标 22×22（外框 28），文字 10vp，图标与文字间距 3vp；
- 单 Tab 高 46vp；
- 选中：图标/文字主题色 + Medium 字重；
- 未选中：`TEXT_SECONDARY` / 深色模式下白色；
- 点击只更新 `activeIndex`，页面切换走 `changeIndex()`，避免绕过切页动画；
- 固定 5 个 Tab：今日 / 课表 / 日历 / 校园 / 我的。

## 5. 加号按钮（FAB）

参考 XJAU `IconCircleButton`：

```text
Stack:
  Toggle(Type.Button, isOn=false) 56×56 圆形透明承载层
    + uiMaterial.ImmersiveMaterial(style: REGULAR/THIN, applyShadow: true)
    + interactive: true, lightEffect: 主题色
  SymbolGlyph(plus) 24vp，主题色或 ON_BRAND，hitTestBehavior(None)
```

规则：

- 只有一层圆形，不再叠加第二个圆底；
- 按压缩放/流光由 Toggle 承载层响应；
- 不支持材质时回落到 `FAB_BG` 玻璃底 + 微阴影；
- 位置：右侧 16vp，底部高于底栏 92vp；
- 默认用于日历“新建”，点击打开添加 Sheet；
- 如果后续增加多个快捷操作，不新增第二个同款 FAB，改为 Sheet 内动作。

## 6. 分类胶囊（校园新闻等）

**不设外层胶囊容器**，只给每个分类项自己的胶囊。

- 容器：仅 `Row`，间距 8vp，无背景、无边框、无模糊；
- 单项：高 44vp，圆角 22vp，横向内边距 14–16vp；
- 选中：主题色实底 + `ON_BRAND` 文字 + Medium；
- 未选中：透明/半透明材质承载层 + 1px 淡亮边 + `TEXT_PRIMARY`；
- 沉浸光感开启时，未选中项使用系统材质；关闭时用半透明卡片色兜底；
- 每项等宽或按文字宽度自适应，不出现“外层胶囊”；
- 图标可选；若使用图标，需保证同一栏图标风格一致。

## 7. “我的”页图标规范

### 7.1 唯一性规则

- **同一张卡片内不得出现重复图标**；
- **同一层级不得用同一图标表达两个不同入口**；
- 重复概念必须换层级或换图形：
  - 当前学期 → 日历；
  - 系统日历同步 → 同步箭头；
  - 提醒 → 时钟；
- 新增入口先查本表，再决定是否新增自定义 SVG。

### 7.2 建议映射

| 入口 | 建议图标 | 说明 |
|---|---|---|
| 桌面小组件 | `sys.symbol.square_fill_grid_2x2` | 2×2 网格，表达组件 |
| 外观 | `sys.symbol.eye` | 主题/视觉 |
| 功能设置 | `sys.symbol.list_square` | 功能列表 |
| 当前学期 | `sys.symbol.calendar` | 学期/日期 |
| 数据与备份 | `sys.symbol.doc_plaintext` | 数据文件 |
| 系统日历同步 | `sys.symbol.arrow_clockwise` | 同步，避免与当前学期重复 |
| 上课与考试提醒 | `sys.symbol.clock` | 时间提醒 |
| 关于工大助手 | 自定义 `info.svg` 或 `sys.symbol.questionmark_circle` | 避免与头像 `person` 重复 |
| 图书馆 | 自定义 `book.svg` | 校园页入口，避免与成绩/空教室图标重复 |

> 如果系统符号名在目标 SDK 不可用，使用 XJAU 风格的 48×48 线性 SVG，统一 `currentColor` 染色。

### 7.3 现有重复项

| 位置 | 现状 | 问题 | 建议 |
|---|---|---|---|
| 校园与效率 | 桌面小组件、功能设置都用 `list_square` | 同层重复 | 桌面小组件改网格图标 |
| 同步与数据 | 当前学期、系统日历同步都用 `calendar` | 同层重复 | 系统日历同步改同步箭头 |

## 8. 图书馆入口与更多服务

校园服务四张网格卡片：高 118vp、内边距 14vp、图标与文字间距 6vp。图书馆作为第四张网格卡，“更多服务”改为下方全宽入口：

```text
[成绩与 GPA] [体测成绩]
[空教室]     [图书馆]

[grid icon 42×42 / 主题色淡底]
更多服务
更多校园服务入口                              >
```

- 图书馆网格卡沿用 118vp 网格卡高度，使用自定义 `ic_library_book.svg`（已落地），不与成绩卡 `doc_plaintext` 重复；
- 更多服务宽入口高 68vp，圆角 18vp，图标容器 42×42、主题色 10% 透明底，右侧 chevron 14vp；
- 点击图书馆进入原生图书馆页，而不是直接跳出浏览器；
- 图书馆页提供“在浏览器打开”原生按钮。

图书馆页：

- 顶部：姓名/学院、当前可借数量、当前借阅数量；
- 当前借阅：书名、作者、应还日期、馆藏地；
- 无借阅：空状态；
- 登录失败：提供“登录图书馆”（WebView 统一认证）与“重新加载”；
- WebView 登录成功读取 `jwt`/`jwtHeader` 后，通过会话版本号通知图书馆页自动刷新；
- 数据来自 OPAC，不在备份中保存借阅记录；
- 原生 CAS 登录已打通：init 预热 → CAS → passport2 → `/find/sso/login` → 解析 hash 中的 `jwt`/`jwtHeader`，首次进入自动登录；
- 原生登录异常时保留 WebView 统一认证兜底。

## 9. 其他组件

### 卡片

- 圆角 16–20vp；卡片之间 12–14vp；
- 材质卡使用 `MaterialCard` 承载层；材质生效时卡片自身底色/磨砂/阴影让出；
- 同一张卡只保留一层视觉。

### 按钮

- 主按钮：主题色实底，高 42–46vp，胶囊 21–23vp；
- 次按钮：玻璃/材质底，文字 `TEXT_PRIMARY`；
- 圆形图标按钮：34–40vp，使用 `IconCircleButton` 模式；
- 顶栏按钮材质常驻，不随全局光感关闭而消失。

## 9.1 动效基线

- 页面切换：仅使用 `HdsTabs.animationDuration = 280ms` 的页面平移动画；不做内容淡入/上浮，不纳入逐元素浮现；
- 日期条高亮：空教室页与日历周视图使用单层高亮块，`220ms EaseOut` 移动；跨周直接重置，不做长距离滑动；
- 高亮块只动位置，不改变日期项布局；文字/圆点保持在上层；
- 不做逐卡错峰动画，避免与滚动和列表复用冲突。

## 10. 实施阶段（待确认）

**阶段 1（已完成）**
- 固定分类胶囊规则；
- 图书馆网格卡、更多服务宽入口与图书馆页；
- 统一“我的”页图标映射，修复重复图标。

**阶段 2（已完成）**
- 底栏加 `lightColor` 与 340/420/500 宽度；
- 新增 FAB 材质承载 Toggle，材质不可用时回落 `FAB_BG`；
- 日历 FAB 改为材质承载圆形按钮。

**阶段 3（后续）**
- 设置页/校园页卡片逐步迁到 `MaterialCard`；
- 分类胶囊逐项材质化；
- 统一按压/流光/降级策略。

## 11. 已确认项

- [x] 底栏保持 5 个 Tab，采用 340/420/500 悬浮宽度。
- [x] 加号按钮固定 56vp 材质圆形，位置右 16 / 底栏上 92。
- [x] “我的”页图标映射按上表执行；新增 `info.svg`、`book.svg`（实际使用系统 `info_circle` 与自定义书本 SVG）。
- [x] 分类栏完全去掉外层容器，仅保留单项胶囊。
- [x] 图书馆原生 CAS 自动登录，WebView 仅作异常兜底。
- [ ] 卡片 `MaterialCard` 全量迁移：列为后续阶段。
