# Pet Island: путеводитель по коду для C++/Qt/Python-разработчика

Этот документ объясняет текущую архитектуру Pet Island, назначение каждого
исходного файла и роль основных типов и функций. Это не справочник по всему
Swift: его задача — помочь открыть конкретный файл проекта и быстро понять,
зачем он существует и куда передаёт данные.

Актуально для контрольной версии от 18 июля 2026 года.

## 1. Главная модель проекта

Если мыслить в терминах Qt, приложение разделено примерно так:

| Pet Island | Аналогия с C++/Qt |
| --- | --- |
| `View` в SwiftUI | `QWidget` или QML-компонент |
| `PetSessionController` | controller/view-model с сигналами состояния |
| структуры из `Domain` и `Shared` | DTO, value objects и модели предметной области |
| `@Published`, `@State`, `@Binding` | observable property, сигнал об изменении и двусторонняя привязка |
| `FilePetStore` | repository/DAO для файла с состоянием |
| `PetLifeStore`, `PetHabitatStore` | общее хранилище между двумя процессами |
| Widget extension | отдельная небольшая программа, встроенная в основное приложение |
| `AppIntent` | системная команда/слот, которую iOS может вызвать без открытия UI |
| `TimelineProvider` | поставщик заранее рассчитанных кадров состояния виджета |
| `ActivityKit` | API системной Live Activity и Dynamic Island |

Основной поток данных:

```text
SwiftUI View
    ↓ вызывает async-метод
PetSessionController
    ↓ изменяет модель
PersistedAppState / PetLifeState / SharedPetHabitat
    ↓ сохраняется
файл приложения или App Group UserDefaults
    ↓ читается другим процессом
WidgetKit / ActivityKit
    ↓ строит представление
Home Screen widget / Dynamic Island / Lock Screen
```

Важное отличие от обычного Qt-приложения: SwiftUI не просит вручную вызвать
`update()` или `repaint()`. `body` — функция от состояния. Когда `@State` или
`@Published` меняется, SwiftUI заново вычисляет нужную часть дерева UI.

## 2. Targets и процессы

В проекте три target:

1. **PetIsland** — основное приложение. Оно показывает экраны, игровую,
   редактирует питомцев и запускает Live Activity.
2. **PetIslandLiveActivity** — extension. В нём живут medium-виджет,
   Dynamic Island и Lock Screen Live Activity. Extension работает в другом
   процессе и не может читать обычную память основного приложения.
3. **PetIslandTests** — unit-тесты доменной логики.

Общие Swift-файлы из `PetIsland/Shared` включены и в приложение, и в extension.
Поэтому эти файлы не должны зависеть от экранов основного приложения.

## 3. Рекомендуемый порядок чтения

Не начинай с самого большого файла. Удобный маршрут:

1. `PetIslandApp.swift` — точка входа.
2. `ContentView.swift` — корневой экран и жизненный цикл.
3. `HomeView.swift` — действия пользователя.
4. `PetSessionController.swift` — координация приложения.
5. `PetDomain.swift` — основные модели.
6. `PetLifeState.swift` и `PetHabitatState.swift` — общее состояние и поведение.
7. `PetPixelArtwork.swift` — выбор кадров анимации.
8. `PetLiveActivityWidget.swift` — Dynamic Island.
9. `PetEnclosureWidget.swift` — Home Screen widget.
10. Тесты — примеры ожидаемого поведения без UI.

## 4. Основное приложение: `PetIsland/App`

### `PetIsland/App/PetIslandApp.swift`

Точка входа программы. Атрибут `@main` говорит Swift, с какого типа начинать
запуск.

- `PetIslandApp: App` — аналог класса `QApplication` вместе с созданием
  главного окна.
- `body: some Scene` — возвращает `WindowGroup`, внутри которого создаётся
  `ContentView`.

### `PetIsland/App/ContentView.swift`

Корень SwiftUI-интерфейса.

- `controller` — `@StateObject`, поэтому один экземпляр
  `PetSessionController` живёт столько же, сколько корневой экран.
- `scenePhase` — состояние процесса: active, inactive или background.
- `body` — в Debug может выбрать специальный QA-экран по аргументу запуска;
  в обычном запуске показывает `appContent`.
- `appContent` — запускает `controller.bootstrap()`, реагирует на смену
  жизненного цикла, deep link, onboarding и ошибки.
- `previewParty` — тестовые питомцы для отладочных экранов.

Debug-типы:

- `LiveActivityRecoveryHostView` — проверяет восстановление сохранённой сессии,
  когда Live Activity отсутствует.
- `PetLiveActivitySmokeHostView.startPetActivity()` — удаляет старые Live
  Activities и создаёт настоящую тестовую активность питомца.
- `LiveActivitySmokeHostView.startSmokeActivity()` — минимальная проверка
  ActivityKit без моделей питомца.
- `PetCollectionDebugPreview` — наполняет коллекцию тестовыми животными.
- `DynamicIslandSpritePreview` — показывает спрайты в размерах, близких к
  Dynamic Island, внутри обычного приложения.

