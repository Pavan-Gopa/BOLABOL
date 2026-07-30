# SmartScribe Code Review System

Автоматизированная система код-ревью для проекта NativeSmartScribe.

## Быстрый старт

```bash
# Полный прогон (сканирование + генерация + все проверки)
.review/run_review.sh

# Только сканирование функций
.review/run_review.sh --scan-only

# Поиск новых функций
.review/run_review.sh --new

# Прогон существующих скриптов
.review/run_review.sh --run-only

# Ревью конкретного файла
.review/run_review.sh --file Sources/NativeSmartScribe/Services/AudioRecorder.swift

# Последний отчёт
.review/run_review.sh --summary
```

## Что проверяется (10 категорий)

| # | Проверка | Что ищет |
|---|----------|----------|
| 1 | `check_naming.sh` | Нарушения конвенций именования |
| 2 | `check_complexity.sh` | Длинные функции, много параметров, вложенность |
| 3 | `check_force_unwrap.sh` | `!`, `try!`, `as!` |
| 4 | `check_error_handling.sh` | Пустые catch, необработанные ошибки |
| 5 | `check_documentation.sh` | Отсутствие документации для public API |
| 6 | `check_access_control.sh` | Неправильные модификаторы доступа |
| 7 | `check_async_patterns.sh` | Проблемы с async/await, Task |
| 8 | `check_memory_safety.sh` | Утечки памяти, retain cycles |
| 9 | `check_swift6_concurrency.sh` | Sendable, actor isolation, data races |
| 10 | `check_todo_fixme.sh` | TODO/FIXME/HACK, закомментированный код |

## Per-Function скрипты

В директории `per_function/` находится **897 скриптов** — по одному на каждую функцию.
Каждый скрипт запускает все 10 проверок для конкретной функции.

```bash
# Запустить проверку одной функции
.review/per_function/0042_NativeSmartScribe_App_AppDelegate_showMainWindow.sh
```

## Для новых ревьюеров

1. Убедитесь, что Python 3 установлен
2. Запустите `.review/run_review.sh`
3. Отчёт появится в `.review/reports/latest.md`
4. Для детального ревью используйте суб-агентов (см. `skill/code-review-skill.md`)

## Добавление новых проверок

1. Создайте скрипт в `checks/` (формат: `[SEVERITY] file:line: message`)
2. `chmod +x checks/check_new.sh`
3. `python3 generate_scripts.py .` — перегенерация per-function скриптов
4. Новая проверка автоматически подхватится всеми скриптами

## Структура

```
.review/
├── run_review.sh           # Главный скрипт
├── scan_functions.py       # Сканер функций → JSON
├── generate_scripts.py     # Генератор per-function скриптов
├── registry/functions.json # Реестр всех функций (897)
├── checks/                 # 10 проверок
├── per_function/           # 897 скриптов + INDEX.md
├── reports/                # Отчёты
└── skill/                  # Скилл для AI-ассистентов
```
