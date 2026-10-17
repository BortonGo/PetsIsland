# Pet Island — материалы для App Store

Пакет для первого выпуска **1.0**, подготовлен 17 октября 2026 года. Это материалы для переноса в App Store Connect. Сайт опубликован через GitHub Pages; товары ещё не созданы в консоли, приложение не отправлено на проверку.

Полный порядок регистрации, подписи, TestFlight и отправки: [APP-STORE-LAUNCH.md](../APP-STORE-LAUNCH.md).

## Тексты карточки

В каждом `.txt` лежит только содержимое поля, без заголовка и служебных пометок. Для английского выбран **English (U.S.)**, код `en-US`; русский — `ru`. Это локализации страницы магазина, язык интерфейса пользователь выбирает отдельно в iOS.

| Поле App Store Connect | Русский | English (U.S.) | Ограничение |
| --- | --- | --- | --- |
| Name | [name.txt](metadata/ru/name.txt) | [name.txt](metadata/en-US/name.txt) | 2–30 символов |
| Subtitle | [subtitle.txt](metadata/ru/subtitle.txt) | [subtitle.txt](metadata/en-US/subtitle.txt) | 30 символов |
| Promotional Text | [promotional-text.txt](metadata/ru/promotional-text.txt) | [promotional-text.txt](metadata/en-US/promotional-text.txt) | 170 символов |
| Description | [description.txt](metadata/ru/description.txt) | [description.txt](metadata/en-US/description.txt) | 4000 символов, обычный текст |
| Keywords | [keywords.txt](metadata/ru/keywords.txt) | [keywords.txt](metadata/en-US/keywords.txt) | 100 байт UTF-8 |

В Keywords не вставляй перенос строки в конце файла. Русские буквы занимают больше одного байта; оба набора подготовлены с запасом. Ограничения проверены по [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) и [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/). Поле What's New не заполняется для первой версии, поэтому отдельного файла нет.

Предложение для категории: **Games → Casual / Simulation**. Имя **Pet Island** ещё нужно проверить на доступность в App Store Connect и подтвердить права на него. Основной язык и страны распространения выбирает владелец.

## Сайт и ссылки

