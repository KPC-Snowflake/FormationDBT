with suppliers as (
    select * from {{ ref('stg_tpch__suppliers') }}
),

nations as (
    select * from {{ ref('stg_tpch__nations') }}
),

regions as (
    select * from {{ ref('stg_tpch__regions') }}
),

part_agg as (
    select * from {{ ref('int_part_suppliers_agg') }}
),

final as (
    select
        suppliers.supplier_key,
        suppliers.supplier_name,
        suppliers.address,
        suppliers.phone,
        suppliers.account_balance,
        nations.nation_name,
        nations.nation_key,
        regions.region_name,
        regions.region_key,
        part_agg.parts_supplied_count,
        part_agg.avg_supply_cost,
        part_agg.total_available_quantity
    from suppliers
    inner join nations
        on suppliers.nation_key = nations.nation_key
    inner join regions
        on nations.region_key = regions.region_key
    left join part_agg
        on suppliers.supplier_key = part_agg.supplier_key
)

select * from final