### `PetIsland/App/PetSessionController.swift`

Главный координатор приложения. Это ближайший аналог QObject-controller или
view-model. Он помечен `@MainActor`, следовательно его UI-состояние изменяется
только на главном потоке.

Состояния:

- `Operation` — загрузка, ожидание, запуск, активная сессия и остановка.
- `LiveActivityConnection` — состояние связи с системной Live Activity.
- свойства `@Published` — данные, за которыми наблюдают SwiftUI-экраны.
- `store` — абстракция постоянного хранилища.
- `activity` — текущий объект ActivityKit.
- `Task`-поля — фоновые асинхронные наблюдатели и отложенное завершение.

Публичные функции:

| Функция | Что делает |
| --- | --- |
| `bootstrap()` | Один раз загружает файл состояния, нормализует питомцев, синхронизирует App Group и восстанавливает/завершает Live Activity. |
| `completeOnboarding(profile:)` | Сохраняет первого выбранного питомца и завершает onboarding. |
| `updateProfile(_:)` | Совместимый короткий путь для изменения ведущего питомца. |
| `addPet(_:)` | Добавляет уникального питомца; при наличии места включает его в активную группу. |
| `updatePet(_:)` | Обновляет существующий профиль по `UUID`. |
| `removePet(id:)` | Удаляет питомца, но не позволяет оставить пустую коллекцию или удалить участника активной сессии. |
| `togglePetActive(id:)` | Добавляет/удаляет питомца из активной группы с проверкой лимита. |
| `makeLeadPet(id:)` | Перемещает питомца на первое место активной группы. |
| `updateSettings(_:)` | Сохраняет настройки и публикует их для UI. |
| `saveHabitat(theme:residentPetIDs:)` | Сохраняет тему и состав вольера в App Group. |
| `startSession(duration:)` | Создаёт `PetSession`, завершает старые Activity, запускает новую Live Activity и планирует окончание. |
| `placePet(in:)` | Перемещает ведущего пса между вольером и Dynamic Island; следит, чтобы он не отображался сразу в двух местах. |
| `reconnectLiveActivity()` | Явно пересоздаёт пропавшую Live Activity для текущей сессии. |
| `interact(_:)` | Меняет позу после поглаживания, игры или еды и отправляет новое состояние в ActivityKit. |
| `endSession(...)` | Записывает историю, показывает финальный сон, завершает Activity и при необходимости возвращает питомца в вольер. |
| `handleDeepLink(_:)` | Обрабатывает URL вида `petisland://...`. |
| `sceneBecameActive()` | Повторно сверяет состояние после возврата приложения на экран. |
| `sceneEnteredBackground()` | Сохраняет активную сессию перед приостановкой процесса. |

Внутренние функции:

| Функция | Что делает |
| --- | --- |
| `reconcileActivities(at:)` | Сопоставляет сохранённую сессию и реально существующие ActivityKit-объекты; удаляет лишние и восстанавливает нужную. |
| `scheduleExpiry(for:)` | Создаёт отменяемый `Task`, который завершит сессию по `endsAt`. |
| `observeCurrentActivity()` | Читает асинхронный поток `activityStateUpdates`. |
| `activityWasDismissed(activityID:)` | Фиксирует ручное удаление Live Activity пользователем. |
| `observeAuthorization()` | Наблюдает, разрешены ли Live Activities в настройках iOS. |
| `publishPetCollection()` | Копирует нормализованную модель в `@Published`-свойства UI. |
| `activityIdentity(for:)` | Делает компактный DTO питомца для ActivityKit payload. |
| `requestLiveActivity(...)` | Проверяет разрешение и вызывает `Activity.request`. |
| `updateLiveActivityConnection(_:)` | Переводит системный `ActivityState` в состояние контроллера. |
| `recoverParty(from:)` | Восстанавливает профиль из атрибутов найденной Live Activity. |
| `ensureMVPDog()` | Гарантирует наличие ведущего пса для текущего MVP. |
| `synchronizeSharedLifeState()` | Синхронизирует одиночную модель `PetLifeState` с App Group. |
| `synchronizeSharedHabitat()` | Синхронизирует коллекцию и жителей многопитомцевого вольера. |
| `moveLeadInSharedHabitat(...)` | Переносит ведущего питомца между вольером и Dynamic Island. |
| `reloadSharedLifeState()` | Повторно читает общее состояние из App Group. |
| `updateSharedPlacement(_:)` | Атомарно меняет местоположение в `PetLifeStore`. |
| `clearLiveActivityState()` | Немедленно завершает все Pet Island Live Activities и очищает сессию. |
| `persist()` | Сохраняет приватное состояние приложения через `PetStore`. |

`Haptics.light` и `Haptics.success` инкапсулируют два вида виброотклика.

## 5. Домен и сохранение: `Domain` и `Data`

### `PetIsland/Domain/PetDomain.swift`

Здесь находятся базовые value types. Файл почти не знает про UI.

