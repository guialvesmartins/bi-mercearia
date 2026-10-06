-- =====================================================================
-- ETAPA 4 — DIMENSÕES (integração + historicidade + LGPD)
--   Produto e Cliente: SCD tipo 2 (nova versão quando um atributo muda)
--   Fornecedor, Funcionário, Canal: SCD tipo 1 (sobrescreve)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 4.0 Membros especiais (-1 = Não informado, 0 = Não se aplica)
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_produto (sk_produto, origem, id_origem, nome_produto, categoria_origem, categoria_corporativa, dt_inicio, hash_atributos)
VALUES (-1, '--', '-1', 'Não informado', 'Não informado', 'Não informado', '1900-01-01', '-') ON CONFLICT DO NOTHING;
INSERT INTO dw.dim_cliente (sk_cliente, origem, id_origem, nome_exibicao, tipo_pessoa, pais, dt_inicio, hash_atributos)
VALUES (-1, '--', '-1', 'Não informado', 'Não informado', 'Não informado', '1900-01-01', '-') ON CONFLICT DO NOTHING;
INSERT INTO dw.dim_fornecedor (sk_fornecedor, origem, id_origem, nome_fornecedor, tipo_pessoa)
VALUES (-1, '--', '-1', 'Não informado', 'Não informado') ON CONFLICT DO NOTHING;
INSERT INTO dw.dim_funcionario (sk_funcionario, origem, id_origem, nome_funcionario, cargo, pais)
VALUES (-1, '--', '-1', 'Não informado', 'Não informado', NULL),
       ( 0, 'MC', 'N/A', 'Não se aplica (varejo)', 'Não se aplica', 'Brasil') ON CONFLICT DO NOTHING;
INSERT INTO dw.dim_canal (sk_canal, origem, id_origem, canal, meio_entrega)
VALUES (-1, '--', '-1', 'Não informado', 'Não informado') ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- 4.1 Mapeamento de categorias das duas fontes -> categoria corporativa
-- ---------------------------------------------------------------------
INSERT INTO dw.map_categoria (origem, categoria_origem, categoria_corporativa) VALUES
('NW','Beverages','Bebidas'), ('NW','Condiments','Molhos e Temperos'), ('NW','Confections','Doces e Snacks'),
('NW','Dairy Products','Laticínios e Frios'), ('NW','Grains/Cereals','Grãos, Massas e Cereais'),
('NW','Meat/Poultry','Carnes'), ('NW','Produce','Hortifruti'), ('NW','Seafood','Pescados'),
('MC','Bebidas','Bebidas'), ('MC','Cafe e Cha','Bebidas'), ('MC','Bebidas Alcoolicas','Bebidas'), ('MC','Sucos','Bebidas'),
('MC','Laticinios','Laticínios e Frios'), ('MC','Frios','Laticínios e Frios'),
('MC','Padaria','Padaria'), ('MC','Acougue','Carnes'), ('MC','Peixaria','Pescados'), ('MC','Hortifruti','Hortifruti'),
('MC','Limpeza','Limpeza e Higiene'), ('MC','Higiene','Limpeza e Higiene'), ('MC','Bebe','Limpeza e Higiene'),
('MC','Mercearia','Mercearia Seca'), ('MC','Enlatados','Mercearia Seca'), ('MC','Oleos','Mercearia Seca'),
('MC','Massas','Grãos, Massas e Cereais'), ('MC','Cereais','Grãos, Massas e Cereais'),
('MC','Graos','Grãos, Massas e Cereais'), ('MC','Farinaceos','Grãos, Massas e Cereais'),
('MC','Molhos','Molhos e Temperos'), ('MC','Temperos','Molhos e Temperos'),
('MC','Doces','Doces e Snacks'), ('MC','Biscoitos','Doces e Snacks'), ('MC','Snacks','Doces e Snacks'),
('MC','Congelados','Congelados'), ('MC','Sorvetes','Congelados'),
('MC','Pet','Outros'), ('MC','Bazar','Outros'), ('MC','Diversos','Outros')
ON CONFLICT (origem, categoria_origem) DO UPDATE SET categoria_corporativa = EXCLUDED.categoria_corporativa;

