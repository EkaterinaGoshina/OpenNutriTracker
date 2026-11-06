# План: веб-версия OpenNutriTracker

Ветка: `webport`. Здесь живут и документы, и код порта.

## Решение

Приложение написано на Flutter, поэтому переписывать его на другой стек не нужно. Мы делаем fork оригинала (`simonoppowa/OpenNutriTracker`) на личный аккаунт и добавляем веб-платформу поверх него. Оригинал остаётся как `upstream`, чтобы подтягивать его обновления.

Оценка: рабочий MVP за 1–2 недели одного разработчика, полноценная версия за 3–5 недель. Оценка сделана по коду, сборка ещё не запускалась.

## О репозитории

- Около 550 файлов Dart, ~80 тыс. строк, 302 теста.
- Слои data / domain / presentation, `flutter_bloc`, DI через `get_it`.
- Все данные пользователя хранятся локально в Hive (`hive_ce`) с AES-шифрованием.
- Еда приходит из Open Food Facts и Supabase. Своего бэкенда нет.
- Flutter 3.44.6 (закреплён в `.fvmrc`), Dart SDK >= 3.11.

## Что работает в вебе без изменений

- Весь UI, графики (`fl_chart`), календарь, onboarding.
- Блоки, Hive, расчёты (TDEE, калории), дневник, рецепты, вода, голодание, вес.
- Запросы к Open Food Facts и Supabase (CORS проверить).
- Локализация и Sentry.

## Что нужно переделать

| Проблема | Где | Сложность | Решение |
|---|---|---|---|
| `dart:io` в 39 файлах | `Platform.isAndroid`, `File`, `Directory` | Средняя | `kIsWeb` и `defaultTargetPlatform`, файловые операции за интерфейс |
| Хранилище и ключ шифрования | `secure_app_storage_provider.dart`, `path_provider` | Средняя | Hive на IndexedDB, новая схема хранения ключа |
| Фото | `user_image_storage.dart`, `meal_photo_encoder.dart` | Средняя | Байты в Hive вместо файлов, веб-сжатие |
| Экспорт и импорт | `export_data_usecase`, `import_*_usecase` | Средняя | Скачивание и загрузка файла через браузер |
| Apple Health, Health Connect | пакет `health` | Лёгкая | Отключить на вебе (есть `NoopHealthService`) |
| Виджет и уведомления | `home_widget`, `flutter_local_notifications` | Лёгкая | Отключить на вебе |
| Сканер штрихкодов | `mobile_scanner` | Лёгкая | Поддержка веба есть, нужен HTTPS и доступ к камере |
| Язык приложения | `AppLocaleService` (Android) | Лёгкая | Заглушка для веба |

## Риски

1. **Шифрование.** В браузере нет аналога Keychain и Keystore. Решить: шифровать паролем пользователя или отказаться от шифрования.
2. **Данные живут в браузере.** Очистка сайта стирает всё. Нужны напоминание об экспорте и `navigator.storage.persist()`. Синхронизация между устройствами — отдельный проект, серверная часть описана в [WEB_ARCHITECTURE.md](WEB_ARCHITECTURE.md).
3. **CORS у AI-функций.** Anthropic требует особый заголовок для запросов из браузера, локальный Ollama по `http://` с HTTPS-страницы блокируется. Возможно, понадобится прокси.
4. **Размер загрузки.** Flutter Web даёт 2–3 МБ на старте. Для приложения за логином приемлемо.
5. **Адаптив.** UI сделан под телефон, на десктопе нужна доработка вёрстки.

## Шаги

1. [x] Создать fork на личном аккаунте GitHub, переключить `origin` на него, оригинал оставить как `upstream`.
2. [x] Установить Flutter 3.44.6 (в `~/development/flutter`).
3. [x] Создать `.env` из `.env.example`, запустить `just install` и `just build` (кодогенерация).
4. [x] `flutter create --platforms web .`, первая пробная сборка, собрать список ошибок компилятора.
5. [~] Убрать `dart:io` из общего кода: ввести абстракции для файлов и платформы.
6. [~] Хранилище: Hive в вебе, решение по шифрованию.
7. [ ] Фото, экспорт и импорт через браузерные API.
8. [ ] Отключить на вебе: health, виджет, уведомления, системный язык.
9. [~] CORS: Open Food Facts — через прокси Worker'а, работает. Supabase — открыт. AI-провайдеры — не проверены.
10. [ ] Адаптивная вёрстка под десктоп.
11. [~] Деплой: Cloudflare Worker, https://opennutritracker.goshina.workers.dev. Без HTTPS приложение не стартует: по адресу в локальной сети (http) браузер не даёт WebCrypto, белый экран.

