-- =====================================================================
-- ETAPA 6 — CARGA DOS DATAMARTS (fonte: somente o schema dw)
-- =====================================================================

-- #####################################################################
-- DM 1 — COMERCIAL
-- #####################################################################
TRUNCATE dm_comercial.fato_vendas_diaria, dm_comercial.dim_tempo, dm_comercial.dim_produto,
         dm_comercial.dim_localidade, dm_comercial.dim_canal, dm_comercial.dim_vendedor RESTART IDENTITY;

INSERT INTO dm_comercial.dim_tempo
SELECT sk_tempo, data, ano, trimestre, mes, nome_mes, ano_mes, dia_semana, nome_dia_semana,
       fim_de_semana, feriado, nome_feriado, dia_util
FROM dw.dim_tempo;

INSERT INTO dm_comercial.dim_produto
SELECT sk_produto, origem, nome_produto, categoria_origem, categoria_corporativa, preco_lista, versao_atual
FROM dw.dim_produto;

INSERT INTO dm_comercial.dim_localidade (pais, uf_regiao, cidade)
SELECT DISTINCT pais, coalesce(uf_regiao, '-'), coalesce(cidade, '-') FROM dw.dim_cliente;

INSERT INTO dm_comercial.dim_canal
SELECT sk_canal, origem, canal, meio_entrega FROM dw.dim_canal;

INSERT INTO dm_comercial.dim_vendedor
SELECT sk_funcionario, nome_funcionario, cargo, pais FROM dw.dim_funcionario;

INSERT INTO dm_comercial.fato_vendas_diaria
SELECT f.sk_tempo, f.sk_produto, l.sk_localidade, f.sk_canal, f.sk_funcionario, f.origem,
       count(DISTINCT f.nr_documento),
       count(DISTINCT c.id_origem),
       sum(f.quantidade),
       sum(f.valor_bruto),
       sum(f.valor_desconto),
       sum(f.valor_liquido),
       round(sum(f.valor_liquido) * etl.fn_fator_ipca(t.data), 2)
FROM dw.fato_vendas f
JOIN dw.dim_tempo t   ON t.sk_tempo = f.sk_tempo
JOIN dw.dim_cliente c ON c.sk_cliente = f.sk_cliente
JOIN dm_comercial.dim_localidade l
  ON l.pais = c.pais AND l.uf_regiao = coalesce(c.uf_regiao, '-') AND l.cidade = coalesce(c.cidade, '-')
GROUP BY f.sk_tempo, t.data, f.sk_produto, l.sk_localidade, f.sk_canal, f.sk_funcionario, f.origem;

-- #####################################################################
-- DM 2 — SUPRIMENTOS
-- #####################################################################
TRUNCATE dm_suprimentos.fato_compras_mensal, dm_suprimentos.dim_mes, dm_suprimentos.dim_produto,
         dm_suprimentos.dim_fornecedor;

INSERT INTO dm_suprimentos.dim_mes
SELECT t.ano * 100 + t.mes, t.ano, t.semestre, t.trimestre, t.mes, t.nome_mes, t.ano_mes,
       count(*) FILTER (WHERE t.dia_util), i.ipca_var_pct
FROM dw.dim_tempo t
LEFT JOIN dw.ext_ipca i ON i.mes = date_trunc('month', t.data)
GROUP BY t.ano, t.semestre, t.trimestre, t.mes, t.nome_mes, t.ano_mes, i.ipca_var_pct;

INSERT INTO dm_suprimentos.dim_produto
SELECT sk_produto, nome_produto, categoria_corporativa, preco_lista, versao_atual
FROM dw.dim_produto WHERE origem IN ('MC', '--');

INSERT INTO dm_suprimentos.dim_fornecedor
SELECT sk_fornecedor, nome_fornecedor, tipo_pessoa, cidade, uf_regiao FROM dw.dim_fornecedor;

