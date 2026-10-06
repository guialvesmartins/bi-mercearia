#!/bin/bash
# Executado uma única vez pelo entrypoint do Postgres (volume vazio).
# Cria os bancos de origem com os scripts originais da disciplina e
# atualiza o movimento para os últimos 2 anos.
set -euo pipefail

psql() { command psql -v ON_ERROR_STOP=1 -q -U postgres "$@"; }

psql -c "CREATE DATABASE northwind" -c "CREATE DATABASE mercearia" -c "CREATE DATABASE dw"

echo ">> Fonte 1: Northwind"
psql -d northwind -f /scripts_bd/northwind.sql
psql -d northwind -f /fontes/01_northwind_atualiza_datas.sql

echo ">> Fonte 2: Mercearia"
# o DDL original tem quebras de linha CRLF (Windows)
tr -d '\r' < "/scripts_bd/SQL criação DB Mercearia.sql" | psql -d mercearia
psql -d mercearia -f /scripts_bd/seed_mercearia.sql
psql -d mercearia -f /fontes/02_mercearia_movimento.sql

echo ">> Fontes prontas"
