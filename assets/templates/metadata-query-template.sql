-- template_name: get_data_freshness_v1
-- metric_name: data_update_time
-- dataset: ODS_YL.external_order_day_result
-- description:  数据最后更新时间

select
    max(update_time) as last_update_time
from
    ODS_YL.external_order_day_result 