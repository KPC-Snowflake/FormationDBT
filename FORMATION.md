# Formation dbt avec Snowflake - De Debutant a Expert

## Informations generales

| Element | Detail |
|---------|--------|
| **Duree** | 2 jours (16 heures, 8 modules) |
| **Public** | Data analysts / analytics engineers avec des bases SQL |
| **Plateforme** | Snowflake |
| **Dataset** | `SNOWFLAKE_SAMPLE_DATA.TPCH_SF1` (benchmark TPC-H) |
| **dbt version** | dbt-core 1.9+ avec dbt-snowflake |
| **Outils** | VS Code, Python 3.10+, Git/GitHub, Snowflake UI |

---

## Schema du dataset TPCH_SF1

Le dataset TPC-H modelise un systeme de gestion de commandes pour un distributeur de pieces :

```
REGION (5 lignes)
  └── NATION (25 lignes)
        ├── CUSTOMER (150 000 lignes)
        │     └── ORDERS (1 500 000 lignes)
        │           └── LINEITEM (6 001 215 lignes)
        │                 ├── → PART (200 000 lignes)
        │                 └── → SUPPLIER (10 000 lignes)
        └── SUPPLIER
              └── PARTSUPP (800 000 lignes)
                    └── → PART
```

| Table | Description | Colonnes cles |
|-------|------------|---------------|
| `REGION` | 5 regions du monde | R_REGIONKEY, R_NAME |
| `NATION` | 25 nations | N_NATIONKEY, N_NAME, N_REGIONKEY |
| `CUSTOMER` | Clients | C_CUSTKEY, C_NAME, C_NATIONKEY, C_MKTSEGMENT, C_ACCTBAL |
| `ORDERS` | Commandes | O_ORDERKEY, O_CUSTKEY, O_ORDERSTATUS, O_TOTALPRICE, O_ORDERDATE |
| `LINEITEM` | Lignes de commande | L_ORDERKEY, L_PARTKEY, L_SUPPKEY, L_QUANTITY, L_EXTENDEDPRICE, L_DISCOUNT |
| `PART` | Pieces/produits | P_PARTKEY, P_NAME, P_BRAND, P_TYPE, P_RETAILPRICE |
| `SUPPLIER` | Fournisseurs | S_SUPPKEY, S_NAME, S_NATIONKEY, S_ACCTBAL |
| `PARTSUPP` | Lien piece-fournisseur | PS_PARTKEY, PS_SUPPKEY, PS_AVAILQTY, PS_SUPPLYCOST |

---

## Architecture cible du projet dbt

```
tpch_analytics/
├── dbt_project.yml
├── packages.yml
├── profiles.yml.example
├── seeds/
│   └── order_priority_mapping.csv
├── snapshots/
│   └── snap_customers.sql
├── macros/
│   ├── generate_schema_name.sql
│   ├── discount_amount.sql
│   ├── grant_select.sql
│   └── log_dbt_run.sql
├── models/
│   ├── sources.yml
│   ├── staging/          (8 modeles - vues)
│   ├── intermediate/     (3 modeles - ephemeral)
│   └── marts/            (7 modeles - tables)
└── tests/
    ├── singular/
    └── generic/
```

---

# JOUR 1

---

## Module 1 - Introduction a dbt (1h00)

### 1.1 - Qu'est-ce que dbt ? (15 min)

**dbt (data build tool)** est un outil de transformation de donnees qui permet aux analystes d'ecrire des requetes SELECT en SQL, pendant que dbt se charge de toute la partie DDL/DML (CREATE TABLE, INSERT, etc.).

dbt s'inscrit dans l'approche **ELT** (Extract, Load, Transform) :
- **Extract** : les donnees sont extraites des sources (API, bases, fichiers)
- **Load** : elles sont chargees brutes dans le data warehouse (par Fivetran, Airbyte, etc.)
- **Transform** : dbt transforme les donnees brutes en modeles analytiques

```
Sources (API, BDD, Fichiers)
    │
    ▼
Ingestion (Fivetran, Airbyte)
    │
    ▼
Snowflake RAW (donnees brutes)
    │
    ▼
★ dbt ★ (transformation)
    │
    ▼
Snowflake ANALYTICS (modeles propres)
    │
    ▼
BI (Tableau, Looker, Streamlit)
```

**dbt Core** = open source, en ligne de commande
**dbt Cloud** = plateforme SaaS avec IDE web, scheduling, CI/CD

### 1.2 - Pourquoi dbt ? (15 min)

Les problemes que dbt resout :

1. **Inference des dependances** : la fonction `{{ ref('model_name') }}` construit automatiquement un DAG (Directed Acyclic Graph) des dependances
2. **Tests integres** : tests de qualite des donnees (unique, not_null, relationships, accepted_values)
3. **Documentation** : site de documentation auto-genere a partir des fichiers YAML
4. **Version control** : les modeles SQL vivent dans Git = code review, historique, CI/CD
5. **Modularite** : macros Jinja pour eviter la duplication de code

### 1.3 - Le dataset TPCH que nous allons utiliser (15 min)

Connectez-vous a Snowflake et explorez les donnees :

```sql
-- Compter les lignes de chaque table
SELECT 'CUSTOMER' AS table_name, COUNT(*) AS row_count
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER
UNION ALL
SELECT 'ORDERS', COUNT(*)
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
UNION ALL
SELECT 'LINEITEM', COUNT(*)
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM
UNION ALL
SELECT 'PART', COUNT(*)
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PART
UNION ALL
SELECT 'SUPPLIER', COUNT(*)
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.SUPPLIER
UNION ALL
SELECT 'PARTSUPP', COUNT(*)
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.PARTSUPP
UNION ALL
SELECT 'NATION', COUNT(*)
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION
UNION ALL
SELECT 'REGION', COUNT(*)
  FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.REGION
ORDER BY row_count DESC;
```

```sql
-- Explorer la structure d'une commande
SELECT
    o.O_ORDERKEY,
    o.O_ORDERDATE,
    o.O_ORDERSTATUS,
    o.O_TOTALPRICE,
    c.C_NAME AS customer_name,
    c.C_MKTSEGMENT,
    n.N_NAME AS nation
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS o
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.CUSTOMER c ON o.O_CUSTKEY = c.C_CUSTKEY
JOIN SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.NATION n ON c.C_NATIONKEY = n.N_NATIONKEY
LIMIT 10;
```

