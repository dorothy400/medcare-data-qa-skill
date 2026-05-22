

-- template_name: sales_amount_healthy_actual_v1
-- metric_name: sales_amount_healthy_actual
-- dataset: ADS_YL.ads_external_order_day_result
-- description: 医疗康养实际销售额聚合查询（USD）。amount 是真实成交金额。
--
-- 字段差异（与目标表 ads_external_healthy_order_shipment_target 对比）：
--   时间字段：order_date（YYYY-MM-DD 日期粒度）/ ship_date（船期）
--             目标表是 biz_date（YYYY-MM）
--   销售字段：salesman（销售姓名）
--             目标表是 nick_name
--   type 取值：healthy_order（接单/下单）/ healthy_shipment（出货）
--             目标表是 接单指标 / 出货指标

select
    -- group_by_select example:
    --   按销售拆：   "salesman as group_dimension,"
    --   按月拆：     "toStartOfMonth(order_date) as group_dimension,"
    --   按产品拆：   "product_type as group_dimension,"
    --   按区域拆：   "area as group_dimension,"
    --   按客户拆：   "customer_short_name as group_dimension,"
    ${group_by_select}
    sum(amount) as sales_amount_healthy_actual
from
    ADS_YL.ads_external_order_day_result
where
    -- 时间筛选（接单口径用 order_date；出货口径如需按船期筛选可改用 ship_date）
    order_date BETWEEN '${start_date}' AND '${end_date}'   -- YYYY-MM-DD
    -- ship_date BETWEEN '${ship_start_date}' AND '${ship_end_date}'   -- 仅在用户明确按船期查询时启用

    -- 业务类型（必填）
    and type = '${type}'   -- 'healthy_order' = 接单/下单; 'healthy_shipment' = 出货

    -- 组织维度（人员 / 部门）筛选（可选，未提供时整段过滤被参数化为 IS NULL 跳过）
    and (${dept} IS NULL OR dept = '${dept}')                                              -- 一级部门
    and (${source} IS NULL OR source = '${source}')                                        -- 二级部门
    and (${salesman} IS NULL OR salesman = '${salesman}')                                  -- 销售姓名
    and (${user_name} IS NULL OR user_name = '${user_name}')                               -- 销售工号（JOIN 目标表的关键字段）

    -- 订单信息筛选（公司 / 工厂 / 客户，可选）
    and (${sales_organization} IS NULL OR sales_organization = '${sales_organization}')   -- 公司
    and (${factory} IS NULL OR factory = '${factory}')                                     -- 工厂
    and (${customer_short_name} IS NULL OR customer_short_name = '${customer_short_name}') -- 客户简称

    -- 产品维度筛选（可选；四层分类：大类 → 材料 → 详细物料名 → 型号代码）
    and (${product_type} IS NULL OR product_type = '${product_type}')                      -- 产品大类（手动轮椅/电动轮椅/助行器等）
    and (${material} IS NULL OR material = '${material}')                                  -- 材料（铁质/碳纤维等）
    -- material_name 必须用 LIKE 模糊查询，因为存的是含型号规格的全名
    -- 例：'轮椅 智能化多功能可调节轮椅 Y069型 YK253139-2 24寸 表面喷塑黑'
    and (${material_name} IS NULL OR material_name LIKE '%${material_name}%')             -- 详细物料名（模糊查询）
    -- remark = 产品型号/系列代码，短字符串，常用精确匹配；用户给完整代码时用 = ，只给一半时用 LIKE
    -- 例：'SPIRIT X4' / 'Y069' / 'A100'
    and (${remark} IS NULL OR remark = '${remark}')                                        -- 型号代码（精确匹配）
    -- 模糊变体（用户只给型号一部分时用）：
    -- and (${remark_fuzzy} IS NULL OR remark LIKE '%${remark_fuzzy}%')

    -- 订单明细筛选（可选，数值字段用范围查询）
    and (${price_min} IS NULL OR price >= ${price_min})                                    -- 单价下限（USD）
    and (${price_max} IS NULL OR price <= ${price_max})                                    -- 单价上限（USD）
    and (${quantity_min} IS NULL OR quantity >= ${quantity_min})                           -- 件数下限
    and (${quantity_max} IS NULL OR quantity <= ${quantity_max})                           -- 件数上限

    -- 地理维度筛选（可选）
    and (${area} IS NULL OR area = '${area}')                                              -- 销售区域
    and (${country} IS NULL OR country = '${country}')                                     -- 销售国家
${group_by_clause}
 ;