Перечисления:

- `PetSpecies` — вид животного.
- `PetBreed` — порода/визуальный подвид; `available(for:)` фильтрует варианты,
  `defaultVariant(for:)` возвращает первый безопасный вариант.
- `PetCoat` — базовая палитра.
- `PetPersonality` — характер.
- `PetPose` — состояние спрайта: idle, walk, run, jump, fly, play, eat, sleep.
- `PetDirection` — направление взгляда.
- `SessionPreset` — готовые длительности старого сценария сессии.
- `PetInteraction` — пользовательское действие над питомцем.

Структуры и функции:

- `PetColorSelection.init` ограничивает RGB диапазоном `0...1`.
- `PetProfile` хранит профиль. `resolvedBreed` исправляет отсутствующий или
  несовместимый вариант; `personality` вычисляет характер; `normalizeName()`
  убирает лишние пробелы и ограничивает имя 16 символами.
- `PetSnapshot` — один кадр поведения. Инициализатор ограничивает координату
  безопасным диапазоном `0.08...0.92`; `initial(at:)` создаёт стартовый кадр.
- `PetSession.duration`, `isExpired(at:)`, `progress(at:)` вычисляют параметры
  сессии и не позволяют progress выйти за `0...1`.
- `PetHistory.record` добавляет только реально прошедшее время.
- `AppSettings` — пользовательские настройки.
- `PersistedAppState` — версия приватного сохранения. `profile` оставлен как
  compatibility bridge; `activeParty` восстанавливает объекты по ID;
  `normalizePetCollection()` убирает дубликаты и соблюдает лимит;
  `init(from:)` мигрирует schema v1; `encode(to:)` пишет schema v2.
- `PetBehaviorMachine.initialSnapshot`, `reacting` и `ambientSnapshot`
  детерминированно создают позы, движение, разворот на границе и сон.

### `PetIsland/Data/PetStore.swift`

Repository-слой.

- `PetStore` — протокол с асинхронными `load` и `save`.
- `FilePetStore` — `actor`, который сериализует `PersistedAppState` в
  `Application Support/PetIsland/state.json`. Запись атомарная.
- `InMemoryPetStore` — хранит состояние в памяти; нужен unit-тестам и Debug UI.

`actor` здесь решает ту же задачу, что mutex + строго контролируемый доступ в
C++, но компилятор Swift проверяет изоляцию.

## 6. Экраны приложения: `PetIsland/Features`

### `HomeView.swift`

Главный экран.

- `body` создаёт `NavigationStack`, toolbar и модальные экраны.
- `habitat` показывает живой preview вольера и кнопку редактирования.
- `identity` выводит количество жителей и тему.
- `placementCard` выбирает, где сейчас живёт Pixel.
- `placementButton(...)` строит переиспользуемую кнопку и вызывает
  `controller.placePet`.
- `playCard` открывает полноэкранную игровую.
- `widgetHelp` объясняет добавление системного виджета.
- `liveActivityStatus` показывает состояние ActivityKit и кнопку восстановления.
- `activityAvailabilityNotice` предупреждает об отключённых Live Activities.
- `placementTitle`, `placementDescription`, `placementSymbol`, `themeTitle`
  преобразуют enum-состояния в пользовательский текст и SF Symbols.

### `OnboardingView.swift`

Первый запуск из трёх страниц.

- `body` управляет номером страницы и завершает onboarding.
- `welcome`, `choosePet`, `firstSession` — три вычисляемых SwiftUI-поддерева.
- `OnboardingPage<Content>` — generic-контейнер с заголовком, текстом и
  произвольным `@ViewBuilder`-контентом.

### `PetCollectionView.swift`

Управление коллекцией и активной группой.

- `body` строит список, редактор и действия удаления/добавления.
- `partyHeader` объясняет лимит активной группы.
- `partyPreview` показывает до трёх выбранных питомцев.
- `collection` и `petRow(_:)` строят строки коллекции, переключатель активности,
  выбор ведущего, редактирование и удаление.
- `addButton` создаёт черновик нового питомца.
- `PetEditorRoute` — модель навигации в редактор.
- `PetProfileEditor` — модальный редактор нового или существующего профиля;
  `onSave` передаётся closure, поэтому экран не зависит от конкретного store.

### `Sheets.swift`

Набор небольших модальных экранов.

- `SessionComposerView` — старый редактор длительности. `durationButton`,
  `durationTitle` и `formattedDuration` управляют preset/custom временем.
- `PetEditorView` — редактор ведущего пса.
- `PetPicker` — общий компонент выбора имени, вида, подвида, окраса и цвета.
- `variantPicker` и `variantButton` — горизонтальный выбор породы/варианта.
- `customColorEnabled` и `customColor` — вручную созданные `Binding`, которые
  переводят SwiftUI `Color` в сохраняемый RGB.
- `speciesButton` — карточка вида; одновременно сбрасывает неподходящую породу.
- `SettingsView` — редактирует haptics и Reduce Motion в локальном draft.
- `SessionSummaryView` — итог завершённой сессии.

