# Mase Telegram (Telegram User Client)

Неофициальный iOS-клиент для **обычного Telegram-аккаунта** (user API через [TDLib](https://core.telegram.org/tdlib), не Bot API). Интерфейс на SwiftUI в стиле Telegram: тёмная тема, glass-панели, жесты, реакции, папки чатов и мультиаккаунт.

| | |
|---|---|
| **Платформа** | iOS 16.0+ (iPhone) |
| **Язык** | Swift 5.9, SwiftUI |
| **Backend** | TDLib (JSON API) |
| **Bundle ID** | `online.maseai.telegramuserclient` |
| **Схема Xcode** | `TelegramUserClient` |

> Это неофициальный клиент. Для работы нужны собственные `api_id` / `api_hash` с [my.telegram.org](https://my.telegram.org).

---

## Возможности

### Чаты и сообщения
- Список чатов с превью, непрочитанными, закреплёнными и архивом
- Папки чатов (вкладки) с кастомными emoji в названиях
- Отправка и редактирование текста, ответы, пересылка
- Удаление у себя / у всех
- Реакции: быстрый тап, долгий тап (панель как в TG), двойной тап
- Свайп по сообщению (настраиваемое действие)
- Кликабельные ссылки, `@username`, invite-ссылки `t.me/+…` прямо в чате
- Переход к автору пересланного сообщения
- Локальный кэш сообщений в SQLite (офлайн-история после загрузки)

### Медиа
- Фото, видео, альбомы, документы, голосовые, видеокружки
- Стикеры (в т.ч. анимированные `.tgs` через Lottie), подарки
- Просмотр медиа, скачивание вложений
- Отправка фото, файлов, голосовых и видеокружков с камеры/галереи

### Контакты и поиск
- Вкладка **Контакты** с поиском и секциями A–Z
- Глобальный **Поиск** по чатам, сообщениям и контактам
- Синхронизация телефонной книги с Telegram
- Создание личных чатов, групп и каналов

### Профили и приватность
- Профиль пользователя, профиль чата / канала
- Блокировка / разблокировка, настройки приватности
- Активные сессии (**Устройства**): просмотр и завершение

### Настройки приложения
- **Мультиаккаунт**: добавление, переключение, удаление сессий
- Тема (светлая / тёмная / системная), акцент, фоны чатов, стиль пузырей
- Язык интерфейса RU / EN
- Уведомления: push (при платном Apple Developer), баннеры in-app, звуки
- Поведение: жесты, реакции, папки, свайпы
- Настройка вкладок нижней панели (аватар профиля на вкладке «Настройки»)
- Очистка кэша и управление данными

---

## Технологии

| Компонент | Описание |
|-----------|----------|
| **TDLib** | Официальная C++ библиотека Telegram; линковка через `tdjson` |
| **XcodeGen** | Генерация `.xcodeproj` из `project.yml` |
| **SQLite** | `LocalMessageStore`, `LocalChatStore` — локальный кэш |
| **Lottie** | Анимированные стикеры `.tgs` |
| **Keychain** | Хранение `api_id` / `api_hash` и сессий аккаунтов |
| **Flask** | Маркетинговый лендинг в `website/` |

---

## Структура репозитория

```
ios-telegram-user-client/
├── Sources/App/
│   ├── Core/           # TDLibBridge, TDLibClient, модели, сервисы
│   ├── Data/           # TelegramRepository, SQLite-хранилища, сессии
│   ├── UI/             # SwiftUI-экраны и компоненты
│   │   └── Theme/      # Оформление, язык, настройки
│   ├── Entitlements/   # Push entitlements (платная подпись Apple)
│   ├── Assets.xcassets
│   └── Info.plist
├── tdlib/
│   ├── include/        # Заголовки TDLib
│   ├── lib/            # Симулятор (libtdjson.a)
│   └── lib-iphoneos/   # Устройство (libtdjson_static.a и др.)
├── website/            # Лендинг Mase Telegram (Flask)
├── project.yml         # Спецификация XcodeGen
├── codemagic.yaml      # CI: simulator / device IPA / AltStore
└── README.md
```

### Слои приложения

```
SwiftUI (Views)
      ↓
AppViewModel
      ↓
TelegramRepository  ←→  LocalMessageStore / LocalChatStore
      ↓
TDLibClient  ←→  TDLib (tdjson)
```

---

## Требования

- **macOS** с Xcode 15+ (CI использует latest Xcode на Codemagic)
- **XcodeGen**: `brew install xcodegen`
- **TDLib** — собранные библиотеки для симулятора и/или устройства (см. [`tdlib/README.md`](tdlib/README.md))
- **API credentials** — `api_id` и `api_hash` с [my.telegram.org](https://my.telegram.org/apps)

### TDLib-артефакты

Минимум для локальной сборки:

| Путь | Назначение |
|------|------------|
| `tdlib/include/` | Заголовки (`td_json_client.h`, …) |
| `tdlib/lib/libtdjson.a` | Симулятор |
| `tdlib/lib-iphoneos/libtdjson_static.a` | Реальное устройство (Release) |

Без библиотек линковка завершится ошибкой `-ltdjson`.

---

## Локальная сборка

```bash
# 1. Клонировать репозиторий и перейти в каталог
cd ios-telegram-user-client

# 2. Положить TDLib в tdlib/ (см. tdlib/README.md)

# 3. Сгенерировать Xcode-проект
xcodegen generate

# 4. Открыть и собрать
open TelegramUserClient.xcodeproj
```

При первом запуске:
1. Введите `api_id` и `api_hash`.
2. Авторизуйтесь: номер телефона → код → 2FA (если включена).
3. Для нескольких аккаунтов: **Настройки → Аккаунты → Добавить аккаунт**.

---

## Codemagic CI

Конфигурация: [`codemagic.yaml`](codemagic.yaml).

| Workflow | Результат |
|----------|-----------|
| `telegram-user-client-simulator` | Unsigned `.app` → zip для симулятора |
| `telegram-user-client-device-ipa` | Подписанный ad-hoc `.ipa` (LiveContainer, TestFlight-подобная установка) |
| `telegram-user-client-altstore-ipa` | Unsigned Release `.ipa` для AltStore / sideload |

### Device IPA (ad-hoc)

Перед запуском `telegram-user-client-device-ipa`:
- App Store Connect API key в Codemagic
- Сертификат и provisioning profile для `online.maseai.telegramuserclient`
- UDID устройства в профиле

Артефакты: `build/ios/ipa/*.ipa`, `build/ios/archive/*.xcarchive`

### AltStore IPA

Workflow `telegram-user-client-altstore-ipa` собирает unsigned Release для `iphoneos`. AltStore подписывает при установке.

Нужны оба набора TDLib:
- `tdlib/lib/libtdjson.a`
- `tdlib/lib-iphoneos/libtdjson_static.a`

---

## Push-уведомления

Push (APNs) доступен только с **платным** Apple Developer Program ($99/год).

| Сценарий | Push |
|----------|------|
| Бесплатный Personal Team | ❌ — не указывать push entitlements в `project.yml` |
| Платный Developer Program | ✅ — раскомментировать `CODE_SIGN_ENTITLEMENTS` в `project.yml` |

Подробнее: [`Sources/App/Entitlements/README.md`](Sources/App/Entitlements/README.md).

Без push работают in-app баннеры и звук, пока приложение активно.

---

## Лендинг (`website/`)

Маркетинговый сайт **Mase Telegram**: Flask + Jinja2 + Tailwind (CDN), RU/EN, страница `/privacy`.

```bash
cd website
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python app.py
# → http://127.0.0.1:5000
```

Детали: [`website/README.md`](website/README.md).

---

## Разрешения iOS

Приложение запрашивает доступ к:
- **Фото** — отправка медиа и обои
- **Камера / микрофон** — видеокружки и голосовые
- **Контакты** — синхронизация с Telegram
- **Уведомления** — push о новых сообщениях

---

## Важно

- **Неофициальный клиент.** Не связан с Telegram FZ-LLC. Используйте на свой риск и соблюдайте [ToS Telegram](https://telegram.org/tos).
- **Секреты.** `api_id` / `api_hash` хранятся в Keychain на устройстве; не коммитьте их в репозиторий.
- **TDLib не в git.** Бинарники TDLib обычно не включены в репозиторий — их нужно собрать или добавить в CI отдельно.
- **Удалённые сообщения.** Сообщения, удалённые на сервере до синхронизации клиента, восстановить нельзя.
- **iOS 16.** Минимальная версия — iOS 16.0; часть SwiftUI-API обходится для совместимости.

---

## Полезные ссылки

- [TDLib](https://core.telegram.org/tdlib)
- [Telegram API — получение api_id](https://my.telegram.org/apps)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [Codemagic](https://codemagic.io)
