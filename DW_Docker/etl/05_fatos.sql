-- =====================================================================
-- ETAPA 5 — FATOS
-- Recarga completa (as fontes guardam todo o histórico de transações).
-- A chave de produto/cliente é a versão SCD2 VIGENTE NA DATA DO FATO,
-- o que preserva a historicidade mesmo após reprocessamentos.
-- Chaves não encontradas vão para o membro -1 (Não informado).
-- =====================================================================
TRUNCATE dw.fato_vendas, dw.fato_compras RESTART IDENTITY;

-- ---------------------------------------------------------------------
-- 5.1 FATO_VENDAS — Northwind (order_details × orders)
-- ---------------------------------------------------------------------
INSERT INTO dw.fato_vendas (sk_tempo, sk_produto, sk_cliente, sk_funcionario, sk_canal, origem,
                            nr_documento, nr_item, quantidade, preco_unitario, pct_desconto,
                            valor_bruto, valor_desconto, valor_liquido)
SELECT to_char(v.data, 'YYYYMMDD')::int,
       coalesce(p.sk_produto, -1), coalesce(c.sk_cliente, -1), coalesce(f.sk_funcionario, -1), coalesce(cn.sk_canal, -1),
       'NW', v.nr_documento, v.nr_item, v.quantidade, v.preco, v.desconto,
       v.bruto, round(v.bruto * v.desconto, 2), v.bruto - round(v.bruto * v.desconto, 2)
FROM (
    SELECT o.order_date AS data, od.order_id::text AS nr_documento,
           row_number() OVER (PARTITION BY od.order_id ORDER BY od.product_id) AS nr_item,
           od.product_id::text AS id_produto, o.customer_id::text AS id_cliente,
           o.employee_id::text AS id_funcionario, o.ship_via::text AS id_canal,
           od.quantity AS quantidade,
           round(od.unit_price::numeric, 2) AS preco,
           round(od.discount::numeric, 4) AS desconto,
           round(round(od.unit_price::numeric, 2) * od.quantity, 2) AS bruto
    FROM stg_nw.order_details od
    JOIN stg_nw.orders o ON o.order_id = od.order_id
) v
LEFT JOIN dw.dim_produto p      ON p.origem = 'NW' AND p.id_origem = v.id_produto AND v.data BETWEEN p.dt_inicio AND p.dt_fim
LEFT JOIN dw.dim_cliente c      ON c.origem = 'NW' AND c.id_origem = v.id_cliente AND v.data BETWEEN c.dt_inicio AND c.dt_fim
LEFT JOIN dw.dim_funcionario f  ON f.origem = 'NW' AND f.id_origem = v.id_funcionario
LEFT JOIN dw.dim_canal cn       ON cn.origem = 'NW' AND cn.id_origem = v.id_canal;

-- ---------------------------------------------------------------------
-- 5.2 FATO_VENDAS — Mercearia (itens_vendas × vendas); sem desconto e sem vendedor
-- ---------------------------------------------------------------------
INSERT INTO dw.fato_vendas (sk_tempo, sk_produto, sk_cliente, sk_funcionario, sk_canal, origem,
                            nr_documento, nr_item, quantidade, preco_unitario, pct_desconto,
                            valor_bruto, valor_desconto, valor_liquido)
SELECT to_char(v.data, 'YYYYMMDD')::int,
       coalesce(p.sk_produto, -1), coalesce(c.sk_cliente, -1), 0, coalesce(cn.sk_canal, -1),
       'MC', v.nr_documento, v.nr_item, v.quantidade, v.preco, 0,
       v.bruto, 0, v.bruto
FROM (
    SELECT ve.data_venda AS data, iv.id_venda::text AS nr_documento,
           row_number() OVER (PARTITION BY iv.id_venda ORDER BY iv.id_itemvenda) AS nr_item,
           iv.id_produto::text AS id_produto, ve.id_pessoa::text AS id_cliente, ve.tipo_venda::text AS id_canal,
           iv.quantidade,
           round(iv.vlr_unitario::numeric, 2) AS preco,
           round(round(iv.vlr_unitario::numeric, 2) * iv.quantidade, 2) AS bruto
    FROM stg_mc.itens_vendas iv
    JOIN stg_mc.vendas ve ON ve.id_venda = iv.id_venda
) v
LEFT JOIN dw.dim_produto p ON p.origem = 'MC' AND p.id_origem = v.id_produto AND v.data BETWEEN p.dt_inicio AND p.dt_fim
LEFT JOIN dw.dim_cliente c ON c.origem = 'MC' AND c.id_origem = v.id_cliente AND v.data BETWEEN c.dt_inicio AND c.dt_fim
LEFT JOIN dw.dim_canal cn  ON cn.origem = 'MC' AND cn.id_origem = v.id_canal;

-- ---------------------------------------------------------------------
-- 5.3 FATO_COMPRAS — Mercearia (itens_compras × compras)
-- ---------------------------------------------------------------------
INSERT INTO dw.fato_compras (sk_tempo_pedido, sk_tempo_entrada, sk_produto, sk_fornecedor, origem,
                             nr_documento, nr_item, quantidade, custo_unitario, valor_total, prazo_entrega_dias)
SELECT to_char(v.data_pedido, 'YYYYMMDD')::int,
       to_char(v.data_entrada, 'YYYYMMDD')::int,
       coalesce(p.sk_produto, -1), coalesce(fo.sk_fornecedor, -1),
       'MC', v.nr_documento, v.nr_item, v.quantidade, v.custo,
       round(v.custo * v.quantidade, 2),
       v.data_entrada - v.data_pedido
FROM (
    SELECT co.data_pedido, co.data_entrada, ic.id_compra::text AS nr_documento,
           row_number() OVER (PARTITION BY ic.id_compra ORDER BY ic.id_itemcompra) AS nr_item,
           ic.id_produto::text AS id_produto, co.id_pessoa::text AS id_fornecedor,
           ic.quantidade, round(ic.vlr_unitario::numeric, 2) AS custo
    FROM stg_mc.itens_compras ic
    JOIN stg_mc.compras co ON co.id_compra = ic.id_compra
) v
LEFT JOIN dw.dim_produto p     ON p.origem = 'MC' AND p.id_origem = v.id_produto AND v.data_pedido BETWEEN p.dt_inicio AND p.dt_fim
LEFT JOIN dw.dim_fornecedor fo ON fo.origem = 'MC' AND fo.id_origem = v.id_fornecedor;

ANALYZE dw.fato_vendas;
ANALYZE dw.fato_compras;

INSERT INTO dw.etl_log (data_carga, etapa, tabela, linhas)
SELECT :'data_carga'::date, 'fato', 'dw.fato_vendas', count(*) FROM dw.fato_vendas UNION ALL
SELECT :'data_carga'::date, 'fato', 'dw.fato_compras', count(*) FROM dw.fato_compras;
