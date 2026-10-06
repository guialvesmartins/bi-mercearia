-- =====================================================================
-- ETAPA 3 — DADO EXTERNO: IPCA mensal (BCB/SGS série 433)
-- Arquivo baixado de https://api.bcb.gov.br/dados/serie/bcdata.sgs.433/dados
-- Gera um nº-índice encadeado e o fator para trazer valores a R$ do
-- último mês disponível (valor_real = valor_nominal × fator_atualizacao).
-- =====================================================================
CREATE TEMP TABLE tmp_ipca (mes date, ipca_var_pct numeric(6,2));
\copy tmp_ipca FROM '/dados_externos/ipca_bcb_sgs433.csv' WITH (FORMAT csv, HEADER true, DELIMITER ';')

WITH idx AS (
    SELECT mes, ipca_var_pct,
           100 * exp(sum(ln(1 + ipca_var_pct / 100)) OVER (ORDER BY mes)) AS indice
    FROM tmp_ipca
)
INSERT INTO dw.ext_ipca (mes, ipca_var_pct, indice, fator_atualizacao)
SELECT mes, ipca_var_pct, round(indice, 6),
       round((SELECT indice FROM idx ORDER BY mes DESC LIMIT 1) / indice, 6)
FROM idx
ON CONFLICT (mes) DO UPDATE
   SET ipca_var_pct = EXCLUDED.ipca_var_pct, indice = EXCLUDED.indice,
       fator_atualizacao = EXCLUDED.fator_atualizacao, dt_carga = now();

-- fator do mês da data; meses ainda sem IPCA publicado usam o último disponível
CREATE OR REPLACE FUNCTION etl.fn_fator_ipca(p_data date) RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT fator_atualizacao FROM dw.ext_ipca
                     WHERE mes <= date_trunc('month', p_data) ORDER BY mes DESC LIMIT 1), 1)
$$;

INSERT INTO dw.etl_log (data_carga, etapa, tabela, linhas)
SELECT :'data_carga'::date, 'externo', 'dw.ext_ipca', count(*) FROM dw.ext_ipca;
