-- =====================================================================
-- Mercearia: gera movimento sintético (vendas e compras) para os últimos
-- 2 anos (01/10/2024 a 28/09/2026), a partir dos cadastros do seed.
--   * +120 clientes pessoa física (ID 31..150) e +6 fornecedores PJ (151..156)
--   * TRABALHO 2: cada cliente recebe um PERFIL DE COMPRA, que define
--     frequência de visitas e "missões" (cestas típicas), por exemplo
--     pão + presunto, picanha + cerveja, arroz + feijão + óleo
--   * preços e custos com reajuste mensal (~0,45% a.m.)
--   * compras semanais por fornecedor, dimensionadas pela demanda da semana
-- O perfil NÃO é carregado no DW: a clusterização precisa redescobri-lo.
-- Ele fica só na tabela gabarito_perfil (usada para validar os clusters).
-- Determinístico (setseed): toda execução gera os mesmos dados.
-- =====================================================================
BEGIN;

SELECT setseed(0.42);

-- ---------------------------------------------------------------------
-- 1) Parâmetros por produto (preço/custo base vêm do seed)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE prm_produto AS
SELECT p.id_produto,
       p.valor_venda::numeric                              AS preco_base,
       ic.vlr_unitario::numeric                            AS custo_base,
       (1 + floor(random() * 10))::int                     AS peso_demanda,
       CASE WHEN p.id_produto IN (3, 4, 5, 21) THEN 30     -- perecíveis: Mercado Central
            ELSE 151 + ((p.id_produto - 1) % 6) END        AS id_fornecedor
FROM produtos p
JOIN itens_compras ic ON ic.id_produto = p.id_produto;

-- sorteio ponderado de itens avulsos: cada produto aparece "peso" vezes
CREATE TEMP TABLE urna_produto AS
SELECT row_number() OVER () AS pos, id_produto
FROM prm_produto, generate_series(1, peso_demanda);

-- fator de reajuste mensal a partir de out/2024
CREATE FUNCTION pg_temp.fator(d date) RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT 1 + 0.0045 * ((extract(year FROM d) - 2024) * 12 + extract(month FROM d) - 10)::numeric
$$;

-- ---------------------------------------------------------------------
-- 2) Limpa o movimento de exemplo do seed
-- ---------------------------------------------------------------------
TRUNCATE itens_vendas, vendas, itens_compras, compras;

-- ---------------------------------------------------------------------
-- 3) Novas pessoas: 120 clientes PF + 6 fornecedores PJ
-- ---------------------------------------------------------------------
INSERT INTO pessoas (id_pessoa, id_profissao, tipo_pessoa, nome, cpf_cnpj, sexo, renda, estado_civil, data_nascimento)
SELECT id,
       1 + floor(random() * 29)::int,
       1,
       n.nome || ' ' || s.sobrenome,
       lpad(floor(random() * 1000)::text, 3, '0') || '.' || lpad(floor(random() * 1000)::text, 3, '0') || '.' ||
       lpad(floor(random() * 1000)::text, 3, '0') || '-' || lpad(floor(random() * 100)::text, 2, '0'),
       n.sexo,
       round((1500 + random() * random() * 18000)::numeric, 2),
       (ARRAY['Solteiro','Casado','Casado','Divorciado','Viuvo'])[1 + floor(random() * 5)::int],
       DATE '1950-01-01' + floor(random() * 365 * 55)::int
FROM generate_series(31, 150) AS id
CROSS JOIN LATERAL (
    SELECT * FROM (VALUES ('Adriana','F'),('Beatriz','F'),('Cristina','F'),('Daniela','F'),('Fernanda','F'),
                          ('Helena','F'),('Juliana','F'),('Larissa','F'),('Patricia','F'),('Renata','F'),
                          ('Andre','M'),('Carlos','M'),('Eduardo','M'),('Fabio','M'),('Gustavo','M'),
                          ('Igor','M'),('Marcelo','M'),('Otavio','M'),('Rodrigo','M'),('Sergio','M')) v(nome, sexo)
    WHERE id > 0 ORDER BY random() LIMIT 1) n
