with part_suppliers as (
    select * from {{ ref('stg_tpch__part_suppliers') }}
),

aggregated as (
    select
        supplier_key,
        count(distinct part_key)  as parts_supplied_count,
        sum(available_quantity)   as total_available_quantity,
        avg(supply_cost)          as avg_supply_cost,
        min(supply_cost)          as min_supply_cost,
        max(supply_cost)          as max_supply_cost
    from part_suppliers
    group by 1
)

select * from aggregated