### 1.4 - Les couches de notre projet (15 min)

Notre projet dbt suivra une architecture en 3 couches :

| Couche | Role | Materialisation | Convention de nommage |
|--------|------|----------------|----------------------|
| **Staging** | Nettoyage et renommage des colonnes sources | `view` | `stg_tpch__<table>` |
| **Intermediate** | Jointures et enrichissements | `ephemeral` | `int_<description>` |
| **Marts** | Modeles business-ready pour la BI | `table` | `fct_`, `dim_`, `agg_` |

---

## Module 2 - Mise en place de l'environnement (1h30)

### 2.1 - Installation des outils (20 min)

#### Pre-requis a verifier

```bash
python3 --version   # Python 3.10+
git --version       # Git installe
code --version      # VS Code installe
```

#### Extensions VS Code recommandees

- **dbt Power User** : navigation, preview, auto-complete dbt
- **SQLFluff** : linter SQL
- **YAML** : coloration syntaxique YAML
- **GitLens** : visualisation Git avancee

### 2.2 - Environnement virtuel et installation dbt (20 min)

```bash
# Creer le repertoire du projet
mkdir tpch_analytics && cd tpch_analytics

# Creer et activer l'environnement virtuel
python3 -m venv venv
source venv/bin/activate        # Mac/Linux
# venv\Scripts\activate          # Windows

# Installer dbt-snowflake (inclut dbt-core)
pip install dbt-snowflake

# Verifier l'installation
dbt --version
```

### 2.3 - Configuration de la connexion Snowflake (20 min)

Initialiser le projet :

```bash
dbt init tpch_analytics
```

Configurer `~/.dbt/profiles.yml` :

```yaml
tpch_analytics:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: "<VOTRE_ACCOUNT>"          # ex: QRQOCXI-KD48953
      user: "<VOTRE_USER>"                # ex: JULIEN.JOUCLARD
      authenticator: externalbrowser      # Authentification SSO
      role: ACCOUNTADMIN
      database: ANALYTICS
      warehouse: COMPUTE_WH
      schema: "DEV_{{ env_var('DBT_USER', 'default') }}"
      threads: 4
```

> **Note securite** : le fichier `profiles.yml` contient des informations de connexion. Ne JAMAIS le commiter dans Git. Il doit rester dans `~/.dbt/`.

### 2.4 - Preparation de Snowflake (10 min)

Executer dans une worksheet Snowflake :

```sql
-- Creer la base de donnees cible
CREATE DATABASE IF NOT EXISTS ANALYTICS;

-- Creer les schemas pour chaque couche
CREATE SCHEMA IF NOT EXISTS ANALYTICS.STAGING;
CREATE SCHEMA IF NOT EXISTS ANALYTICS.INTERMEDIATE;
CREATE SCHEMA IF NOT EXISTS ANALYTICS.MARTS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS.SNAPSHOTS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS.SEEDS;

-- Schema de developpement (adapter le nom)
CREATE SCHEMA IF NOT EXISTS ANALYTICS.DEV_JULIEN;
```

### 2.5 - Configuration du projet dbt (15 min)

Le fichier `dbt_project.yml` est le coeur de la configuration :

```yaml
name: 'tpch_analytics'
version: '1.0.0'
profile: 'tpch_analytics'

model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:
  - "target"
  - "dbt_packages"

seeds:
  tpch_analytics:
    +schema: seeds

snapshots:
  tpch_analytics:
    +target_schema: snapshots

models:
  tpch_analytics:
    staging:
      +materialized: view
      +schema: staging
    intermediate:
      +materialized: ephemeral
    marts:
      +materialized: table
      +schema: marts
      +tags: ['daily']
```

Points cles :
- Les modeles **staging** sont materialises en `view` (leger, toujours a jour)
- Les modeles **intermediate** sont `ephemeral` (pas de table creee, inlines dans le SQL)
- Les modeles **marts** sont materialises en `table` (performant pour la BI)

### 2.6 - Verification et GitHub (5 min)

#### Exercice 2A - Verifier la connexion

```bash
dbt debug
```

Resultat attendu : tous les checks sont verts (connection OK, dependencies OK).

#### Exercice 2B - Initialiser le depot Git

```bash
git init

# Creer .gitignore
cat > .gitignore << 'EOF'
target/
dbt_packages/
logs/
venv/
profiles.yml
.env
*.pyc
EOF

git add .
git commit -m "feat: initial dbt project setup"
```

---

## Module 3 - Construction du projet dbt (3h00)

### 3.1 - Declaration des sources (20 min)

Le fichier `models/sources.yml` declare les tables sources que nous allons utiliser :

```yaml
version: 2

sources:
  - name: tpch
    description: "Donnees benchmark TPC-H depuis la base Snowflake Sample Data"
    database: SNOWFLAKE_SAMPLE_DATA
    schema: TPCH_SF1
    tables:
      - name: ORDERS
        description: "Commandes clients avec statut et priorite"
        columns:
          - name: O_ORDERKEY
            description: "Cle primaire de la table des commandes"
            tests:
              - unique
              - not_null
      - name: CUSTOMER
        description: "Donnees maitres des clients"
        columns:
          - name: C_CUSTKEY
            tests:
              - unique
              - not_null
      - name: LINEITEM
        description: "Lignes de commande avec details prix et expedition"
      - name: PART
        description: "Catalogue de pieces"
      - name: SUPPLIER
        description: "Donnees maitres des fournisseurs"
      - name: PARTSUPP
        description: "Relation piece-fournisseur"
      - name: NATION
        description: "Donnees de reference des nations"
      - name: REGION
        description: "Donnees de reference des regions"
```

**Principe** : on ne reference JAMAIS les tables sources directement dans les modeles. On utilise toujours `{{ source('tpch', 'ORDERS') }}`.

### 3.2 - Modeles staging (40 min)