INSERT INTO dm_suprimentos.fato_compras_mensal
SELECT t.ano * 100 + t.mes, f.sk_produto, f.sk_fornecedor,
       count(DISTINCT f.nr_documento),
       sum(f.quantidade),
       sum(f.valor_total),
       round(sum(f.valor_total) / nullif(sum(f.quantidade), 0), 4),
       min(f.custo_unitario),
       max(f.custo_unitario),
       round(avg(f.prazo_entrega_dias), 2),
       max(f.prazo_entrega_dias)
FROM dw.fato_compras f
JOIN dw.dim_tempo t ON t.sk_tempo = f.sk_tempo_pedido
GROUP BY t.ano, t.mes, f.sk_produto, f.sk_fornecedor;

-- #####################################################################
-- DM 3 — RENTABILIDADE (Mercearia)
-- #####################################################################
TRUNCATE dm_rentabilidade.fato_margem_mensal, dm_rentabilidade.dim_mes, dm_rentabilidade.dim_produto;

INSERT INTO dm_rentabilidade.dim_mes
SELECT DISTINCT t.ano * 100 + t.mes, t.ano, t.trimestre, t.mes, t.nome_mes, t.ano_mes,
       i.ipca_var_pct, etl.fn_fator_ipca(date_trunc('month', t.data)::date)
FROM dw.dim_tempo t
LEFT JOIN dw.ext_ipca i ON i.mes = date_trunc('month', t.data);

-- um registro por produto de negócio (consolida as versões SCD2, atributos da versão atual)
INSERT INTO dm_rentabilidade.dim_produto
SELECT id_origem::int, id_origem, nome_produto, categoria_corporativa, preco_lista
FROM dw.dim_produto
WHERE origem = 'MC' AND versao_atual;

WITH vendas AS (
    SELECT t.ano * 100 + t.mes AS sk_mes, date_trunc('month', t.data)::date AS mes, p.id_origem::int AS sk_produto_mart,
           sum(f.quantidade) AS qtd, sum(f.valor_liquido) AS receita
    FROM dw.fato_vendas f
    JOIN dw.dim_tempo t   ON t.sk_tempo = f.sk_tempo
    JOIN dw.dim_produto p ON p.sk_produto = f.sk_produto
    WHERE f.origem = 'MC'
    GROUP BY 1, 2, 3
), custo AS (      -- custo médio ponderado de todas as compras até o fim do mês
    SELECT v.*,
           (SELECT sum(fc.valor_total) / nullif(sum(fc.quantidade), 0)
            FROM dw.fato_compras fc
            JOIN dw.dim_tempo tc   ON tc.sk_tempo = fc.sk_tempo_pedido
            JOIN dw.dim_produto pc ON pc.sk_produto = fc.sk_produto
            WHERE pc.id_origem::int = v.sk_produto_mart AND tc.data < v.mes + interval '1 month') AS custo_medio
    FROM vendas v
)
INSERT INTO dm_rentabilidade.fato_margem_mensal
SELECT sk_mes, sk_produto_mart, qtd, receita,
       round(receita / qtd, 4),
       round(coalesce(custo_medio, 0), 4),
       round(qtd * coalesce(custo_medio, 0), 2),
       receita - round(qtd * coalesce(custo_medio, 0), 2),
       round((receita - qtd * coalesce(custo_medio, 0)) / nullif(receita, 0), 4),
       round(receita * etl.fn_fator_ipca(mes), 2),
       round((receita - round(qtd * coalesce(custo_medio, 0), 2)) * etl.fn_fator_ipca(mes), 2)
FROM custo;

INSERT INTO dw.etl_log (data_carga, etapa, tabela, linhas)
SELECT :'data_carga'::date, 'datamart', 'dm_comercial.fato_vendas_diaria', count(*) FROM dm_comercial.fato_vendas_diaria UNION ALL
SELECT :'data_carga'::date, 'datamart', 'dm_suprimentos.fato_compras_mensal', count(*) FROM dm_suprimentos.fato_compras_mensal UNION ALL
SELECT :'data_carga'::date, 'datamart', 'dm_rentabilidade.fato_margem_mensal', count(*) FROM dm_rentabilidade.fato_margem_mensal;
