-- =====================================================================
-- Northwind: traz o movimento (1996-07 a 1998-05) para os últimos 2 anos.
-- Desloca todas as datas de pedidos pelo mesmo nº de semanas, de modo que
-- o último pedido caia em set/2026. Deslocar em semanas inteiras preserva
-- o dia da semana de cada pedido. Valores passam a ser tratados como R$.
-- =====================================================================
DO $$
DECLARE
    v_dias integer;
BEGIN
    SELECT ((DATE '2026-09-26' - max(order_date)) / 7) * 7 INTO v_dias FROM orders;

    UPDATE orders
       SET order_date    = order_date    + v_dias,
           required_date = required_date + v_dias,
           shipped_date  = shipped_date  + v_dias;

    -- contratação acompanha o deslocamento (continua anterior aos pedidos)
    UPDATE employees SET hire_date = hire_date + v_dias;

    RAISE NOTICE 'Northwind: datas deslocadas em % dias', v_dias;
END $$;
