# DW Organizacional Northwind + Mercearia (Docker) — Trabalho 2

Mesmo DW do Trabalho 1, com duas mudanças:

- `fontes/02_mercearia_movimento.sql`: o movimento da Mercearia é gerado com **perfis de compra** (café da manhã, família com bebê, churrasco, compra do mês, ocasional);
- **DataMart `dm_crm`** (`ddl/03_dm_crm.sql`, `etl/07_dm_crm.sql`): cestas e RFM dos clientes da Mercearia, usado pelo notebook de clusterização e regras de associação.

## Subir tudo

```bash
docker compose up -d        # cria as fontes e roda o ETL (DW, DataMarts, dm_crm e validação)
docker compose logs etl     # log/validação da carga
```

| Serviço | Acesso |
|---|---|
| PostgreSQL | `localhost:5434`, usuário `postgres`, senha `postgres` (bancos `northwind`, `mercearia`, `dw`) |

A porta e o nome do projeto (`bi_trabalho2`) são diferentes dos do Trabalho 1, então os dois ambientes podem coexistir.

## Outros comandos

```bash
docker compose run --rm etl   # nova carga
docker compose down -v        # apaga tudo (volumes inclusive)
```

## Estrutura

```
ddl/01_dw.sql            DDL do DW (schema dw)
ddl/02_datamarts.sql     DDL dos DataMarts do Trabalho 1
ddl/03_dm_crm.sql        DDL do DataMart CRM (Trabalho 2)
etl/                     etapas do ETL (staging, tempo, IPCA, dimensões, fatos, marts, dm_crm, validação)
fontes/                  preparação das bases de origem (inclui o povoamento com perfis)
dados_externos/          IPCA (BCB/SGS 433)
```

## Solução de problemas

**No Windows, o `t2_db` sai com exit 127 e o log traz
`00_init_fontes.sh: cannot execute: required file not found`.**

Com `core.autocrlf=true`, o git converte os `.sh` para CRLF no checkout; o Docker
monta o `\r` no Linux e o shebang vira `#!/bin/bash\r`. O repositório traz um
`.gitattributes` (`*.sh text eol=lf`) para evitar isso — se a cópia local ainda
estiver com CRLF, converta os scripts para LF e recrie o volume:

```bash
docker compose down -v
docker compose up -d
```

O `down -v` é necessário porque o Postgres só executa `/docker-entrypoint-initdb.d`
quando o diretório de dados está vazio.