### `HabitatEditorView.swift`

Экран выбора темы и до шести жителей.

- `HabitatEditorView.body` собирает preview, picker темы, picker питомцев,
  статусы и кнопку сохранения.
- `themeButton` и `residentButton` строят выбираемые карточки.
- `selectedPets` нормализует ID и соблюдает лимит.
- `toggleSelection` добавляет/убирает жителя, но не оставляет вольер пустым.
- `sectionHeader` — общий заголовок секций.
- `HabitatEditorCanvas` — живая сцена внутри приложения. `TimelineView`
  периодически получает дату, `PetHabitatEngine` вычисляет позиции, а
  `PetAnimationLibrary` выбирает кадр.
- `statusTitle` переводит статус в подпись; `pixelFence` рисует забор.
- `HabitatThemeBackdrop` и `HabitatThemeSwatch` рисуют фон и миниатюру темы.
- `HabitatResidentStatusRow` показывает питомца и три vital-показателя;
  `overallStatus`, `statusColor`, `percent` формируют понятный статус.
- `HabitatStatusDots` — компактная версия vital-индикаторов.
- `HabitatThemePresentation` — presentation-only палитры пяти тем.
- Debug preview в конце файла создаёт тестовых жителей без запуска приложения.

### `PlayYardView.swift`

Полноэкранная игровая. В отличие от WidgetKit, она может иметь настоящий цикл
обновления, пока приложение находится на экране.

- `PlayYardView` владеет `PlayYardSimulation`, рисует актёров и мяч.
- `yardBall` подключает `DragGesture`; `hint` показывает подсказку.
- `PlayYardPetFigure` — единственный адаптер между физикой и `PetArtwork`.
- `YardBall` и `PlayYardBackdrop` рисуют игровую площадку.
- `PlayYardMotionRules.shouldJump` решает, можно ли прыгать;
  `launchVelocity` рассчитывает вертикальную скорость по формуле движения.
- `PlayYardSimulation.Actor` хранит физическое состояние одного питомца.
- `Frame` — полный отображаемый кадр симуляции.
- `configure` задаёт размер комнаты; `start` создаёт `CADisplayLink`;
  `stop` его уничтожает; `setReduceMotion` меняет FPS; `reset` расставляет
  объекты заново.
- `dragBall` измеряет скорость жеста; `throwBall` формирует начальный вектор.
- `update(_:)` — игровой tick. Он ограничивает `deltaTime`, обновляет мяч,
  питомцев и одним присваиванием публикует новый `Frame`.
- `advanceBall` применяет гравитацию, отскок, границы и трение.
- `advancePets` ведёт питомцев к мячу, запускает прыжок, меняет позы и кадры.
- `clampFrameToRoom`, `groundY`, `clampedBallPoint`, `movementSpeed` —
  геометрические вспомогательные функции.
- `CGVector.limited(to:)` ограничивает длину вектора без изменения направления.

## 7. Общий код приложения и extension: `PetIsland/Shared`

### `PetActivityAttributes.swift`

Контракт данных между приложением и ActivityKit extension.

- `PetActivityIdentity` — небольшой профиль, безопасный для payload.
- `PetActivityAttributes` — неизменяемые атрибуты сессии;
  `ContentState` — обновляемая часть Live Activity.
- `PetLiveAction` — действия expanded Dynamic Island; `pose` сопоставляет
  действие с позой.
- `PetLiveMotionSequence.snapshots` создаёт конечную последовательность кадров;
  `spriteStep` выбирает одну из двух фаз бега; `interpolatedSnapshots` строит
  промежуточные положения для игры.
- `PetLiveActionIntent.perform()` находит Activity по ID, отправляет кадры через
  `activity.update` и делает короткие `Task.sleep` между ними.
- `LiveActivitySmokeAttributes` существует только в Debug для диагностики.

### `PetLifeState.swift`

Одиночная, долговечная модель питомца для MVP и medium-виджета.

- `PetPlacement` гарантирует одно авторитетное местоположение.
- `PetVitals.projected` рассчитывает естественное уменьшение сытости, счастья и
  энергии; `clamp` держит значения в `0...1`.
- `PetLifeState` хранит профиль, placement, anchors времени, seed поведения и
  последнее бросание мяча.
- `initial` создаёт стабильное начальное состояние.
- `materializeVitals` фиксирует расчётные vitals перед изменением;
  `move` меняет место; `throwBall` меняет настроение и запускает fetch-сцену.
- `init(from:)` задаёт defaults при чтении старой схемы; `seed(for:)` получает
  стабильный seed из UUID.
- `PetLifePresentation` — готовая для рендера, но не сохраняемая проекция.
- `PetLifeEngine.presentation` — чистая функция `state + date → presentation`.
- `ballPresentation` рассчитывает десятисекундную историю мяча, погони, прыжка
  и приземления; `mixed` — детерминированное перемешивание seed.
