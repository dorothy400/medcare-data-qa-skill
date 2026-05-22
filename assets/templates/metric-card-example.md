# 指标卡示例

## metric_name

sales_target_healthy

## display_name

医疗康养销售目标

## business_definition

在指定时间范围内，医疗康养主题下按目标类型（接单目标 / 出货目标）汇总的**销售目标金额（USD）**总和。

**重要提示**：这是**目标数据**，不是实际销售额。每行 `amount` 代表对应销售在该月份的销售目标，反映"该月期望完成多少"而非"该月实际完成多少"。实际销售额（actual sales）目前在本 skill 范围之外（另有数据源，未接入），不要将本指标当作"已实现销售额"展示给用户。

## technical_definition

基于 `ADS_YL.ads_external_healthy_order_shipment_target` 表中的 `amount` 字段按 `biz_date` 与 `type` 筛选条件聚合：

- `amount` (USD)：该销售在该月份的销售目标金额，单位美元
- `biz_date`：目标所属月份，存储格式为 `yyyy-MM`（注意是月份字符串，不是日期）；查询前需要将时间参数格式对齐为 `yyyy-MM`
- `type`：目标类型，取值 `接单指标` 或 `出货指标`——分别代表接单目标和出货目标

聚合方式：`sum(amount)`。

## grain

month（目标按月份维度存储，最细粒度是月）

## default_time_rule

current_natural_month

## default_type

接单指标（即"接单目标"；用户未明确说"出货"时取此默认）

## supported_filters

- biz_date（必填，月份范围 YYYY-MM）
- type（默认接单指标；可选出货指标）
- user_name（按销售工号筛选；**也是与实际销售表 JOIN 的关键字段**，见 SKILL.md "JOIN 策略"节）
- nick_name（按销售姓名筛选）
- source（按二级团队/二级部门筛选）
- dept（按一级团队/一级部门筛选）
- director_nick_name（按二级部门经理筛选）
- manager_nick_name（按一级部门经理筛选）

## supported_group_by

- user_name
- nick_name
- source
- dept
- director_nick_name
- manager_nick_name
- biz_date（按月拆分）

## exclusion_rules

无（目标表已是已批准、已治理的数据；无需排除内部交易、无效订单等过滤）

## owner

business_owner_tbd

## data_owner

data_team_tbd

## approved_dataset

ADS_YL.ads_external_healthy_order_shipment_target

## approved_template

sales_target_healthy_v1

## not_supported_questions

以下问题**不能用本指标回答**（避免把目标当成实际销售额误导用户）：

- "今年实际卖了多少？" / "本季度实际销售额是多少？"
- "完成率/达成率是多少？"（需同时有目标与实际销售额数据，目前只有目标）
- "和去年同期实际销售对比"（缺少实际销售额数据）
- 任何带"实际"、"已完成"、"已实现"语义的查询

对这类问题应拒答并明确说明："当前本 skill 仅覆盖**销售目标数据**，实际销售额查询能力即将接入；如需查询销售目标，请改述为'2026 年 1 月康养接单目标'等表述。"
