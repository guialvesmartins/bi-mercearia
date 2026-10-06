#!/bin/bash
# Orquestrador do ETL: cria as estruturas (1ª execução) e roda as etapas em ordem.
# Reexecutar é seguro: dimensões são incrementais (SCD), fatos e marts são recarregados.
#   DATA_CARGA=AAAA-MM-DD  simula a data da carga (usado na demonstração de historicidade)
set -euo pipefail

DATA_CARGA="${DATA_CARGA:-$(date +%F)}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1 -v "data_carga=${DATA_CARGA}" -v "lgpd_salt=${LGPD_SALT}")

until pg_isready -q; do sleep 2; done

if [ "$(psql -X -tAc "select count(*) from information_schema.schemata where schema_name = 'dw'")" = "0" ]; then
    echo ">> [DDL] criando DW e DataMarts"
    "${PSQL[@]}" -f /ddl/01_dw.sql
    "${PSQL[@]}" -f /ddl/02_datamarts.sql
    "${PSQL[@]}" -f /ddl/03_dm_crm.sql
fi

for etapa in /etl/[0-9][0-9]_*.sql; do
    echo ">> [ETL ${DATA_CARGA}] $(basename "$etapa")"
    "${PSQL[@]}" -f "$etapa"
done

echo ">> ETL concluído"