## Альтернатива, которую не выбираем

Переписать на React или Vue: потребуется заново написать весь UI и логику, это 80 тыс. строк и несколько месяцев. Имеет смысл только при потребности в SEO или другой команде без опыта во Flutter.

## Журнал

### Первая сборка (шаги 1–4)

- Flutter 3.44.6 стоит в `~/development/flutter`, веб включён.
- `flutter pub get`, `build_runner` и `flutter analyze` проходят без ошибок.
- `flutter create --platforms web .` добавил папку `web/`. Шаблонный `test/widget_test.dart` удалён. `pubspec.lock` после `create` обновился сам, мы вернули его к версии оригинала.
- `flutter build web` собирается. Предупреждение про Wasm: `meal_entity.dart:571`, проверка `is int` / `is double`. Мешает только сборке в Wasm, для обычной JS-сборки не критично.
- Тесты: 3327 проходят, 1 падает: `plaintext_destination_guard_test` («zoned link-local literal»). Он падает и на чистом коде оригинала, к порту не относится.
- Для проверки в браузере нужен `.env` из шаблона (с заглушками). В `.gitignore` он уже есть.

### Первый запуск в браузере (шаг 5–6, начало)

Сначала белый экран: `MissingPluginException` для `path_provider.getApplicationDocumentsDirectory`. Его вызывала `_hasExistingEncryptedHiveData()` в `secure_app_storage_provider.dart`, проверка «есть ли уже зашифрованные файлы Hive» через обход папки. В вебе она теперь спрашивает IndexedDB: `Hive.boxExists('ProfileBox')`.

Для `Platform.isAndroid`, `isIOS`, `localeName` (8 файлов) добавлен `lib/core/utils/platform_info.dart`. На нативных платформах он возвращает то же, что `Platform`, в вебе не бросает `UnsupportedError`.

После этих двух правок приложение стартует и показывает экран приветствия (onboarding). В консоли остаются некритичные `MissingPluginException`, которые приложение само перехватывает:

- `getApplicationLocale` (канал `com.opennutritracker/locale`, смена языка Android);
- `getWidgetData` (`home_widget`, виджет iOS);
- «unknown error when fetching the script», источник ещё не выяснен.

### Что ещё не проверено в браузере

Прохождение onboarding и демо-режим, сохранение в IndexedDB после перезагрузки, поиск еды (CORS у Open Food Facts и Supabase), камера и сканер, фото, экспорт и импорт, AI-функции. Известные места, где в вебе будет падать при использовании: `getTemporaryDirectory` (4 файла), `getApplicationSupportDirectory` (кэш картинок), `File(...)` (25 файлов), `gzip` из `dart:io` (3 файла), `InternetAddress` и DNS-проверка в `plaintext_destination_guard.dart`.

### CORS у Open Food Facts

Из браузера поиск Open Food Facts не работает: `search.openfoodfacts.org/search` и `world.openfoodfacts.org/cgi/search.pl` не отдают `Access-Control-Allow-Origin`, и браузер блокирует ответ (проверено с `http://localhost:8090`). Поиску в вебе нужен прокси, его можно поставить в тот же Worker, что и `/api/photos/*`. Поиск по справочнику Supabase этой проблемы не имеет: у Supabase CORS открыт.

### Выкладка на Cloudflare

Worker `opennutritracker` отдаёт `build/web` и проксирует Open Food Facts (`worker/src/index.js`). Проверено на узком экране: демо, поиск «борщ» с картинками.

- Основной поиск (`search.openfoodfacts.org/search`) и товар по штрихкоду через прокси отвечают. Запасной поиск `world.openfoodfacts.org/cgi/search.pl` серверам Cloudflare отдаёт 503 «Page temporarily unavailable», хотя с обычного компьютера отвечает. Он нужен только когда основной поиск лежит.
- Локальный `wrangler dev` не может достучаться до Open Food Facts (внутренняя ошибка через 2 минуты), хотя `curl` с того же Mac работает. Прокси проверять на выложенной версии.
- Справочник Supabase в вебе отвечает 405, пока в `.env` заглушка `PROJECT_URL`: приложение шлёт запрос на свой же сайт.
