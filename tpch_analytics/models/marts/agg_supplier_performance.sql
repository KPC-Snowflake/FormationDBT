with order_items as (
    select * from {{ ref('int_order_items') }}
),

suppliers as (
    select * from {{ ref('dim_suppliers') }}
),

performance as (
    select
        suppliers.supplier_key,
        suppliers.supplier_name,
        suppliers.nation_name,
        suppliers.region_name,
        suppliers.parts_supplied_count,
        suppliers.avg_supply_cost,
        count(distinct order_items.order_key)   as orders_fulfilled,
        sum(order_items.quantity)                as total_quantity_sold,
        sum(order_items.final_price)             as total_revenue,
        avg(order_items.final_price)             as avg_line_item_value,
        sum(case when order_items.return_flag = 'R'
            then 1 else 0 end)                  as returned_items,
        count(*)                                as total_items,
        sum(case when order_items.return_flag = 'R'
            then 1 else 0 end)::float
            / nullif(count(*), 0)               as return_rate,
        avg(datediff('day', order_items.ship_date, order_items.receipt_date))
                                                as avg_delivery_days
    from order_items
    inner join suppliers
        on order_items.supplier_key = suppliers.supplier_key
    group by 1, 2, 3, 4, 5, 6
)

select * from performance
