---
name: medcare-data-qa
description: 当需要由一个基于治理后数仓的机器人来回答医疗康养业务的销售目标 / 实际销售额 / 完成率问题时使用此 skill。覆盖两套指标：销售目标（sales_target_healthy，来自 ads_external_healthy_order_shipment_target 月度目标表）和实际销售额（sales_amount_healthy_actual，来自 ads_external_order_day_result 订单明细表）。支持接单/出货两种业务类型，支持按销售个人/部门/月度等维度拆分，支持目标 vs 实际对比与完成率计算。
---

# 医疗康养数据问答 Skill

当任务是通过一个受控的机器人流程来回答医疗康养数据域中的业务指标问题时，使用这个 skill。

这个 skill 适用于：

- 将用户问题映射到标准指标
- 自动补齐时间范围、组织、区域、产品线等默认参数
- 选择已批准的 SQL 模板，而不是自由生成 SQL
- 在返回答案前补充执行元数据查询，获取相同筛选条件下的数据最后更新时间
- 输出带有指标定义、筛选条件、数据来源和更新时间的结构化答案

这个 skill 不适用于：

- 发明未定义的非官方指标
- 在整个数仓里自由生成不受限制的 SQL
- 返回超出允许数据集范围的敏感字段
- 回答"实际销售额 / 已完成销售 / 销售完成率 / 达成率"等需要**已实现销售**数据的问题（目前只覆盖**销售目标**数据，实际销售额表暂未接入）

## ⚠️ 重要业务定义（必读）

### 🗂️ 三表对照（用途 + 完整表名，写脚注前必须对照核对）

本 skill 涉及**三张物理表**，名字非常相似、worker 之前混淆过——写卡片脚注 / SQL 前**必须**严格按下表：

| 用途 | 完整表名 | 易混点 |
|---|---|---|
| **销售目标** | `ADS_YL.ads_external_healthy_order_shipment_target` | 有 `healthy` 和 `_target` 后缀 |
| **实际销售（接单/出货）** | `ADS_YL.ads_external_order_day_result` | `ADS_YL` + `ads_` 前缀 + `_day_result` |
| **数据更新时间元数据** | `ODS_YL.external_order_day_result` | `ODS_YL`（不是 ADS）+ **没有** `ads_` 前缀 |

**命名陷阱**：实际销售表（`ADS_YL.ads_external_order_day_result`）和更新时间表（`ODS_YL.external_order_day_result`）只差 **DB 前缀** 和 **`ads_` 前缀**——一字之差，但代表完全不同的数据：
- ADS 层 + `ads_` 前缀 = 治理后的**业务数据**（销售明细）
- ODS 层 + 无 `ads_` 前缀 = **原始数据 + 元数据**（如 update_time）

**worker 之前的错误**（2026-05-22 15:49 卡片脚注）：把"实际"标为 `ODS_YL.external_order_day_result` ❌——把更新时间表误标成了实际销售表。**严禁**再犯。

### 指标 → 数据集映射

| 指标 | 含义 | 数据集 | 用户用语 |
|---|---|---|---|
| **`sales_target_healthy`**（销售目标） | 销售在某月被设定的目标金额（USD） | `ADS_YL.ads_external_healthy_order_shipment_target` | "销售目标"、"接单目标"、"出货目标"、"月度目标"、"区域目标" |
| **`sales_amount_healthy_actual`**（实际销售额） | 真实成交的销售金额（USD） | `ADS_YL.ads_external_order_day_result` | "销售额"、"实际销售"、"已卖了多少"、"销售业绩"、"已完成销售" |
| `completion_rate`（完成率，派生） | 实际 / 目标 × 100% | 上面两张表 JOIN | "完成率"、"达成率"、"目标完成度"、"完成情况" |

### 两张表的字段差异（务必牢记，不能混用）

