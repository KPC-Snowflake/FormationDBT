with orders as (
    select * from {{ ref('stg_tpch__orders') }}
),

line_items as (
    select * from {{ ref('stg_tpch__line_items') }}
),

joined as (
    select
        line_items.line_item_key,
        line_items.order_key,
        orders.customer_key,
        orders.order_date,
        orders.order_status,
        orders.order_priority,
        line_items.part_key,
        line_items.supplier_key,
        line_items.line_number,
        line_items.quantity,
        line_items.extended_price,
        line_items.discount_percentage,
        line_items.tax_rate,
        line_items.discounted_price,
        line_items.final_price,
        line_items.return_flag,
        line_items.line_status,
        line_items.ship_date,
        line_items.commit_date,
        line_items.receipt_date,
        line_items.ship_mode
    from line_items
    inner join orders
        on line_items.order_key = orders.order_key
)

select * from joined
