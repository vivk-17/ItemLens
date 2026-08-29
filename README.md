# ItemLens

Аддон для World of Warcraft 1.12.1 (сервер [Emberveil](https://emberveil.org)).

Взгляд на предмет вблизи: сколько он стоит у торговца, что даст взамен
надетого и во сколько обошлась добыча.

![версия](https://img.shields.io/badge/version-0.1.0-blue) ![клиент](https://img.shields.io/badge/client-1.12.1-orange)

## Что умеет

- **Цена в подсказке.** У клиента нет API цены предмета, поэтому аддон
  подсматривает её у торговца: пока открыто окно продавца, подсказка сообщает
  стоимость стопки, и эти числа запоминаются. Показывает цену за стопку и за
  штуку — в сумках, в окне добычи и среди наград за задание.
- **Сравнение с надетым по Shift.** Разница по каждой характеристике: зелёным
  прибавка, красным потеря. Кольца, аксессуары и одноручное оружие
  сравниваются с обоими слотами.
- **Итог добычи в чат.** Одна строка на тушку: сколько собрано и на сколько.
- **Автопродажа серого** у торговца, со списком защищённых предметов.
- **Починка у торговца** с потолком трат. По умолчанию выключена.
- **Стоимость сумок и банка.** Банк считается, пока открыто его окно, и
  запоминается до следующего визита.
- Кнопка у миникарты, окно настроек, русский и английский интерфейс.

## Установка

1. Скачайте архив из [релизов](../../releases).
2. Распакуйте папку `ItemLens` в `Interface/AddOns`.
3. Путь должен получиться такой: `Interface/AddOns/ItemLens/ItemLens.toc`

Один раз зайдите к любому торговцу — цены соберутся сами.

## Команды

Полное имя — `/itemlens`, короткое — `/il`.

| Команда | Что делает |
| --- | --- |
| `/il config` | окно настроек (то же, что клик по кнопке у миникарты) |
| `/il worth` | сколько добра в сумках и в банке |
| `/il scan` | собрать цены прямо сейчас (у торговца) |
| `/il compare` | сравнение по Shift вкл/выкл |
| `/il repair` / `/il repair 2g` | автопочинка и потолок трат |
| `/il autosell`, `/il keep <имя>` | автопродажа серого и защита предмета |
| `/il loot 2` | задержка итога добычи |
| `/il mode vendor\|stack\|each` | как показывать цену |
| `/il lang ru\|en\|auto` | язык |
| `/il probe`, `/il tiptest` | самодиагностика |

## Для авторов других аддонов

ItemLens объявляет четыре функции. Вызывать их безопасно с проверкой
`type(...) == "function"` — без ItemLens ничего не сломается:

```lua
ItemLens_BagValue()            -- медь, известных цен, неизвестных
ItemLens_BankValue()           -- то же для банка + признак «свежие данные»
ItemLens_SlotPrice(bag, slot)  -- цена за штуку в ячейке
ItemLens_Format(copper)        -- «12g 30s 5c» с цветами
```

Так с ним работает окно сумок [AllBags](https://github.com/vivk-17/AllBags).

## Особенности клиента

Найдено по дороге, может пригодиться:

- вставка картинок в текст (`|T...|t`) не отображается — монеты только буквами;
- цветовые коды при чтении строки подсказки срезаются;
- строки за пределами `NumLines` хранят текст предыдущей подсказки;
- убрать строку из подсказки нельзя, только перерисовать её целиком;
- колесо мыши над окном аддона забирает камера.

---

# ItemLens (English)

An addon for World of Warcraft 1.12.1 on the [Emberveil](https://emberveil.org)
server: a closer look at items — what a vendor pays, what an item would change
about your gear, and what the loot was worth.

## Features

- **Vendor price in the tooltip.** The client has no price API, so the addon
  learns prices from the merchant window and remembers them. Works in the bags,
  the loot window and on quest rewards.
- **Shift compares with worn gear**, stat by stat, both slots for rings,
  trinkets and one-handers.
- **Loot total in chat**, one line per corpse.
- **Selling greys** automatically, with a protection list.
- **Repairing** at a merchant, with a spending ceiling. Off by default.
- **Bag and bank value**, the bank counted while its window is open.
- A minimap button, a settings window, Russian and English.

## Installation

Unpack the `ItemLens` folder into `Interface/AddOns` so that
`Interface/AddOns/ItemLens/ItemLens.toc` exists, then visit any merchant once.

## Licence

MIT — see [LICENSE](LICENSE).