-- ---------------------------------------------------------------------
-- 4.2 DIM_PRODUTO (SCD2)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_produto AS
SELECT 'NW'::char(2) AS origem, p.product_id::text AS id_origem, p.product_name AS nome_produto,
       c.category_name AS categoria_origem, coalesce(m.categoria_corporativa, 'Outros') AS categoria_corporativa,
       p.quantity_per_unit AS embalagem, round(p.unit_price::numeric, 2) AS preco_lista,
       p.discontinued = 1 AS descontinuado
FROM stg_nw.products p
LEFT JOIN stg_nw.categories c ON c.category_id = p.category_id
LEFT JOIN dw.map_categoria m ON m.origem = 'NW' AND m.categoria_origem = c.category_name
UNION ALL
SELECT 'MC', p.id_produto::text, p.produto, c.nome_categoria, coalesce(m.categoria_corporativa, 'Outros'),
       NULL, round(p.valor_venda::numeric, 2), false
FROM stg_mc.produtos p
LEFT JOIN stg_mc.categorias c ON c.id_categoria = p.id_categoria
LEFT JOIN dw.map_categoria m ON m.origem = 'MC' AND m.categoria_origem = c.nome_categoria;

ALTER TABLE tmp_produto ADD COLUMN hash_atributos char(32);
UPDATE tmp_produto SET hash_atributos = md5(concat_ws('|', nome_produto, categoria_origem, categoria_corporativa,
                                                      embalagem, preco_lista, descontinuado));

-- fecha a versão vigente dos produtos que mudaram
UPDATE dw.dim_produto d
   SET dt_fim = :'data_carga'::date - 1, versao_atual = false
  FROM tmp_produto t
 WHERE d.origem = t.origem AND d.id_origem = t.id_origem
   AND d.versao_atual AND d.hash_atributos <> t.hash_atributos;

-- insere novos produtos (vigência desde sempre) e novas versões (vigência a partir da carga)
INSERT INTO dw.dim_produto (origem, id_origem, nome_produto, categoria_origem, categoria_corporativa,
                            embalagem, preco_lista, descontinuado, dt_inicio, hash_atributos)
SELECT t.origem, t.id_origem, t.nome_produto, t.categoria_origem, t.categoria_corporativa,
       t.embalagem, t.preco_lista, t.descontinuado,
       CASE WHEN EXISTS (SELECT 1 FROM dw.dim_produto x WHERE x.origem = t.origem AND x.id_origem = t.id_origem)
            THEN :'data_carga'::date ELSE DATE '1900-01-01' END,
       t.hash_atributos
FROM tmp_produto t
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_produto d
                  WHERE d.origem = t.origem AND d.id_origem = t.id_origem AND d.versao_atual);

-- ---------------------------------------------------------------------
-- 4.3 DIM_CLIENTE (SCD2 + LGPD)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE tmp_endereco_mc AS          -- pessoa -> bairro/cidade/UF (endereço preferencial)
SELECT DISTINCT ON (e.id_pessoa)
       e.id_pessoa, b.nome_bairro, b.regiaocidade, ci.nome_cidade, u.sigla
FROM stg_mc.enderecos e
JOIN stg_mc.logradouros l ON l.id_logradouro = e.id_logradouro
JOIN stg_mc.bairros b     ON b.id_bairro = l.id_bairro
JOIN stg_mc.cidades ci    ON ci.id_cidade = b.id_cidade
JOIN stg_mc.uf u          ON u.id_uf = ci.id_uf
ORDER BY e.id_pessoa, e.preferencial DESC, e.id_endereco;

CREATE TEMP TABLE tmp_cliente AS
SELECT 'NW'::char(2) AS origem, c.customer_id::text AS id_origem,
       NULL::char(64) AS cliente_hash,
       c.company_name AS nome_exibicao,                       -- PJ: razão social não é dado pessoal
       'Pessoa Jurídica' AS tipo_pessoa,
       NULL AS sexo, NULL AS faixa_etaria, NULL AS faixa_renda, NULL AS estado_civil, NULL AS profissao,
       NULL AS bairro, NULL AS regiao_cidade, c.city AS cidade, coalesce(c.region, '-') AS uf_regiao, c.country AS pais
