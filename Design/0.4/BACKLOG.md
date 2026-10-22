# Что сделать

## В коде приложения

- [x] `Theme` (`Glassine/UI/Theme.swift`): `.themed()` у корня каждого SwiftUI-окна — окружение и
      `.tint(theme.accent)`; AppKit берёт `Theme.shared`. Акцент, текст на нём, `showsPaperDetails`.
- [x] Цвета из `tokens.json` → `Glassine/Resources/Theme.xcassets` (светлая + тёмная) скриптом
      `scripts/theme-tokens.py`; он же пишет `ThemeTokens.swift` (шкала шрифтов, радиусы, перфорация).
      В коде `blue` → `postmark`, `blue_deep` → `stamp` (иначе конфликт с `Color.blue`).
- [x] Перерисовка при смене системного акцента: `NSColor.systemColorsDidChangeNotification`.
- [x] Акцент по умолчанию: Ink при Multicolor (нет ключа `AppleAccentColor`), иначе System.
- [x] Settings → General → Appearance: акцент — ряд кружков, первый System.
- [ ] Стиль System и его карточки в Appearance — отложен (DECISIONS 5: пока только Glassine).
- [x] Fraunces прямой и курсив (variable) в бандле из `Design/fonts`, загрузка через `ATSApplicationFontsPath`;
      `Typography` ставит SOFT 100, WONK 0, opsz = размер; без шрифта — New York.
- [x] Increase Contrast / Reduce Transparency → `showsPaperDetails = false`.
- [x] Превью снимка и записи — марки (`QuickAccess/PreviewStampView.swift`), кнопки `PillButton` paper / stamp.
- [x] Настройки (`Settings/SettingsKit.swift`): бумага, вкладки-таблетка, разделы с Fraunces, карточки строк
      с нативными контролами, карточки-превью с кольцом акцента и нейтральными мини-сценами.
- [x] Всплывающие: приветствие (марка в конверте, клавиши-капы, галочки), обновление (теги-штампы),
      уведомления-таблетки, отсчёт таймера; общие кнопки `PaperButtonStyle` и `KeyCaps` в `UI/Paper.swift`.
- [x] DMG (`Design/tools/dmg-background.swift`): марки под иконками, перфорированная стрелка, токены из `tokens.json`.
- [ ] Экраны: перевести окна на `Color.paper`/`.card`/`.ink`, заголовки на `.textStyle(ThemeTokens.title)`;
      `OptionCard` и прочие места с `Color.accentColor` — на `theme.accent`.
- [x] Таймер записи: у Fraunces нет `tnum` — каждая цифра в `frame` фиксированной ширины (`TimerText`: 0,62 em, двоеточие 0,3 em).
- [x] Регистр: кнопки и меню остаются в Title Case по HIG (DECISIONS 10).

## Редактор в коде

- [x] Пресеты фона: Sleeve, Sage, Stamp, Peach, Ink вместо Ocean, Sunset, Mint, Graphite, Paper
      (`BackgroundSettings.gradients`); старые сохранённые переводятся на ближайшие (`migratedGradient`, версия 2).
- [x] Панели на `card` с обводкой `border` и тенью средней (`paperPanel`); разделители — три точки.
- [x] Подсказка: карточка с названием, клавишами-капами справа, одна-две строки `ink2`.
- [x] Холст — системный нейтральный `underPageBackgroundColor`.

## Панель записи в коде

- [x] Панель на `card` с точечной фактурой `ink` (гаснет при Increase Contrast); стекло убрано.
- [x] Кнопка записи — `rec`, единственное красное до старта; в плеере — точки и ■.
- [x] Чипы на `key`: метка моноширинной капителью 11 pt, значение Fraunces 14,5; разделители — линия отрыва из точек.
- [x] Редактор звука на `card`, дорожки на `key`; подпись размера рамки — тёмный чернильный ярлык в обеих темах.

## Экраны, которых ещё нет в сценах

- [ ] Приветствие без разрешения: три шага выдачи Screen Recording.
- [ ] Приветствие с конфликтом системных шорткатов ⇧⌘3/4/5.
- [ ] Стиль System для тех же сцен (и вкладка Appearance).
- [x] Редактор в стиле Glassine (`scenes/7-editor`): холст нейтральный, панели, подсказка, поповер фона.
- [ ] Редактор в стиле System.
- [x] Пин (кромка, бумажная ✕, кольцо ⌥⌘), ярлыки размеров и линейки. Меню превью и QR — системные NSMenu, остаются.
- [x] Стопка из 5 превью-марок на 13" экране — не помещается (≈ 4); стопка теперь закрывает старые по высоте экрана.
- [x] Иконка в новой палитре (кремовая G на чернилах, нижняя часть в пергаминовом конверте); режимы Default, Dark, Clear, Tinted проверены через `ictool`.

## Проверить

- [ ] Сравнение старого и нового варианта на людях (r/macapps, знакомые не-дизайнеры).
- [ ] Пятисекундный тест: «что это за приложение и на что похоже?».
- [ ] Выключенный тумблер на `card`: дорожка 1,3:1 — как у macOS; при Increase Contrast добавить обводку.
- [x] Дата на превью локализуется («22 окт.», в США «Oct 22 · 2:14 PM»).
