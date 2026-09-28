# Бо Хам Знакомства

iOS-приложение знакомств «Бо Хам» (SwiftUI): анкеты и лента, пары и «Путь к браку», встречи, чаты и секретные чаты, звонки, каналы и боты.

## Установка

Нужен Mac с Xcode 15+ (для оформления Liquid Glass — Xcode 26). `OrzuApp.xcodeproj` лежит в репозитории, поэтому проект можно клонировать прямо из Xcode (Integrate → Clone) или из терминала:

```bash
git clone https://github.com/aslanmanov06-ai/bo-ham-znakomstva.git
cd bo-ham-znakomstva
open OrzuApp.xcodeproj
```

При первом открытии Xcode сам скачает SPM-зависимости (нужен интернет), в том числе [stasel/WebRTC](https://github.com/stasel/WebRTC) для звонков. Для запуска на iPhone выберите свою команду разработчика в Signing & Capabilities.

Приложение подключается к серверу `https://adm.orzu.pro` (`OrzuApp/Networking/AppConfig.swift`) и работает и в Симуляторе, и на iPhone. Аккаунт можно зарегистрировать прямо в приложении.

## Разработка

Источник правды — `project.yml`: проект генерирует [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Настройки таргетов, пакеты и Info.plist меняются в `project.yml`, затем `xcodegen generate` и коммит вместе с `OrzuApp.xcodeproj` и `OrzuApp/Info.plist`; правки, сделанные только в Xcode, при следующей генерации пропадут. CI проверяет, что закоммиченный проект совпадает с `project.yml`, собирает приложение и прогоняет unit-тесты.

## Языки

Интерфейс на русском, таджикском и английском. Строки в коде пишутся по-русски: литералы SwiftUI (`Text("…")`, `Button("…")`) переводятся сами, а строку, которая уходит в `String` (ошибки, подписи своих компонентов, `return "…"`), нужно обернуть в `String(localized: "…")`. Переводы лежат в `OrzuApp/Localizable.xcstrings` (подписи системных запросов доступа — в `OrzuApp/InfoPlist.xcstrings`); Xcode сам добавляет туда новые строки при сборке, перевод остаётся вписать.

Таджикского нет среди языков iOS, поэтому язык выбирается в приложении: Настройки → Приложение → Язык. Запросы к серверу несут `Accept-Language` с языком интерфейса. Тесты запускаются на русском (схема, `language: ru`), потому что сверяют русские строки.

## Push и ссылки

- **Расширение уведомлений** (`OrzuNotificationService`, таргет в `project.yml`) расшифровывает превью секретных чатов прямо на устройстве и прикрепляет миниатюру фото. Для этого сервер ставит в push `mutable-content: 1` и кладёт `chatId`, `senderId`, для секретного чата — `ciphertext` и `senderKey`, для фото — `imageUrl` (подписанная ссылка). Превью расшифровывается, только если ключ собеседника совпадает с тем, что приложение уже запомнило. Общие с приложением данные — в App Group `group.com.orzuapp.messenger` и группе Keychain `<Team ID>.com.orzuapp.messenger.shared`.
- **Ссылки**: `https://adm.orzu.pro/u/<username>` — человек, `/c/<username>` — канал (Universal Links: сервер отдаёт `/.well-known/apple-app-site-association`); то же без сайта — `boham://u/<username>`, `boham://c/<username>`. «Поделиться профилем» — в «Моём профиле», «Поделиться каналом» — в меню канала.
- Таргет расширения появляется в `OrzuApp.xcodeproj` после `xcodegen generate` — выполните его после обновления и закоммитьте проект.
