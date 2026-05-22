# 指标卡：实际销售额

## metric_name

sales_amount_healthy_actual

## display_name

医疗康养实际销售额

## business_definition

在指定时间范围内，医疗康养主题下按 type 类型（healthy_order / healthy_shipment）汇总的**实际成交销售金额（USD）**总和。

与 sales_target_healthy（销售目标）的关键区别：
- **本指标** = 实际已发生的销售金额
- **sales_target_healthy** = 期望完成的销售目标金额
- 两者可以做对比、算完成率 / 达成率

## technical_definition

基于 `ADS_YL.ads_external_order_day_result` 表中的 `amount` 字段按 `order_date` 与 `type` 筛选条件聚合：

- `amount` (USD)：单条订单/出货记录的总金额；满足 `amount = price × quantity`
- `price` (USD)：单价
- `quantity`：件数 / 数量（不是金额，跟 amount 区别开）
- `order_date`：订单日期，存储格式为 **`YYYY-MM-DD`**（日期粒度，不是月度！）—— 区别于目标表的 `biz_date`（YYYY-MM）
- `type`：业务类型，取值：
  - `healthy_order` → 康养接单 / 下单
  - `healthy_shipment` → 康养出货 / 发货
- `salesman`：销售姓名（不是 `nick_name`——区别于目标表）

主要聚合方式：
- `sum(amount)` — 总销售额（USD），最常用
- `sum(quantity)` — 总件数（"卖了多少件"）
- `avg(price)` — 平均单价
- `count(*)` — 订单条数

## grain

day（订单日粒度，最细）

## default_time_rule

current_natural_month

## default_type

healthy_order（即"接单 / 下单"；用户未明确说"出货"时取此默认）

## supported_filters

时间维度（2）：
- `order_date`（必填，YYYY-MM-DD，下单日期）
- `ship_date`（可选，YYYY-MM-DD，船期；按出货时间筛选时使用）

业务维度（1）：
- `type`（默认 `healthy_order`；可选 `healthy_shipment`）

组织维度（4，人员 / 部门）：
- `dept`（一级部门）
- `source`（二级部门）
- `salesman`（销售姓名）
- `user_name`（销售工号；**也是与目标表 JOIN 的关键字段**，见 SKILL.md "JOIN 策略"节）

订单信息（3，订单归属的公司 / 工厂 / 客户）：
- `sales_organization`（公司）
- `factory`（工厂）
- `customer_short_name`（客户简称）

产品维度（4，四层分类）：
- `product_type`（产品大类，如 手动轮椅 / 电动轮椅 / 助行器，精确匹配）
- `material`（材料，如 铁质 / 碳纤维，精确匹配）
- `material_name`（详细物料名，含型号规格的全名；**必须用 `LIKE '%xxx%'` 模糊查询**，不要用 `=`）
  - 示例值：`轮椅 智能化多功能可调节轮椅 Y069型 YK253139-2 24寸 表面喷塑黑`
  - 用户给的是带规格 / 颜色 / 尺寸的长描述时，定位到此字段
- `remark`（型号 / 系列代码，短字符串；默认精确匹配，必要时 LIKE）
  - 示例值：`SPIRIT X4` / `Y069` / `A100`
  - 用户给的是简短型号代码（字母数字组合）时，定位到此字段
  - **典型查询**：用户问"助行器 X4" → `product_type = '助行器' AND remark = 'SPIRIT X4'`
  - 如果用户只给型号一部分（如"X4"而不是"SPIRIT X4"）：用 `remark LIKE '%X4%'` 兜底

订单明细维度（2，数值字段，用范围查询）：
- `price`（单价 USD；筛选用 `price BETWEEN x AND y` 或 `price >= x`）
- `quantity`（件数 / 数量；筛选用 `quantity BETWEEN x AND y`；也常用作 `sum(quantity)` 算总件数）

地理维度（2）：
- `area`（销售区域）
- `country`（销售国家）

## supported_group_by

时间维度（用于按时间拆分趋势）：
- `toStartOfMonth(order_date)` — 按月
- `toStartOfQuarter(order_date)` — 按季度
- `toYear(order_date)` — 按年
- `order_date` — 按日

组织维度（人员 / 部门）：
- `dept` / `source` / `salesman` / `user_name`

订单信息（公司 / 工厂 / 客户）：
- `sales_organization` / `factory` / `customer_short_name`

产品维度：
- `product_type` / `material` / `material_name` / `remark`

订单明细维度（数值字段，可按区间分桶 group by）：
- `price` 单价区段（如 0–100 / 100–500 / 500+ USD）
- `quantity` 件数区段

地理维度：
- `area` / `country`

业务类型：
- `type`（对比接单 vs 出货）

## owner

business_owner_tbd

## data_owner

data_team_tbd

## approved_dataset

ADS_YL.ads_external_order_day_result

## approved_template

sales_amount_healthy_actual_v1

## SQL 样例（来自用户提供）

```sql
SELECT sum(amount)
FROM ADS_YL.ads_external_order_day_result
WHERE type = 'healthy_order'
  AND salesman = '卢鸿颖'
  AND order_date BETWEEN '2026-01-01' AND '2026-12-31';
```
