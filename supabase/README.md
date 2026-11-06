# Supabase: аккаунты и семьи

Схема нашего проекта Supabase: профили, семьи, приглашения. Справочник еды живёт в другом проекте и здесь не описан ([docs/supabase-self-hosting.md](../docs/supabase-self-hosting.md)). Архитектура: [docs/WEB_ARCHITECTURE.md](../docs/WEB_ARCHITECTURE.md).

## Что внутри

| Файл | Что делает |
|---|---|
| `migrations/20261106120000_family.sql` | Таблицы `profiles`, `families`, `family_members`, `family_invites`, RPC, политики RLS |
| `tests/family_test.mjs` | Применяет все миграции к Postgres в памяти (PGlite) и проверяет RPC и права от лица разных пользователей |

## RPC

Клиент меняет состав семьи только через эти функции. Прямая запись в таблицы запрещена, кроме `profiles.display_name` (своё имя), `families.name` (только владелец) и удаления неиспользованных приглашений (только владелец).

| Функция | Кто вызывает | Что делает |
|---|---|---|
| `create_family(name)` | Человек без семьи | Создаёт семью, вызвавший становится владельцем |
| `create_invite()` | Владелец | Одноразовый код из 8 символов на 48 часов, не больше 10 активных |
| `join_family(code)` | Человек без семьи | Вступает в семью. Регистр, пробелы и дефисы в коде не важны. Повторный вызов с тем же кодом не ошибка |
| `leave_family()` | Участник | Выходит. Владелец выходит, только если он последний, и тогда семья удаляется |
| `remove_member(user_id)` | Владелец | Удаляет участника |
| `transfer_ownership(user_id)` | Владелец | Передаёт роль владельца |
| `is_family_member(family_id)`, `my_family_id()` | Любой вошедший | Проверки для приложения и Worker |

Ошибки приходят как текст исключения: `not_authenticated`, `invalid_name`, `already_in_family`, `not_in_family`, `not_owner`, `not_a_member`, `invite_not_found`, `invite_expired`, `invite_used`, `owner_must_transfer`, `too_many_invites`. Приложение переводит их в сообщения для пользователя.

Если удалить аккаунт владельца, владельцем становится участник, вступивший раньше всех. Если удалить последний аккаунт, семья удаляется.

## Проверка

Нужен Node.js 22 или новее.

```bash
cd supabase/tests && npm install && npm test
```

Стенд подменяет схему `auth` Supabase минимальной заглушкой: таблица `auth.users`, функция `auth.uid()`, роли `anon` и `authenticated`. Он проверяет логику и права, но не заменяет прогон на настоящем проекте.

## Как применить к проекту Supabase

Вариант без установки инструментов: открыть в панели Supabase **SQL Editor**, вставить содержимое файла миграции и выполнить.

Вариант с CLI:

```bash
supabase link --project-ref <ref>
supabase db push
```

После применения стоит открыть **Advisors → Security** в панели: предупреждений про RLS и `search_path` быть не должно.

## Настройка входа

В панели проекта:

1. **Authentication → Sign In / Providers → Email**: включить. Подтверждение email можно оставить включённым: код из письма и есть подтверждение.
2. **Authentication → Emails**: в шаблоны **Magic Link** и **Confirm signup** добавить `{{ .Token }}`. Первое письмо новому человеку уходит по шаблону Confirm signup, следующие — по Magic Link. Приложение просит ввести шестизначный код, а не переходить по ссылке.
3. **Authentication → Sign In / Providers → Google**: включить и указать Client ID и Secret из Google Cloud Console. В Google Cloud в «Authorized redirect URIs» добавить `https://<ref>.supabase.co/auth/v1/callback`.
4. **Authentication → URL Configuration**: в «Redirect URLs» добавить адрес веб-версии и `http://localhost:*` для разработки.

Затем в `.env` приложения:

```
ACCOUNT_SUPABASE_URL="https://<ref>.supabase.co"
ACCOUNT_SUPABASE_PUBLISHABLE_KEY="sb_publishable_..."
```

и пересобрать: `just build`.
