-- =====================================================================
-- DDL — DATAMARTS (derivados do DW Organizacional)
--   dm_comercial      : Vendas & Faturamento      (NW + MC)
--   dm_suprimentos    : Compras & Fornecedores    (MC)
--   dm_rentabilidade  : Margem por produto        (MC)
-- Cada mart é um schema autocontido (fato + dimensões próprias), carregado
-- SOMENTE a partir do schema dw (nunca das fontes).
-- =====================================================================

-- #####################################################################
-- DATAMART 1 — COMERCIAL (Vendas & Faturamento)
-- Fato agregada: dia × produto × localidade × canal × vendedor
-- (o cliente individual é removido: minimização de dados / LGPD)
-- #####################################################################
CREATE SCHEMA IF NOT EXISTS dm_comercial;

CREATE TABLE dm_comercial.dim_tempo (
    sk_tempo        integer     PRIMARY KEY,
    data            date        NOT NULL,
    ano             smallint    NOT NULL,
    trimestre       smallint    NOT NULL,
    mes             smallint    NOT NULL,
    nome_mes        varchar(10) NOT NULL,
    ano_mes         char(7)     NOT NULL,
    dia_semana      smallint    NOT NULL,
    nome_dia_semana varchar(10) NOT NULL,
    fim_de_semana   boolean     NOT NULL,
    feriado         boolean     NOT NULL,
    nome_feriado    varchar(40),
    dia_util        boolean     NOT NULL
);

CREATE TABLE dm_comercial.dim_produto (
    sk_produto            integer      PRIMARY KEY,     -- mesma SK do DW (versão SCD2)
    origem                char(2)      NOT NULL,
    nome_produto          varchar(80)  NOT NULL,
    categoria_origem      varchar(60)  NOT NULL,
    categoria_corporativa varchar(40)  NOT NULL,
    preco_lista           numeric(12,2),
    versao_atual          boolean      NOT NULL
);

CREATE TABLE dm_comercial.dim_localidade (
    sk_localidade serial      PRIMARY KEY,
    pais          varchar(30) NOT NULL,
    uf_regiao     varchar(30) NOT NULL,
    cidade        varchar(60) NOT NULL,
    UNIQUE (pais, uf_regiao, cidade)
);

CREATE TABLE dm_comercial.dim_canal (
    sk_canal     integer     PRIMARY KEY,
    origem       char(2)     NOT NULL,
    canal        varchar(20) NOT NULL,
    meio_entrega varchar(40) NOT NULL
);

CREATE TABLE dm_comercial.dim_vendedor (
    sk_funcionario   integer     PRIMARY KEY,
    nome_funcionario varchar(60) NOT NULL,
    cargo            varchar(40),
    pais             varchar(30)
);

CREATE TABLE dm_comercial.fato_vendas_diaria (
    sk_tempo            integer       NOT NULL REFERENCES dm_comercial.dim_tempo,
    sk_produto          integer       NOT NULL REFERENCES dm_comercial.dim_produto,
    sk_localidade       integer       NOT NULL REFERENCES dm_comercial.dim_localidade,
    sk_canal            integer       NOT NULL REFERENCES dm_comercial.dim_canal,
    sk_funcionario      integer       NOT NULL REFERENCES dm_comercial.dim_vendedor,
    origem              char(2)       NOT NULL,
    qtd_pedidos         integer       NOT NULL,
    qtd_clientes        integer       NOT NULL,
    quantidade          integer       NOT NULL,
    valor_bruto         numeric(14,2) NOT NULL,
    valor_desconto      numeric(14,2) NOT NULL,
    valor_liquido       numeric(14,2) NOT NULL,
    valor_liquido_real  numeric(14,2) NOT NULL,    -- deflacionado pelo IPCA (R$ do último mês)
    PRIMARY KEY (sk_tempo, sk_produto, sk_localidade, sk_canal, sk_funcionario)
);


-- #####################################################################
-- DATAMART 2 — SUPRIMENTOS (Compras & Fornecedores)
-- Fato agregada: mês × produto × fornecedor
-- #####################################################################
CREATE SCHEMA IF NOT EXISTS dm_suprimentos;