Convention : **un modele staging par table source**. On y fait :
- Renommage des colonnes (snake_case, noms metier)
- Cast de types si necessaire
- Ajout de colonnes calculees simples

#### stg_tpch__orders.sql

```sql
with source as (
    select * from {{ source('tpch', 'ORDERS') }}
),

renamed as (
    select
        o_orderkey      as order_key,
        o_custkey       as customer_key,
        o_orderstatus   as order_status,
        o_totalprice    as total_price,
        o_orderdate     as order_date,
        o_orderpriority as order_priority,
        o_clerk         as clerk,
        o_shippriority  as ship_priority,
        o_comment       as comment
    from source
)

select * from renamed
```

#### stg_tpch__customers.sql

```sql
with source as (
    select * from {{ source('tpch', 'CUSTOMER') }}
),

renamed as (
    select
        c_custkey    as customer_key,
        c_name       as customer_name,
        c_address    as address,
        c_nationkey  as nation_key,
        c_phone      as phone,
        c_acctbal    as account_balance,
        c_mktsegment as market_segment,
        c_comment    as comment
    from source
)

select * from renamed
```

#### stg_tpch__line_items.sql (avec colonnes calculees)

```sql
with source as (
    select * from {{ source('tpch', 'LINEITEM') }}
),

renamed as (
    select
        {{ dbt_utils.generate_surrogate_key(['l_orderkey', 'l_linenumber']) }}
                        as line_item_key,
        l_orderkey      as order_key,
        l_partkey       as part_key,
        l_suppkey       as supplier_key,
        l_linenumber    as line_number,
        l_quantity      as quantity,
        l_extendedprice as extended_price,
        l_discount      as discount_percentage,
        l_tax           as tax_rate,
        l_returnflag    as return_flag,
        l_linestatus    as line_status,
        l_shipdate      as ship_date,
        l_commitdate    as commit_date,
        l_receiptdate   as receipt_date,
        l_shipinstruct  as ship_instructions,
        l_shipmode      as ship_mode,
        l_comment       as comment,
        -- Colonnes calculees
        l_extendedprice * (1 - l_discount)               as discounted_price,
        l_extendedprice * (1 - l_discount) * (1 + l_tax) as final_price
    from source
)

select * from renamed
```

> **Note** : `dbt_utils.generate_surrogate_key` cree une cle de hashage a partir de plusieurs colonnes. La table LINEITEM n'a pas de cle primaire unique simple, on la genere a partir de `order_key + line_number`.

#### Exercice 3A - Creer les modeles staging manquants

Creez les fichiers suivants en suivant le meme pattern :
- `stg_tpch__parts.sql` (colonnes : part_key, part_name, manufacturer, brand, part_type, part_size, container, retail_price, comment)
- `stg_tpch__suppliers.sql` (colonnes : supplier_key, supplier_name, address, nation_key, phone, account_balance, comment)
- `stg_tpch__part_suppliers.sql` (colonnes : part_supplier_key [surrogate], part_key, supplier_key, available_quantity, supply_cost, comment)
- `stg_tpch__nations.sql` (colonnes : nation_key, nation_name, region_key, comment)
- `stg_tpch__regions.sql` (colonnes : region_key, region_name, comment)

Puis executez :

```bash
dbt run --select staging
```

> **Indice** : pour `stg_tpch__part_suppliers`, utilisez `{{ dbt_utils.generate_surrogate_key(['ps_partkey', 'ps_suppkey']) }}` comme cle surrogate.

### 3.3 - Tests et documentation staging (20 min)

Le fichier `_stg__models.yml` definit les tests et descriptions pour chaque modele staging :

```yaml
version: 2

models:
  - name: stg_tpch__orders
    description: "Commandes nettoyees depuis la source TPCH"
    columns:
      - name: order_key
        description: "Cle primaire"
        tests:
          - unique
          - not_null
      - name: customer_key
        description: "Cle etrangere vers les clients"
        tests:
          - not_null
          - relationships:
              to: ref('stg_tpch__customers')
              field: customer_key
      - name: order_status
        tests:
          - accepted_values:
              values: ['F', 'O', 'P']
```

Les 4 tests generiques de dbt :
- **unique** : aucun doublon dans la colonne
- **not_null** : aucune valeur NULL
- **accepted_values** : les valeurs sont dans une liste definie
- **relationships** : chaque valeur existe dans une autre table (integrite referentielle)

```bash
dbt test --select staging
```

### 3.4 - Installation des packages (10 min)

Avant d'aller plus loin, installons les packages dbt que nous utilisons :

`packages.yml` :

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: ">=1.3.0"
  - package: calogica/dbt_expectations
    version: ">=0.10.0"
```

```bash
dbt deps
```

`dbt_utils` fournit des macros utilitaires (surrogate_key, date_spine, etc.)
`dbt_expectations` fournit des tests avances inspires de Great Expectations.

### 3.5 - Modeles intermediaires (30 min)

Les modeles intermediaires joignent et enrichissent les donnees staging.

#### int_order_items.sql

Jointure commandes + lignes de commande :

```sql
with orders as (
    select * from {{ ref('stg_tpch__orders') }}
),

line_items as (
    select * from {{ ref('stg_tpch__line_items') }}
),

joined as (
    select
        line_items.line_item_key,
        line_items.order_key,
        orders.customer_key,
        orders.order_date,
        orders.order_status,
        orders.order_priority,
        line_items.part_key,
        line_items.supplier_key,
        line_items.line_number,
        line_items.quantity,
        line_items.extended_price,
        line_items.discount_percentage,
        line_items.tax_rate,
        line_items.discounted_price,
        line_items.final_price,
        line_items.return_flag,
        line_items.line_status,
        line_items.ship_date,
        line_items.commit_date,
        line_items.receipt_date,
        line_items.ship_mode
    from line_items
    inner join orders
        on line_items.order_key = orders.order_key
)