- `PetLifeStore.load/save/update` синхронно и под `NSLock` работает с App Group
  UserDefaults; `loadUnlocked/saveUnlocked` — реализации без повторного lock.
- `PetLifeStoreError` переводит ошибки хранилища в понятный текст.

### `PetHabitatState.swift`

Модель многопитомцевого вольера.

- `HabitatTheme` — стабильный строковый ID темы. Неизвестная тема безопасно
  декодируется как meadow.
- `PetHabitatState` хранит жителей, ведущего Dynamic Island, epoch и seed.
- `setTheme`, `setResidents`, `addResident`, `removeResident` — проверяемые
  мутации с увеличением `revision`.
- `setDynamicIslandLead` удаляет ведущего из вольера;
  `returnDynamicIslandLeadToHabitat` возвращает его при наличии места.
- `reconcile` удаляет ID несуществующих профилей; `normalize` убирает дубли.
- `HabitatPetProjection` — готовые координаты, поза, статус и глубина рендера.
- `PetHabitatEngine.projections` распределяет питомцев по дорожкам.
- `stateFrame` реализует цикл watching → walk/run/fly → play → rest → sleep.
- `horizontalTrack` разводит нескольких жителей по разным горизонтальным
  сегментам; `verticalPosition` — по глубине.
- `pose`, `cadence`, `opposite`, `seed`, `mixed` — helpers state machine.
- `SharedHabitatResident` — профиль и vitals одного жителя в App Group.
- `SharedPetHabitat.initial/reconcile` создаёт и нормализует полный payload.
- `PetHabitatStore.load/save/update` атомарно работает с App Group и backup.

### `PetPixelArtwork.swift`

Единый слой рендера животных.

- extensions `PetSpecies`, `PetCoat`, `PetBreed` добавляют локализованные имена.
- `PetColors.resolve` выбирает палитру или строит её из custom RGB.
- `PetAnimationClip` хранит имена кадров и скорость. `frameIndex` безопасно
  зацикливает время, `frameName` возвращает asset для времени или шага.
- `PetArtwork` — основной SwiftUI-компонент питомца. Он выбирает спрайт,
  отражает его по X и при необходимости добавляет lift-анимацию.
- `ImportedPetSprite` загружает `Image` из asset catalog, включает nearest
  interpolation и накладывает custom color через mask.
- `PetAnimationLibrary.clip` выбирает конкретные assets по виду, варианту и
  позе; остальные private-функции задают скорость, префиксы и fallback-кадры.
- `PetPortraitArtwork` — compatibility wrapper для больших экранов.
- `PixelPetCanvas` и `PixelPetLibrary` — старый code-drawn fallback из строковых
  пиксельных матриц. Он полезен как запасной renderer, но основные виды уже
  используют PNG assets.
- `PetHabitatView` — крупная декоративная сцена для onboarding/editor.
- `oppositeDirection` разворачивает направление.

## 8. Widget и Dynamic Island: `PetIslandLiveActivity`

### `PetIslandWidgetBundle.swift`

Точка входа extension.

- `PetIslandWidgetBundle.body` регистрирует `PetEnclosureWidget` и
  `PetLiveActivityWidget`.
- `LiveActivitySmokeWidget` в Debug — минимальная диагностическая Live Activity.

### `PetEnclosureWidget.swift`

Medium Home Screen widget.

- `ThrowBallIntent.perform` атомарно вызывает `state.throwBall`, затем просит
  WidgetKit перечитать timeline.
- `PetEnclosureEntry` — один заранее рассчитанный момент виджета.
- `PetEnclosureProvider.placeholder` даёт заглушку;
  `getSnapshot` строит preview; `getTimeline` создаёт расписание.
- `entry` объединяет `PetLifeEngine` и `PetHabitatEngine`;
  `timelineDates` добавляет короткие точки fetch-сцены и редкие ambient-точки.
- `PetEnclosureWidget` описывает kind, provider и поддерживаемый medium-размер.
- `PetEnclosureView` рисует фон, жителей, мяч, header/footer и away-state.
- `effectivePose/direction/position/verticalPosition/step` временно переводят
  всех жителей в общую fetch-сцену.
- `WidgetPetArtwork: Animatable` позволяет SwiftUI интерполировать числовую
  фазу между timeline entries.
- `WidgetSpriteAtlasLibrary.descriptor` выбирает единый atlas движения.
- `WidgetAtlasSprite` вырезает нужный кадр из atlas через `Canvas`, поэтому
  WidgetKit видит стабильный image node.
- `WidgetHabitatPalette.palette` выбирает цвета темы.
- `VitalsStrip` и `VitalMeter` рисуют показатели состояния.

Важно: timeline не является игровым циклом. iOS может объединить или задержать
entries. Непрерывная физика существует только в `PlayYardSimulation`.

### `PetLiveActivityWidget.swift`

Все варианты Live Activity.

- `PetLiveActivityWidget.body` описывает Lock Screen, expanded, compact и
  minimal Dynamic Island.