CREATE TABLE dm_suprimentos.dim_mes (
    sk_mes        integer      PRIMARY KEY,          -- AAAAMM
    ano           smallint     NOT NULL,
    semestre      smallint     NOT NULL,
    trimestre     smallint     NOT NULL,
    mes           smallint     NOT NULL,
    nome_mes      varchar(10)  NOT NULL,
    ano_mes       char(7)      NOT NULL,
    dias_uteis    smallint     NOT NULL,
    ipca_var_pct  numeric(6,2)                        -- dado externo
);

CREATE TABLE dm_suprimentos.dim_produto (
    sk_produto            integer      PRIMARY KEY,
    nome_produto          varchar(80)  NOT NULL,
    categoria_corporativa varchar(40)  NOT NULL,
    preco_lista           numeric(12,2),
    versao_atual          boolean      NOT NULL
);

CREATE TABLE dm_suprimentos.dim_fornecedor (
    sk_fornecedor   integer     PRIMARY KEY,
    nome_fornecedor varchar(80) NOT NULL,
    tipo_pessoa     varchar(15) NOT NULL,
    cidade          varchar(60),
    uf_regiao       varchar(30)
);

CREATE TABLE dm_suprimentos.fato_compras_mensal (
    sk_mes              integer       NOT NULL REFERENCES dm_suprimentos.dim_mes,
    sk_produto          integer       NOT NULL REFERENCES dm_suprimentos.dim_produto,
    sk_fornecedor       integer       NOT NULL REFERENCES dm_suprimentos.dim_fornecedor,
    qtd_pedidos         integer       NOT NULL,
    quantidade          integer       NOT NULL,
    valor_total         numeric(14,2) NOT NULL,
    custo_medio_unit    numeric(12,4) NOT NULL,
    custo_min_unit      numeric(12,2) NOT NULL,
    custo_max_unit      numeric(12,2) NOT NULL,
    prazo_medio_dias    numeric(6,2),
    prazo_max_dias      smallint,
    PRIMARY KEY (sk_mes, sk_produto, sk_fornecedor)
);


-- #####################################################################
-- DATAMART 3 — RENTABILIDADE (Margem por produto)
-- Fato consolidada: mês × produto (receita de venda × custo médio de compra)
-- Escopo: Mercearia — única fonte com os dois lados (venda e compra).
-- #####################################################################
CREATE SCHEMA IF NOT EXISTS dm_rentabilidade;

CREATE TABLE dm_rentabilidade.dim_mes (
    sk_mes            integer      PRIMARY KEY,      -- AAAAMM
    ano               smallint     NOT NULL,
    trimestre         smallint     NOT NULL,
    mes               smallint     NOT NULL,
    nome_mes          varchar(10)  NOT NULL,
    ano_mes           char(7)      NOT NULL,
    ipca_var_pct      numeric(6,2),
    fator_atualizacao numeric(12,6)
);

CREATE TABLE dm_rentabilidade.dim_produto (
    sk_produto_mart       integer      PRIMARY KEY,  -- produto de negócio (todas as versões SCD2)
    id_origem             varchar(20)  NOT NULL,
    nome_produto          varchar(80)  NOT NULL,
    categoria_corporativa varchar(40)  NOT NULL,
    preco_lista_atual     numeric(12,2)
);

CREATE TABLE dm_rentabilidade.fato_margem_mensal (
    sk_mes              integer       NOT NULL REFERENCES dm_rentabilidade.dim_mes,
    sk_produto_mart     integer       NOT NULL REFERENCES dm_rentabilidade.dim_produto,
    quantidade_vendida  integer       NOT NULL,
    receita_liquida     numeric(14,2) NOT NULL,
    preco_medio_venda   numeric(12,4) NOT NULL,
    custo_medio_unit    numeric(12,4) NOT NULL,     -- custo médio ponderado acumulado até o mês
    cmv                 numeric(14,2) NOT NULL,     -- custo da mercadoria vendida
    margem_bruta        numeric(14,2) NOT NULL,
    margem_pct          numeric(7,4),
    receita_real        numeric(14,2) NOT NULL,     -- deflacionada (IPCA)
    margem_real         numeric(14,2) NOT NULL,
    PRIMARY KEY (sk_mes, sk_produto_mart)
);
