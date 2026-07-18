# Pet Island: быстрый старт в Xcode для C++/Qt-разработчика

## Как мысленно сопоставить Xcode и Qt

| Qt / C++ | Xcode / SwiftUI |
| --- | --- |
| проект CMake/qmake | `.xcodeproj` |
| executable/library target | Target |
| конфигурация Debug/Release | Scheme + Build Configuration |
| QWidget/QML-компонент | SwiftUI `View` |
| signals/slots | изменение `@Published`/`@State` и реактивное обновление UI |
| модель приложения | обычные `struct`, `enum`, `actor` и `ObservableObject` |
| ресурсный файл `.qrc` | Asset Catalog и String Catalog |
| debugger + application output | Debug area и Console |

SwiftUI декларативный: `body` описывает, каким должен быть экран для текущего состояния. Его не нужно вручную перерисовывать. Контроллер изменяет состояние, SwiftUI пересчитывает только нужные части дерева интерфейса.

## Где что находится в Xcode

- Левая панель, Project Navigator (`⌘1`) — файлы проекта.
- Синий элемент **PetIsland** — настройки всего проекта и targets.
- Target **PetIsland** — основное iOS-приложение.
- Target **PetIslandLiveActivity** — расширение для Lock Screen и Dynamic Island.
- Target **PetIslandTests** — unit-тесты.
- Верхняя строка **PetIsland > iPhone …** — выбранная схема и устройство запуска.
- Кнопка ▶ или `⌘R` — сборка, установка и запуск.
- `⌘B` — только сборка.
- `⌘U` — запуск тестов.
- `⇧⌘K` — очистка build folder, если Xcode показывает явно устаревшие ошибки.

## Первый запуск на симуляторе

1. Откройте [PetIsland.xcodeproj](PetIsland.xcodeproj) двойным кликом.
2. В верхней панели выберите схему **PetIsland**.
3. Справа от неё выберите **iPhone 17 Pro (iOS 26.5)** или другой iPhone с Dynamic Island.
4. Нажмите `⌘R`.
5. Пройдите onboarding и выберите имя/окрас собаки.
6. Нажмите **Dynamic Island**, сверните приложение и удерживайте остров для
   expanded-представления.
7. Вернитесь в приложение и нажмите **Вольер**, чтобы завершить Live Activity.

Если нужного iPhone нет в списке: **Xcode → Settings → Components**, установите iOS Simulator Runtime. На текущем Mac iOS 26.4 и 26.5 уже установлены.

## Запуск на настоящем iPhone

1. Подключите разблокированный iPhone кабелем и подтвердите доверие к Mac.
2. Включите **Настройки → Конфиденциальность и безопасность → Режим разработчика**.
3. В Xcode откройте синий **PetIsland** → target **PetIsland** → **Signing & Capabilities**.
4. Оставьте **Automatically manage signing** включённым и выберите свой **Team**.
5. Повторите выбор Team для **PetIslandLiveActivity**.
6. У обоих targets в **Signing & Capabilities** должен быть одинаковый App Group:
   `group.org.bortongo.PetIsland`. Если меняете Bundle ID, создайте собственный
   App Group и одновременно замените строку в `PetLifeStore`.
7. Убедитесь, что идентификаторы уникальны и согласованы:
   - приложение: `org.bortongo.PetIsland` или ваш новый идентификатор;
   - расширение: тот же префикс + `.LiveActivity`.
8. В верхней панели выберите свой iPhone и нажмите `⌘R`.

Для запуска без расширенных capabilities обычно достаточно бесплатной Personal
Team. App Group, TestFlight и App Store могут потребовать участие в платной
Apple Developer Program и заново созданные provisioning profiles.

## Как проверять Pet Island

Основной сценарий:

1. Первый запуск → onboarding → выбор окраса и имени собаки.
2. На Home Screen зажать пустое место → **+** → **Pet Island** → добавить
   medium-виджет **Pet Enclosure**.
3. В приложении выбрать **Вольер**: собака должна появиться в виджете.
4. Нажать **Ball** на виджете: собака кратко бежит за мячом, затем возвращается
   к автономному состоянию.
5. В приложении выбрать **Dynamic Island** и свернуть его: компактный остров
   должен показать собаку без таймера.
6. Удержать Dynamic Island: откроется expanded-представление.
7. Заблокировать iPhone: появится Lock Screen Live Activity.
8. На iPhone с Always-On погасить экран: питомец должен перейти в статичную позу сна.
9. Вернуться в приложение и выбрать **Вольер**: Live Activity должна завершиться,
   а собака — вернуться в medium-виджет.

Always-On есть не на всех моделях. На устройстве без него этот пункт просто пропускается; приложение и Lock Screen Live Activity продолжают работать.

## Как читать структуру кода

- `PetIsland/App` — точка входа и координация жизненного цикла.
- `PetIsland/Domain` — модели и чистая state machine поведения питомца.
- `PetIsland/Data` — локальное сохранение состояния приложения.
- `PetIsland/Features` — SwiftUI-экраны и sheets.
- `PetIsland/Shared` — общие модели ActivityKit, App Group-состояние и пиксельные sprites.
- `PetIslandLiveActivity` — medium-виджет-вольер и представления Live Activity.
- `PetIslandTests` — проверки доменной логики, persistence и размера payload.

Хорошая точка входа для чтения: `PetIslandApp.swift` → `ContentView.swift` → `HomeView.swift` → `PetSessionController` → `PetDomain.swift`.

## Типичные проблемы

**No profiles / Communication with Apple failed**

- iPhone должен быть подключён, разблокирован и доверять Mac;
- Team нужно выбрать у обоих targets;
- Bundle Identifier должен быть уникальным;
- App Group должен существовать в аккаунте и совпадать у обоих targets;
- после подключения нажмите **Try Again**.

**Developer Mode disabled**

- включите Режим разработчика на iPhone и перезагрузите его по запросу iOS.

**Live Activity не появилась**

- проверьте **Настройки iPhone → Pet Island → Live Activities**;
- снова выберите **Dynamic Island** после включения;
- на iPhone без Dynamic Island проверяйте экран блокировки.

**Симулятор отсутствует или не запускается**

- проверьте runtime в **Xcode → Settings → Components**;
- закройте и снова откройте Xcode после установки;
- при необходимости выполните **Product → Clean Build Folder**.

## Перед TestFlight

1. Выберите **Any iOS Device (arm64)**.
2. Откройте **Product → Archive**.
3. В Organizer выполните **Validate App**.
4. Исправьте все signing/metadata warnings.
5. Нажмите **Distribute App → App Store Connect → Upload**.

Перед архивированием пройдите реальную матрицу из `APP_STORE.md` и замените контактный placeholder в `PRIVACY.md`.