- `resolvedSnapshot`, `resolvedPose`, `status`, `symbol`, `deepLink` готовят
  данные для системного UI.
- `CompactTimerPet` выбирает сон для stale/AOD, timer-font для активного острова
  и обычный `PetArtwork` как fallback.
- `LiveTimerGlyphPet` показывает системный `Text(..., style: .timer)` шрифтом,
  где последняя цифра является питомцем; остальные цифры обрезаются.
- `LockScreenPetView` строит карточку экрана блокировки и принудительный сон
  при reduced luminance.
- `LiveTimerPetFontRegistry` регистрирует TTC через CoreText и сопоставляет
  профиль с PostScript-именем нужного font face.
- `ActivityPetTrack` вычисляет позицию на expanded/Lock Screen дорожке.
- `ActivityAnimatedPet` выбирает одну из двух фаз gait.
- `accent(for:)` получает акцентный цвет питомца.

## 9. Тесты: `PetIslandTests`

### `PetDomainTests.swift`

Проверяет:

- цикл и phase offset `PetAnimationClip`;
- совместимость имён assets и вариантов животных;
- ограничение координат `PetSnapshot`;
- детерминизм `PetBehaviorMachine` и сон просроченной сессии;
- миграцию старых профилей без breed и schema v1 → v2;
- нормализацию имени, progress и историю;
- `FilePetStore`-совместимый in-memory round trip;
- лимит активной группы и запрет удаления последнего питомца;
- размер ActivityKit payload;
- двухкадровый бег/полёт Dynamic Island и финальный сон;
- отталкивание от границ;
- `PetLifeState`, deterministic presentation и fetch-сцену;
- физические правила прыжка игровой;
- наличие run/jump/landing и смены кадров в widget fetch.

`LegacyPersistedAppState` — test fixture, который кодирует старую schema v1.

### `PetHabitatStateTests.swift`

Проверяет:

- уникальность и лимит жителей;
- взаимное исключение вольера и Dynamic Island;
- миграцию старого payload и неизвестной темы;
- детерминированные координаты и отсутствие столкновений для шести питомцев;
- отсутствие ведущего Dynamic Island в projection;
- достижимость движения, игры и сна в state machine.

`makePets` создаёт fixtures, `LegacyHabitatState` имитирует старый формат.

## 10. Скрипты обработки графики

### `Design/tools/build_live_activity_timer_fonts.py`

Генерирует `PetIslandTimerPets.ttc` для compact Dynamic Island.

- `PetFontSpec` связывает PostScript name с тремя PNG-кадрами.
- `locate_asset` ищет один asset по имени.
- `normalized_png` обрезает прозрачные поля и помещает рисунок на общий canvas.
- `pixel_image` переводит рисунок в сетку 48×39, фиксирует alpha и добавляет
  внешний контур, не меняя внутреннюю фигурку.
- `silhouette_glyph` создаёт монохромный fallback outline.
- `sbix_png` делает цельный bitmap strike. Это исправляет потерю отдельных
  TrueType-контуров в CoreText.
- `build_face` создаёт один font face: цифры 0...6 чередуют бег, 7...9 спят.
- `build_mask_face` оставлен как инженерный эксперимент и не поставляется.
- `main` собирает 19 faces в TTC.

### `Design/tools/build_widget_atlases.py`

Собирает кадры движения каждого вида в одну горизонтальную PNG-ленту.
`image_for_asset` читает кадр, `write_atlas` объединяет изображения и создаёт
Xcode `imageset`, `main` обрабатывает таблицу `ATLASES`.

### `Design/tools/clean_isolated_pixels.py`

Удаляет маленькие отдельные артефакты далеко от основного спрайта.
`components` ищет connected components, `bounds` и `box_distance` измеряют их,
`main` сохраняет очищенную копию. Скрипт не должен автоматически удалять
детали рядом с основной фигуркой.

### `Design/tools/slice_sprite_sheet.py`

Режет лист из шести поз на `idle`, два шага, `jump`, `play`, `sleep`.
`alpha_bbox` находит видимую область, `normalize_frames` выравнивает масштаб и
baseline, `write_image_set` создаёт Xcode asset, `main` читает CLI-аргументы.

### `Design/tools/slice_motion_sheet.py`

Похож на предыдущий скрипт, но режет произвольное количество последовательных
кадров движения, например восемь фаз полёта ара.

### `Scripts/build_pet_assets.mjs`

Node.js/Sharp-скрипт для портретов из общего source sheet. Он делит сетку,
удаляет связанный светлый фон, удаляет далёкие маленькие компоненты, вычисляет
alpha bounds и пишет `PetPortraits.imageset`.

### `Scripts/import_vscode_pets_assets.mjs`

Воспроизводимый импорт разрешённых GIF из зафиксированного commit vscode-pets.
Он может читать локальный checkout или raw GitHub, извлекает кадры без
перерисовки, создаёт Xcode assets и `PetSpritesManifest.json`. При изменении
списка imports обязательно обновлять `THIRD_PARTY_NOTICES.md` и проверять
лицензию каждого media asset отдельно.

