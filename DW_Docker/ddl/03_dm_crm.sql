-- =====================================================================
-- DDL — DATAMART 4: CRM da Mercearia
--   (Clusterização de clientes + Regras de Associação)
--   Construído a partir do schema dw, só com a fonte Mercearia (MC).
--   fato_cesta        : itens de cada cupom       -> transações do Apriori
--   fato_cliente_rfm  : 1 linha por cliente (RFM) -> entrada do K-Means
--   cliente_cluster   : cluster de cada cliente   (gravado pelo notebook)
--   regra_associacao  : regras por cluster        (gravado pelo notebook)
-- LGPD: o cliente aparece só pela SK e pelo pseudônimo do DW.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS dm_crm;

-- cliente de negócio: consolida as versões SCD2 do DW (SK e atributos da versão atual)
CREATE TABLE dm_crm.dim_cliente (
    sk_cliente     integer      PRIMARY KEY,
    id_origem      varchar(20)  NOT NULL UNIQUE,
    nome_exibicao  varchar(80)  NOT NULL,          -- pseudônimo (ex.: Cliente MC-00042)
    bairro         varchar(60),
    cidade         varchar(60)
);

-- produto de negócio: consolida as versões SCD2 do DW (SK e atributos da versão atual)
CREATE TABLE dm_crm.dim_produto (
    sk_produto            integer      PRIMARY KEY,
    id_origem             varchar(20)  NOT NULL UNIQUE,
    nome_produto          varchar(80)  NOT NULL,
    categoria             varchar(60)  NOT NULL,
    categoria_corporativa varchar(40)  NOT NULL
);

-- FATO CESTA — grão: 1 produto em 1 cupom
CREATE TABLE dm_crm.fato_cesta (
    nr_documento   varchar(20)   NOT NULL,
    sk_produto     integer       NOT NULL REFERENCES dm_crm.dim_produto,
    sk_cliente     integer       NOT NULL REFERENCES dm_crm.dim_cliente,
    data           date          NOT NULL,
    quantidade     integer       NOT NULL,
    valor_liquido  numeric(14,2) NOT NULL,
    PRIMARY KEY (nr_documento, sk_produto)
);
CREATE INDEX ix_cesta_cliente ON dm_crm.fato_cesta (sk_cliente);

-- FATO CLIENTE RFM — grão: 1 cliente (foto na data de referência)
CREATE TABLE dm_crm.fato_cliente_rfm (
    sk_cliente       integer       PRIMARY KEY REFERENCES dm_crm.dim_cliente,
    data_referencia  date          NOT NULL,         -- dia seguinte à última venda
    primeira_compra  date          NOT NULL,
    ultima_compra    date          NOT NULL,
    recencia_dias    integer       NOT NULL,         -- R: dias desde a última compra
    frequencia       integer       NOT NULL,         -- F: nº de cupons
    ticket_medio     numeric(12,2) NOT NULL,         -- M: valor médio por cupom
    valor_total      numeric(14,2) NOT NULL
);

-- RESULTADOS (preenchidos pelo notebook; o ETL não apaga)
CREATE TABLE dm_crm.cliente_cluster (
    sk_cliente        integer      PRIMARY KEY,
    cluster           smallint     NOT NULL,
    nome_cluster      varchar(40)  NOT NULL,
    dt_processamento  timestamp    NOT NULL DEFAULT now()
);

CREATE TABLE dm_crm.regra_associacao (
    nome_cluster      varchar(40)   NOT NULL,        -- 'Base inteira' = regras sem segmentar
    antecedente       text          NOT NULL,
    consequente       text          NOT NULL,
    suporte           numeric(6,4)  NOT NULL,
    confianca         numeric(6,4)  NOT NULL,
    lift              numeric(8,3)  NOT NULL,
    dt_processamento  timestamp     NOT NULL DEFAULT now(),
    PRIMARY KEY (nome_cluster, antecedente, consequente)
);
