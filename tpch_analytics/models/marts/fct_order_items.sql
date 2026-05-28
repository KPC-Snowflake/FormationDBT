{{
    config(
        materialized='incremental',
        unique_key='line_item_key',
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

with order_items as (
    select * from {{ ref('int_order_items') }}
)

select *
from order_items

{% if is_incremental() %}
    where ship_date > (select max(ship_date) from {{ this }})
{% endif %}