## 11. Xcode, конфигурация и ресурсы

### `PetIsland.xcodeproj/project.pbxproj`

Текстовая база проекта Xcode: targets, build phases, target membership, ссылки
на файлы, deployment target, Bundle ID и embedding extension. Редактировать
вручную можно, но безопаснее через Xcode или очень маленькими проверяемыми
патчами.

### `PetIsland.xcodeproj/xcshareddata/xcschemes/*.xcscheme`

- `PetIsland.xcscheme` — сборка/запуск основного приложения и тестов.
- `PetIslandLiveActivity.xcscheme` — запуск extension preview; не используется
  для обычного старта приложения.

### `Info.plist`

- `PetIsland/Info.plist` — свойства приложения, URL scheme и поддержка Live
  Activities.
- `PetIslandLiveActivity/Info.plist` — описание WidgetKit extension и fonts.

### `*.entitlements`

Подписанные разрешения targets. Оба файла должны содержать одинаковый App
Group. Несовпадение не является обычной runtime-ошибкой: оно часто ломает
provisioning или приводит к разным UserDefaults.

### Asset catalogs

- `PetIsland/Assets.xcassets` — AppIcon, AccentColor и крупные портреты.
- `SharedResources/PetSprites.xcassets` — общие PNG-кадры и widget atlases.
- каждый `*.imageset/Contents.json` сообщает Xcode имя PNG, idiom и scale;
  сотни таких файлов механически описывают assets и не содержат поведения.
- `PetSpritesManifest.json` фиксирует происхождение импортированных кадров,
  commit, состояния и исходные задержки.

### `Localizable.xcstrings`

String Catalog локализации. Xcode хранит в нём переводы и состояние проверки
строк. Строковый литерал в `Text("...")` может автоматически ссылаться сюда.

### Fonts

- `PetIslandLiveActivity/Resources/PetIslandTimerPets.ttc` — поставляемая
  коллекция bitmap-font faces для Dynamic Island.
- `PetTimerFaces/` — локальные диагностические TTF, создаваемые генератором;
  они игнорируются Git и не включаются в target.

## 12. Документы репозитория

- `README.md` — публичное описание, возможности, запуск и ограничения.
- `XCODE_GUIDE_RU.md` — пошаговая работа в Xcode.
- `CODE_GUIDE_RU.md` — текущий учебный путеводитель по коду.
- `ROADMAP.md` — следующие продуктовые этапы.
- `CHECKPOINT.md` — зафиксированный проверяемый объём MVP.
- `KNOWN_ISSUES.md` — ограничения WidgetKit, ActivityKit, signing и QA.
- `APP_STORE.md` — checklist TestFlight/App Store.
- `PRIVACY.md` — проект политики конфиденциальности.
- `THIRD_PARTY_NOTICES.md` — происхождение и лицензии сторонних материалов.
- `LICENSE` — MIT-лицензия собственного кода проекта.
- `Design/TIMER_FONT_AUDIT.md` — история и проверка timer-font механизма.
- `Design/VSCODE_PETS_MECHANICS.md` — заметки об адаптации механик референса.
- `Design/*/PROMPTS.md` — история требований к создававшимся вариантам арта.
- `Design/*.png` и подпапки previews/sources — исходники и контрольные листы;
  они не исполняются приложением, пока не помещены в asset catalog.

## 13. Словарь Swift для C++/Python-разработчика

