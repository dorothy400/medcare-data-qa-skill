

-- template_name: sales_amount_healthy_v1
-- metric_name: sales_amount_healthy
-- dataset: ADS_YL.ads_external_healthy_order_shipment_target

select
    -- group_by_select example: "dept as group_dimension,"
    ${group_by_select}
    sum(amount) as sales_amount_healthy
from
    ADS_YL.ads_external_healthy_order_shipment_target
where
    biz_date BETWEEN '${start_month}' AND '${end_month}'
    and type = '${type}'
    and (${nick_name} IS NULL OR nick_name = '${nick_name}')
    and (${source} IS NULL OR source = '${source}')
    and (${dept} IS NULL OR dept = '${dept}')
    and (${director_nick_name} IS NULL OR director_nick_name = '${director_nick_name}')
    and (${manager_nick_name} IS NULL OR manager_nick_name = '${manager_nick_name}')
${group_by_clause}
 ;