select * from joined
```

> **Important** : la fonction `{{ ref('stg_tpch__orders') }}` cree une dependance dans le DAG. dbt sait qu'il doit executer `stg_tpch__orders` AVANT `int_order_items`.

#### int_order_items_summary.sql

Agregation au niveau commande :

```sql
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
```

#### int_part_suppliers_agg.sql

Agregation fournisseurs :

```sql
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
```

> **Rappel** : les modeles intermediaires sont `ephemeral` par defaut (configure dans `dbt_project.yml`). Ils ne creent pas de table/vue dans Snowflake - leur SQL est inline dans les modeles qui les referencent.

### 3.6 - Modeles marts (40 min)

Les marts sont les modeles "business-ready" que la BI va consommer.

#### fct_orders.sql (table de faits)

```sql
with order_summary as (
    select * from {{ ref('int_order_items_summary') }}
),

customers as (
    select * from {{ ref('stg_tpch__customers') }}
),

final as (
    select
        order_summary.order_key,
        order_summary.customer_key,
        customers.customer_name,
        customers.market_segment,
        order_summary.order_date,
        order_summary.order_status,
        order_summary.order_priority,
        order_summary.line_item_count,
        order_summary.total_quantity,
        order_summary.gross_amount,
        order_summary.discounted_amount,
        order_summary.net_amount,
        order_summary.first_ship_date,
        order_summary.last_ship_date,
        datediff('day', order_summary.order_date, order_summary.last_ship_date)
            as days_to_fulfill
    from order_summary
    inner join customers
        on order_summary.customer_key = customers.customer_key
)

select * from final
```

#### dim_customers.sql (dimension)

```sql
with customers as (
    select * from {{ ref('stg_tpch__customers') }}
),

nations as (
    select * from {{ ref('stg_tpch__nations') }}
),

regions as (
    select * from {{ ref('stg_tpch__regions') }}
),

final as (
    select
        customers.customer_key,
        customers.customer_name,
        customers.address,
        customers.phone,
        customers.account_balance,
        customers.market_segment,
        nations.nation_name,
        nations.nation_key,
        regions.region_name,
        regions.region_key
    from customers
    inner join nations
        on customers.nation_key = nations.nation_key
    inner join regions
        on nations.region_key = regions.region_key
)

select * from final
```

#### agg_customer_lifetime_value.sql (agregat metier)

```sql
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
```

#### agg_supplier_performance.sql (agregat metier)

```sql
with order_items as (
    select * from {{ ref('int_order_items') }}
),

suppliers as (
    select * from {{ ref('dim_suppliers') }}
),

performance as (
    select
        suppliers.supplier_key,
        suppliers.supplier_name,
        suppliers.nation_name,
        suppliers.region_name,
        suppliers.parts_supplied_count,
        suppliers.avg_supply_cost,
        count(distinct order_items.order_key)   as orders_fulfilled,
        sum(order_items.quantity)                as total_quantity_sold,
        sum(order_items.final_price)             as total_revenue,
        avg(order_items.final_price)             as avg_line_item_value,
        sum(case when order_items.return_flag = 'R'
            then 1 else 0 end)                  as returned_items,
        count(*)                                as total_items,
        sum(case when order_items.return_flag = 'R'
            then 1 else 0 end)::float
            / nullif(count(*), 0)               as return_rate,
        avg(datediff('day', order_items.ship_date, order_items.receipt_date))
                                                as avg_delivery_days
    from order_items
    inner join suppliers
        on order_items.supplier_key = suppliers.supplier_key
    group by 1, 2, 3, 4, 5, 6
)

select * from performance
```

### 3.7 - Exercice 3C - Build complet et exploration

```bash
# Construire tout le projet (modeles + tests)
dbt build
```

Puis dans Snowflake, explorez les resultats :

```sql
-- Top 10 clients par valeur a vie
SELECT customer_name, market_segment, nation_name,
       total_orders, lifetime_value, avg_order_value
FROM ANALYTICS.MARTS.AGG_CUSTOMER_LIFETIME_VALUE
ORDER BY lifetime_value DESC
LIMIT 10;

-- Fournisseurs avec les plus hauts taux de retour
SELECT supplier_name, nation_name, orders_fulfilled,
       total_revenue, return_rate
FROM ANALYTICS.MARTS.AGG_SUPPLIER_PERFORMANCE
WHERE orders_fulfilled > 100
ORDER BY return_rate DESC
LIMIT 10;

-- Repartition des commandes par segment de marche
SELECT market_segment,
       COUNT(*) as nb_orders,
       ROUND(AVG(net_amount), 2) as avg_order_value,
       ROUND(SUM(net_amount), 2) as total_revenue
FROM ANALYTICS.MARTS.FCT_ORDERS
GROUP BY 1
ORDER BY total_revenue DESC;
```

### 3.8 - Les materialisations (20 min)

| Materialisation | Description | Quand l'utiliser |
|----------------|-------------|-----------------|
| `view` | Vue SQL, recalculee a chaque requete | Staging, donnees legeres |
| `table` | Table physique, recalculee a chaque `dbt run` | Marts, donnees lourdes, BI |
| `ephemeral` | Pas de table/vue, SQL inline via CTE | Intermediaire, transformations internes |
| `incremental` | Table avec ajout/mise a jour incrementale | Faits volumineux (Module 5) |

#### Exercice 3D - Changer la materialisation

Modifiez `int_order_items` de `ephemeral` a `view` :

```sql
-- Ajouter en haut de int_order_items.sql :
{{ config(materialized='view') }}
```

Puis :
```bash
dbt run --select int_order_items
```

Observez dans Snowflake : la vue `INT_ORDER_ITEMS` apparait maintenant. Remettez en `ephemeral` apres l'exercice.

---

## Module 4 - Tests avances (1h30)

### 4.1 - Severite et seuils des tests (15 min)

Par defaut, un test en echec bloque le `dbt build`. On peut configurer la severite :

```yaml
# Dans _stg__models.yml
- name: order_key
  tests:
    - unique:
        severity: error        # Bloque si echec
    - not_null:
        severity: warn         # Avertissement seulement
        warn_if: ">10"         # Warn si plus de 10 lignes en erreur
        error_if: ">100"       # Error si plus de 100
```

Configuration globale dans `dbt_project.yml` :

```yaml
tests:
  tpch_analytics:
    +severity: warn    # Tous les tests en warn par defaut