[Сайт опубликован](https://bortongo.github.io/pet-island-support/) в отдельном [репозитории](https://github.com/BortonGo/pet-island-support). Исходники находятся в [AppStoreSite](../AppStoreSite/), порядок обновления — в [README сайта](../AppStoreSite/README.md).

| Поле | Русский | English (U.S.) |
| --- | --- | --- |
| Support URL | https://bortongo.github.io/pet-island-support/index.html#support | https://bortongo.github.io/pet-island-support/en/index.html#support |
| Marketing URL (необязательно) | https://bortongo.github.io/pet-island-support/index.html | https://bortongo.github.io/pet-island-support/en/index.html |
| Privacy Policy URL | https://bortongo.github.io/pet-island-support/privacy.html | https://bortongo.github.io/pet-island-support/en/privacy.html |

Эти адреса ещё нужно внести в App Store Connect; публичная ссылка политики также пока не добавлена в приложение. Контакт поддержки: **bortone52@yandex.ru**.

## Скриншоты

Файлы витрины размещаются отдельно по языкам и размерам:

| Слот App Store Connect | Размер | Русский | English |
| --- | --- | --- | --- |
| iPhone with Dynamic Island (medium display), обязательный | 1206 × 2622 | [medium/ru](Screenshots/medium/ru/) | [medium/en](Screenshots/medium/en/) |
| iPhone with Dynamic Island (large display), дополнительный | 1320 × 2868 | [ru](Screenshots/ru/) | [en](Screenshots/en/) |

Оба размера сняты на соответствующих симуляторах, без растягивания одного набора в другой. Порядок загрузки соответствует числовым префиксам. Перед загрузкой проверь соответствие снимков именно отправляемой сборке и отсутствие персональных данных. Происхождение и порядок кадров описаны в [README снимков](Screenshots/README.md).

Используй только проверенные финальные PNG из этих каталогов, без контактных листов, тестовых логов и снимков из `outputs/`. Нужны 1–10 скриншотов на размер и локализацию, без alpha. На дату подготовки Apple требует хотя бы один снимок среднего экрана iPhone с Dynamic Island; большой набор его не заменяет. iPad-снимки для текущего iPhone-only target не нужны. [Спецификации Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

Снимок экрана покупок для IAP Review — отдельный материал: его следует снять после настройки реальных товаров в Sandbox/TestFlight. Локальные тестовые цены не подтверждают цены App Store и не должны выдавать тестовый каталог за настроенные реальные покупки.

## Добровольная поддержка автора

Копируй идентификаторы, Reference Name, тип и RU/EN-тексты из [iap/products.json](metadata/iap/products.json). Это таблица для ручной настройки, а не файл автоматического импорта в App Store Connect. Все три товара — **Consumable**. Цены и доступность намеренно отсутствуют: владелец задаёт их отдельно в консоли.

| Product ID | RU Display Name | EN Display Name |
| --- | --- | --- |
| `org.bortongo.PetIsland.tip.small` | Маленькое спасибо | A little thank-you |
| `org.bortongo.PetIsland.tip.medium` | Тёплое спасибо | A warm thank-you |
| `org.bortongo.PetIsland.tip.large` | Большое спасибо | A big thank-you |

Описание каждого товара:

- RU: `Разовая поддержка автора. Без подписки.`
- EN: `A one-time tip. No subscription.`

Display Name ограничено 30 символами, Description — 45. Короткое описание подходит для поля IAP; подробные условия уже объяснены в приложении, описании и заметках для ревью. [Поля IAP](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/)

В заметки каждого товара вставь [iap/review-notes.en.txt](metadata/iap/review-notes.en.txt). Сначала заверши Paid Apps Agreement, налоговые и банковские данные, создай товары и проверь их в Sandbox. Затем приложи все три товара к первой версии приложения. [Первая отправка IAP](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase)

## Для App Review

Готовый текст: [review-notes.en.txt](metadata/review-notes.en.txt). Вход не нужен, демонстрационный аккаунт не требуется. Контактный email — **bortone52@yandex.ru**; настоящее имя и телефон добавляет владелец в приватные поля App Review Contact.

Перед отправкой повтори описанные шаги в итоговой TestFlight-сборке. Системные ограничения Live Activities и Always-On указаны в тексте, непрерывная анимация не обещается.

## Что должен подтвердить владелец

- [ ] Apple Developer Program активна; продавец, команда, Bundle ID и App Group соответствуют итоговой подписи. Доступность оплаты членства и выплат для своих данных уточнена у Apple.
- [ ] Приложение предлагается бесплатно, выбраны реальные страны доступности и цены трёх добровольных платежей. Дополнительные региональные требования проверены до включения соответствующих стран.
- [ ] Имя приложения доступно; подтверждены права на код, рисунки, шрифты, звуки и название. В Copyright указаны год и настоящий владелец прав; никаких вымышленных ФИО в пакет не добавлено.
- [ ] Проверены опубликованные страницы; ссылки поддержки и политики внесены в App Store Connect для каждой локализации.
- [ ] Ссылка политики добавлена в приложение рядом с офлайн-текстом.
- [ ] Владелец подтвердил фактическую обработку и хранение писем поддержки; политика соответствует этой практике.
- [ ] App Privacy заполнена по фактической сборке и обработке обращений поддержки. Сейчас прогресс хранится локально, нет рекламного/аналитического SDK или сервера разработчика; это не основание автоматически копировать ответы при будущих изменениях. [Определения Apple](https://developer.apple.com/app-store/app-privacy-details/)
- [ ] Возрастная анкета заполнена по текущему контенту. Милые животные сами по себе не означают Kids Category. Рейтинг определяет анкета Apple. [Возрастной рейтинг](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- [ ] Выбран соответствующий обстоятельствам статус trader для ЕС; при необходимости предоставлены проверяемые контакты. [DSA](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
- [ ] Подтверждены сведения об экспортном шифровании, контакт для ревью и применимое лицензионное соглашение. Значение в Info.plist сверено с итоговыми SDK и функциями.
- [ ] Настоящие товары проверены в Sandbox/TestFlight: загрузка цен, покупка каждой суммы, отмена, повторная покупка и отложенное подтверждение. Подготовлены IAP Review screenshots.
- [ ] Подписанный архив прошёл Validate App и проверку на устройстве: обновление сохранений, RU/EN, VoiceOver, крупный текст, блокировка, DI с музыкой, возврат из фона и минимальная iOS 17.
- [ ] Выбрана проверенная сборка, к ней приложены покупки; включён ручной выпуск после одобрения. Отправку и публикацию подтверждает владелец.

Материалы не содержат платёжных реквизитов, сертификатов, профилей подписи или секретов. Их следует вводить только в соответствующих кабинетах Apple.
