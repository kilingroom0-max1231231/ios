# Entitlements (права приложения)

Файлы `.entitlements` — это plist со списком возможностей (capabilities). Xcode подставляет их при подписи IPA.

## Бесплатный Apple ID (Personal Team)

**Push-уведомления (APNs) недоступны.** Apple выдаёт `aps-environment` только участникам **платной** программы Apple Developer Program (99 USD/год).

Для бесплатной сборки в `project.yml` **не** указывайте `CODE_SIGN_ENTITLEMENTS` с push — иначе ошибка подписи вроде *Personal development teams do not support the Push Notifications capability*.

В приложении при этом работают:

- баннеры и звук **пока приложение открыто**;
- синхронизация при сворачивании (ограниченно, пока iOS даёт время в фоне).

## Платный Apple Developer Program

1. [developer.apple.com](https://developer.apple.com) → Identifiers → ваш App ID → включить **Push Notifications**.
2. Пересоздать **Provisioning Profile** с push.
3. В `project.yml` раскомментировать блок `configs` с путями:
   - `Sources/App/Entitlements/TelegramUserClient-Push-Debug.entitlements`
   - `Sources/App/Entitlements/TelegramUserClient-Push-Release.entitlements`
4. `xcodegen generate` и пересобрать IPA.

Файлы лежат в этой папке; Xcode их **не создаёт сам** — мы добавили их в репозиторий для платной подписи.