```

### 4.2 - Tests dbt_utils (20 min)

Le package `dbt_utils` offre des tests supplementaires :

```yaml
models:
  - name: stg_tpch__line_items
    tests:
      # Combinaison unique de colonnes
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - order_key
            - line_number
    columns:
      - name: discount_percentage
        tests:
          # Valeur dans un intervalle
          - dbt_utils.accepted_range:
              min_value: 0
              max_value: 1
              inclusive: true
      - name: ship_date
        tests:
          # Expression SQL personnalisee
          - dbt_utils.expression_is_true:
              expression: ">= '1992-01-01'"
```

### 4.3 - Tests dbt_expectations (20 min)

Le package `dbt_expectations` offre des tests inspires de Great Expectations :

```yaml
models:
  - name: fct_orders
    columns:
      - name: net_amount
        tests:
          # Valeur entre deux bornes avec condition
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
              max_value: 1000000
              row_condition: "order_status != 'F'"
      - name: order_date
        tests:
          # Verification du type de colonne
          - dbt_expectations.expect_column_values_to_be_of_type:
              column_type: date
    tests:
      # Nombre de lignes dans un intervalle
      - dbt_expectations.expect_table_row_count_to_be_between:
          min_value: 1000000
          max_value: 2000000
```

### 4.4 - Tests singuliers personnalises (15 min)

Un test singulier est un fichier SQL dans `tests/singular/`. Il doit retourner **zero ligne** pour passer.

`tests/singular/assert_positive_order_totals.sql` :

```sql
-- Ce test echoue si des commandes ont un montant net negatif
select
    order_key,
    net_amount
from {{ ref('fct_orders') }}
where net_amount < 0
```

```bash
dbt test --select assert_positive_order_totals
```

#### Exercice 4A - Ecrire un test singulier

Creez `tests/singular/assert_positive_lifetime_value.sql` qui verifie qu'aucun client n'a une valeur a vie (lifetime_value) negative.

### 4.5 - Tests generiques personnalises (15 min)

Un test generique est reutilisable sur n'importe quelle colonne de n'importe quel modele.

`tests/generic/test_accepted_range.sql` :

```sql
{% test accepted_range(model, column_name, min_val, max_val) %}

select
    {{ column_name }}
from {{ model }}
where {{ column_name }} < {{ min_val }}
   or {{ column_name }} > {{ max_val }}

{% endtest %}
```

Utilisation dans le YAML :

```yaml
- name: quantity
  tests:
    - accepted_range:
        min_val: 1
        max_val: 50
```

### 4.6 - Unit tests (dbt 1.8+) (15 min)

Les unit tests permettent de tester la logique d'un modele avec des donnees fictives :

```yaml
unit_tests:
  - name: test_clv_calculation
    description: "Verifie que la valeur a vie est correctement calculee"
    model: agg_customer_lifetime_value
    given:
      - input: ref('fct_orders')
        rows:
          - {order_key: 100, customer_key: 1, customer_name: "Test Co",
             market_segment: "BUILDING", order_date: "1995-01-01",
             order_status: "F", order_priority: "1-URGENT",
             line_item_count: 2, total_quantity: 10, gross_amount: 600.00,
             discounted_amount: 550.00, net_amount: 500.00,
             first_ship_date: "1995-01-10", last_ship_date: "1995-01-15",
             days_to_fulfill: 14}
          - {order_key: 101, customer_key: 1, customer_name: "Test Co",
             market_segment: "BUILDING", order_date: "1995-06-01",
             order_status: "F", order_priority: "3-MEDIUM",
             line_item_count: 1, total_quantity: 5, gross_amount: 350.00,
             discounted_amount: 320.00, net_amount: 300.00,
             first_ship_date: "1995-06-05", last_ship_date: "1995-06-05",
             days_to_fulfill: 4}
      - input: ref('dim_customers')
        rows:
          - {customer_key: 1, customer_name: "Test Co", address: "123 Rue",
             phone: "555-0001", account_balance: 1000.00,
             market_segment: "BUILDING", nation_name: "FRANCE",
             nation_key: 1, region_name: "EUROPE", region_key: 3}
    expect:
      rows:
        - {customer_key: 1, total_orders: 2, lifetime_value: 800.00,
           avg_order_value: 400.00}
```

```bash
dbt test --select "test_type:unit"
```

#### Exercice 4B - Ecrire un unit test

Ecrivez un unit test pour `agg_supplier_performance` qui verifie le calcul du `return_rate` :
- 2 lignes de commande dont 1 avec return_flag = 'R'
- Le return_rate attendu doit etre 0.5

---

# JOUR 2

---

## Module 5 - Modelisation avancee (2h00)

### 5.1 - La fonction doc() (15 min)

La fonction `{{ doc() }}` permet d'ecrire de la documentation riche en Markdown dans des fichiers `.md` separes.

`models/staging/_stg__docs.md` :

```markdown
{% docs order_status %}

Le statut de la commande :
- **F** = Fulfilled (Finalisee) - la commande est completement livree
- **O** = Open (Ouverte) - la commande est en cours de traitement
- **P** = Partial (Partielle) - la commande est partiellement livree

{% enddocs %}

{% docs market_segment %}

Le segment de marche auquel appartient le client :
- **AUTOMOBILE** - Industrie automobile
- **BUILDING** - Construction et batiment
- **FURNITURE** - Mobilier et ameublement
- **HOUSEHOLD** - Articles menagers
- **MACHINERY** - Machines et equipements industriels

{% enddocs %}
```

Reference dans le YAML :

```yaml
- name: order_status
  description: "{{ doc('order_status') }}"
```

### 5.2 - Seeds (20 min)

Les seeds sont des fichiers CSV qui sont charges en table dans Snowflake. Utiles pour les tables de reference statiques.

`seeds/order_priority_mapping.csv` :

```csv
order_priority,priority_label,priority_rank
1-URGENT,Urgent,1
2-HIGH,High,2
3-MEDIUM,Medium,3
4-NOT SPECIFIED,Not Specified,4
5-LOW,Low,5
```

```bash
dbt seed
```

Utilisation dans un modele :

```sql
-- Ajouter a fct_orders.sql
with priority_mapping as (
    select * from {{ ref('order_priority_mapping') }}
),
-- ... puis joindre :
left join priority_mapping
    on order_summary.order_priority = priority_mapping.order_priority
