# Обзор: что есть в приложении и как оно устроено

Карта проекта. С неё начинают, когда нужно понять, что уже сделано и где это лежит. Подробности — в документах, на которые она ссылается.

**Правило:** кто добавляет, убирает или заметно меняет функцию или архитектуру, обновляет этот файл в том же коммите. Строку в таблице функций, раздел архитектуры, ссылку на новый документ.

## Что это

Fork [OpenNutriTracker](https://github.com/simonoppowa/OpenNutriTracker) — трекер калорий и нутриентов на Flutter. Ведётся в `EkaterinaGoshina/OpenNutriTracker`, ветка `webport`. Оригинал подключён как `upstream`.

Цели fork'а:

1. **Веб-версия** того же приложения, без переписывания на другой стек ([WEB_PORT_PLAN.md](WEB_PORT_PLAN.md)).
2. **Семья:** аккаунты, объединение в семью, общие блюда «Кухни» ([WEB_ARCHITECTURE.md](WEB_ARCHITECTURE.md)).
3. **Упрощение под домашнюю готовку:** быстрые блюда из ингредиентов, лишнее убрано с экранов.

## Функции

Статус: ✅ работает, 🟡 частично, ⬜ не начато, ❌ убрано в fork'е.

| Функция | Статус | Где |
|---|---|---|
| Дневник еды по приёмам пищи, календарь | ✅ | `features/diary`, `features/home` |
| Поиск еды: Open Food Facts и справочник Supabase | ✅ на телефоне, 🟡 в вебе | `features/add_meal`. В вебе Open Food Facts идёт через прокси Worker'а (`/api/off`), справочнику нужен адрес в `.env` |
| Сканер штрихкодов | ✅ | `features/scanner` |
| AI: описать еду текстом или фото | ✅ | `features/add_meal`, [ai-architecture.md](ai-architecture.md) |
| Свои продукты, избранное | ✅ | `features/add_meal`, `features/recipes` |
| Блюда (рецепты) из ингредиентов, вес или порции | ✅ | `features/recipes`, `core/domain/usecase/compute_recipe_nutrition_usecase.dart` |
| Добавление ингредиентов пачкой, создание продукта из поиска | ✅ fork | `features/recipes/presentation/screens/ingredient_picker_screen.dart` |
| «Кухня» на главной: блюда, «Ам» — записать порцию, свайп — удалить | ✅ fork | `features/home/presentation/widgets/kitchen_card.dart`, `kitchen_eat_sheet.dart` |
| Упрощённая главная: калории и макросы в одной карточке | ✅ fork | `features/home/presentation/widgets/dashboard_widget.dart` |
| Активности и расход калорий | ✅, по умолчанию скрыто | `features/add_activity`, включается в настройках |
| Вес, тренды, цели по калориям и макросам | ✅ | `features/profile`, `features/trends`, `features/settings` |
| Несколько локальных профилей на устройстве | ✅ | `core/utils/hive_db_provider.dart` |
| Экспорт и импорт (zip, JSON, CSV) | ✅ на телефоне, ⬜ в вебе | `features/settings`, [export-format.md](export-format.md) |
| Apple Health / Health Connect, виджет iOS, напоминания | ✅ на телефоне, ⬜ отключить в вебе | `core/data/data_source/health`, [ios-calorie-widget.md](ios-calorie-widget.md) |
| Демо-режим | ✅ | `core/utils/demo`, [demo-data.md](demo-data.md) |
| Русский язык | ✅ fork | `lib/l10n/intl_ru.arb`, [ru-translation-guide.md](ru-translation-guide.md) |
| Учёт воды, таймер голодания | ❌ убраны | коммит `e5734880` |
| Веб-версия | 🟡 выложена на https://opennutritracker.goshina.workers.dev, демо и поиск работают | [WEB_PORT_PLAN.md](WEB_PORT_PLAN.md), `worker/` |
| Аккаунт: вход по коду из письма, Google | 🟡 код готов, экранов нет | `features/family/data/account_repository.dart` |
| Семья: создать, пригласить по коду, вступить, выйти | 🟡 сервер и код готовы, экранов нет | `features/family`, `supabase/` |
| Общие блюда семьи и синхронизация «Кухни» | 🟡 сервер готов, в приложении нет | `supabase/migrations/20261106130000_family_dishes.sql` |
| Cloudflare Worker: сайт и прокси Open Food Facts | ✅ | `worker/src/index.js` |
| Фото блюд в R2 | ⬜ | [WEB_ARCHITECTURE.md](WEB_ARCHITECTURE.md) |

## Архитектура приложения

**Стек:** Flutter 3.44.6, Dart ≥ 3.11. Состояние — `flutter_bloc`, зависимости — `get_it` (`lib/core/utils/locator.dart`). Подробные правила кода — в [AGENTS.md](../AGENTS.md), раздел Architecture.

**Слои.** `lib/core` — общее: данные (`data/dbo`, `data/data_source`, `data/repository`), домен (`domain/entity`, `domain/usecase`), общие виджеты и утилиты. `lib/features/<функция>` — экраны и блоки функции, иногда со своими `data` и `domain`.

**Данные пользователя** лежат на устройстве в Hive с AES-шифрованием. На телефоне ключ хранится в Keychain/Keystore. В вебе ящики лежат в IndexedDB, а как хранить ключ, ещё не решено ([WEB_PORT_PLAN.md](WEB_PORT_PLAN.md), риск 1).

- У каждого локального профиля свои ящики: дневник, активности, вес, избранное, личные настройки (`HiveDBProvider.perProfileBoxNames`).
- Общие для устройства: блюда (`recipeBox`), свои продукты, шаблоны активностей, общие настройки.
- Поэтому аккаунт и семья привязаны к устройству, а не к профилю: семья синхронизирует блюда, а они общие для всего устройства.

**Внешние сервисы:**

| Сервис | Для чего | Клиент |
|---|---|---|
| Open Food Facts | Поиск продуктов, штрихкоды | HTTP в `features/add_meal/data` |
| Supabase автора (справочник еды) | Поиск по базам FDC, BLS и др. | `SupabaseClient` в `locator`, [supabase-self-hosting.md](supabase-self-hosting.md) |
| Наш Supabase `opennutritracker` | Аккаунты, семьи, общие блюда | `Supabase.instance`, только если в `.env` есть `ACCOUNT_SUPABASE_*` |
| AI-провайдеры | Распознавание еды | ключи пользователя, [ai-architecture.md](ai-architecture.md) |
| Sentry | Отчёты об ошибках, по согласию | `core/utils/sentry_config.dart` |

## Сервер

Схема нашего Supabase лежит в `supabase/migrations`, применяется по порядку имён. Описание таблиц, RPC и кодов ошибок, тестовый стенд на PGlite, настройка входа — в [supabase/README.md](../supabase/README.md).

Кратко: `profiles`, `families`, `family_members`, `family_invites`, `family_dishes`. Писать в них можно только через RPC (`create_family`, `join_family`, `save_family_dish` и др.), читать — только свою семью (RLS).

Cloudflare Worker (`worker/`, аккаунт Cloudflare пользователя) отдаёт веб-сборку из `build/web` и отвечает на `/api/*`. Сейчас там только `/api/off/<host><path>`: прокси для трёх адресов Open Food Facts, которые использует приложение (`OFFConst` в вебе строит URL на него). Запланировано: подпись ссылок на фото в R2, прокси для AI.

## Ветки, коммиты, сборка

- Работа идёт в `webport`, push в `origin` по SSH.
- Коммиты по [conventional commits](https://www.conventionalcommits.org/), без AI в соавторах ([AGENTS.md](../AGENTS.md), раздел Commits).
- `.env` не в git. После правки `.env` нужен `dart run build_runner clean`, затем `dart run build_runner build`: иначе build_runner берёт значения из кэша.
- Веб: `flutter build web`, затем `cd worker && npm run deploy` (нужен `npx wrangler login`). Адрес: https://opennutritracker.goshina.workers.dev. Локально: `npm run dev` в `worker/`, но локальный эмулятор не достаёт до Open Food Facts, поиск проверять на выложенной версии.
- Тесты Worker'а: `cd worker && npm test`.

## Документы

| Документ | О чём |
|---|---|
| [WEB_PORT_PLAN.md](WEB_PORT_PLAN.md) | Перенос в браузер: что сделано, что осталось, журнал проблем |
| [WEB_ARCHITECTURE.md](WEB_ARCHITECTURE.md) | Сервер, аккаунты, семья, фото, хостинг: решения и шаги |
| [supabase/README.md](../supabase/README.md) | Схема базы, RPC, тесты, настройка проекта |
| [ru-translation-guide.md](ru-translation-guide.md) | Глоссарий и правила русского перевода |
| [export-format.md](export-format.md) | Формат экспорта |
| [ai-architecture.md](ai-architecture.md) | Как устроены AI-функции |
| [AGENTS.md](../AGENTS.md) | Правила кода, тестов и коммитов оригинального проекта |