| 字段 | 目标表 `ads_external_healthy_order_shipment_target` | 实际销售表 `ads_external_order_day_result` |
|---|---|---|
| 时间字段 | `biz_date` (YYYY-MM 月份字符串) | `order_date` (YYYY-MM-DD 日期) + `ship_date`（船期，YYYY-MM-DD） |
| 销售姓名 | `nick_name` | `salesman` |
| **销售工号** | `user_name`（两表都有，**JOIN key**） | `user_name`（两表都有，**JOIN key**） |
| type 取值 | `接单指标` / `出货指标`（中文） | `healthy_order` / `healthy_shipment`（英文） |
| 金额字段 | `amount`（月度目标） | `amount`（订单实际金额） |
| 粒度 | month | day |
| 字段丰富度 | 8 个 filter | 18 个 filter（多了产品四层分类/单价/件数/工厂/公司/区域/国家/客户/船期等） |

**实际销售表的 18 个 filter 字段速查**（详见 `assets/templates/metric-card-sales-actual.md`）：

| 维度 | 字段 |
|---|---|
| 时间（2） | `order_date` / `ship_date` |
| 业务（1） | `type` |
| 组织 — 人员/部门（4） | `dept` / `source` / `salesman` / `user_name` |
| 订单信息 — 归属（3） | `sales_organization`（公司）/ `factory`（工厂）/ `customer_short_name`（客户）|
| 产品 — 四层分类（4） | `product_type`（**品类**，=）/ `material`（材料，=）/ `material_name`（详细物料名，**模糊 LIKE**）/ `remark`（**车型**，默认=）|
| 订单明细 — 数值（2） | `price`（单价 USD，范围筛选）/ `quantity`（件数，范围筛选 + 可 sum）|
| 地理（2） | `area`（区域）/ `country`（国家）|

**产品查询路由约束**：
- 用户给**车型**（短字符串字母数字组合，如 `X4` / `Y069` / `A100` / `SPIRIT X4`）→ **`remark`** 字段（车型），默认精确匹配 `remark = '...'`；若用户只给一半（如 `X4` 而不是 `SPIRIT X4`），用 `remark LIKE '%X4%'`。
  - 典型查询：用户问"助行器 X4" → `WHERE product_type = '助行器' AND remark = 'SPIRIT X4'`（品类 = 助行器，车型 = SPIRIT X4）
- 用户给**长描述**（带颜色 / 尺寸 / 材质等修饰词，如"智能可调节轮椅" / "24 寸轮椅"）→ **`material_name`** 字段（详细物料名），**必须**用 `LIKE '%xxx%'`，不能用 `=`。
- 用户给**品类**（如"轮椅" / "助行器" / "手动轮椅" / "电动轮椅"）→ **`product_type`** 字段（品类），精确匹配。
- 用户给**材料**（如"碳纤维" / "铁质"）→ **`material`** 字段，精确匹配。

**其他约束**：
- 总销售额用 `sum(amount)`；总件数用 `sum(quantity)`；这两者**不要混淆**——`quantity` 是件数不是金额。

⚠️ **绝对禁止**：用目标表的字段名（`biz_date`/`nick_name`/`接单指标`）去查实际销售表，或反过来。SQL 模板已经分别封装在两个文件里：
- 目标查询走 `assets/templates/sql-template-example.sql`（即 `sql-template-sales-target.sql` 的别名）
- 实际销售查询走 `assets/templates/sql-template-sales-actual.sql`

### 🕐 数据更新时间强制规则（必读，不许猜）

**目标表和实际销售表本身都没有 `update_time` 字段**——`SELECT max(update_time) FROM ADS_YL.ads_external_*` 一定会报 `Missing columns: 'update_time'`。worker 之前的失败案例就是这个：试了一次报错后就在卡片脚注写"目标表无 update_time 字段，数据鲜度未知"，给用户一个错误印象。

**唯一正确的获取方法**：查 `ODS_YL.external_order_day_result` 这张**专门的元数据来源表**，用模板 `assets/templates/metadata-query-template.sql`：

```sql
SELECT max(update_time) AS last_update_time
FROM ODS_YL.external_order_day_result;
```

这张表的 `update_time` 字段记录的是数仓 ETL 链路的最新写入时间——它和两张主业务表（target / actual）共享同一个上游数据源，所以代表整个 medcare-data-qa 数据域的"数据新鲜度"。

