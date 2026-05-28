{% snapshot snap_customers %}

{{
    config(
        target_database='ANALYTICS',
        target_schema='SNAPSHOTS',
        unique_key='customer_key',
        strategy='check',
        check_cols=['account_balance', 'market_segment', 'address', 'phone'],
    )
}}

select * from {{ ref('stg_tpch__customers') }}

{% endsnapshot %}
