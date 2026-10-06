-- =====================================================================
-- DDL — DW ORGANIZACIONAL (Northwind + Mercearia)            schema: dw
-- Modelo dimensional (estrela) com duas fatos:
--   fato_vendas  : grão = 1 item de pedido/venda (NW order_details + MC itens_vendas)
--   fato_compras : grão = 1 item de compra       (MC itens_compras)
-- Convenções:
--   sk_*          chave substituta (surrogate) gerada no DW
--   origem        'NW' = Northwind | 'MC' = Mercearia
--   id_origem     chave natural na fonte (rastreabilidade)
--   dt_inicio/dt_fim/versao_atual  -> historicidade (SCD tipo 2)
--   sk = -1       membro "Não informado"; sk = 0 membro "Não se aplica"
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS dw;

-- ---------------------------------------------------------------------
-- DIMENSÃO TEMPO (grão diário) — inclui feriados nacionais (dado externo)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_tempo (
    sk_tempo        integer      PRIMARY KEY,          -- AAAAMMDD
    data            date         NOT NULL UNIQUE,
    ano             smallint     NOT NULL,
    semestre        smallint     NOT NULL,
    trimestre       smallint     NOT NULL,
    mes             smallint     NOT NULL,
    nome_mes        varchar(10)  NOT NULL,
    ano_mes         char(7)      NOT NULL,             -- 'AAAA-MM'
    semana_ano      smallint     NOT NULL,
    dia             smallint     NOT NULL,
    dia_semana      smallint     NOT NULL,             -- 1=segunda ... 7=domingo (ISO)
    nome_dia_semana varchar(10)  NOT NULL,
    fim_de_semana   boolean      NOT NULL,
    feriado         boolean      NOT NULL DEFAULT false,
    nome_feriado    varchar(40),
    dia_util        boolean      NOT NULL
);

