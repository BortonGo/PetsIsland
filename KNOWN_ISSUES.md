# Pet Island — известные ограничения и риски MVP

Статусы ниже относятся к новой архитектуре с одним псом, medium-виджетом и
Live Activity. Результаты старого многопитомцевого прототипа не считаются
проверкой этой интеграции.

## PI-001 — визуальная проверка medium-виджета ещё не выполнена

Статус: **код собран, ожидает ручной проверки в галерее**

Сборка подтверждает, что widget extension встроен в приложение и App Intent
извлечён Xcode. Нужно вручную подтвердить, что medium family доступна в галерее,
а timeline provider читает актуальное состояние пса.
Приложение не может автоматически положить виджет на Home Screen: пользователь
добавляет его через системную галерею.

## PI-002 — WidgetKit не обеспечивает непрерывную анимацию

Статус: **системное ограничение, исправлению не подлежит**

Widget extension не остаётся запущенным, пока виджет виден. WidgetKit строит
timeline, распределяет reload по системному бюджету и может показать entry
позже указанной даты. Поэтому пёс не будет бесконечно бегать в medium-виджете.
Поддерживаемое поведение MVP — спокойная поза и короткая реакция после нажатия
мяча или другого значимого изменения состояния.

Не следует добавлять частый polling, фоновые таймеры или фиктивный background
mode: это не делает widget realtime и создаёт риск энергопотребления/App Review.

## PI-003 — App Group и signing легко рассинхронизировать

Статус: **требует ручной настройки для каждой Team**

Приложение и extension работают в разных процессах. Для общего состояния оба
targets должны иметь один App Group, одну Team и provisioning profiles с этим
entitlement. Suite identifier в коде должен совпасть с App Group точно.

Типичный симптом ошибки: приложение сохраняет выбор, но виджет показывает
placeholder/default; либо установка завершается ошибкой подписи. После смены
Bundle Identifier необходимо заново проверить App Group в обоих targets.

## PI-004 — Live Activity не является обычным Home Screen widget

Статус: **системное различие**

Live Activity создаётся приложением через ActivityKit; её не добавляют из
галереи виджетов. На iPhone с Dynamic Island доступны compact/minimal/expanded
presentations, а на поддерживаемом iPhone без Dynamic Island — Lock Screen
presentation. Схему extension нельзя использовать как замену запуску основного
приложения.

## PI-005 — реакция в Dynamic Island короткая и не гарантирует каждый кадр

Статус: **системное ограничение, требуется real-device QA**

Live Activity получает новое состояние от приложения/App Intent, а WidgetKit
анимирует изменение. Длительность анимаций ограничена двумя секундами; система
может сократить или не показать отдельные переходы. На Always-On Display
анимации отключаются ради батареи, поэтому MVP показывает статичную спящую позу.

В compact Dynamic Island экспериментально используется публичный системный
`Text(..., style: .timer)` с собственным пиксельным шрифтом питомцев: семь
секунд чередуются две позы, затем три секунды показывается сон. Таймер является
самим питомцем, а не маской обычной картинки. Цикл и автоматическая смена
кадров после закрытия приложения подтверждены в iOS Simulator 26.5.
Поведение на реальном iPhone и Always-On нужно проверить отдельно; приватные
clock API не используются.

## PI-006 — интерактивная кнопка может потребовать разблокировку

Статус: **ожидаемое поведение iOS**

Кнопки widget и Live Activity работают через App Intents. На заблокированном
устройстве iOS может потребовать аутентификацию перед выполнением действия.
После intent состояние нужно сохранить в App Group и запросить у WidgetKit
обновление timeline; UI не должен полагаться на долговременный процесс intent.

## Матрица незавершённой проверки

- [ ] medium-виджет появляется после чистой установки;
- [ ] состояние синхронизируется через App Group;
- [ ] мяч работает в medium widget;
- [ ] Live Activity запускается и корректно завершается при смене места;
- [ ] compact и expanded Dynamic Island проверены на реальном iPhone;
- [ ] Lock Screen и Always-On проверены на совместимом устройстве;
- [ ] Reduce Motion и VoiceOver проверены вручную;
- [ ] поведение после перезагрузки устройства задокументировано.

Справка Apple:

- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Timeline](https://developer.apple.com/documentation/widgetkit/timeline)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [ActivityKit](https://developer.apple.com/documentation/activitykit/)