**强制规则**：
1. **任何**会在卡片脚注里展示"数据更新时间"的回答（实际上**所有**正常查询都应包含），都**必须**先跑一遍上面这条元数据查询。
2. SQL **必须**严格按上面写，不要给它加 WHERE 条件（不要试图按主查询的 filters 去过滤元数据表，更新时间是整表层面的）。
3. 跑出来用 `purpose: "metadata"` 写一条审计日志，然后把返回的 `last_update_time` 填到卡片脚注的"更新时间"字段。
4. **不允许**跳过这一步；**不允许**把 `max(update_time)` 套到 ADS_YL 的目标 / 实际表上（它们没这字段）；**不允许**写"数据鲜度未知 / 无法获取"——这是 worker 偷懒的信号，必须返工。
5. 如果 `ODS_YL.external_order_day_result` 这张元数据表本身查询失败（数仓异常 / 表权限问题），脚注里写"_数据更新时间获取失败：<具体错误>_"，**不要**假装目标 / 实际表没字段。

### JOIN 策略：目标 vs 实际（用于完成率 / 达成率查询）

当用户问"完成率 / 达成率 / 目标完成度"时，必须 JOIN 两张表。

**JOIN key**：`user_name`（销售工号）+ 月份。
- 实际表用 `toStartOfMonth(toDate(order_date))` 或截取 `formatDateTime(order_date, '%Y-%m')` 得到月份
- 目标表的 `biz_date` 本身就是 `YYYY-MM` 字符串，直接对齐

**JOIN 类型**：根据问题语义决定
- 默认 `LEFT JOIN`（以目标为主，对齐到该销售该月的实际销售；实际可能为空表示该销售该月没出单）
- 算"超额完成 Top N"用 `INNER JOIN`（同时有目标和实际）

**SQL 骨架示例**：
```sql
WITH target AS (
  SELECT user_name, biz_date AS month, sum(amount) AS target_amount
  FROM ADS_YL.ads_external_healthy_order_shipment_target
  WHERE biz_date BETWEEN '2026-01' AND '2026-04'
    AND type = '接单指标'
  GROUP BY user_name, biz_date
),
actual AS (
  SELECT user_name, formatDateTime(order_date, '%Y-%m') AS month, sum(amount) AS actual_amount
  FROM ADS_YL.ads_external_order_day_result
  WHERE order_date BETWEEN '2026-01-01' AND '2026-04-30'
    AND type = 'healthy_order'
  GROUP BY user_name, month
)
SELECT
  t.user_name,
  t.month,
  t.target_amount,
  a.actual_amount,
  round(a.actual_amount / t.target_amount * 100, 1) AS completion_rate_pct
FROM target t
LEFT JOIN actual a ON t.user_name = a.user_name AND t.month = a.month
ORDER BY t.month, t.user_name;
```

**注意 type 取值要同步切换**：算"接单完成率"用目标 `接单指标` + 实际 `healthy_order`；算"出货完成率"用目标 `出货指标` + 实际 `healthy_shipment`。**不能混搭**（用目标接单算实际出货的完成率没业务意义）。

**完成率查询的图表表现**（强制规则，详见 [references/chart-conventions.md § 3](references/chart-conventions.md)）：
- **目标和实际的柱状图必须并列（grouped），严禁堆叠（stacked）**——堆叠会让用户看不到"差距"，而差距正是完成率分析的核心
- **必须用双轴图**：左轴金额（USD，承载目标柱 + 实际柱）；右轴完成率（%，折线 + 数据点）
- 完成率折线**必须用百分比格式**（`87%` / `120%`），不能用 `0.87` / `1.2`
- 单一 x 轴分类（部门 / 区域）下并列两个柱 + 折线点；多分类时折线连成趋势，方便横向对比哪个部门最接近达成

🎯 **必须用 chart-conventions.md § 3 里的"标准 VChart spec 模板"** 直接照抄，三处换数据即可：
1. 顶层 `"type": "common"`（**不是 "bar"**，否则会堆叠且折线无法上右轴）
2. bar series 的 `xField: ["dept", "metric"]` **数组形式**让柱并列
3. axes 数组配置 left（绑 bar）/ right（绑 line，必须含 `seriesId: ["line"]`）/ bottom（band 分类轴）

worker 之前生成的卡片就是错在用了 `type: "bar"` 单 series、没 axes 数组，所以柱堆叠、折线掉左轴底。**严禁继续用旧写法**。

### 用户问法 → 处理方式

