# Pet Island — выпуск в App Store

Проверено по документации Apple **17 октября 2026 года**. Контакт автора: **bortone52@yandex.ru**.

Это инструкция для владельца проекта. Код и локальные проверки не заменяют регистрацию в Apple, подписанный архив, Sandbox/TestFlight и проверку App Review. Сейчас платного Apple Developer Account и опубликованного сайта ещё нет. Приложение никуда не загружалось, реальные платежи не выполнялись.

## 1. Сначала реши вопрос регистрации из России

Членство Apple Developer Program стоит **99 USD в год либо местный эквивалент**, окончательная сумма отображается у Apple. Для Individual нужны реальные ФИО, адрес, совершеннолетие и Apple Account с двухфакторной аутентификацией. Имя физического лица будет именем продавца в App Store. D‑U‑N‑S для Individual не нужен. [Регистрация Apple](https://developer.apple.com/help/account/membership/program-enrollment/)

**Не покупай подарочную карту для оплаты членства.** В актуальной инструкции Apple баланс Apple Account для этой покупки не принимается; исключение указано для разработчиков в Индии. Apple также предупреждает, что регистрация через приложение может быть ограничена в отдельных регионах. [Оплата членства в Apple Developer](https://developer.apple.com/help/account/membership/enrolling-in-the-app)

С 1 апреля 2026 Apple сообщает о недоступности оплаты с российских мобильных счетов; обычные покупки в российском App Store возможны при наличии остатка баланса. Это **не означает**, что этим остатком можно оплатить Developer Program. Поэтому старые инструкции «пополнить с МТС/Билайн и купить подписку» здесь не подходят. [Официальное сообщение Apple](https://support.apple.com/en-gb/126891)

Порядок действий:

1. Включи 2FA у своего Apple Account; проверь реальные ФИО, телефон и адрес.
2. Открой [Apple Developer Support](https://developer.apple.com/contact/) → Membership and Account → Program Enrollment. До оплаты уточни доступность регистрации и способ оплаты именно для твоих данных и страны.
3. Можно отправить этот текст через форму поддержки; секреты и реквизиты карты не нужны:

   > Hello. I reside in Russia and would like to enroll in the Apple Developer Program as an Individual using my real identity and address. I have not purchased membership yet. Which enrollment and payment methods are currently supported for my account? Apple Account balance is not accepted for membership, and Russian mobile billing is unavailable. Please also clarify whether I can sign the Paid Apps Agreement and receive proceeds from optional consumable In-App Purchase tips, and which banking requirements apply. I do not want to use an incorrect country or another person's developer account.

4. Если Apple подтверждает доступность, используй предложенный ими путь: приложение **Apple Developer → Account → Enroll Now → Individual → проверка личности → соглашение → оплата**, либо веб-регистрацию, если поддержка направит туда. Итоговый статус должен быть Active, а не только списание денег.
5. Если у тебя есть собственный иностранный платёжный инструмент, заранее уточни у Apple, допустим ли он для твоей регистрации и платёжного адреса. Наличие карты само по себе не гарантирует приём платежа.
6. Если поддержка не предлагает доступного способа, на текущих данных регистрацию завершить нельзя. Не подменяй страну/личность и не передавай посреднику Apple Account. Локальная работа над приложением может продолжаться до решения этого вопроса.

**Оплата членства и получение дохода — разные задачи.** Для дохода нужны действующее Paid Apps Agreement, налоговые формы и банковский счёт зарегистрированного лица. Если банк отсутствует в App Store Connect, Apple может не поддерживать выплаты в него. Условия для конкретного банка подтверждает Apple; работоспособность российской карты/счёта здесь не обещается. [Банковские данные](https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information), [налоговые формы](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information), [доступность банка](https://developer.apple.com/help/app-store-connect/reference/reporting/banking-information)

## 2. Что подготовлено в проекте

- «Настройки → Язык приложения»: русский и английский, переход к штатному выбору языка **только этого приложения** в iOS. Язык iPhone менять не требуется. Если пункта «Язык» нет, добавь второй язык в «Основные → Язык и регион», сохрани текущий основной язык и вернись в настройки Pet Island. iOS может перезапустить приложение после выбора. Дополнены переводы счётчиков, запасов и шагов; автоматическая проверка обнаруживает пропуски русского перевода во всех каталогах.
- «Настройки → Поддержать автора»: добровольные разовые платежи через **StoreKit 2**, без подписки и игровых преимуществ. Цена и название поступают из App Store. При отсутствии товаров доступна повторная загрузка; остальное приложение работает.
- Обработка отмены, ограничения покупок, ожидания подтверждения, недостоверной транзакции и отложенного получения покупки после запуска. Платёжный код не меняет сохранения, монеты или питомцев.
- «Настройки → Помощь и конфиденциальность»: локальная политика, контакт автора, копирование адреса при отсутствии почтового приложения.
- `SharedResources/PrivacyInfo.xcprivacy` включён в приложение и расширение. Объявлено отсутствие отслеживания и сборов данных; UserDefaults используются для миграции собственных данных App Group (`1C8F.1`).
- Экспортное шифрование: в Info.plist отмечено отсутствие non-exempt encryption. В текущей версии нет собственного криптографического протокола или SDK; системная обработка StoreKit не требует добавления собственного шифрования.
- У взрослого льва и львицы четыре ключевых кадра ходьбы и бега; на DI и блокировке используются два читаемых основных кадра. Обновлены соответствующие наряды, шрифты и бег в аркаде. Остальные питомцы сохранены.
- `Configuration/PetIslandTips.storekit` и схема `PetIslandTips` предназначены для локальной отладки. Тестовая конфигурация не включается в релиз приложения.
- Готовые страницы сайта: `Docs/AppStoreSite/`. Они пока **не опубликованы**.

Итоги выполненных проверок и ограничения смотри в [RELEASE-READINESS-2026-10-17.md](RELEASE-READINESS-2026-10-17.md).

## 3. Опубликуй страницы поддержки и конфиденциальности

Домен покупать необязательно. Один из вариантов — отдельный публичный репозиторий GitHub Pages только для сайта:

1. Создай у себя репозиторий `pet-island-support`.
2. Положи **содержимое** `Docs/AppStoreSite/` в корень этого репозитория. Исходники приложения и промежуточные файлы туда не нужны.
3. В Settings → Pages выбери публикацию из ветки `main`, папка `/ (root)`.
4. Дождись адреса, который выдаст GitHub. Открой его в приватном окне и на iPhone: без авторизации должны работать главная, политика, email и переключение языка.
5. В App Store Connect укажи этот адрес как **Support URL**, а адрес `privacy.html` — как **Privacy Policy URL**. Не вставляй пример с чужим логином.
6. Проверь, что описание на сайте соответствует сборке. При добавлении рекламы, аналитики или серверов политику и App Privacy нужно пересмотреть до выпуска.

Пошаговая настройка Pages: [документация GitHub](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site).

Apple требует доступную политику и контакт поддержки. В приложении политика работает и без сети. [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

## 4. Зарегистрируй идентификаторы и подпись

Текущие значения:

| Назначение | Значение |
| --- | --- |
| Приложение | `org.bortongo.PetIsland` |
| Расширение | `org.bortongo.PetIsland.LiveActivity` |
| App Group | `group.org.bortongo.PetIsland` |
| Версия / сборка | `1.0` / `1` |
| Минимальная система | iOS 17.0 |
| Устройства | iPhone, портретная ориентация |

После активации членства:

1. В Xcode → Settings → Accounts добавь свою команду Developer Program.
2. Открой `PetIsland.xcodeproj`. Для **обоих** targets (`PetIsland`, `PetIslandLiveActivity`) выбери платную команду, Automatically manage signing.
3. Зарегистрируй два App ID и App Group в аккаунте; группа должна быть включена у обоих идентификаторов. В основном target включи In-App Purchase.
4. Сохраняй идентификаторы, если Apple разрешает зарегистрировать их на твоей команде. Сейчас в проекте записана команда `J93HMY294J`; проверь её соответствие после вступления.
5. Если Apple требует другой Bundle ID или App Group, меняй согласованно настройки targets, entitlements и константы хранилищ. **Не меняй их вслепую:** другая группа/идентификатор может лишить новую установку доступа к старому острову. Сначала экспортируй копию на iPhone.
6. В App Store Connect → Apps → «+» создай iOS-приложение, выбери зарегистрированный Bundle ID. SKU можно задать `pet-island-ios`; это внутренний идентификатор. Bundle ID после загрузки менять нельзя без отдельного приложения.

## 5. Настрой добровольную поддержку

Выбран **Apple In-App Purchase**, а не ЮKassa, Stripe или СБП внутри приложения. Для обычной глобальной версии это штатный путь добровольных чаевых разработчику по §3.1.1. Региональные исключения Apple не применяются автоматически; стороннюю оплату сейчас не добавляем. [Правила Apple](https://developer.apple.com/app-store/review/guidelines/)

В Business заполни Paid Apps Agreement, налоги и банковские данные. Затем Apps → Pet Island → Monetization → In-App Purchases создай **Consumable**:

| Product ID — копировать точно | RU | EN | Локальная тестовая цена |
| --- | --- | --- | --- |
| `org.bortongo.PetIsland.tip.small` | Маленькое спасибо | A little thank-you | $0.99 |
| `org.bortongo.PetIsland.tip.medium` | Тёплое спасибо | A warm thank-you | $2.99 |
| `org.bortongo.PetIsland.tip.large` | Большое спасибо | A big thank-you | $4.99 |

Цены в последнем столбце — **тестовые ориентиры**, они не настраивают App Store Connect. Реальные цены, регионы и доступность выбирает владелец в консоли. Приложение покажет локализованную цену Apple. Product ID в коде и консоли должны совпадать; при смене Bundle ID согласованно пересмотри эти ID до первой публикации.

Описание для всех товаров:

- RU: «Добровольная разовая поддержка автора. Без подписки, монет и дополнительных функций.»
- EN: “An optional one-time tip to the author. No subscription, coins or additional features.”

Добавь локализации, цену, доступность, screenshot экрана поддержки для ревью и примечание о добровольном платеже. Consumable можно покупать повторно; постоянного контента и восстановления таких платежей нет. Не выбирай Non-Consumable или Subscription. [Создание IAP](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)

Для первого выпуска добавь **все три IAP и версию приложения в одну отправку на проверку**. До отправки товары должны быть полностью настроены, а не только присутствовать в локальном `.storekit`. [Подача первого IAP](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)

Если выплаты и договор пока недоступны, можно отдельно подготовить бесплатный релиз без раздела оплаты; не отправляй на ревью заведомо неработающий магазин. Для этого нужен отдельный явный релизный вариант, а не скрытая ссылка на сторонний платёж.

## 6. Заполни карточку приложения

Предлагаемый текст, который можно отредактировать:

- **Название:** Pet Island
- **Подзаголовок RU:** Питомцы всегда рядом
- **Подзаголовок EN:** Little companions, always near
- **Категория:** Games; подкатегории выбирай по фактическому содержанию, например Casual / Simulation.
- **Keywords RU:** питомцы,кот,собака,остров,вольер,прогулки,аркада,виджет
- **Keywords EN:** pets,cat,dog,island,companion,enclosure,walks,arcade,widget

Описание RU:

> Небольшой остров для ваших питомцев. Выберите характерного зверька, обустройте его дом и проводите время вместе.
>
> — Поселите соседей в вольере, подберите обстановку и наблюдайте за их занятиями.
> — Отправляйтесь на прогулки, находите маленькие сокровища и собирайте открытки.
> — Играйте в четыре аркады и тратьте заработанные монеты на уход и украшения.
> — Подберите питомцу окрас и аксессуар.
> — Возьмите друга на экран блокировки и в Dynamic Island на совместимом iPhone.
> — Добавьте виджет вольера на экран «Домой».
>
> Без регистрации, рекламы и отслеживания. Прогресс хранится на устройстве; копию острова можно экспортировать самостоятельно. Поддержка автора полностью добровольна и не открывает игровые преимущества.
>
> Dynamic Island доступен только на поддерживаемых моделях. iOS управляет частотой обновления виджетов и Live Activities; на Always-On Display питомец отдыхает.

Описание EN:

> A little island for your companions. Choose a pet, decorate its home and spend time together.
>
> Build a cozy enclosure, watch your pets meet, collect discoveries and postcards on walks, and play four arcade games. Earn coins for care and decorations, choose colors and accessories, and take a companion onto your Lock Screen or Dynamic Island on a supported iPhone. A Home Screen widget keeps the enclosure close.
>
> No sign-up, advertising or tracking. Progress stays on your device, with optional manual island backups. Supporting the author is entirely optional and provides no game advantage.
>
> Dynamic Island requires a supported iPhone. iOS controls widget and Live Activity refresh timing; pets rest on Always-On Display.

Дополнительно:

- Пройди возрастную анкету честно по текущим функциям. Не ставь Kids Category только из-за милых животных: у неё отдельные требования к внешним ссылкам и покупкам. Возрастной рейтинг определяет анкета Apple.
- Copyright заполняй настоящим именем владельца прав, не ником ассистента.
- Для App Privacy текущая архитектура обрабатывает игровой прогресс и StoreKit на устройстве, без серверов разработчика и SDK аналитики. Обработка только на устройстве не считается сбором по определению Apple. Проверь ответы с учётом добровольной переписки поддержки и будущих изменений; не объявляй «Data Not Collected» после добавления серверных чеков/рекламы. [Определения App Privacy](https://developer.apple.com/app-store/app-privacy-details/)
- Для ЕС необходимо заполнить статус trader. Не выбирай статус автоматически: у trader Apple публикует проверенные адрес, телефон и email. [DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)
- App Review Contact: твоё имя, телефон и `bortone52@yandex.ru`. Вход в приложении не требуется, тестовый логин не нужен.

## 7. Скриншоты

Сделай реальные снимки финальной сборки, желательно в RU и EN: остров, список питомцев/карточка, прогулка с открыткой, аркада и наряд. Покажи настоящий интерфейс и не обещай непрерывную анимацию в DI.

Для основного iPhone-набора используй поддерживаемый 6.9″ симулятор/устройство и нативный размер снимков, например **1320 × 2868**. Не растягивай снимки с iPhone SE. Apple принимает 1–10 изображений без alpha; актуальные размеры проверь перед загрузкой. [Спецификации](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

Снимки проверок в `outputs/` — диагностические материалы, не автоматически готовая витрина App Store. Экранов iPad не требуется, пока target остаётся iPhone-only.

## 8. Проверки до архива

Из корня проекта, с установленными Pillow и fontTools:

```sh
python3 Tools/validate_release_readiness.py
python3 Tools/validate_timer_fonts.py
python3 Tools/validate_accessories.py
python3 Tools/validate_natural_gaits.py
python3 Tools/validate_companion_assets.py
```

Полный прогон (укажи UUID отдельного симулятора, без своих сохранений):

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
PET_TEST_DESTINATION='platform=iOS Simulator,id=UUID_ТЕСТОВОГО_СИМУЛЯТОРА' \
  bash Tools/check_project.sh
```

Для локальной проверки цен открой схему **PetIslandTips** и Run. Apple Developer Account для локального каталога не нужен. Для работы с настоящим Sandbox и для архива используй **PetIsland**, без локальной StoreKit Configuration. Ни симуляторный макет, ни локальные тестовые товары не подтверждают, что IAP заведены в App Store Connect.

**Незавершённая проверка оплаты:** на этом Mac локальный тест каталога проходит, но создание транзакции через StoreKit Test завершается `SKServiceErrorDomain 2 / SKInternalErrorDomain 12` на iOS 27; на iOS 26.5 встречалась ошибка загрузки каталога. Это не считается успешным тестом оплаты. Apple отдельно подтверждала проблему синхронизации StoreKit Configuration при CLI-запуске; совпадение причин для нашей версии Xcode пока не доказано. [Обсуждение Apple DTS](https://developer.apple.com/forums/thread/826971)

`check_project.sh` явно исключает только этот интеграционный тест по умолчанию; остальные проверки платёжной логики выполняются. После настройки окружения включи обязательную проверку перед выпуском:

```sh
PET_STOREKIT_TESTS=1 PET_TEST_DESTINATION='platform=iOS Simulator,id=UUID_ТЕСТОВОГО_СИМУЛЯТОРА' \
  bash Tools/check_project.sh
```

Если схема `PetIslandTips` не подтягивает каталог, проверь Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration: должен быть выбран `Configuration/PetIslandTips.storekit`. Не вводи настоящий Apple Account в неожиданное окно входа при локальном тесте. Сначала добейся локальной тестовой транзакции, затем проверь Sandbox; не отправляй платёжный раздел на ревью с неподтверждённым сценарием покупки.

После регистрации обязательно проверь реальные Sandbox/TestFlight сценарии: три цены, успешная поддержка, отмена, запрет покупок, отсутствие сети, отложенное подтверждение и повторный запуск. Не используй реальные деньги для проверки. [Sandbox перед ревью](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases/)

На настоящем iPhone проверь: восстановление существующего острова, льва/львицу в ходьбе и беге, все три наряда, повороты, фон/прозрачность блокировки, DI вместе с музыкой, Always-On, возврат после фона, закрытие приложения во время покупки. Также нужна проверка минимальной iOS 17, VoiceOver и большого текста. Симулятор не доказывает отсутствие нагрева или расхода батареи.

## 9. Архив → TestFlight → App Review

1. Сохрани остров на телефоне через экспорт. Закоммить проверенные изменения; не добавляй `outputs/`, DerivedData, `.xcresult`, локальные профили и ключи.
2. В Xcode выбери **PetIsland → Any iOS Device (arm64)** и платную команду у обоих targets.
3. Version — `1.0`. Для каждой новой загрузки повышай Build **сразу у приложения и расширения**. Первая сборка может быть `1`; после загрузки этот номер повторно не используй.
4. Product → Archive. В Organizer проверь архив и создай Privacy Report: в него должны попасть оба privacy manifest. Затем Validate App.
5. Distribute App → App Store Connect → Upload. Дождись обработки сборки в App Store Connect. Релизный архив нужно подписать своей командой; локальный архив без подписи загрузить нельзя. [Подготовка дистрибутива](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
6. TestFlight → Internal Testing: установи сборку сам. Для внешних тестировщиков потребуется отдельное Beta App Review. Пройди пункты предыдущего раздела и проверь покупки Sandbox.
7. В карточке версии выбери прошедший TestFlight build, заполни все сведения, добавь три IAP в ту же отправку. Выбери **Manual release**, чтобы выпуск не случился сразу после одобрения.
8. Add for Review → проверь состав отправки → Submit for Review. При замечаниях Apple исправь причину; если менялся бинарник, загрузи следующий Build. [Отправка приложения](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
9. После одобрения ещё раз проверь тексты, регионы, цены и сайт, затем нажми выпуск вручную. Следи за crash reports и письмами поддержки. Одобрение App Review заранее гарантировать нельзя.

Текст Review Notes (EN):

> No sign-in is required. Pet Island stores pet and game progress locally and does not include ads or tracking SDKs. The optional tip screen is under Settings → Support the author. All three products are consumable, one-time tips with no currency, feature or entitlement granted. The app remains fully usable without a tip. The Help and privacy screen includes the support contact and an offline privacy policy. Dynamic Island requires a supported iPhone; the enclosure, arcade and Lock Screen Live Activity do not require it. To start a Live Activity, select a pet and use the take-along action. iOS controls background refresh and Always-On behavior.

## Финальные условия выпуска

- [ ] Apple Developer Program активна, выбран верный продавец и команда.
- [ ] Apple подтвердила доступный платёжный путь и возможность выплат для твоего аккаунта.
- [ ] Сайт поддержки и политика открываются публично по HTTPS.
- [ ] Договор, налоги, банк, три IAP и их локализации готовы.
- [ ] Согласованы права на название, код, рисунки и другие ресурсы.
- [ ] Проверена итоговая сборка, включая оплату в Sandbox/TestFlight и минимум iOS 17.
- [ ] Загружен подписанный архив, успешно прошедший Validate App.
- [ ] Заполнены App Privacy, возраст, экспортное шифрование, DSA и контакт ревью.
- [ ] Загружены настоящие скриншоты и добавлены IAP в отправку версии.
- [ ] Выбран ручной выпуск; пользователь сам подтвердил отправку и публикацию.
