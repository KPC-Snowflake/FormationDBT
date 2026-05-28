{% macro grant_select(role='ANALYST') %}
    {% set sql %}
        GRANT SELECT ON {{ this }} TO ROLE {{ role }};
    {% endset %}
    {% do run_query(sql) %}
    {% do log("Granted SELECT on " ~ this ~ " to " ~ role, info=True) %}
{% endmacro %}
