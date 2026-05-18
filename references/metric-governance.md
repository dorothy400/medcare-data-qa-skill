# 指标治理

## 每个治理后指标必须具备的字段

- metric_name
- business_definition
- technical_definition
- grain
- default_time_rule
- supported_filters
- exclusion_rules
- owner
- data_owner
- approved_dataset
- approved_template

## 解释规则

如果一个用户问题可能对应多个业务含义，应以治理后的指标卡为准，并在答案中明确当前支持的是哪种解释。

## 冲突示例

- “金额”可能对应接单金额、出货金额或开票金额
- skill 不能自行猜测用户到底想问哪一个
- 必须由当前支持的指标卡明确给出官方含义