| 用户问法 | 指标 | type 取值 |
|---|---|---|
| 销售目标 / 接单目标 / 月度目标 / 区域目标 | `sales_target_healthy` | `接单指标` |
| 出货目标 / 月度出货目标 | `sales_target_healthy` | `出货指标` |
| 销售额 / 实际销售额 / 销售业绩 / 已卖了多少 | `sales_amount_healthy_actual` | `healthy_order`（默认）|
| 出货额 / 实际出货 / 已发了多少 | `sales_amount_healthy_actual` | `healthy_shipment` |
| 完成率 / 达成率 / 完成情况 | `completion_rate`（JOIN） | 两表都查 |
| 仅说"康养接单 / 康养下单" 没说目标也没说销售额 | **必须反问**：是要查"接单目标"还是"实际接单销售额"？两者数据来源不同，结果会差异很大，不要默认。 | — |
| 仅说"康养出货 / 康养发货" 没说目标也没说销售额 | **必须反问**同上 | — |

### 卡片输出的免歧义要求

为避免用户混淆，**任何涉及金额数据的卡片**必须在以下位置明确标注是"**目标**"还是"**实际销售**"：
1. 卡片 header 标题（如 `🎯 销售目标查询结果` 或 `💰 实际销售额查询结果`）
2. 表头列名（如 `接单目标(USD)` 或 `实际销售额(USD)`）
3. 灰字脚注的"口径"字段（如 `口径：康养接单目标` 或 `口径：康养实际销售额`）

不允许只写"销售额(USD)"或"金额(USD)"这种歧义表述。

## 工作流程

1. 先阅读 [references/overview.md](references/overview.md)，了解整体架构和执行链路。
2. 当问题依赖指标定义、业务含义或 owner 时，阅读 [references/metric-governance.md](references/metric-governance.md)。
3. 在构建或选择查询之前，阅读 [references/query-contract.md](references/query-contract.md)。
   **任何包含图表的回答都必须先阅读 [references/chart-conventions.md](references/chart-conventions.md)，不允许跳过——即使是"简单的部门排名柱状图"也不许。** chart-conventions 不是参考资料，是强制规则。

   **🚫 严禁使用 plotly / matplotlib / seaborn 等 Python 库生成 PNG 再上传。** 必须使用飞书原生 `chart` 元素（基于 VChart）直接在卡片里渲染。原因：
   - PNG 路径会拆成 3 条消息（占位卡 + 图片 + 主卡），用户体验极差
   - 服务端字体渲染中文容易出问题
   - 用户无法点击放大、无法导出、无法交互
   - VChart 路径只发 1 条卡片，所有内容（标题 / 图 / 表 / 脚注）合在一起

   **正确的图表写法**：把 VChart spec 作为 JSON 对象直接嵌入卡片 body 的 `chart` 元素，不要序列化成字符串、不要塞进 markdown 元素的 content 里。

   ```json
   {
     "tag": "chart",
     "aspect_ratio": "16:9",
     "preview": true,
     "chart_spec": {
       "type": "bar",
       "data": { "values": [
         { "month": "2026-01", "amount": 244020 },
         { "month": "2026-02", "amount": 248375 }
       ]},
       "xField": "month",
       "yField": "amount"
       /* 不设 color，不设 color_theme，由 VChart 默认 brand 主题自动配色 */
     }
   }
   ```

   **错误反模式**（worker 之前的错误路径，绝对禁止）：
   ```
   ❌ 用 plotly/matplotlib 画图 → 存 /tmp/*.png → lark-cli upload-image → 发图片消息 → 再发卡片
   ❌ 把整段 VChart JSON 序列化成字符串塞到 markdown 元素的 content 里
   ❌ 同一次问答回复拆成"占位卡 + 图片 + 主卡"3 条消息
   ```

   **单卡片原则**：每次回答**只发一条飞书消息**——一张完整的 interactive card，body.elements 里依次包含：
   1. `chart` 元素（VChart 图表）
   2. `table` 元素（明细数据）
   3. `markdown` 元素（insight 文字）
   4. `markdown` 元素（💡 追问建议 + 飞书表格导出提示，**合并为一行**）
   5. `hr` 分隔
   6. `markdown` 元素（灰字脚注）

   **🚫 调用 reply 工具时必须用 `card` 参数（对象），严禁用 `text` 参数传卡片 JSON 字符串。** feishu-card skill 已经明确说明这一点：
   - ✅ 正确写法：
     ```
     reply({
       chat_id: "oc_xxx",
       card: { schema: "2.0", header: {...}, body: { elements: [...] } },   // 直接传对象
       reply_to: "om_xxx"
     })
     ```
   - ❌ 错误写法（worker 之前犯过的错，导致整段 JSON 作为文本显示）：
     ```
     reply({
       chat_id: "oc_xxx",
       text: "{\n  \"schema\": \"2.0\", ...}",   // 手工序列化字符串→ 飞书把整段 JSON 当文本显示
       reply_to: "om_xxx"
     })
     ```
   - 原因：`card` 参数让 lark-customized 插件代为序列化，自动 escape 引号 / 反斜杠 / 中文字符；`text` 参数会把字符串原样发出，导致结构丢失或显示成纯文本。
   - 这条规则不止本 skill 适用，**所有飞书卡片回复都必须用 `card` 参数**，由 feishu-card skill 强制。

   **chart-conventions 颜色规则速记（VChart 版）**：

   - **默认情形（单系列 / 多系列 / 离散分类 x 轴 / 时间 x 轴 / 多分组叠加）**：**不要**在 chart_spec 里设 `color` 或 `color_theme`。让飞书 VChart 用默认 brand 主题自动配色。多分组靠 `seriesField` 自动分色：
     ```json
     "chart_spec": {
       "type": "bar",
       "data": { "values": [{"dept": "一部", "amt": 1518.9}, {"dept": "二部", "amt": 748.6}, {"dept": "三部", "amt": 651.8}] },
       "xField": "dept", "yField": "amt",
       "seriesField": "dept"
     }
     ```
   - **唯一手工配色场景：双轴图同分组的不同指标用深浅区分**。例如双轴图展示"亚洲+日韩"的差值柱+环比%折线，4 个系列里柱用 VChart 默认色，折线手工指定为对应柱色的深色变体（明度降 25-35%），让"颜色相近 = 同一分组"成立。详见 [references/chart-conventions.md § 1.2](references/chart-conventions.md)。
   - 双轴图零点对齐、差值-柱+百分比-折线、时间轴、何时不画图等其它规则去 chart-conventions.md 查。
   - VChart 完整 chart_spec 参数（type / xField / yField / seriesField / legends / axes 等）见 feishu-card skill 的 `references/card-elements.md` § 8。
