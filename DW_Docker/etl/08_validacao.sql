-- =====================================================================
-- ETAPA 8 — VALIDAÇÃO (reconciliação fonte × DW × DataMarts)
-- Aborta o ETL se algum total não bater.
-- =====================================================================
\echo '--- Reconciliação ---'
CREATE TEMP TABLE chk AS
SELECT 'Itens de venda NW'   AS verificacao, (SELECT count(*) FROM stg_nw.order_details)::numeric AS fonte,
       (SELECT count(*) FROM dw.fato_vendas WHERE origem = 'NW')::numeric AS destino
UNION ALL SELECT 'Itens de venda MC', (SELECT count(*) FROM stg_mc.itens_vendas),
       (SELECT count(*) FROM dw.fato_vendas WHERE origem = 'MC')
UNION ALL SELECT 'Itens de compra MC', (SELECT count(*) FROM stg_mc.itens_compras),
       (SELECT count(*) FROM dw.fato_compras)
UNION ALL SELECT 'Receita MC (R$)', (SELECT round(sum(round(vlr_unitario::numeric, 2) * quantidade), 2) FROM stg_mc.itens_vendas),
       (SELECT sum(valor_liquido) FROM dw.fato_vendas WHERE origem = 'MC')
UNION ALL SELECT 'Receita DW = DM Comercial (R$)', (SELECT sum(valor_liquido) FROM dw.fato_vendas),
       (SELECT sum(valor_liquido) FROM dm_comercial.fato_vendas_diaria)
UNION ALL SELECT 'Compras DW = DM Suprimentos (R$)', (SELECT sum(valor_total) FROM dw.fato_compras),
       (SELECT sum(valor_total) FROM dm_suprimentos.fato_compras_mensal)
UNION ALL SELECT 'Receita MC DW = DM Rentabilidade (R$)', (SELECT sum(valor_liquido) FROM dw.fato_vendas WHERE origem = 'MC'),
       (SELECT sum(receita_liquida) FROM dm_rentabilidade.fato_margem_mensal)
UNION ALL SELECT 'Receita MC DW = DM CRM (R$)', (SELECT sum(valor_liquido) FROM dw.fato_vendas WHERE origem = 'MC'),
       (SELECT sum(valor_liquido) FROM dm_crm.fato_cesta)
UNION ALL SELECT 'Cupons MC DW = Frequência DM CRM', (SELECT count(DISTINCT nr_documento) FROM dw.fato_vendas WHERE origem = 'MC'),
       (SELECT sum(frequencia) FROM dm_crm.fato_cliente_rfm)
UNION ALL SELECT 'Fatos com membro "Não informado"', 0,
       (SELECT count(*) FROM dw.fato_vendas WHERE -1 IN (sk_produto, sk_cliente, sk_funcionario, sk_canal))
     + (SELECT count(*) FROM dw.fato_compras WHERE -1 IN (sk_produto, sk_fornecedor));

SELECT verificacao, fonte, destino, CASE WHEN fonte = destino THEN 'OK' ELSE 'ERRO' END AS status FROM chk;

\echo '--- Log desta carga ---'
SELECT etapa, tabela, linhas FROM dw.etl_log WHERE data_carga = :'data_carga'
  AND inicio > now() - interval '1 hour' ORDER BY id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM chk WHERE fonte <> destino) THEN
        RAISE EXCEPTION 'Validação falhou: totais divergentes entre fonte e DW/DataMarts';
    END IF;
END $$;
