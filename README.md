# bi-mercearia

**Clusterização de clientes + Regras de Associação** — Tópicos 1, Business Intelligence (Trabalho 2).

Segmenta os clientes da Mercearia com **RFM + K-Means** e descobre, dentro de cada segmento, quais produtos são comprados juntos (**Apriori**). Segmentar primeiro, associar depois.

**Por onde começar:** abra o [`mapa_aprendizado.html`](mapa_aprendizado.html) no navegador — um guia interativo, em nove etapas, de todos os conceitos e resultados do trabalho.

| Pasta / arquivo | Conteúdo |
|---|---|
| `mapa_aprendizado.html` | guia interativo do trabalho (abrir no navegador) |
| `apresentacao/` | slides da apresentação (PDF) |
| `relatorio/` | relatório técnico (`.md` e `.pdf`) e figuras |
| `notebook/` | `clusterizacao_regras.ipynb` — código da análise |
| `DW_Docker/` | PostgreSQL + ETL do DW (fontes, DW, DataMarts e o DataMart `dm_crm`) |
| `Scripts BD/` | scripts originais das bases de origem |

## Como executar

```bash
cd DW_Docker
docker compose up -d                 # PostgreSQL (porta 5434) + ETL até o dm_crm
docker compose logs etl              # conferir a validação da carga
cd ..
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cd notebook && ../.venv/bin/jupyter notebook clusterizacao_regras.ipynb
```

Para regerar o PDF do relatório (pandoc + Google Chrome):

```bash
cd relatorio
pandoc RELATORIO_TECNICO.md -s --embed-resources --css estilo.css -o /tmp/relatorio.html
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --no-pdf-header-footer \
  --print-to-pdf=RELATORIO_TECNICO.pdf file:///tmp/relatorio.html
```