4. 复用 `assets/templates/` 下的模板示例（注意有两套指标，分别对应不同 metric-card 和 sql-template）：
   - **销售目标指标**：
     - `metric-card-example.md`（即 sales_target_healthy 的指标卡）
     - `sql-template-example.sql`（即 sales_target_healthy_v1）
   - **实际销售额指标**：
     - `metric-card-sales-actual.md`（sales_amount_healthy_actual 的指标卡）
     - `sql-template-sales-actual.sql`（sales_amount_healthy_actual_v1）
   - **通用**：
     - `metadata-query-template.sql` —— **数据更新时间专用模板**，查 `ODS_YL.external_order_day_result.update_time` 表。详见下方"数据更新时间强制规则"
     - `parameter-dictionary-example.yaml`
     - `term-mapping-example.yaml`（注意：metric_aliases 现在区分目标/实际两套；type_aliases 也按 target_type / actual_type 分组）
     - `field-enum-dictionary.yaml`
     - `question-example.md`
     - `answer-template-example.md`
     - `result-table-card-example.json`
5. 如果某个问题无法匹配到标准指标定义，应停止继续推断，并回答说明该问题超出了当前的支持范围。
6. **必须记录所有 SQL 执行的审计日志**——每跑一条 SQL 就立刻写一条，不能合并、不能漏。

   规则：
   - **每次调用 `bytehouse-readonly-query` 跑 SQL，无论 SQL 是主查询、附加明细查询、元数据查询（如 `SELECT max(update_time) FROM ODS_YL.external_order_day_result`）、还是失败查询，都必须在该次 SQL 返回后立刻写一条审计**。一次问答经常需要跑 2-4 条 SQL（主聚合 + 月度拆分 + 数据更新时间 + ...），那就写 2-4 条审计，**不允许只写其中一条**。
   - 同一次问答内的多条审计必须共享相同的 `user_id` / `chat_id` / `question`，只有 `sql` / `purpose` / `row_count` / `latency_ms` 不同。
   - **拒答路径**也必须写一条（`purpose: "rejection"`，`sql` 填 null，`error` 填拒答原因）。
   - 调用时机：紧跟 SQL 执行完成，**不要等到最后回复用户后才统一记**——那样异常退出会丢日志。

   单条审计写入命令：

   ```bash
   python3 ~/.claude/skills/medcare-data-qa/scripts/log_query.py --json-stdin <<'EOF'
   {
     "user_id": "<飞书消息 meta 中的 sender open_id>",
     "chat_id": "<飞书消息 meta 中的 chat_id>",
     "question": "<用户原始问题>",
     "metric": "<解析出的标准指标名；拒答 / 元数据查询时填 null>",
     "filters": {"<参数名>": "<参数值>"},
     "template": "<使用的 SQL 模板文件名；自由 SQL / 拒答时填 null>",
     "purpose": "<main | detail | metadata | rejection>",
     "sql": "<本次执行的完整 SQL；拒答时填 null>",
     "row_count": <本次返回行数；未执行时填 null>,
     "latency_ms": <本次查询耗时毫秒；未执行时填 null>,
     "error": "<错误信息；成功时填 null>"
   }
   EOF
   ```

   `purpose` 字段语义：
   - `main` — 直接回答用户主问题的核心 SQL
   - `detail` — 同一问答内的附加明细 / 拆分 / 排名 SQL（例：主查询是合计、附加查询是按月拆分）
   - `metadata` — 元信息查询，如 `SELECT max(update_time) FROM ODS_YL.external_order_day_result`（**唯一正确的"数据更新时间"查法**，见上方"🕐 数据更新时间强制规则"）、`DESCRIBE table`、schema 探查等
   - `rejection` — 拒答未执行 SQL 的占位记录

   审计日志位置：`~/.lark-dispatcher/logs/medcare-queries.jsonl`（每行一条 JSON）。
   SQL 字段会被脚本自动截断到 2000 字符，无需手动截断。

