-- =====================================================================
-- ETAPA 2 — DIMENSÃO TEMPO + FERIADOS NACIONAIS (dado externo)
-- Feriados: Lei 662/1949, Lei 6.802/1980, Lei 14.759/2023 (Consciência Negra)
-- e datas móveis calculadas a partir da Páscoa (algoritmo de Meeus).
-- =====================================================================
CREATE OR REPLACE FUNCTION etl.fn_pascoa(p_ano int) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE a int; b int; c int; d int; e int; f int; g int; h int; i int; k int; l int; m int; mes int; dia int;
BEGIN
    a := p_ano % 19; b := p_ano / 100; c := p_ano % 100; d := b / 4; e := b % 4;
    f := (b + 8) / 25; g := (b - f + 1) / 3; h := (19 * a + b - d - g + 15) % 30;
    i := c / 4; k := c % 4; l := (32 + 2 * e + 2 * i - h - k) % 7;
    m := (a + 11 * h + 22 * l) / 451;
    mes := (h + l - 7 * m + 114) / 31; dia := ((h + l - 7 * m + 114) % 31) + 1;
    RETURN make_date(p_ano, mes, dia);
END $$;

CREATE OR REPLACE FUNCTION etl.fn_feriado(p_data date) RETURNS varchar LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE to_char(p_data, 'MM-DD')
             WHEN '01-01' THEN 'Confraternização Universal'
             WHEN '04-21' THEN 'Tiradentes'
             WHEN '05-01' THEN 'Dia do Trabalho'
             WHEN '09-07' THEN 'Independência do Brasil'
             WHEN '10-12' THEN 'Nossa Senhora Aparecida'
             WHEN '11-02' THEN 'Finados'
             WHEN '11-15' THEN 'Proclamação da República'
             WHEN '11-20' THEN 'Consciência Negra'
             WHEN '12-25' THEN 'Natal'
           END
$$;

WITH limites AS (
    SELECT date_trunc('year', least(
               (SELECT min(order_date) FROM stg_nw.orders),
               (SELECT min(data_venda) FROM stg_mc.vendas),
               (SELECT min(data_pedido) FROM stg_mc.compras)))::date                 AS ini,
           (date_trunc('year', greatest(:'data_carga'::date,
               (SELECT max(data_entrada) FROM stg_mc.compras))) + interval '1 year - 1 day')::date AS fim
), dias AS (
    SELECT d::date AS data, etl.fn_pascoa(extract(year FROM d)::int) AS pascoa
    FROM limites, generate_series(ini, fim, interval '1 day') d
), feriados AS (
    SELECT data,
           coalesce(etl.fn_feriado(data),
                    CASE data - pascoa
                        WHEN -47 THEN 'Carnaval'
                        WHEN  -2 THEN 'Sexta-feira Santa'
                        WHEN  60 THEN 'Corpus Christi'
                    END) AS nome_feriado
    FROM dias
)
INSERT INTO dw.dim_tempo
SELECT to_char(data, 'YYYYMMDD')::int,
       data,
       extract(year FROM data),
       CASE WHEN extract(month FROM data) <= 6 THEN 1 ELSE 2 END,
       extract(quarter FROM data),
       extract(month FROM data),
       (ARRAY['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho',
              'Agosto','Setembro','Outubro','Novembro','Dezembro'])[extract(month FROM data)],
       to_char(data, 'YYYY-MM'),
       extract(week FROM data),
       extract(day FROM data),
       extract(isodow FROM data),
       (ARRAY['Segunda','Terça','Quarta','Quinta','Sexta','Sábado','Domingo'])[extract(isodow FROM data)],
       extract(isodow FROM data) IN (6, 7),
       nome_feriado IS NOT NULL,
       nome_feriado,
       extract(isodow FROM data) NOT IN (6, 7) AND nome_feriado IS NULL
FROM feriados
ON CONFLICT (sk_tempo) DO UPDATE
   SET feriado = EXCLUDED.feriado, nome_feriado = EXCLUDED.nome_feriado, dia_util = EXCLUDED.dia_util;

INSERT INTO dw.etl_log (data_carga, etapa, tabela, linhas)
SELECT :'data_carga'::date, 'dimensao', 'dw.dim_tempo', count(*) FROM dw.dim_tempo;