-- ---------------------------------------------------------------------
-- DADO EXTERNO: IPCA mensal (Banco Central, SGS série 433)
-- Usado para deflacionar valores monetários (R$ constantes).
-- ---------------------------------------------------------------------
CREATE TABLE dw.ext_ipca (
    mes              date          PRIMARY KEY,        -- 1º dia do mês
    ipca_var_pct     numeric(6,2)  NOT NULL,           -- variação mensal %
    indice           numeric(12,6) NOT NULL,           -- nº-índice encadeado (base 1º mês = 100)
    fator_atualizacao numeric(12,6) NOT NULL,          -- índice do último mês / índice do mês
    fonte            varchar(60)   NOT NULL DEFAULT 'BCB/SGS 433 - IPCA',
    dt_carga         timestamp     NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- MAPEAMENTO DE INTEGRAÇÃO: categoria de cada fonte -> categoria corporativa
-- ---------------------------------------------------------------------
CREATE TABLE dw.map_categoria (
    origem                char(2)      NOT NULL,
    categoria_origem      varchar(60)  NOT NULL,
    categoria_corporativa varchar(40)  NOT NULL,
    PRIMARY KEY (origem, categoria_origem)
);

-- ---------------------------------------------------------------------
-- DIMENSÃO PRODUTO (SCD2: preço, categoria, nome, status)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_produto (
    sk_produto            serial        PRIMARY KEY,
    origem                char(2)       NOT NULL,
    id_origem             varchar(20)   NOT NULL,
    nome_produto          varchar(80)   NOT NULL,
    categoria_origem      varchar(60)   NOT NULL,
    categoria_corporativa varchar(40)   NOT NULL,
    embalagem             varchar(40),
    preco_lista           numeric(12,2),
    descontinuado         boolean       NOT NULL DEFAULT false,
    dt_inicio             date          NOT NULL,
    dt_fim                date          NOT NULL DEFAULT '9999-12-31',
    versao_atual          boolean       NOT NULL DEFAULT true,
    hash_atributos        char(32)      NOT NULL,
    UNIQUE (origem, id_origem, dt_inicio)
);

-- ---------------------------------------------------------------------
-- DIMENSÃO CLIENTE (SCD2) — dados pessoais minimizados/pseudonimizados (LGPD)
--   Não armazena: CPF, nome de PF, data de nascimento, renda exata,
--   telefone e logradouro. Guarda apenas faixas e localização até bairro.
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_cliente (
    sk_cliente        serial        PRIMARY KEY,
    origem            char(2)       NOT NULL,
    id_origem         varchar(20)   NOT NULL,
    cliente_hash      char(64),                        -- SHA-256(salt + CPF/CNPJ) p/ cruzamentos sem expor o documento
    nome_exibicao     varchar(80)   NOT NULL,          -- razão social (PJ) ou pseudônimo (PF)
    tipo_pessoa       varchar(15)   NOT NULL,          -- 'Pessoa Física' / 'Pessoa Jurídica'
    sexo              varchar(15),
    faixa_etaria      varchar(15),
    faixa_renda       varchar(15),
    estado_civil      varchar(15),
    profissao         varchar(30),
    bairro            varchar(60),
    regiao_cidade     varchar(30),
    cidade            varchar(60),
    uf_regiao         varchar(30),
    pais              varchar(30)   NOT NULL,
    dt_inicio         date          NOT NULL,
    dt_fim            date          NOT NULL DEFAULT '9999-12-31',
    versao_atual      boolean       NOT NULL DEFAULT true,
    hash_atributos    char(32)      NOT NULL,
    UNIQUE (origem, id_origem, dt_inicio)
);

-- ---------------------------------------------------------------------
-- DIMENSÃO FORNECEDOR (SCD1)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_fornecedor (
    sk_fornecedor   serial       PRIMARY KEY,
    origem          char(2)      NOT NULL,
    id_origem       varchar(20)  NOT NULL,
    nome_fornecedor varchar(80)  NOT NULL,
    tipo_pessoa     varchar(15)  NOT NULL,
    cidade          varchar(60),
    uf_regiao       varchar(30),
    pais            varchar(30),
    dt_atualizacao  timestamp    NOT NULL DEFAULT now(),
    UNIQUE (origem, id_origem)
);

-- ---------------------------------------------------------------------
-- DIMENSÃO FUNCIONÁRIO / VENDEDOR (SCD1) — só a Northwind registra vendedor
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_funcionario (
    sk_funcionario   serial       PRIMARY KEY,
    origem           char(2)      NOT NULL,
    id_origem        varchar(20)  NOT NULL,
    nome_funcionario varchar(60)  NOT NULL,
    cargo            varchar(40),
    cidade           varchar(30),
    pais             varchar(30),
    dt_contratacao   date,
    dt_atualizacao   timestamp    NOT NULL DEFAULT now(),
    UNIQUE (origem, id_origem)
);

-- ---------------------------------------------------------------------
-- DIMENSÃO CANAL DE VENDA / ENTREGA (SCD1)
--   NW: B2B, meio de entrega = transportadora (shippers)
--   MC: Varejo, meio de entrega = Balcão / Delivery (tipo_venda)
-- ---------------------------------------------------------------------
CREATE TABLE dw.dim_canal (
    sk_canal      serial       PRIMARY KEY,
    origem        char(2)      NOT NULL,
    id_origem     varchar(20)  NOT NULL,
    canal         varchar(20)  NOT NULL,
    meio_entrega  varchar(40)  NOT NULL,
    UNIQUE (origem, id_origem)
);

-- ---------------------------------------------------------------------
-- FATO VENDAS — grão: 1 linha por item de pedido/venda
-- ---------------------------------------------------------------------
CREATE TABLE dw.fato_vendas (
    sk_venda        bigserial     PRIMARY KEY,
    sk_tempo        integer       NOT NULL REFERENCES dw.dim_tempo,
    sk_produto      integer       NOT NULL REFERENCES dw.dim_produto,
    sk_cliente      integer       NOT NULL REFERENCES dw.dim_cliente,
    sk_funcionario  integer       NOT NULL REFERENCES dw.dim_funcionario,
    sk_canal        integer       NOT NULL REFERENCES dw.dim_canal,
    origem          char(2)       NOT NULL,
    nr_documento    varchar(20)   NOT NULL,            -- nº do pedido/venda na fonte (dimensão degenerada)
    nr_item         smallint      NOT NULL,
    quantidade      integer       NOT NULL,
    preco_unitario  numeric(12,2) NOT NULL,
    pct_desconto    numeric(5,4)  NOT NULL DEFAULT 0,
    valor_bruto     numeric(14,2) NOT NULL,
    valor_desconto  numeric(14,2) NOT NULL,
    valor_liquido   numeric(14,2) NOT NULL,
    dt_carga        timestamp     NOT NULL DEFAULT now(),
    UNIQUE (origem, nr_documento, nr_item)
);
CREATE INDEX ix_fv_tempo   ON dw.fato_vendas (sk_tempo);
CREATE INDEX ix_fv_produto ON dw.fato_vendas (sk_produto);
CREATE INDEX ix_fv_cliente ON dw.fato_vendas (sk_cliente);

-- ---------------------------------------------------------------------
-- FATO COMPRAS — grão: 1 linha por item de compra (somente Mercearia)
-- ---------------------------------------------------------------------
CREATE TABLE dw.fato_compras (
    sk_compra            bigserial     PRIMARY KEY,
    sk_tempo_pedido      integer       NOT NULL REFERENCES dw.dim_tempo,
    sk_tempo_entrada     integer       REFERENCES dw.dim_tempo,
    sk_produto           integer       NOT NULL REFERENCES dw.dim_produto,
    sk_fornecedor        integer       NOT NULL REFERENCES dw.dim_fornecedor,
    origem               char(2)       NOT NULL,
    nr_documento         varchar(20)   NOT NULL,
    nr_item              smallint      NOT NULL,
    quantidade           integer       NOT NULL,
    custo_unitario       numeric(12,2) NOT NULL,
    valor_total          numeric(14,2) NOT NULL,
    prazo_entrega_dias   smallint,
    dt_carga             timestamp     NOT NULL DEFAULT now(),
    UNIQUE (origem, nr_documento, nr_item)
);
CREATE INDEX ix_fc_tempo   ON dw.fato_compras (sk_tempo_pedido);
CREATE INDEX ix_fc_produto ON dw.fato_compras (sk_produto);

-- ---------------------------------------------------------------------
-- CONTROLE DE CARGA (auditoria do ETL)
-- ---------------------------------------------------------------------
CREATE TABLE dw.etl_log (
    id          serial     PRIMARY KEY,
    data_carga  date       NOT NULL,
    etapa       varchar(40) NOT NULL,
    tabela      varchar(60),
    linhas      bigint,
    inicio      timestamp  NOT NULL DEFAULT clock_timestamp()
);