CROSS JOIN LATERAL (
    SELECT * FROM (VALUES ('Silva'),('Santos'),('Oliveira'),('Souza'),('Costa'),('Carvalho'),('Araujo'),
                          ('Ribeiro'),('Martins'),('Barbosa'),('Moura'),('Campos')) v(sobrenome)
    WHERE id > 0 ORDER BY random() LIMIT 1) s;

INSERT INTO pessoas (id_pessoa, id_profissao, tipo_pessoa, nome, cpf_cnpj, sexo, renda, estado_civil, data_nascimento) VALUES
(151, 1, 2, 'Distribuidora Bebidas Brasil LTDA',  '22.222.222/0001-51', NULL, NULL, NULL, '2001-03-10'),
(152, 1, 2, 'Laticinios Serra Azul SA',            '22.222.222/0001-52', NULL, NULL, NULL, '1998-06-22'),
(153, 1, 2, 'Atacadao Alimentos Goias LTDA',       '22.222.222/0001-53', NULL, NULL, NULL, '2005-01-15'),
(154, 1, 2, 'Higiene & Limpeza Distrib. LTDA',     '22.222.222/0001-54', NULL, NULL, NULL, '2010-09-01'),
(155, 1, 2, 'Frigorifico Centro-Oeste SA',         '22.222.222/0001-55', NULL, NULL, NULL, '1995-11-30'),
(156, 1, 2, 'Comercial Doces e Snacks LTDA',       '22.222.222/0001-56', NULL, NULL, NULL, '2012-04-18');

INSERT INTO enderecos (id_endereco, id_pessoa, id_logradouro, tipo_endereco, complemento, preferencial)
SELECT id_pessoa, id_pessoa, 1 + floor(random() * 30)::int,
       CASE WHEN tipo_pessoa = 2 THEN 2 ELSE 1 END, NULL, B'1'
FROM pessoas WHERE id_pessoa > 30;

INSERT INTO telefones (id_telefone, id_pessoa, ddd, telefone, tipo, preferencial, status)
SELECT id_pessoa, id_pessoa, 62, '9' || lpad(floor(random() * 100000000)::text, 8, '0'), 1, B'1', 'A'
FROM pessoas WHERE id_pessoa > 30;

-- ---------------------------------------------------------------------
-- 4) Perfis de compra e missões
--    visitas_semana : frequência média de idas à loja
--    missão         : cesta típica; em cada visita, cada missão do perfil
--                     ocorre com prob_missao e cada produto dela entra
--                     com prob_item (quantidade de 1 a qtd_max)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE perfil (perfil text PRIMARY KEY, visitas_semana numeric, pct_delivery numeric, so_fim_de_semana boolean);
INSERT INTO perfil VALUES
('Café da manhã',    3.50, 0.10, false),
('Família com bebê', 1.50, 0.40, false),
('Churrasco',        0.75, 0.20, true),
('Compra do mês',    0.23, 0.60, false),
('Ocasional',        0.25, 0.20, false);