## 回答规则

- 永远先识别标准指标。
- 以指标卡作为业务定义和技术定义的唯一可信来源。
- 只能使用已批准的数据集名称和 SQL 模板。
- 按参数字典中的默认规则补齐缺失参数。
- `type` 字段用于区分“接单指标”与“出货指标”：用户问“接单/下单”时取“接单指标”，用户问“出货”时取“出货指标”；如果用户没有明确说明，默认取“接单指标”，并在答案脚注中明确写出“口径说明：接单指标；查询月份范围：<start_month> ~ <end_month>”。
- 返回结构化答案，**按以下顺序自上而下排版**：
  1. **查询结果**（图表 / 表格 / 数据 insight）—— 放最上方，让用户第一眼看到结论。
  2. **可选的后续追问建议** —— 紧接结果，提示下一步可深挖的方向。
  3. **元信息脚注**（统一放在卡片底部，灰色小字、`hr` 分隔，作为"注脚"性质的注释）：
     - 时间范围
     - 筛选条件
     - 指标定义摘要（口径说明）
     - 数据集名称
     - 数据更新时间

  排版示意：

  ```
  ┌─────────────────────────────────────────┐
  │ 📊 标题                                  │
  │ ───────────────────────────────────────  │
  │ [图表 1：月度接单目标柱状图]              │
  │ [图表 2：差值+环比% 双轴图]               │
  │ [数据表 7 列 × 10 行]                    │
  │ [数据 insight 文字]                      │
  │                                          │
  │ 💡 可继续追问：按产品线拆分 / 与去年同期…；│
  │    或回复"生成飞书表格"导出明细到表格。     │
  │ ───────────────────────────────────────  │
  │ **时间口径**：2026-01 ~ 2026-05            │
  │ **筛选**：无限制                            │
  │ **口径**：康养接单目标（USD，非实际销售额）  │
  │ **数据集**：ADS_YL.ads_external_..._target  │
  │ **更新时间**：2026-05-15 05:02              │
  │ **口径说明**：接单目标；月份 2026-01 ~ 2026-05 │
  └─────────────────────────────────────────┘
  ```

  - 元信息脚注用 markdown 元素渲染成灰字小号（`<font color='grey'>...</font>` 或 `_斜体_`），让用户视觉上能区分"主内容"和"参考信息"。v2 卡片不支持 `note` 元素，必须用 markdown 包灰字色。
  - **脚注内每个元信息字段（时间口径 / 筛选 / 口径 / 数据集 / 更新时间 / 口径说明）必须独占一行**，用 `\n` 换行，不允许用 ` · ` 或其他分隔符挤在一行——单行版本字段密度太高、用户扫读慢。
  - **格式规则**（worker 之前违规过，必须严格遵守）：
    - 每行格式：`**类别**：值`（类别加粗 + 中文冒号 + 值不加粗）
    - ❌ **严禁** 把整行都加粗（如 `**时间口径 2026-01 ~ 2026-05**`）—— 这会让"值"也加粗、跟"类别"视觉上没区别
    - ❌ **严禁** 漏掉冒号（如 `**时间口径** 2026-01 ~ 2026-05`）—— 看起来不清晰，需要冒号明确分隔
    - ❌ **严禁** 在"值"里使用 `**...**` 加粗任何字（如 `**口径** 康养接单**目标**金额`）—— 值部分应全部纯文本
  - **正确示例**：
    ```
    <font color='grey'>**时间口径**：2026-01 ~ 2026-05
    **筛选**：area IN ('亚洲（除日韩）','日韩')
    **口径**：康养接单目标金额（USD，非实际销售额）
    **数据集**：`ADS_YL.ads_external_healthy_order_shipment_target`
    **更新时间**：2026-05-15 06:00
    **口径说明**：接单目标；查询月份范围：2026-01 ~ 2026-05</font>
    ```
  - 不允许把指标口径、数据集、更新时间放在卡片**最上方**——那会让"业务结论"被技术性参数稀释。
