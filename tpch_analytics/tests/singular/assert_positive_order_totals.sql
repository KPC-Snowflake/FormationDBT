select
    order_key,
    net_amount
from {{ ref('fct_orders') }}
where net_amount < 0