CREATE TEMP TABLE missao (perfil text, missao text, prob_missao numeric, id_produto int, prob_item numeric, qtd_max int);
INSERT INTO missao VALUES
-- Café da manhã
('Café da manhã',    'Pão com frios',  0.55,  3, 0.95,  1),   -- Pão Francês
('Café da manhã',    'Pão com frios',  0.55, 20, 0.60,  1),   -- Presunto
('Café da manhã',    'Pão com frios',  0.55,  2, 0.50,  2),   -- Leite
('Café da manhã',    'Café com leite', 0.40, 17, 0.90,  1),   -- Café
('Café da manhã',    'Café com leite', 0.40,  2, 0.80,  3),   -- Leite
('Café da manhã',    'Café com leite', 0.40, 11, 0.50,  2),   -- Biscoito
('Café da manhã',    'Fitness',        0.25, 13, 0.85,  1),   -- Aveia
('Café da manhã',    'Fitness',        0.25,  5, 0.85,  2),   -- Banana
-- Família com bebê
('Família com bebê', 'Bebê',           0.50, 24, 0.90,  3),   -- Fralda
('Família com bebê', 'Bebê',           0.50,  7, 0.70,  3),   -- Sabonete
('Família com bebê', 'Bebê',           0.50,  2, 0.60,  4),   -- Leite
('Família com bebê', 'Lanche',         0.45, 11, 0.85,  3),   -- Biscoito
('Família com bebê', 'Lanche',         0.45, 28, 0.75,  2),   -- Suco
('Família com bebê', 'Lanche',         0.45, 10, 0.60,  2),   -- Chocolate
('Família com bebê', 'Jantar rápido',  0.25,  9, 0.80,  2),   -- Pizza
('Família com bebê', 'Jantar rápido',  0.25,  1, 0.70,  1),   -- Refrigerante
('Família com bebê', 'Jantar rápido',  0.25, 29, 0.40,  1),   -- Sorvete
-- Churrasco (só sexta, sábado e domingo)
('Churrasco',        'Churrasco',      0.60,  4, 0.95,  3),   -- Picanha
('Churrasco',        'Churrasco',      0.60, 18, 0.85, 12),   -- Cerveja
('Churrasco',        'Churrasco',      0.60, 16, 0.60,  1),   -- Sal
('Churrasco',        'Churrasco',      0.60, 30, 0.40,  1),   -- Fósforo
('Churrasco',        'Happy hour',     0.40, 18, 0.90, 12),   -- Cerveja
('Churrasco',        'Happy hour',     0.40, 19, 0.85,  2),   -- Batata Chips
('Churrasco',        'Peixe',          0.20, 21, 0.90,  2),   -- Tilápia
('Churrasco',        'Peixe',          0.20,  1, 0.60,  1),   -- Refrigerante
-- Compra do mês
('Compra do mês',    'Cesta básica',   0.90,  8, 0.95,  3),   -- Arroz
('Compra do mês',    'Cesta básica',   0.90, 25, 0.90,  5),   -- Feijão
('Compra do mês',    'Cesta básica',   0.90, 27, 0.85,  5),   -- Óleo
('Compra do mês',    'Cesta básica',   0.90, 16, 0.40,  1),   -- Sal
('Compra do mês',    'Massas',         0.70, 12, 0.90,  6),   -- Macarrão
('Compra do mês',    'Massas',         0.70, 15, 0.90,  6),   -- Molho de Tomate
('Compra do mês',    'Massas',         0.70, 14, 0.50,  3),   -- Milho Verde
('Compra do mês',    'Limpeza',        0.70,  6, 0.90,  6),   -- Detergente
('Compra do mês',    'Limpeza',        0.70,  7, 0.70,  6),   -- Sabonete
('Compra do mês',    'Limpeza',        0.70, 23, 0.30,  1),   -- Vassoura
('Compra do mês',    'Despensa',       0.60, 17, 0.85,  3),   -- Café
('Compra do mês',    'Despensa',       0.60, 26, 0.60,  3),   -- Farinha de Trigo
('Compra do mês',    'Pet',            0.35, 22, 0.90,  3),   -- Ração
-- Ocasional (passa na loja por conveniência)
('Ocasional',        'Conveniência',   1.00,  1, 0.50,  1),   -- Refrigerante
('Ocasional',        'Conveniência',   1.00, 10, 0.40,  2),   -- Chocolate
('Ocasional',        'Conveniência',   1.00, 19, 0.40,  1),   -- Batata Chips
('Ocasional',        'Conveniência',   1.00, 18, 0.30,  6),   -- Cerveja
('Ocasional',        'Conveniência',   1.00, 29, 0.25,  1),   -- Sorvete
('Ocasional',        'Conveniência',   1.00, 11, 0.30,  2);   -- Biscoito

