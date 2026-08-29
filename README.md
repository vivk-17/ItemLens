# ItemLens

An addon for World of Warcraft 1.12.1 on the [Emberveil](https://emberveil.org) server.

A closer look at items: what a vendor pays, what one would change about the
gear you are wearing, and what the loot was worth.

![version](https://img.shields.io/badge/version-0.1.0-blue) ![client](https://img.shields.io/badge/client-1.12.1-orange)

[Русский](#itemlens-по-русски)

## What it does

- **Vendor price in the tooltip.** The client has no price API, so the addon
  learns prices at a merchant: while the vendor window is open the tooltip
  reports the price of a stack, and those numbers are remembered. After that
  the price shows in the bags, in the loot window and on quest rewards — per
  stack and per item.
- **Shift compares with worn gear.** The difference in every stat: green for a
  gain, red for a loss. Rings, trinkets and one-handers are compared against
  both slots.
- **Loot total in chat.** One line per corpse: what you picked up and what it
  is worth.
- **Selling greys** automatically at a merchant, with a protection list.
- **Repairing** at a merchant with a spending ceiling. Off by default.
- **Bag and bank value.** The bank is counted while its window is open and
  remembered until the next visit.
- A minimap button, a settings window, Russian and English.

## Installation

1. Download the archive from [releases](../../releases).
2. Unpack the `ItemLens` folder into `Interface/AddOns`.
3. The path should end up like this: `Interface/AddOns/ItemLens/ItemLens.toc`

Visit any merchant once and the prices collect themselves.

## Commands

The full name is `/itemlens`, the short one `/il`.

| Command | What it does |
| --- | --- |
| `/il config` | the settings window (same as the minimap button) |
| `/il worth` | what the bags and the bank are worth |
| `/il scan` | collect prices right now, at a merchant |
| `/il compare` | the Shift comparison on or off |
| `/il repair` / `/il repair 2g` | auto repair and the spending ceiling |
| `/il autosell`, `/il keep <name>` | selling greys, and protecting an item |
| `/il loot 2` | delay before the loot total |
| `/il mode vendor\|stack\|each` | how the price is shown |
| `/il lang ru\|en\|auto` | language |
| `/il probe`, `/il tiptest` | self-diagnostics |

## For other addon authors

ItemLens declares four functions. Calling them is safe behind a
`type(...) == "function"` check — without ItemLens nothing breaks:

```lua
ItemLens_BagValue()            -- copper, prices known, prices unknown
ItemLens_BankValue()           -- the same for the bank, plus a "fresh" flag
ItemLens_SlotPrice(bag, slot)  -- price per item in a slot
ItemLens_Format(copper)        -- "12g 30s 5c", coloured
```

That is how the [AllBags](https://github.com/vivk-17/AllBags) bag window shows
the total value of what you are carrying.

## Client quirks

Found along the way, and possibly useful to someone else:

- inline textures (`|T...|t`) are not rendered — coins have to be letters;
- colour codes are stripped when a tooltip line is read back;
- lines past `NumLines` still hold the text of the previous tooltip;
- a line cannot be removed from a tooltip, only the whole thing redrawn;
- the mouse wheel over an addon window is taken by the camera.

---

# ItemLens по-русски

Аддон для World of Warcraft 1.12.1 (сервер [Emberveil](https://emberveil.org)).

Взгляд на предмет вблизи: сколько он стоит у торговца, что даст взамен
надетого и во сколько обошлась добыча.

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

## Лицензия / Licence

MIT — see [LICENSE](LICENSE).
