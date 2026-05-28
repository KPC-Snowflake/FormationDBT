{% macro log_run_start() %}
    {% set query %}
        CREATE TABLE IF NOT EXISTS {{ target.database }}.{{ target.schema }}.dbt_run_log (
            run_id VARCHAR,
            run_started_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
            target_name VARCHAR,
            target_schema VARCHAR
        );

        INSERT INTO {{ target.database }}.{{ target.schema }}.dbt_run_log
            (run_id, target_name, target_schema)
        VALUES
            ('{{ invocation_id }}', '{{ target.name }}', '{{ target.schema }}');
    {% endset %}
    {% do run_query(query) %}
    {{ log("Run logged: " ~ invocation_id, info=True) }}
{% endmacro %}