-- clientes PF divididos igualmente entre os perfis; "intensidade" varia a frequência de cada um
CREATE TEMP TABLE cliente_perfil AS
SELECT id_pessoa,
       (ARRAY['Café da manhã','Família com bebê','Churrasco','Compra do mês','Ocasional'])
           [1 + (row_number() OVER (ORDER BY random()) - 1) % 5] AS perfil,
       0.8 + random() * 0.4  AS intensidade,
       DATE '2024-10-01'     AS inicio,
       DATE '2026-09-28'     AS fim
FROM pessoas WHERE tipo_pessoa = 1;

-- ocasionais: compram por 5 a 10 meses e depois somem (última compra há 6 a 15 meses)
UPDATE cliente_perfil
   SET fim = DATE '2026-09-28' - (180 + floor(random() * 270)::int)
 WHERE perfil = 'Ocasional';
UPDATE cliente_perfil
   SET inicio = greatest(DATE '2024-10-01', fim - (150 + floor(random() * 150)::int))
 WHERE perfil = 'Ocasional';

-- gabarito: fica só na fonte (não vai para o DW); serve para validar os clusters
CREATE TABLE gabarito_perfil AS SELECT id_pessoa, perfil FROM cliente_perfil;

-- ---------------------------------------------------------------------
-- 5) Vendas (cabeçalho): cada dia do cliente é uma visita com probabilidade
--    visitas_semana/7 (churrasco: visitas_semana/3 de sexta a domingo);
--    dezembro tem 30% a mais de movimento
-- ---------------------------------------------------------------------
CREATE TEMP TABLE visita AS
SELECT row_number() OVER (ORDER BY dia, id_pessoa) AS id_venda, id_pessoa, perfil, dia,
       CASE WHEN sorteio_canal < pct_delivery THEN 2 ELSE 1 END AS tipo_venda
FROM (
    SELECT cp.id_pessoa, cp.perfil, d.dia, p.pct_delivery,
           cp.intensidade * CASE WHEN extract(month FROM d.dia) = 12 THEN 1.3 ELSE 1 END
             * CASE WHEN NOT p.so_fim_de_semana THEN p.visitas_semana / 7
                    WHEN extract(isodow FROM d.dia) >= 5 THEN p.visitas_semana / 3
                    ELSE 0 END AS prob_visita,
           random() AS sorteio, random() AS sorteio_canal
    FROM cliente_perfil cp
    JOIN perfil p USING (perfil)
    CROSS JOIN LATERAL (SELECT g::date AS dia FROM generate_series(cp.inicio, cp.fim, INTERVAL '1 day') g) d
) x
WHERE sorteio < prob_visita;

INSERT INTO vendas (id_venda, id_pessoa, data_venda, data_faturamento, tipo_venda)
SELECT id_venda, id_pessoa, dia, dia, tipo_venda FROM visita;

-- ---------------------------------------------------------------------
-- 6) Itens de venda = produtos das missões sorteadas + itens avulsos
--    (avulsos: 0 a 2 por visita; 1 a 2 quando não houve missão)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE visita_missao AS
SELECT id_venda, perfil, missao
FROM (SELECT v.id_venda, v.perfil, m.missao, m.prob_missao, random() AS sorteio
      FROM visita v
      JOIN (SELECT DISTINCT perfil, missao, prob_missao FROM missao) m USING (perfil)) x
WHERE sorteio < prob_missao;
CREATE INDEX ON visita_missao (id_venda);
ANALYZE visita_missao;

