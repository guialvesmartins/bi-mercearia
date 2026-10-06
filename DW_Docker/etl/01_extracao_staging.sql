-- =====================================================================
-- ETAPA 1 — EXTRAÇÃO / STAGING
-- As fontes são lidas via postgres_fdw: cada banco de origem vira um
-- schema de staging (stg_nw, stg_mc) com tabelas estrangeiras.
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
CREATE SCHEMA IF NOT EXISTS etl;

CREATE SERVER IF NOT EXISTS srv_northwind FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'localhost', port '5432', dbname 'northwind');
CREATE SERVER IF NOT EXISTS srv_mercearia FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'localhost', port '5432', dbname 'mercearia');

CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER SERVER srv_northwind
    OPTIONS (user 'postgres', password 'postgres');
CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER SERVER srv_mercearia
    OPTIONS (user 'postgres', password 'postgres');

DROP SCHEMA IF EXISTS stg_nw CASCADE;
DROP SCHEMA IF EXISTS stg_mc CASCADE;
CREATE SCHEMA stg_nw;
CREATE SCHEMA stg_mc;

IMPORT FOREIGN SCHEMA public FROM SERVER srv_northwind INTO stg_nw;
IMPORT FOREIGN SCHEMA public FROM SERVER srv_mercearia INTO stg_mc;

INSERT INTO dw.etl_log (data_carga, etapa, tabela, linhas)
SELECT :'data_carga'::date, 'staging', 'stg_nw.order_details', count(*) FROM stg_nw.order_details
UNION ALL
SELECT :'data_carga'::date, 'staging', 'stg_mc.itens_vendas', count(*) FROM stg_mc.itens_vendas
UNION ALL
SELECT :'data_carga'::date, 'staging', 'stg_mc.itens_compras', count(*) FROM stg_mc.itens_compras;
