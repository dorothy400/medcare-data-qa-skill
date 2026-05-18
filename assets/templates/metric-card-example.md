# 指标卡示例

## metric_name

sales_amount_healthy

## display_name

医疗康养销售额

## business_definition

在指定时间范围内，医疗康养主题下按指标口径类型汇总的销售金额总和。

## technical_definition

基于 `ADS_YL.ads_external_healthy_order_shipment_target` 表中的 `amount` 字段按 `biz_date` 与 `type` 筛选条件聚合；其中 `biz_date` 在表中存储为 `yyyy-MM`，查询前需要将时间参数格式对齐为 `yyyy-MM`。

## grain

day

## default_time_rule

current_natural_month

## supported_filters

- biz_date
- type
- nick_name
- source
- dept
- director_nick_name
- manager_nick_name

## supported_group_by

- nick_name
- source
- dept
- director_nick_name
- manager_nick_name

## exclusion_rules

- exclude_internal_trade = true
- exclude_void_orders = true

## owner

business_owner_tbd

## data_owner

data_team_tbd

## approved_dataset

ADS_YL.ads_external_healthy_order_shipment_target

## approved_template

sales_amount_healthy_v1