FROM stg_nw.customers c                                       -- contact_name/phone/address NÃO são carregados
UNION ALL
SELECT 'MC', p.id_pessoa::text,
       encode(sha256(convert_to(:'lgpd_salt' || regexp_replace(p.cpf_cnpj, '\D', '', 'g'), 'UTF8')), 'hex'),
       CASE WHEN p.tipo_pessoa = 2 THEN p.nome ELSE 'Cliente MC-' || lpad(p.id_pessoa::text, 5, '0') END,
       CASE WHEN p.tipo_pessoa = 2 THEN 'Pessoa Jurídica' ELSE 'Pessoa Física' END,
       CASE WHEN p.tipo_pessoa = 2 THEN NULL WHEN p.sexo = 'F' THEN 'Feminino' WHEN p.sexo = 'M' THEN 'Masculino' END,
       CASE WHEN p.tipo_pessoa = 2 OR p.data_nascimento IS NULL THEN NULL
            ELSE CASE WHEN age(:'data_carga'::date, p.data_nascimento) < interval '25 years' THEN '18 a 24'
                      WHEN age(:'data_carga'::date, p.data_nascimento) < interval '35 years' THEN '25 a 34'
                      WHEN age(:'data_carga'::date, p.data_nascimento) < interval '45 years' THEN '35 a 44'
                      WHEN age(:'data_carga'::date, p.data_nascimento) < interval '60 years' THEN '45 a 59'
                      ELSE '60+' END END,
       CASE WHEN p.tipo_pessoa = 2 OR p.renda IS NULL THEN NULL
            WHEN p.renda < 2000 THEN 'Até 2 mil' WHEN p.renda < 5000 THEN '2 a 5 mil'
            WHEN p.renda < 10000 THEN '5 a 10 mil' ELSE 'Acima de 10 mil' END,
       CASE WHEN p.tipo_pessoa = 2 THEN NULL ELSE p.estado_civil END,
       CASE WHEN p.tipo_pessoa = 2 THEN NULL ELSE pr.nome_profissao END,
       en.nome_bairro, en.regiaocidade, en.nome_cidade, en.sigla, 'Brasil'
FROM stg_mc.pessoas p
LEFT JOIN stg_mc.profissoes pr ON pr.id_profissao = p.id_profissao
LEFT JOIN tmp_endereco_mc en   ON en.id_pessoa = p.id_pessoa
WHERE p.tipo_pessoa = 1 OR p.id_pessoa IN (SELECT id_pessoa FROM stg_mc.vendas);

ALTER TABLE tmp_cliente ADD COLUMN hash_atributos char(32);
UPDATE tmp_cliente SET hash_atributos = md5(concat_ws('|', nome_exibicao, tipo_pessoa, sexo, faixa_etaria, faixa_renda,
                                                      estado_civil, profissao, bairro, cidade, uf_regiao, pais));

UPDATE dw.dim_cliente d
   SET dt_fim = :'data_carga'::date - 1, versao_atual = false
  FROM tmp_cliente t
 WHERE d.origem = t.origem AND d.id_origem = t.id_origem
   AND d.versao_atual AND d.hash_atributos <> t.hash_atributos;

INSERT INTO dw.dim_cliente (origem, id_origem, cliente_hash, nome_exibicao, tipo_pessoa, sexo, faixa_etaria,
                            faixa_renda, estado_civil, profissao, bairro, regiao_cidade, cidade, uf_regiao, pais,
                            dt_inicio, hash_atributos)
SELECT t.origem, t.id_origem, t.cliente_hash, t.nome_exibicao, t.tipo_pessoa, t.sexo, t.faixa_etaria,
       t.faixa_renda, t.estado_civil, t.profissao, t.bairro, t.regiao_cidade, t.cidade, t.uf_regiao, t.pais,
       CASE WHEN EXISTS (SELECT 1 FROM dw.dim_cliente x WHERE x.origem = t.origem AND x.id_origem = t.id_origem)
            THEN :'data_carga'::date ELSE DATE '1900-01-01' END,
       t.hash_atributos