```

#### Exercice 5A - Creer un seed

Creez `seeds/region_mapping.csv` :

```csv
region_name,business_region
AFRICA,EMEA
EUROPE,EMEA
MIDDLE EAST,EMEA
AMERICA,AMERICAS
ASIA,APAC
```

Chargez-le avec `dbt seed` et utilisez-le pour enrichir `dim_customers` avec une colonne `business_region`.

### 5.3 - Snapshots (30 min)

Les snapshots permettent de capturer les changements de donnees au fil du temps (SCD Type 2 - Slowly Changing Dimension).

`snapshots/snap_customers.sql` :

```sql
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
```

Concepts cles :
- **strategy='check'** : detecte les changements en comparant les colonnes specifiees
- **strategy='timestamp'** : detecte les changements via une colonne de date de modification
- Les snapshots ajoutent des colonnes : `dbt_valid_from`, `dbt_valid_to`, `dbt_scd_id`, `dbt_updated_at`

```bash
dbt snapshot
```

#### Exercice 5B - Executer le snapshot 2 fois

1. Executez `dbt snapshot` une premiere fois
2. Inspectez la table `ANALYTICS.SNAPSHOTS.SNAP_CUSTOMERS` dans Snowflake
3. Executez `dbt snapshot` une deuxieme fois
4. Observez : comme les donnees n'ont pas change, pas de nouvelles lignes
5. Discussion : que se passerait-il si le `market_segment` d'un client changeait ?

```sql
SELECT customer_key, customer_name, market_segment,
       dbt_valid_from, dbt_valid_to, dbt_updated_at
FROM ANALYTICS.SNAPSHOTS.SNAP_CUSTOMERS
WHERE customer_key = 1;
```

### 5.4 - Modeles incrementaux (30 min)

Les modeles incrementaux ne traitent que les **nouvelles donnees** a chaque execution (au lieu de tout recalculer).

`models/marts/fct_order_items.sql` :

```sql
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
```

Points cles :
- `is_incremental()` retourne `true` quand la table existe deja et qu'on n'est pas en `--full-refresh`
- `{{ this }}` reference la table cible existante
- `incremental_strategy='merge'` : fait un MERGE (upsert) base sur `unique_key`
- `--full-refresh` force la reconstruction complete

```bash
# Premier run : chargement complet
dbt run --select fct_order_items --full-refresh

# Runs suivants : incremental
dbt run --select fct_order_items
```

Strategies incrementales disponibles dans Snowflake :
- **merge** : UPSERT base sur la cle unique (defaut)
- **delete+insert** : supprime les lignes existantes puis insere
- **append** : insere seulement, pas de deduplication

### 5.5 - Model Governance (25 min)

La gouvernance des modeles (dbt 1.5+) permet de controler l'acces et la stabilite des modeles.

#### Groupes et acces

```yaml
# Dans dbt_project.yml
groups:
  - name: finance
    owner:
      name: "Equipe Finance Analytics"
      email: "finance@company.com"

  - name: supply_chain
    owner:
      name: "Equipe Supply Chain"
      email: "supply@company.com"
```

```yaml
# Dans _marts__models.yml
models:
  - name: fct_orders
    group: finance
    access: public       # Accessible par tous les groupes

  - name: agg_supplier_performance
    group: supply_chain
    access: protected    # Accessible seulement au sein du groupe
```

Niveaux d'acces :
- **public** : n'importe quel modele peut le referencer
- **protected** : seuls les modeles du meme groupe peuvent le referencer
- **private** : seuls les modeles du meme repertoire peuvent le referencer

#### Contrats

Les contrats garantissent le schema de sortie d'un modele :

```yaml
- name: fct_orders
  config:
    contract:
      enforced: true
  columns:
    - name: order_key
      data_type: number(38,0)
    - name: net_amount
      data_type: number(12,2)
    # Toutes les colonnes doivent avoir un data_type
```

Si le modele produit un schema different, `dbt run` echouera.

---

## Module 6 - Commandes et selecteurs (1h00)

### 6.1 - Commandes essentielles (15 min)

| Commande | Description |
|----------|------------|
| `dbt run` | Execute les modeles (CREATE TABLE/VIEW) |
| `dbt test` | Execute les tests |
| `dbt build` | Run + test dans l'ordre du DAG |
| `dbt compile` | Compile le SQL Jinja en SQL pur (sans executer) |
| `dbt docs generate` | Genere la documentation |
| `dbt docs serve` | Lance un serveur web pour la doc |
| `dbt seed` | Charge les fichiers CSV |
| `dbt snapshot` | Execute les snapshots |
| `dbt clean` | Supprime target/ et dbt_packages/ |
| `dbt deps` | Installe les packages |
| `dbt source freshness` | Verifie la fraicheur des sources |
| `dbt ls` | Liste les ressources (modeles, tests, etc.) |

### 6.2 - Selecteurs et operateurs de graphe (20 min)

```bash
# Executer un seul modele
dbt run --select stg_tpch__orders

# Un modele et TOUS ses descendants
dbt run --select stg_tpch__orders+

# Un modele et TOUS ses ancetres
dbt run --select +fct_orders

# Tout un dossier
dbt run --select staging

# Un modele et ses enfants directs (1 niveau)
dbt run --select stg_tpch__orders+1

# Exclure un modele
dbt run --select marts --exclude agg_supplier_performance

# Intersection : modeles dans staging ET tagues "critical"
dbt run --select staging,tag:critical

# Union : staging OU marts
dbt run --select staging marts

# Par type de ressource
dbt test --select "test_type:unit"
dbt test --select "test_type:singular"
```

### 6.3 - Tags (10 min)

Les tags permettent de categoriser les modeles pour les executions selectionnees :

```yaml
# Dans dbt_project.yml ou en config de modele
models:
  tpch_analytics:
    marts:
      fct_orders:
        +tags: ['daily', 'critical']
      agg_customer_lifetime_value:
        +tags: ['daily', 'finance']
      agg_supplier_performance:
        +tags: ['weekly', 'supply_chain']
