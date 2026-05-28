{% macro discount_amount(price_col, discount_col) %}
    ({{ price_col }} * {{ discount_col }})
{% endmacro %}
