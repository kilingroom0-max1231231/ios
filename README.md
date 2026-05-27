# Telegram User Client (TDLib)

Отдельный iOS-проект с нуля для обычного Telegram-аккаунта (не Bot API):

- инициализация TDLib;
- авторизация (phone/code/password);
- чтение чатов;
- чтение/отправка сообщений;
- локальное хранение в SQLite;
- базовый парсинг медиа: photo/video/voice/video note/document.
- скачивание медиа (`downloadFile`) и сохранение локального пути в БД.

## Структура

- `Sources/App/Core` - TDLib bridge и клиент
- `Sources/App/Data` - репозиторий и локальная SQLite
- `Sources/App/UI` - SwiftUI экран
- `tdlib` - место для слинкованных артефактов TDLib

## Запуск

1. Сгенерировать Xcode проект:
   - `cd ios-telegram-user-client`
   - `xcodegen generate`
2. Подключить TDLib:
   - headers в `tdlib/include`
   - lib в `tdlib/lib` (см. `tdlib/README.md`)
3. Открыть `TelegramUserClient.xcodeproj`.
4. Запустить на устройстве/симуляторе.
5. Ввести `api_id` и `api_hash` (my.telegram.org), затем номер/код/2FA.
6. Для сообщений с вложениями нажать `Скачать медиа`.

## Codemagic

Есть готовый `ios-telegram-user-client/codemagic.yaml`.

Перед запуском workflow убедись, что в репозитории есть:
- `ios-telegram-user-client/tdlib/lib/libtdjson.a`
- `ios-telegram-user-client/tdlib/include/...`

Без этих TDLib-артефактов сборка в Codemagic упадет на линковке.

## Важно

- Это минимальный рабочий каркас. Для production стоит добавить:
  - улучшенный event-loop TDLib (сейчас уже обрабатываются `updateAuthorizationState`, `updateNewMessage`, `updateDeleteMessages`, `updateNewChat`);
  - корректный парсинг всех типов content (фото, видео, voice, video note);
  - безопасное хранение секретов (Keychain);
  - более устойчивую обработку ошибок/ретраев.

- Сообщения, удаленные до их получения клиентом, восстановить нельзя.