- **查询结果的展示形式**：
  - 结果行数 ≥ 2 且列数 ≥ 2 时，**必须使用飞书卡片的原生 `table` 元素**（`"tag": "table"`），不允许使用 markdown 表格或代码块，否则用户复制到 Excel / 飞书表格时会错位。
  - **本场景显式覆盖 feishu-card skill 的"3+ 列禁止 / max 2 columns"限制**。feishu-card 那条规则是为通用移动端可读性设计的；而本 skill 服务于数据查询场景，用户的核心诉求是**把结果复制到 Excel 做进一步分析**，PC 端使用为主，移动端可读性是次要约束。因此：
    - 数据结果列数无上限（实际上飞书 table 最多支持的列数即上限）。
    - 单元格内容应尽量短：数字 + 单位即可，避免长文本撑爆列宽。
    - 复杂分组维度（如"亚洲（除日韩）"这种长字符串）放第一列并 `freeze_first_column: true`，让横向滚动只滚数值列。
  - 数值列必须设置 `data_type: "number"` 并配 `format`（`symbol` / `precision` / `separator`），让金额、百分比、行数等以可读格式渲染。
  - **表格里的金额必须保持完整数字 + 千分位**（如 `$4,528,275`），**严禁**用 K/M/B 缩写。K/M/B 缩写**仅用于图表标签**，详见 chart-conventions.md § 3"金额格式化"节。表格的核心价值是用户复制到 Excel 做分析，缩写会丢精度。
  - 表头列名（`display_name`）必须带单位（如 `接单目标(USD)`、`环比 %`），不允许只写"金额"或"百分比"。
  - 时间序列结果建议把月份/季度/日期列设为**第一列**并开启 `freeze_first_column: true`，方便用户横向滚动查看。
  - 单一数值（1×1）或仅 1 行的结果使用 markdown 卡片即可，不必上 table 元素。
  - 参考模板：[assets/templates/result-table-card-example.json](assets/templates/result-table-card-example.json)
  - 飞书 table 完整能力（列类型、page_size、对齐等）见 feishu-card skill 的 `references/card-elements.md` § 9。
  - **🚫 严格按 feishu-card spec 写字段类型，不能混淆**：
    - `table.columns[].width` **必须是字符串**：`"auto"`（推荐）或 `"120px"`（带 px 后缀）。**严禁**写数字 `120` 或纯数字串 `"120"`——飞书 API 会因 `expected string for width, but: 120` 拒收**整张**卡片，dispatcher 降级后只能从卡片里抽出 markdown 文本作为纯文本发出去，用户看到"只有数据解读、没有图、没有表"。
    - 同理：`freeze_first_column` 必须是 bool（`true`/`false`），`page_size` 必须是 int（`10`，不要 `"10"`），`format.precision` 必须是 int，`format.separator` 必须是 bool。混类型会导致整张卡片失效。
    - 实施提示：写完 card JSON，发送前在脑中过一遍每个字段的类型，特别盯 table 元素的 width。
