with orders as (
    select * from {{ ref('fct_orders') }}
),

customers as (
    select * from {{ ref('dim_customers') }}
),

clv as (
    select
        customers.customer_key,
        customers.customer_name,
        customers.market_segment,
        customers.nation_name,
        customers.region_name,
        count(distinct orders.order_key)    as total_orders,
        sum(orders.net_amount)              as lifetime_value,
        avg(orders.net_amount)              as avg_order_value,
        min(orders.order_date)              as first_order_date,
        max(orders.order_date)              as last_order_date,
        datediff('day',
            min(orders.order_date),
            max(orders.order_date))         as customer_tenure_days
    from customers
    inner join orders
        on customers.customer_key = orders.customer_key
    group by 1, 2, 3, 4, 5
)

select * from clv