CREATE TEMP TABLE itens_tmp AS
SELECT DISTINCT ON (id_venda, id_produto) id_venda, id_produto, data_venda, quantidade
FROM (
    -- produtos das missões
    SELECT id_venda, id_produto, data_venda, quantidade
    FROM (SELECT vm.id_venda, m.id_produto, v.dia AS data_venda, m.prob_item,
                 (1 + floor(random() * m.qtd_max))::int AS quantidade, random() AS sorteio
          FROM visita_missao vm
          JOIN visita v USING (id_venda)
          JOIN missao m ON m.perfil = vm.perfil AND m.missao = vm.missao) x
    WHERE sorteio < prob_item
    UNION ALL
    -- itens avulsos, sorteados na urna ponderada
    SELECT x.id_venda, u.id_produto, x.dia, x.quantidade
    FROM (SELECT v.id_venda, v.dia,
                 1 + floor(random() * (SELECT count(*) FROM urna_produto))::int AS pos,
                 (1 + floor(random() * random() * 4))::int                     AS quantidade
          FROM visita v
          CROSS JOIN LATERAL generate_series(1,
                CASE WHEN NOT EXISTS (SELECT 1 FROM visita_missao vm WHERE vm.id_venda = v.id_venda)
                          THEN 1 + floor(random() * 2)::int
                     ELSE floor(random() * random() * 3)::int END + 0 * v.id_venda) g) x
    JOIN urna_produto u USING (pos)
) i
ORDER BY id_venda, id_produto, quantidade DESC;

INSERT INTO itens_vendas (id_itemvenda, id_venda, id_produto, quantidade, vlr_unitario)
SELECT row_number() OVER (ORDER BY i.id_venda, i.id_produto),
       i.id_venda, i.id_produto, i.quantidade,
       round(p.preco_base * pg_temp.fator(i.data_venda), 2)
FROM itens_tmp i JOIN prm_produto p USING (id_produto);

-- visitas em que nenhum produto foi sorteado não viram venda
DELETE FROM vendas v WHERE NOT EXISTS (SELECT 1 FROM itens_vendas i WHERE i.id_venda = v.id_venda);

-- ---------------------------------------------------------------------
-- 7) Compras semanais (segunda-feira) por fornecedor, cobrindo a demanda
-- ---------------------------------------------------------------------
CREATE TEMP TABLE demanda_semana AS
SELECT date_trunc('week', i.data_venda)::date AS semana, p.id_fornecedor, i.id_produto,
       sum(i.quantidade) AS qtd
FROM itens_tmp i JOIN prm_produto p USING (id_produto)
GROUP BY 1, 2, 3;

CREATE TEMP TABLE compras_tmp AS
SELECT row_number() OVER (ORDER BY semana, id_fornecedor) AS id_compra, semana, id_fornecedor
FROM (SELECT DISTINCT semana, id_fornecedor FROM demanda_semana) x;

INSERT INTO compras (id_compra, data_pedido, data_entrada, id_pessoa)
SELECT id_compra,
       greatest(semana, DATE '2024-10-01'),
       greatest(semana, DATE '2024-10-01') + 1 + floor(random() * random() * 7)::int,
       id_fornecedor
FROM compras_tmp;

INSERT INTO itens_compras (id_itemcompra, id_compra, id_produto, quantidade, vlr_unitario)
SELECT row_number() OVER (ORDER BY c.id_compra, d.id_produto),
       c.id_compra, d.id_produto,
       greatest(5, ceil(d.qtd * (1.0 + random() * 0.25)))::int,
       round(p.custo_base * pg_temp.fator(c.semana) * (0.97 + random() * 0.06)::numeric, 2)
FROM compras_tmp c
JOIN demanda_semana d ON d.semana = c.semana AND d.id_fornecedor = c.id_fornecedor
JOIN prm_produto p ON p.id_produto = d.id_produto;

-- ---------------------------------------------------------------------
-- 8) Cadastro de produtos reflete o preço vigente (último reajuste)
-- ---------------------------------------------------------------------
UPDATE produtos p
   SET valor_venda = round(m.preco_base * pg_temp.fator(DATE '2026-09-28'), 2)
  FROM prm_produto m
 WHERE m.id_produto = p.id_produto;

COMMIT;
