

-- template_name: sales_target_healthy_v1
-- metric_name: sales_target_healthy
-- dataset: ADS_YL.ads_external_healthy_order_shipment_target
-- description: 医疗康养销售目标聚合查询（USD）。amount 字段是销售在该月份的目标金额，不是实际销售额。

select
    -- group_by_select example: "dept as group_dimension," 或 "biz_date as group_dimension,"
    ${group_by_select}
    sum(amount) as sales_target_healthy
from
    ADS_YL.ads_external_healthy_order_shipment_target
where
    biz_date BETWEEN '${start_month}' AND '${end_month}'
    and type = '${type}'   -- '接单指标' = 接单目标; '出货指标' = 出货目标
    and (${user_name} IS NULL OR user_name = '${user_name}')          -- 销售工号（JOIN 实际销售表的关键字段）
    and (${nick_name} IS NULL OR nick_name = '${nick_name}')
    and (${source} IS NULL OR source = '${source}')
    and (${dept} IS NULL OR dept = '${dept}')
    and (${director_nick_name} IS NULL OR director_nick_name = '${director_nick_name}')
    and (${manager_nick_name} IS NULL OR manager_nick_name = '${manager_nick_name}')
${group_by_clause}
 ;