| Swift | Смысл | Аналогия |
| --- | --- | --- |
| `let` | неизменяемая привязка | `const` в C++; обычное имя в Python по соглашению |
| `var` | изменяемая переменная | обычная переменная |
| `struct` | value type, копируется по значению | C++ struct с value semantics; ближе к frozen/data model, чем Python object |
| `class` | reference type | C++/Python class |
| `final class` | запрещено наследование | C++ `final` |
| `enum` | tagged union с методами | `enum class` + `std::variant`; Python `Enum` слабее |
| `protocol` | контракт поведения | pure abstract class/concept; Python Protocol |
| `extension` | добавляет методы существующему типу | свободные helper-функции/категории |
| `actor` | reference type с изолированным состоянием | объект с собственной serial queue/mutex |
| `Optional<T>` / `T?` | значение либо `nil` | `std::optional<T>` / `None` |
| `if let x` | распаковать Optional | `if (opt)` + `*opt`; `if x is not None` |
| `guard ... else` | ранний выход при нарушении условия | inverted `if (...) return` |
| `switch` | исчерпывающий pattern matching | switch + `std::visit`; Python `match` |
| `func` | функция/метод | функция |
| `init` | инициализатор | constructor / `__init__` |
| `deinit` | финализация reference type | destructor; не стоит считать точным `__del__` |
| `mutating func` | метод структуры меняет `self` | non-const метод value type |
| `static` | член типа | C++ static; Python class attribute/method |
| computed property | `var x: T { ... }` без хранения | getter/property |
| `get` / `set` | явный getter/setter | property accessors |
| `private(set)` | читать можно, писать только внутри типа | public getter + private setter |
| `@discardableResult` | разрешает игнорировать return value | отключает warning |
| `throws` | функция может бросить ошибку | C++ exception / Python raise |
| `try`, `try?` | проброс ошибки / превратить ошибку в `nil` | try; `try/except: None` |
| `async` / `await` | structured concurrency | coroutine в C++/Python asyncio |
| `Task` | асинхронная задача | `std::jthread` не точен; ближе к asyncio Task |
| `@MainActor` | изоляция на main executor | выполнять UI-код на main thread |
| `Sendable` | тип безопасно передавать между concurrency domains | compile-time thread-safety contract |
| `Codable` | `Encodable & Decodable` | сериализуемая dataclass/JSON model |
| `Identifiable` | имеет стабильное `id` | модель с primary key |
| `Hashable` | можно использовать в Set/Dictionary | `std::hash` / `__hash__` |
| `Equatable` | поддерживает `==` | operator== / `__eq__` |
| `CaseIterable` | enum предоставляет `allCases` | список всех enum values |
| `some View` | opaque return type: конкретный тип скрыт | похоже на `auto`, но тип один и известен компилятору |
| `any PetStore` | existential: значение любого типа, реализующего protocol | pointer/reference на интерфейс |
| generic `<T>` | параметр типа | C++ template / Python Generic |
| closure `{ value in ... }` | анонимная функция | lambda |
| trailing closure | closure после `)` | синтаксический сахар lambda/callback |
| `$profile.name` | projected value property wrapper | Binding/reference на observable property |
| key path `\.id` | типобезопасная ссылка на property | pointer-to-member / `operator.attrgetter` |
| `inout` | функция может изменить аргумент вызывающего | `T&` в C++; явной прямой аналогии в Python нет |
| `defer` | выполнить при выходе из scope | RAII scope guard / `finally` |
| `#if DEBUG` | условная компиляция | `#ifdef DEBUG` |
| `@unknown default` | fallback для будущих enum cases SDK | defensive default при расширяемом API |

### Property wrappers, которые встречаются в UI

| Wrapper | Кто владеет значением | Когда использовать |
| --- | --- | --- |
| `@State` | текущий View | маленькое локальное состояние экрана |
| `@StateObject` | текущий View | View создаёт и удерживает reference-model |
| `@ObservedObject` | внешний владелец | View только наблюдает переданный controller |
| `@Published` | `ObservableObject` | изменение должно обновить наблюдающие Views |
| `@Binding` | другой View | двусторонний доступ к чужому `@State` |
| `@Environment` | SwiftUI environment | dismiss, scenePhase, accessibility, openURL |
| `@Parameter` | App Intent | параметр системной команды |

### Частые конструкции из проекта

`if let` распаковывает Optional:

```swift
if let activity {
    await activity.update(...)
}
```

Это сокращение для `if let activity = activity`.

`guard` оставляет основной сценарий без глубокой вложенности:

```swift
guard operation == .idle else { return }
```

Closure с изменяемым аргументом:

```swift
try PetLifeStore.update { state in
    state.throwBall()
}
```

`update` принимает `(inout PetLifeState) -> Void`, поэтому closure получает
временную изменяемую ссылку на состояние, а store после closure сохраняет его.

SwiftUI result builder:

```swift
var body: some View {
    VStack {
        Text("Pet Island")
        Button("Play") { ... }
    }
}
```

Это не обычная последовательность вызовов `addWidget`. `@ViewBuilder`
компилирует декларативный блок в типизированное дерево Views.

## 14. Как самостоятельно разбирать незнакомую функцию

Используй один и тот же алгоритм:

1. Найди входные параметры и return type.
2. Проверь, есть ли `async`, `throws`, `mutating`, `@MainActor`.
3. Отметь все ранние `guard` — это предусловия.
4. Отдельно выпиши изменения состояния: присваивания, `append`, `removeAll`.
5. Найди внешние эффекты: файл, App Group, `Activity.request`, widget reload.
6. Посмотри, кто вызывает функцию через **Find Call Hierarchy** в Xcode.
7. Найди unit-тест с похожим именем и проверь ожидаемый результат.

Для эксперимента удобно поставить breakpoint на `placePet(in:)`, затем выбрать
Dynamic Island и пошагово пройти цепочку:

```text
HomeView.placementButton
→ PetSessionController.placePet
→ startSession
→ requestLiveActivity
→ ActivityKit
→ PetLiveActivityWidget
```

А для виджета с мячом:

```text
ThrowBallIntent.perform
→ PetLifeStore.update
→ PetLifeState.throwBall
→ WidgetCenter.reloadTimelines
→ PetEnclosureProvider.getTimeline
→ PetLifeEngine.presentation
→ PetEnclosureView
```

Эти две цепочки дают хорошее понимание почти всех ключевых технологий проекта:
SwiftUI state, async/await, App Group, App Intents, WidgetKit и ActivityKit.
