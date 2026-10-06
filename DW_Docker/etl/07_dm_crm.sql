-- =====================================================================
-- ETAPA 7 — CARGA DO DATAMART CRM (fonte: somente o schema dw, origem MC)
-- Cliente e produto são consolidados na versão atual (SCD2): o cliente
-- que mudou de faixa de renda continua sendo o mesmo cliente no RFM.
-- =====================================================================
TRUNCATE dm_crm.fato_cesta, dm_crm.fato_cliente_rfm, dm_crm.dim_cliente, dm_crm.dim_produto;

INSERT INTO dm_crm.dim_cliente
SELECT sk_cliente, id_origem, nome_exibicao, bairro, cidade
FROM dw.dim_cliente
WHERE versao_atual AND origem = 'MC';

INSERT INTO dm_crm.dim_produto
SELECT sk_produto, id_origem, nome_produto, categoria_origem, categoria_corporativa
FROM dw.dim_produto
WHERE versao_atual AND origem = 'MC';

-- itens de venda -> cesta (qualquer versão SCD2 aponta para a SK atual)
INSERT INTO dm_crm.fato_cesta
SELECT f.nr_documento, pa.sk_produto, ca.sk_cliente, t.data,
       sum(f.quantidade), sum(f.valor_liquido)
FROM dw.fato_vendas f
JOIN dw.dim_tempo t         ON t.sk_tempo = f.sk_tempo
JOIN dw.dim_produto p       ON p.sk_produto = f.sk_produto
JOIN dm_crm.dim_produto pa  ON pa.id_origem = p.id_origem
JOIN dw.dim_cliente c       ON c.sk_cliente = f.sk_cliente
JOIN dm_crm.dim_cliente ca  ON ca.id_origem = c.id_origem
WHERE f.origem = 'MC'
GROUP BY f.nr_documento, pa.sk_produto, ca.sk_cliente, t.data;

-- RFM: a data de referência é o dia seguinte à última venda
INSERT INTO dm_crm.fato_cliente_rfm
WITH cupom AS (
    SELECT nr_documento, sk_cliente, data, sum(valor_liquido) AS valor
    FROM dm_crm.fato_cesta
    GROUP BY nr_documento, sk_cliente, data
), ref AS (
    SELECT max(data) + 1 AS data_referencia FROM cupom
)
SELECT c.sk_cliente, r.data_referencia,
       min(c.data), max(c.data),
       r.data_referencia - max(c.data),
       count(*),
       round(avg(c.valor), 2),
       sum(c.valor)
FROM cupom c
CROSS JOIN ref r
GROUP BY c.sk_cliente, r.data_referencia;

ANALYZE dm_crm.fato_cesta;

INSERT INTO dw.etl_log (data_carga, etapa, tabela, linhas)
SELECT :'data_carga'::date, 'datamart', 'dm_crm.fato_cesta', count(*) FROM dm_crm.fato_cesta UNION ALL
SELECT :'data_carga'::date, 'datamart', 'dm_crm.fato_cliente_rfm', count(*) FROM dm_crm.fato_cliente_rfm;
