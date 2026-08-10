# PDF Tools for Electronics

Kit de extracción de PDFs para datasheets, schematics y reference manuals.

## MCP Server: pdf-mcp (recomendado)

**[pdf-mcp](https://github.com/jztan/pdf-mcp)** v2.1.0 — integrado como MCP server en opencode.

13 herramientas especializadas para PDFs:

| Herramienta | Función |
|---|---|
| `pdf_info` | Metadata, TOC, detección de páginas escaneadas |
| `pdf_search` | Búsqueda híbrida: BM25 (keywords) + semántica |
| `pdf_read_pages` | Leer páginas específicas sin reventar contexto |
| `pdf_read_all` | Leer documento completo |
| `pdf_get_toc` | Tabla de contenidos completa |
| `pdf_render_pages` | Renderizar páginas como imagen PNG |
| `pdf_extract_chart` | Extraer datos (x,y) de gráficos vectoriales |
| `pdf_corpus_warm` | Indexar carpeta de PDFs completa |
| `pdf_corpus_search` | Buscar en todos los PDFs de una carpeta |
| `pdf_corpus_overview` | Resumen por documento de una carpeta |
| `pdf_cache_stats` | Estadísticas de caché SQLite |
| `pdf_cache_clear` | Limpiar caché |
| `server_info` | Capacidades activas (OCR, multi-columna, semántico) |

**Capacidades clave:**
- Búsqueda semántica + keywords combinadas (RRF)
- Extracción de tablas con coordenadas de origen
- Column-aware para PDFs multi-columna
- OCR vía Tesseract para PDFs escaneados
- Detección de texto oculto (anti-injection)
- Caché SQLite persistente entre sesiones
- Sin límite de tamaño — lee solo las páginas necesarias

**Instalado con:** `pip install pdf-mcp[multicolumn]` + `tesseract-ocr`  
**Config:** `C:\Users\laboratorio\.config\opencode\opencode.jsonc` → `pdf-mcp`

## Herramientas CLI (alternativa directa)

| Herramienta | Tipo | Uso principal |
|---|---|---|
| `pdftotext` | CLI (poppler) | Texto con layout preservado (datasheets, manuals) |
| `pdfinfo` | CLI (poppler) | Metadata, número de páginas |
| `pdftoppm` | CLI (poppler) | Convertir páginas a imágenes |
| `pymupdf` (fitz) | Python | Búsqueda, extracción precisa, manipulación |
| `pdfplumber` | Python | Extracción de tablas (pinouts, electrical chars) |
| `pdfminer.six` | Python | Parsing de bajo nivel |

Todas instaladas en WSL. No requieren licencia.

## Scripts del proyecto

### `pdf_extract.py` — Navaja suiza

```bash
# Extraer texto completo con layout (ideal para datasheets)
wsl python3 scripts/pdf_extract.py docs/datasheet.pdf --mode text

# Solo metadata + tabla de contenidos
wsl python3 scripts/pdf_extract.py docs/datasheet.pdf --mode metadata

# Extraer tablas (pinouts, características eléctricas)
wsl python3 scripts/pdf_extract.py docs/datasheet.pdf --mode tables --page 5

# Buscar una palabra clave en todo el PDF
wsl python3 scripts/pdf_extract.py docs/datasheet.pdf --mode search --query "UART"

# Extraer texto de schematic (busca R1, C5, U3, VCC, GND, etc.)
wsl python3 scripts/pdf_extract.py docs/schematic.pdf --mode schem

# Rango de páginas
wsl python3 scripts/pdf_extract.py docs/manual.pdf --mode text --start-page 10 --end-page 25
```

### `pdf_serve.py` — Rápido, para integrar con otros comandos

```bash
# Primeras 100 líneas del PDF
wsl python3 scripts/pdf_serve.py docs/datasheet.pdf --head 100

# Solo páginas 5-8
wsl python3 scripts/pdf_serve.py docs/datasheet.pdf --pages 5-8
```

## Uso directo de poppler (sin Python)

```bash
# Texto con layout (modo más útil para datasheets)
wsl pdftotext -layout docs/datasheet.pdf -

# Solo metadata
wsl pdfinfo docs/datasheet.pdf

# Página específica a imagen PNG
wsl pdftoppm -png -f 1 -l 1 -r 150 docs/schematic.pdf pagina
```

## Nota sobre PDFs de Digilent

Los PDFs de digilent.com (reference manual, schematic) requieren **descarga manual desde navegador** por protección CloudFlare. Son archivos de varios MB — si el archivo pesa ~5 KB es un placeholder HTML, no el PDF real.

URLs para descargar manualmente:
- Schematic: https://digilent.com/reference/_media/nexys-a7/nexys-a7-sch.pdf
- Reference Manual: https://digilent.com/reference/_media/nexys-a7/nexys-a7-rm.pdf