FROM tmp_cliente t
WHERE NOT EXISTS (SELECT 1 FROM dw.dim_cliente d
                  WHERE d.origem = t.origem AND d.id_origem = t.id_origem AND d.versao_atual);

-- ---------------------------------------------------------------------
-- 4.4 DIM_FORNECEDOR (SCD1)
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_fornecedor (origem, id_origem, nome_fornecedor, tipo_pessoa, cidade, uf_regiao, pais)
SELECT 'NW', supplier_id::text, company_name, 'Pessoa Jurídica', city, coalesce(region, '-'), country
FROM stg_nw.suppliers
UNION ALL
SELECT 'MC', p.id_pessoa::text,
       CASE WHEN p.tipo_pessoa = 2 THEN p.nome ELSE 'Fornecedor MC-' || lpad(p.id_pessoa::text, 5, '0') END,
       CASE WHEN p.tipo_pessoa = 2 THEN 'Pessoa Jurídica' ELSE 'Pessoa Física' END,
       en.nome_cidade, en.sigla, 'Brasil'
FROM stg_mc.pessoas p
LEFT JOIN tmp_endereco_mc en ON en.id_pessoa = p.id_pessoa
WHERE p.id_pessoa IN (SELECT id_pessoa FROM stg_mc.compras)
ON CONFLICT (origem, id_origem) DO UPDATE
   SET nome_fornecedor = EXCLUDED.nome_fornecedor, tipo_pessoa = EXCLUDED.tipo_pessoa, cidade = EXCLUDED.cidade,
       uf_regiao = EXCLUDED.uf_regiao, pais = EXCLUDED.pais, dt_atualizacao = now();

-- ---------------------------------------------------------------------
-- 4.5 DIM_FUNCIONARIO (SCD1) — sem data de nascimento, endereço e telefone
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_funcionario (origem, id_origem, nome_funcionario, cargo, cidade, pais, dt_contratacao)
SELECT 'NW', employee_id::text, first_name || ' ' || last_name, title, city, country, hire_date
FROM stg_nw.employees
ON CONFLICT (origem, id_origem) DO UPDATE
   SET nome_funcionario = EXCLUDED.nome_funcionario, cargo = EXCLUDED.cargo, cidade = EXCLUDED.cidade,
       pais = EXCLUDED.pais, dt_contratacao = EXCLUDED.dt_contratacao, dt_atualizacao = now();

-- ---------------------------------------------------------------------
-- 4.6 DIM_CANAL (SCD1)
-- ---------------------------------------------------------------------
INSERT INTO dw.dim_canal (origem, id_origem, canal, meio_entrega)
SELECT 'NW', shipper_id::text, 'B2B', company_name FROM stg_nw.shippers
UNION ALL
SELECT 'MC', v.id, 'Varejo', v.meio FROM (VALUES ('1', 'Balcão'), ('2', 'Delivery')) v(id, meio)
ON CONFLICT (origem, id_origem) DO UPDATE
   SET canal = EXCLUDED.canal, meio_entrega = EXCLUDED.meio_entrega;

INSERT INTO dw.etl_log (data_carga, etapa, tabela, linhas)
SELECT :'data_carga'::date, 'dimensao', 'dw.dim_produto', count(*) FROM dw.dim_produto UNION ALL
SELECT :'data_carga'::date, 'dimensao', 'dw.dim_cliente', count(*) FROM dw.dim_cliente UNION ALL
SELECT :'data_carga'::date, 'dimensao', 'dw.dim_fornecedor', count(*) FROM dw.dim_fornecedor UNION ALL
SELECT :'data_carga'::date, 'dimensao', 'dw.dim_funcionario', count(*) FROM dw.dim_funcionario UNION ALL
SELECT :'data_carga'::date, 'dimensao', 'dw.dim_canal', count(*) FROM dw.dim_canal;
