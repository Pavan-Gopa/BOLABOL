# SmartScribe Localization Guide

Canonical source of truth:
- `en_values.json` — ordered JSON dict of ALL 513 keys → English values, in canonical order.
- `en_keys.txt` — the 513 key names, one per line, canonical order.
- Reference translations already done: `tr_ru.py` (Russian), `tr_es.py` (Spanish). Read them for tone and consistent terminology.

## Output file
Create `tr_XX.py` (XX = language code) in this directory:
```python
T = {}
T["settingsGlossary"] = "..."
T["clearGlossaryTitle"] = "..."
...
```
- Cover EVERY one of the 513 keys, exactly once, ideally in the same order as `en_keys.txt`.
- File must be valid UTF-8 Python. No empty values.

## HARD RULES (enforced by check_tr.py / build_translations.py)
1. Preserve format/interpolation tokens EXACTLY (same set, same count, same order):
   - `%@`, `%d`, `%.2f` (and any `%[.0-9]*[@df]` form present in the EN value).
   - The literal Swift interpolation `\(PromptTemplate.transcriptionPlaceholder)` — copy it verbatim. In Python source write it inside a normal string; a SyntaxWarning about `\(` is harmless and expected.
2. NEVER put an ASCII double-quote `"` inside a value. Use typographic quotes “ ” ‘ ’ « » „ “ as appropriate for the language.
3. Keep these literally (do not translate): SmartScribe, Whisper, WhisperKit, MLX, Core ML, Gemini, OpenAI, Qwen, OpenRouter, Anthropic, Claude, Apple Speech, Markdown, JSON, CSV, API, LLM, HUD, N/A-style codes, model names (Large v3 Full, Large v3 Turbo), URLs, and hotkeys exactly as written (Option+S, Option+1, Option+2, Option+~, ⌥S, Command-C, Shift).
4. "Raw", "Variant 1", "Variant 2" — keep "Raw" as-is; translate the word "Variant" but keep the digit (e.g. ES "Variante 1").
5. Distinguish the two windows:
   - "Floating Translation Window" = the FULL translation panel (source + result).
   - "Quick Translation Window" = the MINIMAL result-only window.
   Use two clearly different native terms and keep them consistent everywhere.

## Terminology glossary (keep consistent across the file)
EN → ES (use as a semantic reference; adapt naturally to your language):
- Settings → Ajustes · General → General · API Providers → Proveedores de API · Hotkey → Atajo · Local Models → Modelos locales · Polishing → Pulido · Prompts → Prompts · Statistics → Estadísticas · Help → Ayuda
- Glossary → Glosario · Transcription → Transcripción · Translation → Traducción · Provider → Proveedor · Model → Modelo · Engine → Motor
- Download → Descargar · Use → Usar · Delete → Eliminar · Reset → Restablecer · Copy → Copiar · Clear → Borrar · Clear All → Borrar todo · Cancel → Cancelar · Close → Cerrar · Save → Guardar · Apply → Aplicar · Retry → Reintentar · Refresh → Actualizar
- Record → Grabar · Stop Recording → Detener grabación · Import Audio → Importar audio · Translate → Traducir · Polish → Pulir
- Microphone → Micrófono · Accessibility → Accesibilidad · Permissions → Permisos · Clipboard → Portapapeles
- Type into Active App → Escribir en la app activa · Copy to Clipboard → Copiar al portapapeles
- Overlay HUD → HUD superpuesto · Theme → Tema · Dark/Light/System → Oscuro/Claro/Sistema · Interface Language → Idioma de la interfaz
- Transcription Language → Idioma de transcripción · Auto detect → Detección automática · Recognition Language → Idioma de reconocimiento
- Polishing Engine → Motor de pulido · Quick Local Cleanup → Limpieza local rápida · Local MLX Model → Modelo MLX local · Polishing Disabled → Pulido desactivado
- Voice Note → Nota de voz · New Note → Nota nueva · Untitled Note → Nota sin título · Notes → Notas
- Idle/Pending/Running/Done/Failed → Inactivo/Pendiente/En ejecución/Hecho/Fallido
- Accuracy/Speed/Quality → Precisión/Velocidad/Calidad
- Onboarding buttons: Next → Siguiente · Back → Atrás · Skip → Omitir · Get Started → Empezar · Grant → Conceder

Tone: native, product-grade, concise. Pick a consistent formality for the language and keep it throughout (e.g. ES uses informal "tú").

## Self-check (DO NOT run build_translations.py — it writes AppText.swift)
From this directory run:
```
python3 check_tr.py XX
```
Iterate until it prints `[XX] OK — 513 keys validated (read-only)`. Fix any MISSING/EXTRA/EMPTY/SPEC/INTERP/ASCII-quote errors it reports.