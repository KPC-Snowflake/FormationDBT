with order_summary as (
    select * from {{ ref('int_order_items_summary') }}
),

customers as (
    select * from {{ ref('stg_tpch__customers') }}
),

final as (
    select
        order_summary.order_key,
        order_summary.customer_key,
        customers.customer_name,
        customers.market_segment,
        order_summary.order_date,
        order_summary.order_status,
        order_summary.order_priority,
        order_summary.line_item_count,
        order_summary.total_quantity,
        order_summary.gross_amount,
        order_summary.discounted_amount,
        order_summary.net_amount,
        order_summary.first_ship_date,
        order_summary.last_ship_date,
        datediff('day', order_summary.order_date, order_summary.last_ship_date)
            as days_to_fulfill
    from order_summary
    inner join customers
        on order_summary.customer_key = customers.customer_key
)

select * from final
