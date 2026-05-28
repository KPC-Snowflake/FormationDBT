with order_items as (
    select * from {{ ref('int_order_items') }}
),

summarized as (
    select
        order_key,
        customer_key,
        order_date,
        order_status,
        order_priority,
        sum(quantity)         as total_quantity,
        sum(extended_price)   as gross_amount,
        sum(discounted_price) as discounted_amount,
        sum(final_price)      as net_amount,
        count(*)              as line_item_count,
        min(ship_date)        as first_ship_date,
        max(ship_date)        as last_ship_date
    from order_items
    group by 1, 2, 3, 4, 5
)

select * from summarized