```

```bash
dbt run --select tag:daily
dbt test --select tag:critical
```

### 6.4 - Documentation et DAG (15 min)

```bash
dbt docs generate
dbt docs serve
```

Explorez :
- Le **graphe de lignage** (DAG) : visualisation des dependances entre modeles
- Les pages de **documentation** de chaque modele
- Les descriptions des **colonnes** et les resultats de **tests**
- La documentation des **sources**

#### Exercice 6A - Challenges selecteurs

1. Listez tous les ancetres de `agg_customer_lifetime_value` :
   ```bash
   dbt ls --select +agg_customer_lifetime_value
   ```

2. Executez uniquement les modeles intermediaires et leurs dependants marts directs :
   ```bash
   dbt run --select intermediate+1
   ```

3. Testez uniquement les modeles marts :
   ```bash
   dbt test --select marts
   ```

4. Compilez le SQL de `fct_orders` pour voir le SQL genere :
   ```bash
   dbt compile --select fct_orders
   ```
   Puis inspectez `target/compiled/tpch_analytics/models/marts/fct_orders.sql`

---

## Module 7 - Jinja et Macros (2h00)

### 7.1 - Fondamentaux Jinja (20 min)

Jinja a trois types de blocs :

```sql
{# Ceci est un commentaire - ignore dans le SQL compile #}

{% set my_variable = 'hello' %}    -- Statement (logique)

{{ my_variable }}                   -- Expression (affichage)
```

Exemple dans un modele :

```sql
{% set price_columns = ['extended_price', 'discounted_price', 'final_price'] %}

select
    order_key,
    {% for col in price_columns %}
        sum({{ col }}) as total_{{ col }}
        {% if not loop.last %},{% endif %}
    {% endfor %}
from {{ ref('int_order_items') }}
group by 1
```

SQL compile genere :

```sql
select
    order_key,
    sum(extended_price) as total_extended_price,
    sum(discounted_price) as total_discounted_price,
    sum(final_price) as total_final_price
from ANALYTICS.DEV_JULIEN.INT_ORDER_ITEMS
group by 1
```

> **Astuce** : utilisez `dbt compile --select <model>` pour voir le SQL genere.

### 7.2 - Construire une macro (20 min)

Une macro est une fonction Jinja reutilisable.

`macros/discount_amount.sql` :

```sql
{% macro discount_amount(price_col, discount_col) %}
    ({{ price_col }} * {{ discount_col }})
{% endmacro %}
```

Utilisation :

```sql
select
    order_key,
    extended_price,
    discount_percentage,
    {{ discount_amount('extended_price', 'discount_percentage') }} as discount_value
from {{ ref('stg_tpch__line_items') }}
```

### 7.3 - La macro generate_schema_name (15 min)

Cette macro controle dans quel schema les modeles sont crees :

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
```

Comportement :
- En **dev** : `stg_tpch__orders` va dans `DEV_JULIEN_staging`
- En **prod** : `stg_tpch__orders` va dans `staging`

### 7.4 - Hooks (20 min)

Les hooks executent du SQL avant ou apres un modele.

#### Post-hook dans dbt_project.yml

```yaml
models:
  tpch_analytics:
    marts:
      +post-hook:
        - "GRANT SELECT ON {{ this }} TO ROLE ANALYST"
```

#### Macro de hook reutilisable

`macros/grant_select.sql` :

```sql
{% macro grant_select(role='ANALYST') %}
    {% set sql %}
        GRANT SELECT ON {{ this }} TO ROLE {{ role }};
    {% endset %}
    {% do run_query(sql) %}
    {% do log("Granted SELECT on " ~ this ~ " to " ~ role, info=True) %}
{% endmacro %}
```

Utilisation :

```yaml
models:
  tpch_analytics:
    marts:
      +post-hook:
        - "{{ grant_select('ANALYST') }}"
```

### 7.5 - Operations (15 min)

Les operations sont des macros executables en standalone avec `dbt run-operation`.

`macros/log_dbt_run.sql` :

```sql
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
```

```bash
dbt run-operation log_run_start
```

### 7.6 - Boucles for et variables (15 min)

#### Pivot dynamique

```sql
{% set segments = dbt_utils.get_column_values(
    table=ref('stg_tpch__customers'),
    column='market_segment'
) %}

select
    nation_name,
    {% for segment in segments %}
        sum(case when market_segment = '{{ segment }}'
            then lifetime_value else 0 end)
            as {{ segment | lower }}_revenue
        {% if not loop.last %},{% endif %}
    {% endfor %}
from {{ ref('agg_customer_lifetime_value') }}
group by 1
```

### 7.7 - La variable target (15 min)

La variable `target` contient les informations du profil actif :

```sql
-- Limiter les donnees en dev pour aller plus vite
select *
from {{ ref('int_order_items') }}
{% if target.name == 'dev' %}
    where order_date >= dateadd('year', -1, current_date())
{% endif %}
```

Proprietes utiles : `target.name`, `target.schema`, `target.database`, `target.type`

#### Exercice 7A - Creer une macro star_except

Creez `macros/star_except.sql` qui selectionne toutes les colonnes d'une relation sauf celles specifiees :

```sql
{% macro star_except(relation, except_columns) %}
    {% set columns = adapter.get_columns_in_relation(relation) %}
    {% set filtered = [] %}
    {% for col in columns %}
        {% if col.name | lower not in except_columns | map('lower') | list %}
            {% do filtered.append(col.name) %}
        {% endif %}
    {% endfor %}
    {{ filtered | join(', ') }}
{% endmacro %}
```

Utilisation :

```sql
select {{ star_except(ref('stg_tpch__customers'), ['comment', 'address']) }}
from {{ ref('stg_tpch__customers') }}
```

#### Exercice 7B - Modele pivot avec boucle for

Creez un modele `analyses/monthly_orders_by_priority.sql` qui genere un tableau pivot : une colonne par priorite de commande, une ligne par mois.

---

## Module 8 - Deploiement et dbt Cloud (2h00)

### 8.1 - Profil de production (15 min)

En production, on utilise un compte de service avec authentification par cle :

```yaml
tpch_analytics:
  target: prod
  outputs:
    prod:
      type: snowflake
      account: QRQOCXI-KD48953
      user: STREAMLIT
      private_key_path: /path/to/rsa_key.p8
      role: SYSADMIN
      database: ANALYTICS
      warehouse: COMPUTE_WH
      schema: PROD
      threads: 8
```

Points importants :
- **Pas de mot de passe** : authentification par paire de cles RSA
- **Compte de service** : `STREAMLIT` (pas un utilisateur humain)
- **Role restreint** : `SYSADMIN` (pas `ACCOUNTADMIN`)
- **Plus de threads** : 8 en prod vs 4 en dev

### 8.2 - Setup dbt Cloud (30 min)

1. Creez un compte sur [cloud.getdbt.com](https://cloud.getdbt.com)
2. **Connexion Snowflake** :
   - Account: votre identifiant Snowflake
   - Warehouse: COMPUTE_WH
   - Database: ANALYTICS
   - Credentials: cle RSA du compte STREAMLIT
3. **Connexion GitHub** :
   - Autorisez dbt Cloud a acceder a votre repo
   - Selectionnez le repository du projet
4. **Configuration projet** :
   - dbt version: 1.9
   - Target name: prod
   - Schema: PROD

### 8.3 - L'IDE dbt Cloud (15 min)

L'IDE dbt Cloud offre :
- Editeur de code avec coloration syntaxique
- Integration Git (branches, commits, PR)
- Compilation et preview du SQL
- Graphe de lignage interactif
- Execution de commandes dbt

### 8.4 - Configuration des jobs (30 min)

#### Job 1 : Run quotidien de production

- **Planification** : tous les jours a 06:00 UTC
- **Commandes** :
  ```
  dbt seed
  dbt run
  dbt test
  ```
- **En cas d'echec** : notification email

#### Job 2 : Full refresh hebdomadaire

- **Planification** : chaque dimanche a 02:00 UTC
- **Commandes** :
  ```
  dbt seed --full-refresh
  dbt run --full-refresh
  dbt test
  dbt source freshness
  ```

#### Job 3 : CI/CD sur Pull Request

- **Declenchement** : sur chaque PR vers la branche main
- **Commandes** :
  ```
  dbt build --select state:modified+
  ```
- **Slim CI** : ne construit que les modeles modifies et leurs dependants

### 8.5 - Source freshness (10 min)

La fraicheur des sources verifie que les donnees sont a jour :

```yaml
sources:
  - name: tpch
    loaded_at_field: _loaded_at    # Colonne de timestamp de chargement
    freshness:
      warn_after: {count: 24, period: hour}
      error_after: {count: 48, period: hour}
```

```bash
dbt source freshness
```

> **Note** : les donnees SNOWFLAKE_SAMPLE_DATA n'ont pas de colonne `_loaded_at`. Dans un vrai pipeline (Fivetran, Airbyte), cette colonne est ajoutee automatiquement.

### 8.6 - Exercice final : workflow complet (20 min)

#### Exercice 8A - Cycle complet feature branch -> PR -> merge

1. Creez une nouvelle branche :
   ```bash
   git checkout -b feature/add-monthly-revenue
   ```

2. Creez un nouveau modele `models/marts/agg_monthly_revenue.sql` :
   ```sql
   with orders as (
       select * from {{ ref('fct_orders') }}
   ),

   monthly as (
       select
           date_trunc('month', order_date) as order_month,
           market_segment,
           count(distinct order_key)       as total_orders,
           sum(net_amount)                 as total_revenue,
           avg(net_amount)                 as avg_order_value
       from orders
       group by 1, 2
   )

   select * from monthly
   ```

3. Ajoutez tests et documentation dans `_marts__models.yml`

4. Testez localement :
   ```bash
   dbt build --select agg_monthly_revenue+
   ```

5. Committez et poussez :
   ```bash
   git add .
   git commit -m "feat: add monthly revenue aggregation model"
   git push -u origin feature/add-monthly-revenue
   ```

6. Ouvrez une Pull Request sur GitHub

7. (Dans dbt Cloud) Observez le job CI se declencher automatiquement

8. Mergez la PR et observez le job de production se lancer

---

## Resume des livrables par module

| Module | Livrables | Duree |
|--------|-----------|-------|
| 1. Introduction | Comprehension de dbt et de la stack data | 1h00 |
| 2. Mise en place | Projet dbt connecte a Snowflake, repo GitHub | 1h30 |
| 3. Projet de base | 8 staging + 3 intermediate + 7 marts + tests | 3h00 |
| 4. Tests avances | Tests custom, unit tests, dbt_utils/expectations | 1h30 |
| 5. Modelisation avancee | Seeds, snapshots, incremental, governance | 2h00 |
| 6. Commandes | Maitrise CLI, selecteurs, tags, docs | 1h00 |
| 7. Jinja & Macros | 4 macros, hooks, boucles for | 2h00 |
| 8. Deploiement | dbt Cloud, 3 jobs, CI/CD | 2h00 |

**Total : 14 heures d'instruction + 2 heures tampon/Q&A = 16 heures**

---

## Aide-memoire des commandes dbt

```bash
# Cycle de developpement
dbt debug              # Verifier la connexion
dbt deps               # Installer les packages
dbt seed               # Charger les seeds CSV
dbt run                # Executer les modeles
dbt test               # Executer les tests
dbt build              # Run + test en ordre DAG
dbt compile            # Compiler sans executer
dbt snapshot           # Executer les snapshots
dbt clean              # Nettoyer target/ et dbt_packages/

# Documentation
dbt docs generate      # Generer la doc
dbt docs serve         # Servir la doc en local

# Selecteurs
dbt run --select <model>           # Un modele
dbt run --select <model>+          # Modele + descendants
dbt run --select +<model>          # Ancetres + modele
dbt run --select <folder>          # Tout un dossier
dbt run --select tag:<tag>         # Par tag
dbt run --exclude <model>          # Exclure
dbt run --full-refresh             # Reconstruire les incrementaux

# Operations
dbt run-operation <macro_name>     # Executer une macro
dbt source freshness               # Fraicheur des sources
dbt ls --select <selector>         # Lister les ressources
```