- **复制问题的解法：按需生成飞书表格，而非默认附 CSV**：
  - 已知问题：飞书 v2 卡片的 `table` 元素**剪贴板复制不带 tab 分隔符**，用户从卡片选中多行粘到飞书表格 / Excel 时会全部塌到一列。这是飞书客户端的已知限制，无法用 card JSON 配置解决。
  - 解法：**不默认附 CSV**（每次查询都附文件会污染群文件区、占用云盘空间），改为在卡片脚注里提示用户用一句话触发"生成飞书表格"。

  **追问建议这一行必须把"生成飞书表格"提示合并进去**（不再单独占一行）。格式参考：
  > 💡 _可继续追问：4月接单明细 / 按产品线拆分 / 与去年同期对比；或回复"生成飞书表格"导出明细到表格。_

  即：追问选项用 ` / ` 分隔，末尾用 ` ；或回复"生成飞书表格"导出明细到表格。` 收尾。整体仍是**一个 markdown 元素一行**，不要拆。

  **当用户在同一 thread 内回复"生成飞书表格"/"导出飞书表格"/"做成飞书表格"等类似表述时**，worker 按以下流程处理：

  1. 从 thread 上下文里取出**最近一次查询的数据**（包括列名、数据行、指标口径、时间范围、筛选条件）。如果数据已被截断或丢失，需要重跑同一条 SQL 模板把数据拿回来。
  2. 调用 `lark-sheets` skill 创建一个新的飞书电子表格：
     - 标题：`<指标名> · <时间范围> · <筛选摘要>`（如 `康养接单目标 · 2026-01~05 · 亚洲（除日韩）vs 日韩`）
     - 第 1 行写表头（中文 + 单位，与卡片 table 的 `display_name` 一致）
     - 数据行**用原始数字**写入（不带千分位、不带货币符号、不带 `%` 后缀）；格式化交给用户在飞书表格里自行设置
     - 末尾追加一行空行 + 一行元信息备注（`数据来源: <数据集> | 口径: <指标定义> | 更新时间: <ts>`），方便溯源
  3. 表格创建成功后，回复一张简短卡片（不再重复数据），内容包括：
     - 飞书表格的可点击链接（`https://xxx.feishu.cn/sheets/<sheet_token>`）
     - 行数与列数确认（如 `已生成 10 行 × 7 列`）
     - 提示：表格已设置当前群可编辑权限（如果走默认共享策略）
  4. 不需要再附图表（图表已在原查询卡片中），保持回复轻量。

  - 例外：用户的"生成飞书表格"请求若不在某次查询结果的同 thread 内（找不到上下文数据），应礼貌反问："请问要导出哪一次的查询结果？" 并列出近期可用的查询。

## 安全默认规则

- 如果用户没有指定时间，默认取当前自然月。
- 如果用户没有指定组织，默认取所有允许查询的组织范围。并且在答案中明确说明这一默认范围。
- 如果用户说“最近”，优先采用参数字典中团队约定好的解释。
- 如果用户提到的指标名称与其他团队定义冲突，应明确给出当前支持的标准定义，而不是猜测。并把当前支持的标准定义作为答案的一部分。

## 何时拒答或升级处理

- 该指标不在当前治理后的指标集合内。
- 该问题需要访问已批准数据集之外的数据。
- 请求的拆分维度当前模板不支持。
- 问题混用了冲突粒度或不兼容的筛选条件。

## 拒答或升级处理的回复模版

- 指出因何原因不能继续处理
- 给出用户可以提问的范围或示例
- 如果可能，提供一个相关的标准指标或已批准的查询模板作为替代
