--[[--------------------------------------------------------------------
  ItemLens 0.1.0
  Client 1.12.1 / Lua 5.1 (Emberveil).

  There is no API for an item's vendor price in this client. But the docs for
  GameTooltip:SetBagItem say that WHILE A MERCHANT WINDOW IS OPEN a sellable
  bag item also fires OnTooltipAddMoney carrying the stack sell price. So the
  addon walks the bags once per merchant visit, catches those numbers and
  remembers them. Nothing is sold and nothing is clicked.

  Unknown at the time of writing: whether OnTooltipAddMoney fires on a tooltip
  we create ourselves, or only on the stock GameTooltip. The harvest tries the
  private tooltip first, falls back to the stock one, and reports which path
  produced numbers — that is what this probe is for.
----------------------------------------------------------------------]]

local ADDON   = "ItemLens"
local VERSION = "0.1.0"

local FIRST_BAG, LAST_BAG = 0, 4

-- The bank is the same kind of container: the main window is -1 and the bags
-- bought into it are 5 to 10. They answer with 0 slots while the bank is shut,
-- which is exactly how we tell whether the numbers are fresh.
local BANK_MAIN = -1
local FIRST_BANK_BAG, LAST_BANK_BAG = 5, 10

local defaults = {
  prices   = nil,   -- filled lazily: itemKey -> copper per single item
  keep     = nil,   -- item names never sold automatically
  tooltip  = true,  -- add a price line to bag tooltips
  mode     = "vendor", -- "vendor" = stack total with the per item price in
                       -- brackets, "stack" = stack total only, "each" = per item
  scanmsg  = false, -- announce in chat how many prices a merchant visit caught
  lootchat = true,  -- report in chat what the picked up loot is worth
  lootwait = 1,     -- seconds to wait so one corpse is summed into one line
  autosell = true,  -- sell poor quality items when a merchant opens
  compare  = true,  -- hold Shift over a bag item to compare it with the worn one
  repair   = false, -- repair everything when a merchant that can repair opens
  repairmax = 0,    -- copper ceiling for that, 0 means no ceiling
  bank     = nil,   -- what the bank held last time we saw it: {total, known, unknown}
  minimap  = true,  -- show the button next to the minimap
  mmangle  = 160,   -- where on the ring it sits, in degrees
  cfgx     = nil,   -- settings window position, absolute bottom left corner
  cfgy     = nil,
  lang     = "auto",-- "ru", "en" or "auto" for the client locale
  debug    = false,
}

local POOR = 0        -- quality index of grey items
local SELL_STEP = 0.3 -- seconds between sales, so the server is not flooded

----------------------------------------------------------------------
-- localisation
----------------------------------------------------------------------

local STRINGS = {
  ru = {
    each        = "%s шт.",
    stackEach   = "%s (%s шт.)",
    caught      = "собрано цен: %d (через %s), всего в базе: %d",
    caughtNone  = "|cffff8080ни одной цены не поймано|r — торговец открыт? В сумках есть что продать?",
    pathHook    = "перехват",
    pathStock   = "штатная ячейка",
    pathLoot    = "окно добычи",
    pathBags    = "AllBags",
    pathNone    = "не найдено",
    loot        = "лут: %s (%d шт.)",
    lootUnknown = ", без цены: %d",
    worth       = "в сумках на %s (известны цены %d предметов, не известны %d)",
    bankWorth   = "в банке на %s (известны %d, не известны %d)%s",
    bankOld     = " — по последнему визиту",
    bankNever   = "банк ещё не открывали при включённом аддоне.",
    repairSet   = "автопочинка: %s",
    repairCap   = "автопочинка: вкл, не дороже %s",
    repairDone  = "починка обошлась в %s",
    repairDear  = "починка стоит %s — дороже вашего потолка %s, не чиню.",
    repairPoor  = "на починку нужно %s — не хватает денег.",
    pathQuest   = "награда за задание",
    cfgTitle    = "ItemLens — настройки",
    cfgTooltip  = "Цена в подсказке",
    cfgCompare  = "Сравнение с надетым по Shift",
    cfgAutosell = "Продавать серое у торговца",
    cfgLootChat = "Итог добычи в чат",
    cfgScanMsg  = "Сообщать о сборе цен",
    cfgRepair   = "Чинить у торговца",
    cfgDebug    = "Отладка",
    cfgMode     = "Цена показывается:",
    cfgLootWait = "Задержка итога добычи:",
    cfgCap      = "Потолок починки:",
    cfgNoCap    = "без предела",
    cfgLang     = "Язык:",
    cfgAuto     = "как в игре",
    cfgScan     = "Собрать цены",
    cfgWorth    = "Сколько добра",
    cfgClear    = "Забыть цены",
    cfgStats    = "цен в базе: %d, защищено от продажи: %d",
    cfgDrag     = "окно тащится за заголовок",
    mmOpenCfg   = "ЛКМ — настройки",
    mmHide      = "ПКМ — убрать эту кнопку",
    mmMove      = "Shift+тащить — переместить по кругу",
    mmState     = "кнопка у миникарты: %s",
    help        = "команды: /itemlens [config | minimap | scan | worth | compare | repair [сумма] | mode vendor|stack|each | loot [сек] | scanmsg | lang ru/en/auto | probe | tiptest | autosell | sell | keep <имя> | unkeep <имя> | tooltip | clear | debug]",
    probeWait   = "наведите мышь на предмет — проверю через 5 секунд.",
    autosellSet = "автопродажа серых: %s",
    noMerchant  = "торговец не открыт.",
    noGrey      = "серых предметов нет.",
    selling     = "продаю серых: %d",
    sold        = "продано серых предметов: %d, получено: %s",
    keepAdd     = "никогда не продавать: %s",
    keepList    = "защищено: %s",
    keepEmpty   = "список защиты пуст. /il keep <имя предмета>",
    keepGone    = "защита снята: %s",
    keepMiss    = "не найдено в списке защиты.",
    tooltipSet  = "строка в подсказке: %s",
    compareSet  = "сравнение по Shift: %s",
    modeVendor  = "за стопку, в скобках за штуку",
    modeStack   = "только за стопку",
    modeEach    = "только за штуку",
    modeSet     = "цена в подсказке: %s",
    modeHelp    = "режимы: vendor (за стопку и в скобках за штуку), stack (только за стопку), each (только за штуку)",
    lootSet     = "итог лута в чат: вкл, задержка %s с",
    lootState   = "итог лута в чат: %s (задержка %s с, менять: /il loot 2)",
    scanmsgSet  = "сообщать о сборе цен у торговца: %s",
    cleared     = "база цен очищена.",
    debugSet    = "отладка: %s, цен в базе: %d, последний рабочий путь: %s",
    langSet     = "язык: %s",
    on          = "вкл",
    off         = "выкл",
    yes         = "да",
    no          = "нет",
    -- comparison
    cmpInstead  = "вместо: %s",
    cmpSame     = "характеристики те же",
    cmpEmpty    = "слот пуст",
    cmpNoData   = "|cffff8080сравнение недоступно|r — клиент не даёт читать строки подсказки.",
    slotHead    = "Голова",    slotNeck = "Шея",       slotShoulder = "Плечи",
    slotShirt   = "Рубаха",    slotChest = "Грудь",    slotWaist = "Пояс",
    slotLegs    = "Ноги",      slotFeet = "Ступни",    slotWrist = "Запястья",
    slotHands   = "Кисти",     slotFinger = "Кольцо",  slotTrinket = "Аксессуар",
    slotBack    = "Спина",     slotMain = "Правая рука", slotOff = "Левая рука",
    slotRanged  = "Дальний бой", slotTabard = "Гербовая накидка", slotAmmo = "Боеприпасы",
    -- probe
    probeHead   = "|cffffd700--- проверка ---|r",
    probeFocus  = "под курсором: %s, тот же объект дважды подряд: %s",
    probeShown  = "подсказка видна: %s, первая строка: %s",
    probeLeft1  = "GameTooltipTextLeft1 найден: %s",
    probeMerch  = "торговец (по событиям): %s, GetMerchantNumItems: %s",
    probeStock  = "штатные сумки перехвачены: %s",
    probeHook   = "перехват SetBagItem: %s, последняя ячейка: %s/%s",
    probeStack  = "в стопке: %s (путь: %s)",
    probeClient = "клиент показывает свою цену: %s, режим: %s",
    probePrice  = "цена по имени: %s",
    probeTotals = "всего цен в базе: %d, шаблонов лута: %d, итог лута: %s",
    probeCmp    = "сравнение: %s, своя подсказка со строками: %s",
    unknown     = "не определить",
    noName      = "(без имени)",
    unstable    = "НЕТ (объект каждый раз новый)",
    works       = "работает",
    worksNot    = "НЕ ставится",
    noFunc      = "функции нет",
  },
  en = {
    each        = "%s ea.",
    stackEach   = "%s (%s ea.)",
    caught      = "prices caught: %d (via %s), %d in the book",
    caughtNone  = "|cffff8080no prices caught|r — is a merchant open? Is there anything sellable in the bags?",
    pathHook    = "hook",
    pathStock   = "stock slot",
    pathLoot    = "loot window",
    pathBags    = "AllBags",
    pathNone    = "not found",
    loot        = "loot: %s (%d items)",
    lootUnknown = ", unpriced: %d",
    worth       = "the bags hold %s (%d priced, %d unknown)",
    bankWorth   = "the bank holds %s (%d priced, %d unknown)%s",
    bankOld     = " — as of the last visit",
    bankNever   = "the bank has not been opened with the addon running yet.",
    repairSet   = "auto repair: %s",
    repairCap   = "auto repair: on, up to %s",
    repairDone  = "repairs cost %s",
    repairDear  = "repairs cost %s — more than your ceiling of %s, leaving it.",
    repairPoor  = "repairs need %s — not enough money.",
    pathQuest   = "quest reward",
    cfgTitle    = "ItemLens — settings",
    cfgTooltip  = "Price in the tooltip",
    cfgCompare  = "Shift compares with worn gear",
    cfgAutosell = "Sell greys at a merchant",
    cfgLootChat = "Loot total in chat",
    cfgScanMsg  = "Announce price gathering",
    cfgRepair   = "Repair at a merchant",
    cfgDebug    = "Debug",
    cfgMode     = "Price is shown:",
    cfgLootWait = "Loot total delay:",
    cfgCap      = "Repair ceiling:",
    cfgNoCap    = "no limit",
    cfgLang     = "Language:",
    cfgAuto     = "as the client",
    cfgScan     = "Gather prices",
    cfgWorth    = "What it is worth",
    cfgClear    = "Forget prices",
    cfgStats    = "prices stored: %d, protected from selling: %d",
    cfgDrag     = "drag the window by its title",
    mmOpenCfg   = "Left click — settings",
    mmHide      = "Right click — hide this button",
    mmMove      = "Shift+drag — move around the ring",
    mmState     = "minimap button: %s",
    help        = "commands: /itemlens [config | minimap | scan | worth | compare | repair [amount] | mode vendor|stack|each | loot [sec] | scanmsg | lang ru/en/auto | probe | tiptest | autosell | sell | keep <name> | unkeep <name> | tooltip | clear | debug]",
    probeWait   = "hover an item — checking in 5 seconds.",
    autosellSet = "selling greys: %s",
    noMerchant  = "no merchant is open.",
    noGrey      = "no grey items.",
    selling     = "selling greys: %d",
    sold        = "greys sold: %d, earned: %s",
    keepAdd     = "never sell: %s",
    keepList    = "protected: %s",
    keepEmpty   = "the protection list is empty. /il keep <item name>",
    keepGone    = "protection removed: %s",
    keepMiss    = "not found in the protection list.",
    tooltipSet  = "tooltip price line: %s",
    compareSet  = "Shift comparison: %s",
    modeVendor  = "stack total, per item in brackets",
    modeStack   = "stack total only",
    modeEach    = "per item only",
    modeSet     = "tooltip price: %s",
    modeHelp    = "modes: vendor (stack total with the per item price in brackets), stack (stack total only), each (per item only)",
    lootSet     = "loot total in chat: on, delay %s s",
    lootState   = "loot total in chat: %s (delay %s s, change with /il loot 2)",
    scanmsgSet  = "announce price gathering: %s",
    cleared     = "the price book is empty again.",
    debugSet    = "debug: %s, prices stored: %d, last working path: %s",
    langSet     = "language: %s",
    on          = "on",
    off         = "off",
    yes         = "yes",
    no          = "no",
    cmpInstead  = "instead of: %s",
    cmpSame     = "same numbers",
    cmpEmpty    = "the slot is empty",
    cmpNoData   = "|cffff8080comparison unavailable|r — this client will not let us read tooltip lines.",
    slotHead    = "Head",      slotNeck = "Neck",      slotShoulder = "Shoulder",
    slotShirt   = "Shirt",     slotChest = "Chest",    slotWaist = "Waist",
    slotLegs    = "Legs",      slotFeet = "Feet",      slotWrist = "Wrist",
    slotHands   = "Hands",     slotFinger = "Ring",    slotTrinket = "Trinket",
    slotBack    = "Back",      slotMain = "Main hand", slotOff = "Off hand",
    slotRanged  = "Ranged",    slotTabard = "Tabard",  slotAmmo = "Ammo",
    probeHead   = "|cffffd700--- check ---|r",
    probeFocus  = "under the cursor: %s, same object twice in a row: %s",
    probeShown  = "tooltip shown: %s, first line: %s",
    probeLeft1  = "GameTooltipTextLeft1 found: %s",
    probeMerch  = "merchant (by events): %s, GetMerchantNumItems: %s",
    probeStock  = "stock bags hooked: %s",
    probeHook   = "SetBagItem hook: %s, last slot: %s/%s",
    probeStack  = "stack size: %s (path: %s)",
    probeClient = "client prints its own price: %s, mode: %s",
    probePrice  = "price by name: %s",
    probeTotals = "prices stored: %d, loot patterns: %d, loot total: %s",
    probeCmp    = "comparison: %s, own tooltip with readable lines: %s",
    unknown     = "cannot tell",
    noName      = "(unnamed)",
    unstable    = "NO (a new object every time)",
    works       = "works",
    worksNot    = "does NOT stick",
    noFunc      = "no such function",
  },
}

local function CurrentLang()
  local pick = ItemLensDB and ItemLensDB.lang or "auto"
  if pick == "ru" or pick == "en" then return pick end
  if GetLocale and GetLocale() == "ruRU" then return "ru" end
  return "en"
end

local function L(key) return STRINGS[CurrentLang()][key] or key end
local function Lf(key, a, b, c, d) return string.format(L(key), a, b, c, d) end

----------------------------------------------------------------------
-- state
----------------------------------------------------------------------

local scanTip, driver
local pendingKey, pendingCount, pendingName = nil, 1, nil
local caught, source = 0, nil
local lastFocus, lastName, lastLines = nil, nil, nil
local hookBag, hookSlot = nil, nil
local hookOK, sweeping = false, false
local stockHookOK = false
local countPath = "-"
local lastShift = false
local hiddenSeen = 0        -- consecutive frames without a tooltip
local hiddenFrames = 0                  -- consecutive frames with no tooltip
local CompareLines            -- defined further down, used by Annotate

-- loot tally, collected for a moment so one corpse makes one chat line
local lootTimer, lootValue, lootItems, lootUnknown = 0, 0, 0, 0
local lootPatterns, lootPatternsN = nil, 0
local timer = 0
local merchantOpen = false
local probeTimer = 0
local bankTimer, bankOpen = 0, false

-- auto sell queue
local queue, queueN, queueAt = {}, 0, 0
local sellTimer, sellStartMoney, sellCount, sellReported = 0, 0, 0, true

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc66" .. ADDON .. ":|r " .. msg)
  end
end

local function Debug(msg)
  if ItemLensDB and ItemLensDB.debug then Print("|cff808080" .. msg .. "|r") end
end

local function InitDB()
  if type(ItemLensDB) ~= "table" then ItemLensDB = {} end
  for k, v in pairs(defaults) do
    if ItemLensDB[k] == nil and v ~= nil then ItemLensDB[k] = v end
  end
  if type(ItemLensDB.prices) ~= "table" then ItemLensDB.prices = {} end
  if type(ItemLensDB.keep) ~= "table" then ItemLensDB.keep = {} end
  if type(ItemLensDB.lootwait) ~= "number" or ItemLensDB.lootwait < 0 then
    ItemLensDB.lootwait = 1
  end
  ItemLensDB.coins = nil        -- retired: this client cannot draw inline icons
  local m = ItemLensDB.mode
  if m ~= "vendor" and m ~= "each" and m ~= "stack" then ItemLensDB.mode = "vendor" end
end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

-- Inline textures (|T...|t) are NOT rendered by this client: it strips the
-- markers and prints the file path as plain text. So money is always spelled
-- out with coloured letters, the way the rest of the addon does it.
local function FormatMoney(copper)
  copper = copper or 0
  local g = math.floor(copper / 10000)
  local s = math.floor(copper / 100) - g * 100
  local c = copper - math.floor(copper / 100) * 100
  local out = ""
  if g > 0 then out = out .. "|cffffd700" .. g .. "g|r " end
  if g > 0 or s > 0 then out = out .. "|cffc7c7cf" .. s .. "s|r " end
  return out .. "|cffeda55f" .. c .. "c|r"
end

-- Colour codes and inline textures out, plain text in.
local function StripCodes(text)
  if not text then return nil end
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|T.-|t", "")
  return text
end

-- item id out of a hyperlink: |cff...|Hitem:1234:0:0:0|h[Name]|h|r
local function ItemKey(link)
  if not link then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  if id then return "i" .. id end
  local _, _, name = string.find(link, "%[(.+)%]")
  if name then return "n" .. name end
  return nil
end

local function ItemName(link)
  if not link then return nil end
  local _, _, name = string.find(link, "%[(.+)%]")
  return name
end

local function PriceOf(bag, slot)
  local link = GetContainerItemLink(bag, slot)
  local key = ItemKey(link)
  if not key then return nil end
  return ItemLensDB.prices[key], key
end

-- Stack size of one bag slot, but only when it really holds `name`.
local function SlotCount(bag, slot, name)
  if bag == nil or slot == nil then return nil end
  if not GetContainerItemLink then return nil end
  local held = ItemName(GetContainerItemLink(bag, slot))
  if not held then return nil end
  if name and held ~= name then return nil end
  local _, count = GetContainerItemInfo(bag, slot)
  return count
end

----------------------------------------------------------------------
-- catching the money
----------------------------------------------------------------------

-- Called by the client with the stack sell price while a merchant is open.
local function OnMoney(self, money)
  local amount = money or arg1
  if type(amount) ~= "number" or amount <= 0 then return end
  if not pendingKey then return end

  local per = amount
  if pendingCount and pendingCount > 1 then
    per = math.floor(amount / pendingCount)
  end

  ItemLensDB.prices[pendingKey] = per
  if pendingName then ItemLensDB.prices["n" .. pendingName] = per end
  caught = caught + 1
  Debug(pendingKey .. " = " .. per .. "c (stack " .. tostring(pendingCount) .. " for " .. amount .. "c)")
end

local function BuildScanTooltip()
  if scanTip then return end
  scanTip = CreateFrame("GameTooltip", "ItemLensScanTooltip", UIParent)
  if scanTip.SetOwner then scanTip:SetOwner(UIParent, "ANCHOR_NONE") end
  scanTip:SetScript("OnTooltipAddMoney", OnMoney)
end

----------------------------------------------------------------------
-- harvest
----------------------------------------------------------------------

-- Walks every bag slot through the given tooltip and returns how many prices
-- the money handler managed to catch.
-- Every container worth sweeping right now: the bags always, the bank when
-- its window is open.
local function SweepBags()
  local list, n = {}, 0
  local bag = FIRST_BAG
  while bag <= LAST_BAG do n = n + 1 list[n] = bag bag = bag + 1 end
  local slots = GetContainerNumSlots(BANK_MAIN)
  if slots and slots > 0 then
    n = n + 1
    list[n] = BANK_MAIN
    bag = FIRST_BANK_BAG
    while bag <= LAST_BANK_BAG do n = n + 1 list[n] = bag bag = bag + 1 end
  end
  return list, n
end

local function Sweep(tip)
  local found = 0
  sweeping = true
  local bags, bagCount = SweepBags()
  local i = 1
  while i <= bagCount do
    local bag = bags[i]
    local slots = GetContainerNumSlots(bag)
    if slots and slots > 0 then
      local slot = 1
      while slot <= slots do
        local texture, count = GetContainerItemInfo(bag, slot)
        if texture and texture ~= "" then
          local link = GetContainerItemLink(bag, slot)
          pendingKey = ItemKey(link)
          pendingName = ItemName(link)
          pendingCount = count or 1
          if pendingKey then
            local before = caught
            if tip.SetOwner then tip:SetOwner(UIParent, "ANCHOR_NONE") end
            tip:SetBagItem(bag, slot)
            if caught > before then found = found + 1 end
          end
          pendingKey, pendingName = nil, nil
        end
        slot = slot + 1
      end
    end
    i = i + 1
  end
  sweeping = false
  return found
end

local function Harvest(quiet)
  InitDB()
  BuildScanTooltip()

  caught = 0
  source = nil

  -- path 1: our own tooltip, nothing on screen moves
  local found = Sweep(scanTip)
  if found > 0 then
    source = "own tooltip"
  else
    -- path 2: the stock GameTooltip, parked off to the side
    if GameTooltip and GameTooltip.SetBagItem then
      local prevMoney = GameTooltip:GetScript("OnTooltipAddMoney")
      GameTooltip:SetScript("OnTooltipAddMoney", OnMoney)
      found = Sweep(GameTooltip)
      GameTooltip:SetScript("OnTooltipAddMoney", prevMoney)
      GameTooltip:Hide()
      if found > 0 then source = "stock GameTooltip" end
    end
  end

  local total = 0
  for _ in pairs(ItemLensDB.prices) do total = total + 1 end

  if found > 0 then
    if not quiet then
      Print(Lf("caught", found, tostring(source), total))
    end
  elseif not quiet then
    Print(L("caughtNone"))
  end
  return found
end

----------------------------------------------------------------------
-- tooltip line under the cursor
----------------------------------------------------------------------

-- Every bag window — the stock one and any addon — fills the tooltip through
-- GameTooltip:SetBagItem, so listening to that call is the one way to learn
-- the exact bag and slot no matter who drew the button. If this client will
-- not keep a function in a widget field the hook is quietly dropped and the
-- name based paths below still work.
local function InstallTooltipHook()
  if hookOK then return end
  if not GameTooltip or type(GameTooltip.SetBagItem) ~= "function" then return end

  local orig = GameTooltip.SetBagItem
  GameTooltip.SetBagItem = function(self, bag, slot)
    if not sweeping then
      hookBag, hookSlot = bag, slot
      lastName, lastLines = nil, nil
    end
    return orig(self, bag, slot)
  end

  if GameTooltip.SetBagItem == orig then
    hookOK = false                       -- assignment did not stick
  else
    hookOK = true
  end
end

-- Path one: a stock container button, where bag and slot are known exactly.
local function FocusSlot(widget)
  if not widget or not widget.GetName then return nil end
  local name = widget:GetName()
  if not name or name == "" then return nil end
  if string.find(name, "^ContainerFrame%d+Item%d+$") == nil then return nil end

  local slot = widget.GetID and widget:GetID()
  local parent = widget.GetParent and widget:GetParent()
  local bag = parent and parent.GetID and parent:GetID()
  if type(bag) ~= "number" or type(slot) ~= "number" then return nil end
  return bag, slot
end

-- Path two: read the item name straight off the tooltip. Works with any bag
-- addon, including our own window, because it needs no bag or slot at all.
local function FocusName()
  if not getglobal then return nil end
  local line = getglobal("GameTooltipTextLeft1")
  if not line or not line.GetText then return nil end
  local text = line:GetText()
  if not text or text == "" then return nil end
  return text
end

-- GetMerchantNumItems can keep reporting a loaded list after the window is
-- gone, so the open state is tracked by events instead.
local function MerchantOpen()
  return merchantOpen
end

-- The loot window is not a bag: how many lie there has nothing to do with
-- what is in the bags. Its own row is read from the button under the cursor,
-- and the count comes from the loot list itself.
local function LootSlot()
  if not GetMouseFocus or not GetLootSlotInfo then return nil end
  local widget = GetMouseFocus()
  if not widget or not widget.GetName then return nil end
  local wname = widget:GetName()
  if not wname or string.find(wname, "^LootButton%d+$") == nil then return nil end
  local id = widget.GetID and widget:GetID()
  if type(id) ~= "number" or id < 1 then return nil end
  return id
end

local function LootCount(name)
  local id = LootSlot()
  if not id then return nil end
  local _, itemName, count = GetLootSlotInfo(id)
  if not itemName or (name and itemName ~= name) then return nil end
  return count or 1
end

-- Which stack is under the cursor. The hook knows it exactly; the stock
-- container buttons can be read straight off the widget; failing both, the
-- item is looked up by name. Also returns which path answered, for the probe.
-- Which bag slot the cursor is over, by the same three paths as the stack
-- size. The comparison needs the slot itself, not just how many are in it.
local function HoverSlot(name)
  if SlotCount(hookBag, hookSlot, name) then return hookBag, hookSlot end

  if type(AllBags_MouseSlot) == "function" then
    local bag, slot = AllBags_MouseSlot()
    if bag and SlotCount(bag, slot, name) then return bag, slot end
  end

  if GetMouseFocus then
    local bag, slot = FocusSlot(GetMouseFocus())
    if bag and SlotCount(bag, slot, name) then return bag, slot end
  end
  return nil
end

-- A quest reward is neither a bag cell nor a loot row: it lives in the quest
-- giver window or in the quest log. The button under the cursor says which
-- one, and the reward is found by matching the name in the tooltip — the
-- index alone would not tell a choice from a fixed reward.
local function QuestReward(name)
  if not GetMouseFocus or not name then return nil end
  local widget = GetMouseFocus()
  if not widget or not widget.GetName then return nil end
  local wname = widget:GetName()
  if not wname then return nil end

  local inLog = string.find(wname, "^QuestLogItem%d+$") ~= nil
  local inGiver = string.find(wname, "^QuestRewardItem%d+$") ~= nil
      or string.find(wname, "^QuestProgressItem%d+$") ~= nil
  if not inLog and not inGiver then return nil end

  local kinds = { "choice", "reward" }
  local k = 1
  while kinds[k] do
    local kind = kinds[k]
    local n = 0
    if inLog then
      if kind == "choice" and GetNumQuestLogChoices then n = GetNumQuestLogChoices() or 0 end
      if kind == "reward" and GetNumQuestLogRewards then n = GetNumQuestLogRewards() or 0 end
    else
      if kind == "choice" and GetNumQuestChoices then n = GetNumQuestChoices() or 0 end
      if kind == "reward" and GetNumQuestRewards then n = GetNumQuestRewards() or 0 end
    end

    local i = 1
    while i <= n do
      local itemName, _, count
      if inLog then
        if kind == "choice" and GetQuestLogChoiceInfo then
          itemName, _, count = GetQuestLogChoiceInfo(i)
        elseif GetQuestLogRewardInfo then
          itemName, _, count = GetQuestLogRewardInfo(i)
        end
      elseif GetQuestItemInfo then
        itemName, _, count = GetQuestItemInfo(kind, i)
      end

      if itemName and itemName == name then
        local link = nil
        if inLog then
          if GetQuestLogItemLink then link = GetQuestLogItemLink(kind, i) end
        elseif GetQuestItemLink then
          link = GetQuestItemLink(kind, i)
        end
        return link, count or 1
      end
      i = i + 1
    end
    k = k + 1
  end
  return nil
end

-- The link of whatever is under the cursor: a bag cell, a row in the loot
-- window, or a quest reward. All three can be compared with the gear being
-- worn; anything else cannot.
local function HoverLink(name)
  local bag, slot = HoverSlot(name)
  if bag and GetContainerItemLink then return GetContainerItemLink(bag, slot) end

  local id = LootSlot()
  if id and GetLootSlotLink then
    local link = GetLootSlotLink(id)
    if link then return link end
  end

  local questLink = QuestReward(name)
  if questLink then return questLink end
  return nil
end

local function HoverCount(name)
  local count = SlotCount(hookBag, hookSlot, name)
  if count then return count, L("pathHook") end

  -- our own bag window tells us the cell it is showing
  if type(AllBags_MouseSlot) == "function" then
    local bag, slot = AllBags_MouseSlot()
    if bag then
      count = SlotCount(bag, slot, name)
      if count then return count, L("pathBags") end
    end
  end

  if GetMouseFocus then
    local bag, slot = FocusSlot(GetMouseFocus())
    if bag then
      count = SlotCount(bag, slot, name)
      if count then return count, L("pathStock") end
    end
  end
  count = LootCount(name)
  if count then return count, L("pathLoot") end

  local _, questCount = QuestReward(name)
  if questCount then return questCount, L("pathQuest") end

  -- Nothing else is guessed. Looking the name up in the bags used to fill
  -- this gap, but it answers with the bag stack even when the tooltip belongs
  -- to a loot window or a vendor list, and a wrong total is worse than none.
  return nil, L("pathNone")
end

-- Does the client print its own price right now? 1 yes, 0 no, nil cannot tell.
-- While a merchant is open the client normally shows the price itself and we
-- keep quiet, but if its money line is missing ours takes over.
local function ClientPriceState()
  if not getglobal then return nil end
  local frame = getglobal("GameTooltipMoneyFrame")
  if not frame or not frame.IsShown then return nil end
  if frame:IsShown() then return 1 end
  return 0
end

-- The tooltip itself is the signal: when its first line changes we have a new
-- item under the cursor. This needs neither the mouse focus nor a bag slot,
-- so it works with the stock bags and with any bag addon alike.
-- /il tiptest answered this for good on the live client:
--   * lines an addon appends CAN be read back (they appear as
--     GameTooltipTextLeftN like any other);
--   * the colour codes inside them do NOT survive — the client stores the
--     text stripped of them.
-- So a fingerprint made of colour codes is invisible, and the honest check is
-- to compare the plain text: strip the codes from what we are about to write
-- and look for that exact text among the lines already there.
local MARK_PRICE  = "|cffffd701"
local MARK_HEAD   = "|cff9d9d9e"
local MARK_PLUS   = "|cff40ff41"
local MARK_MINUS  = "|cffff5051"

local Marked
function MarkedLine(text) return Marked and Marked(text) end

Marked = function(text)
  if not text then return false end
  if string.find(text, MARK_PRICE, 1, true) then return true end
  if string.find(text, MARK_HEAD, 1, true) then return true end
  if string.find(text, MARK_PLUS, 1, true) then return true end
  if string.find(text, MARK_MINUS, 1, true) then return true end
  return false
end

-- Is our work already in this tooltip?
--
-- The line count is read by walking the font strings until one does not
-- exist, NOT by asking NumLines. On this client NumLines does not count the
-- lines an addon appends, so a check based on it looked at the original lines
-- only, never saw our mark, and cheerfully wrote the block again on every
-- pass. That is what made the tooltip grow.
local MAX_SCAN = 60

-- Is this text already among the tooltip lines? The price line and the
-- comparison are asked about separately: the price is normally there before
-- Shift is pressed, and one shared answer would have counted that as
-- "everything is written" and never added the comparison.
local function TooltipHasText(needle)
  if not getglobal or not needle or needle == "" then return false end

  -- Only the lines that belong to the tooltip as it is drawn right now. The
  -- font strings below that keep the text of whatever was shown before, and
  -- reading them made two identical items in different bag slots look like
  -- "already written" — so the second one got no price at all.
  local last = MAX_SCAN
  if GameTooltip.NumLines then
    local n = GameTooltip:NumLines()
    if type(n) == "number" and n > 0 then last = n end
  end

  local i = 2
  while i <= last do
    local fs = getglobal("GameTooltipTextLeft" .. i)
    if not fs then return false end
    local text = fs.GetText and fs:GetText()
    if text and text ~= "" and string.find(text, needle, 1, true) then return true end
    i = i + 1
  end
  return false
end

-- The word the comparison header always carries, whatever the slot is called.
local function CompareToken()
  local token = string.gsub(L("cmpInstead"), "%%s", "")
  token = string.gsub(token, "%s+$", "")
  return token
end

local function ShiftDown()
  return (IsShiftKeyDown and IsShiftKeyDown()) and true or false
end

-- The price line the tooltip gets, or nil when there is nothing to say.
local function PriceLine(name)
  if not ItemLensDB.tooltip then return nil end
  -- while a merchant is open the client usually prints the price itself
  if merchantOpen and ClientPriceState() ~= 0 then return nil end

  local price = ItemLensDB.prices["n" .. name]
  if not price then return nil end

  local count, path = HoverCount(name)
  countPath = path
  local mode = ItemLensDB.mode or "vendor"
  local each = math.floor(price + 0.5)

  if mode == "each" or not count then
    return Lf("each", FormatMoney(each))         -- stack size unknown, be explicit
  elseif count <= 1 then
    return FormatMoney(each)                     -- single item: both numbers agree
  elseif mode == "stack" then
    return FormatMoney(price * count)            -- exactly what the merchant shows
  end
  return Lf("stackEach", FormatMoney(price * count), FormatMoney(each))
end

-- A tooltip cannot have lines removed, only rebuilt. So when Shift is let go
-- the item is simply set into the tooltip again: the client redraws it from
-- scratch, our comparison is gone with it, and the price line is written back
-- below. Without this the comparison would sit there until the cursor moved.
local function Redraw(name)
  if not GameTooltip then return false end

  local bag, slot = HoverSlot(name)
  if bag and GameTooltip.SetBagItem then
    local ok = pcall(function() GameTooltip:SetBagItem(bag, slot) end)
    if ok then return true end
  end

  local id = LootSlot()
  if id and GameTooltip.SetLootItem then
    local ok = pcall(function() GameTooltip:SetLootItem(id) end)
    if ok then return true end
  end
  return false
end

local function Annotate()
  if not GameTooltip or not GameTooltip.IsShown then return end

  if not GameTooltip:IsShown() then
    -- The tooltip has to be gone for a few frames in a row before we believe
    -- it. A single "not shown" frame in the middle of a hover used to re-arm
    -- the writer, and the line was appended again, and again — that is where
    -- the growing column of prices came from.
    hiddenFrames = hiddenFrames + 1
    if hiddenFrames >= 3 then
      lastName = nil
      lastLines = nil
      hookBag, hookSlot = nil, nil   -- do not reuse a slot from the last hover
    end
    return
  end
  hiddenFrames = 0

  local name = FocusName()
  if not name then return end

  local shift = ShiftDown()

  -- Shift has just been released: rebuild the tooltip so the comparison goes
  -- away instead of hanging around. The rebuild wipes our price line too, and
  -- it is written back below.
  if lastShift and not shift and name == lastName then
    Redraw(name)
  end
  lastShift = shift
  lastName = name

  local written = 0

  -- Each part is written only if its own text is not already in the tooltip.
  -- No bookkeeping, no guessing about redraws: the tooltip itself is asked.
  local price = PriceLine(name)
  if price then
    local plain = StripCodes(price)
    if not TooltipHasText(plain) then
      GameTooltip:AddLine(MARK_PRICE .. price .. "|r", 1, 0.82, 0)
      written = written + 1
    end
  end

  if shift and ItemLensDB.compare then
    if not TooltipHasText(CompareToken())
       and not TooltipHasText(L("cmpEmpty"))
       and not TooltipHasText(L("cmpNoData")) then
      written = written + CompareLines(HoverLink(name))
    end
  end

  if written == 0 then return end

  GameTooltip:Show()
  if GameTooltip.NumLines then lastLines = GameTooltip:NumLines() end
end

-- The stock bag button rebuilds its tooltip from scratch every fifth of a
-- second (ContainerFrameItemButton_OnUpdate calls the OnEnter function again),
-- which wipes whatever we appended. Rather than race it frame by frame, the
-- global that does the rebuilding is wrapped so our line is written last,
-- every time. Replacing a global function is something this client allows —
-- unlike keeping a function in a widget field.
local function ForceAnnotate()
  lastName, lastLines = nil, nil
  Annotate()
end

local function HookStockBags()
  if stockHookOK then return end
  if type(ContainerFrameItemButton_OnEnter) ~= "function" then return end

  local orig = ContainerFrameItemButton_OnEnter
  ContainerFrameItemButton_OnEnter = function()
    orig()

    -- inside this call `this` IS the bag button, so the bag and the slot are
    -- known exactly — no need to guess them from the mouse focus, which does
    -- not always answer for the stock frames.
    local btn = this
    if btn and btn.GetID and btn.GetParent then
      local slot = btn:GetID()
      local parent = btn:GetParent()
      local bag = parent and parent.GetID and parent:GetID()
      if type(bag) == "number" and type(slot) == "number" then
        hookBag, hookSlot = bag, slot
      end
    end

    ForceAnnotate()
  end
  stockHookOK = (ContainerFrameItemButton_OnEnter ~= orig)
end

----------------------------------------------------------------------
-- comparing a bag item with what is worn
----------------------------------------------------------------------

-- There is no API for an item's stats on this client — the numbers live only
-- in the text of the tooltip. So the worn item is drawn into a tooltip of our
-- own and its lines are read back. The trick that keeps this language
-- independent: we never try to understand what a stat means. A line is split
-- into "number" and "the rest", and lines whose rest matches are subtracted
-- from one another. "+5 к ловкости" against "+8 к ловкости" gives +3 without
-- anyone knowing what ловкость is.

local COMPARE_SLOTS = {
  INVTYPE_HEAD            = { {"HeadSlot", "slotHead"} },
  INVTYPE_NECK            = { {"NeckSlot", "slotNeck"} },
  INVTYPE_SHOULDER        = { {"ShoulderSlot", "slotShoulder"} },
  INVTYPE_BODY            = { {"ShirtSlot", "slotShirt"} },
  INVTYPE_CHEST           = { {"ChestSlot", "slotChest"} },
  INVTYPE_ROBE            = { {"ChestSlot", "slotChest"} },
  INVTYPE_WAIST           = { {"WaistSlot", "slotWaist"} },
  INVTYPE_LEGS            = { {"LegsSlot", "slotLegs"} },
  INVTYPE_FEET            = { {"FeetSlot", "slotFeet"} },
  INVTYPE_WRIST           = { {"WristSlot", "slotWrist"} },
  INVTYPE_HAND            = { {"HandsSlot", "slotHands"} },
  INVTYPE_FINGER          = { {"Finger0Slot", "slotFinger"}, {"Finger1Slot", "slotFinger"} },
  INVTYPE_TRINKET         = { {"Trinket0Slot", "slotTrinket"}, {"Trinket1Slot", "slotTrinket"} },
  INVTYPE_CLOAK           = { {"BackSlot", "slotBack"} },
  INVTYPE_WEAPON          = { {"MainHandSlot", "slotMain"}, {"SecondaryHandSlot", "slotOff"} },
  INVTYPE_2HWEAPON        = { {"MainHandSlot", "slotMain"} },
  INVTYPE_WEAPONMAINHAND  = { {"MainHandSlot", "slotMain"} },
  INVTYPE_WEAPONOFFHAND   = { {"SecondaryHandSlot", "slotOff"} },
  INVTYPE_SHIELD          = { {"SecondaryHandSlot", "slotOff"} },
  INVTYPE_HOLDABLE        = { {"SecondaryHandSlot", "slotOff"} },
  INVTYPE_RANGED          = { {"RangedSlot", "slotRanged"} },
  INVTYPE_RANGEDRIGHT     = { {"RangedSlot", "slotRanged"} },
  INVTYPE_THROWN          = { {"RangedSlot", "slotRanged"} },
  INVTYPE_RELIC           = { {"RangedSlot", "slotRanged"} },
  INVTYPE_TABARD          = { {"TabardSlot", "slotTabard"} },
  INVTYPE_AMMO            = { {"AmmoSlot", "slotAmmo"} },
}

local CMP_TIP = "ItemLensCompareTooltip"
local cmpTip, cmpReady = nil, nil

-- A tooltip built from the stock template has named font strings we can read.
-- Without the template there is nothing to read, and the feature says so
-- rather than pretending.
local function CompareTooltip()
  if cmpReady ~= nil then return cmpReady end
  cmpReady = false
  if not CreateFrame or not getglobal then return false end

  pcall(function()
    cmpTip = CreateFrame("GameTooltip", CMP_TIP, UIParent, "GameTooltipTemplate")
  end)
  if not cmpTip then return false end
  pcall(function() cmpTip:SetOwner(UIParent, "ANCHOR_NONE") end)
  cmpReady = (getglobal(CMP_TIP .. "TextLeft1") ~= nil)
  return cmpReady
end

-- "the rest" of a stat line: no digits, not too long, and none of the
-- punctuation that marks a requirement or a durability line
local function StatKey(rest)
  if not rest or rest == "" then return nil end
  if string.find(rest, "%d") then return nil end
  if string.find(rest, ":") then return nil end
  if string.find(rest, "/") then return nil end
  if string.len(rest) > 40 then return nil end
  return rest
end

local function ParseStat(text)
  if not text or text == "" then return nil end
  if string.find(text, "/") then return nil end     -- durability
  if string.find(text, ":") then return nil end     -- "Requires level: 5"

  local _, _, sign, num, rest = string.find(text, "^([%+%-])(%d+)%s+(.+)$")
  if num then
    local key = StatKey(rest)
    if not key then return nil end
    local value = tonumber(num)
    if sign == "-" then value = -value end
    return key, value
  end

  local _, _, rest2, num2 = string.find(text, "^(.-)%s+(%d+)$")   -- "Armor 128"
  if num2 then
    local key = StatKey(rest2)
    if key then return key, tonumber(num2) end
  end

  local _, _, num3, rest3 = string.find(text, "^(%d+)%s+(.-)$")   -- "128 Armor"
  if num3 then
    local key = StatKey(rest3)
    if key then return key, tonumber(num3) end
  end
  return nil
end

-- Same walk as above: font strings until one is missing, never NumLines.
local function StatsFrom(prefix)
  local stats = {}
  local i = 2                                   -- line 1 is the item name
  while i <= MAX_SCAN do
    local fs = getglobal(prefix .. "TextLeft" .. i)
    if not fs then return stats end
    local text = fs.GetText and fs:GetText()
    if MarkedLine and MarkedLine(text) then text = nil end   -- never read our own work
    local key, value = ParseStat(text)
    if key then stats[key] = (stats[key] or 0) + value end
    i = i + 1
  end
  return stats
end

-- Stats of the item currently under the cursor, read from the tooltip the
-- client has already drawn.
local function HoveredStats()
  if not GameTooltip then return nil end
  return StatsFrom("GameTooltip")
end

local function WornStats(slotId)
  if not cmpTip then return nil end
  pcall(function() cmpTip:SetOwner(UIParent, "ANCHOR_NONE") end)
  if cmpTip.ClearLines then pcall(function() cmpTip:ClearLines() end) end
  local ok = pcall(function() cmpTip:SetInventoryItem("player", slotId) end)
  if not ok then return nil end
  local first = getglobal(CMP_TIP .. "TextLeft1")
  local wornName = first and first.GetText and first:GetText()
  if not wornName or wornName == "" then return nil end
  return StatsFrom(CMP_TIP), wornName
end

-- One slot: adds the "instead of X" header and a line per changed stat.
local function CompareWithSlot(slotName, labelKey, mine)
  if not GetInventorySlotInfo or not GetInventoryItemLink then return 0 end
  local id = GetInventorySlotInfo(slotName)
  if not id or id == 0 then return 0 end

  local link = GetInventoryItemLink("player", id)
  -- an empty slot answers with a link carrying item id 0, not with nil
  if not link or string.find(link, "item:0:") or string.find(link, "item:0|") then
    GameTooltip:AddLine(MARK_HEAD .. L(labelKey) .. ": " .. L("cmpEmpty") .. "|r", 0.6, 0.6, 0.6)
    return 1
  end

  local theirs, wornName = WornStats(id)
  if not theirs then return 0 end

  GameTooltip:AddLine(MARK_HEAD .. L(labelKey) .. " — "
    .. Lf("cmpInstead", tostring(wornName or "?")) .. "|r", 0.6, 0.6, 0.6)

  local written = 1
  local seen = {}
  for key, value in pairs(mine) do
    seen[key] = true
    local diff = value - (theirs[key] or 0)
    if diff ~= 0 and written < 10 then
      if diff > 0 then
        GameTooltip:AddLine(MARK_PLUS .. "+" .. diff .. " " .. key .. "|r", 0.2, 1, 0.2)
      else
        GameTooltip:AddLine(MARK_MINUS .. diff .. " " .. key .. "|r", 1, 0.3, 0.3)
      end
      written = written + 1
    end
  end
  for key, value in pairs(theirs) do
    if not seen[key] and written < 10 then
      GameTooltip:AddLine(MARK_MINUS .. "-" .. value .. " " .. key .. "|r", 1, 0.3, 0.3)
      written = written + 1
    end
  end

  if written == 1 then
    GameTooltip:AddLine(MARK_HEAD .. L("cmpSame") .. "|r", 0.6, 0.6, 0.6)
    written = 2
  end
  return written
end

-- Returns how many lines were added, so the caller knows whether to redraw.
CompareLines = function(link)
  if not link or not GetItemInfo then return 0 end

  local _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
  if not equipLoc or equipLoc == "" then return 0 end    -- not equippable

  local targets = COMPARE_SLOTS[equipLoc]
  if not targets then return 0 end

  if not CompareTooltip() then
    GameTooltip:AddLine(MARK_HEAD .. L("cmpNoData") .. "|r", 1, 0.5, 0.5)
    return 1
  end

  local mine = HoveredStats()
  if not mine then return 0 end

  local written = 0
  local i = 1
  while targets[i] do
    written = written + CompareWithSlot(targets[i][1], targets[i][2], mine)
    i = i + 1
  end
  return written
end

----------------------------------------------------------------------
-- repairing at the merchant
----------------------------------------------------------------------

-- Money is spent here, so nothing happens unless it was asked for, and never
-- above the ceiling the player set.
local function TryRepair()
  if not ItemLensDB.repair then return end
  if type(CanMerchantRepair) ~= "function" or not CanMerchantRepair() then return end
  if type(GetRepairAllCost) ~= "function" then return end

  local cost, canAfford = GetRepairAllCost()
  if type(cost) ~= "number" or cost <= 0 then return end

  local cap = ItemLensDB.repairmax or 0
  if cap > 0 and cost > cap then
    Print(Lf("repairDear", FormatMoney(cost), FormatMoney(cap)))
    return
  end

  if not canAfford then
    Print(Lf("repairPoor", FormatMoney(cost)))
    return
  end

  if type(RepairAllItems) ~= "function" then return end
  RepairAllItems()
  Print(Lf("repairDone", FormatMoney(cost)))
end

----------------------------------------------------------------------
-- what the loot was worth
----------------------------------------------------------------------

-- The chat message for one's own loot is a localised format string kept in a
-- global, so the patterns are built from those globals instead of hardcoding
-- any language. LOOT_ITEM_SELF is "You receive loot: %s." and the MULTIPLE
-- variant carries the stack size as well.
local function BuildLootPatterns()
  if lootPatterns then return lootPatterns end
  lootPatterns = {}
  lootPatternsN = 0

  local function add(fmt, hasCount)
    if type(fmt) ~= "string" then return end
    local pat = string.gsub(fmt, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    pat = string.gsub(pat, "%%s", "(.+)")
    pat = string.gsub(pat, "%%d", "(%%d+)")
    lootPatternsN = lootPatternsN + 1
    lootPatterns[lootPatternsN] = { pat = "^" .. pat .. "$", count = hasCount }
  end

  add(LOOT_ITEM_SELF_MULTIPLE, true)      -- must be tried before the single form
  add(LOOT_ITEM_PUSHED_SELF_MULTIPLE, true)
  add(LOOT_ITEM_SELF, false)
  add(LOOT_ITEM_PUSHED_SELF, false)
  return lootPatterns
end

-- Returns item name and stack size, or nil when the line is somebody else's.
local function ParseLoot(text)
  if not text then return nil end
  local pats = BuildLootPatterns()

  local i = 1
  while i <= lootPatternsN do
    local entry = pats[i]
    local _, _, a, b = string.find(text, entry.pat)
    if a then
      local name = ItemName(a) or a
      local count = 1
      if entry.count then count = tonumber(b) or 1 end
      return name, count
    end
    i = i + 1
  end

  -- No usable globals on this client: fall back to a line that carries an
  -- item link and no other player name in front of it.
  if lootPatternsN == 0 then
    local name = ItemName(text)
    if name then
      local _, _, n = string.find(text, "[xX](%d+)%.?$")
      return name, tonumber(n) or 1
    end
  end
  return nil
end

local function NoteLoot(text)
  if not ItemLensDB.lootchat then return end
  local name, count = ParseLoot(text)
  if not name then return end

  local price = ItemLensDB.prices["n" .. name]
  if price then
    lootValue = lootValue + price * count
    lootItems = lootItems + count
  else
    lootUnknown = lootUnknown + count
  end

  lootTimer = ItemLensDB.lootwait
  if lootTimer <= 0 then lootTimer = 0.01 end
end

local function FlushLoot()
  if lootValue > 0 then
    local line = Lf("loot", FormatMoney(lootValue), lootItems)
    if lootUnknown > 0 then line = line .. Lf("lootUnknown", lootUnknown) end
    Print(line)
  end
  lootValue, lootItems, lootUnknown = 0, 0, 0
end

----------------------------------------------------------------------
-- bag worth
----------------------------------------------------------------------

-- Walks one container and adds it up. Used for the bags, the bank window and
-- the bank bags alike.
local function ContainerWorth(bag, total, known, unknown)
  local slots = GetContainerNumSlots(bag)
  if not slots or slots <= 0 then return total, known, unknown, false end
  local slot = 1
  while slot <= slots do
    local texture, count = GetContainerItemInfo(bag, slot)
    if texture and texture ~= "" then
      local price = PriceOf(bag, slot)
      if price then
        total = total + price * (count or 1)
        known = known + 1
      else
        unknown = unknown + 1
      end
    end
    slot = slot + 1
  end
  return total, known, unknown, true
end

-- The bank can only be counted while its window is open. The result is kept
-- in the saved variables so the number is still there afterwards, marked as
-- "as of the last visit" rather than pretending to be current.
local function BankWorth()
  local total, known, unknown, seen = 0, 0, 0, false
  local ok
  total, known, unknown, ok = ContainerWorth(BANK_MAIN, total, known, unknown)
  seen = seen or ok
  local bag = FIRST_BANK_BAG
  while bag <= LAST_BANK_BAG do
    total, known, unknown, ok = ContainerWorth(bag, total, known, unknown)
    seen = seen or ok
    bag = bag + 1
  end
  if not seen then return nil end
  return total, known, unknown
end

local function RememberBank()
  local total, known, unknown = BankWorth()
  if not total then return nil end
  ItemLensDB.bank = { total = total, known = known, unknown = unknown }
  return total, known, unknown
end

local function BagWorth()
  local total, known, unknown = 0, 0, 0
  local bag = FIRST_BAG
  while bag <= LAST_BAG do
    local slots = GetContainerNumSlots(bag)
    if slots and slots > 0 then
      local slot = 1
      while slot <= slots do
        local texture, count = GetContainerItemInfo(bag, slot)
        if texture and texture ~= "" then
          local price = PriceOf(bag, slot)
          if price then
            total = total + price * (count or 1)
            known = known + 1
          else
            unknown = unknown + 1
          end
        end
        slot = slot + 1
      end
    end
    bag = bag + 1
  end
  return total, known, unknown
end

----------------------------------------------------------------------
-- selling grey items
----------------------------------------------------------------------

-- Builds the list of poor quality items. Nothing is sold here; the queue is
-- drained one item per tick so the server is not hit with a burst.
local function BuildSellQueue()
  queue, queueN, queueAt = {}, 0, 0

  local bag = FIRST_BAG
  while bag <= LAST_BAG do
    local slots = GetContainerNumSlots(bag)
    if slots and slots > 0 then
      local slot = 1
      while slot <= slots do
        local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
        if texture and texture ~= "" and quality == POOR and not locked then
          local name = ItemName(GetContainerItemLink(bag, slot))
          if not (name and ItemLensDB.keep[name]) then
            queueN = queueN + 1
            queue[queueN] = { bag = bag, slot = slot, name = name, count = count or 1 }
          end
        end
        slot = slot + 1
      end
    end
    bag = bag + 1
  end

  return queueN
end

local function StartSelling()
  if not ItemLensDB.autosell then return end
  if BuildSellQueue() == 0 then return end

  sellStartMoney = GetMoney and GetMoney() or 0
  sellCount = 0
  sellReported = false
  sellTimer = SELL_STEP
  Debug("sell queue: " .. queueN)
end

local function StopSelling()
  queue, queueN, queueAt = {}, 0, 0
  sellTimer = 0
end

local function SellTick(elapsed)
  if queueAt >= queueN then
    -- queue drained: report once, after the last sale has settled
    if not sellReported and queueN > 0 then
      sellTimer = sellTimer - elapsed
      if sellTimer <= 0 then
        sellReported = true
        local gained = (GetMoney and GetMoney() or 0) - sellStartMoney
        if sellCount > 0 then
          Print(Lf("sold", sellCount, FormatMoney(gained)))
        end
        StopSelling()
      end
    end
    return
  end

  sellTimer = sellTimer - elapsed
  if sellTimer > 0 then return end
  sellTimer = SELL_STEP

  queueAt = queueAt + 1
  local it = queue[queueAt]
  if not it then return end

  -- the slot could have changed since the queue was built
  local texture, _, locked, quality = GetContainerItemInfo(it.bag, it.slot)
  if texture and texture ~= "" and quality == POOR and not locked then
    UseContainerItem(it.bag, it.slot)
    sellCount = sellCount + 1
    Debug("sold " .. tostring(it.name))
  end
end

----------------------------------------------------------------------
-- delayed self check: type the command, then hover an item
----------------------------------------------------------------------

local function RunProbe()
  local focus = GetMouseFocus and GetMouseFocus()
  local fname = "-"
  if focus and focus.GetName then fname = focus:GetName() or L("noName") end

  local second = GetMouseFocus and GetMouseFocus()
  local stable = (focus == second) and L("yes") or L("unstable")

  local shown = (GameTooltip and GameTooltip.IsShown and GameTooltip:IsShown()) and L("yes") or L("no")

  local line = getglobal and getglobal("GameTooltipTextLeft1")
  local text = (line and line.GetText and line:GetText()) or nil

  local merchN = GetMerchantNumItems and GetMerchantNumItems() or -1

  local total = 0
  for _ in pairs(ItemLensDB.prices) do total = total + 1 end

  Print(L("probeHead"))
  Print(Lf("probeFocus", fname, stable))
  Print(Lf("probeShown", shown, tostring(text)))
  Print(Lf("probeLeft1", tostring(line ~= nil)))
  Print(Lf("probeMerch", tostring(merchantOpen), tostring(merchN)))
  Print(Lf("probeStock", stockHookOK and L("yes")
      or (type(ContainerFrameItemButton_OnEnter) == "function" and L("no") or L("noFunc"))))
  Print(Lf("probeHook", hookOK and L("works") or L("worksNot"), tostring(hookBag), tostring(hookSlot)))
  if text then
    local c, path = HoverCount(text)
    Print(Lf("probeStack", tostring(c), tostring(path)))
  end
  local cps = ClientPriceState()
  Print(Lf("probeClient", cps == 1 and L("yes") or (cps == 0 and L("no") or L("unknown")),
    tostring(ItemLensDB.mode)))
  if text then
    Print(Lf("probePrice", tostring(ItemLensDB.prices["n" .. text])))
  end
  Print(Lf("probeTotals", total, lootPatternsN, ItemLensDB.lootchat and L("on") or L("off")))
  Print(Lf("probeCmp", ItemLensDB.compare and L("on") or L("off"),
    CompareTooltip() and L("yes") or L("no")))
end

----------------------------------------------------------------------
-- public helpers for other addons (the bag window uses these)
----------------------------------------------------------------------

-- Total vendor value of everything in the bags.
-- Returns copper, how many stacks had a known price, how many did not.
function ItemLens_BagValue()
  InitDB()
  return BagWorth()
end

-- Vendor price of one bag slot, per single item, or nil when unknown.
function ItemLens_SlotPrice(bag, slot)
  InitDB()
  return PriceOf(bag, slot)
end

function ItemLens_Format(copper)
  return FormatMoney(copper)
end

-- What the bank held, fresh if its window is open, otherwise as of the last
-- visit. Returns nil when it has never been seen.
function ItemLens_BankValue()
  InitDB()
  local total, known, unknown = BankWorth()
  if total then return total, known, unknown, true end
  local saved = ItemLensDB.bank
  if type(saved) == "table" then return saved.total, saved.known, saved.unknown, false end
  return nil
end

----------------------------------------------------------------------
-- settings window and the minimap button
----------------------------------------------------------------------

-- Everything the addon can be told is here, so nothing has to be remembered
-- as a slash command. The commands still work; this is the same switches with
-- a face. Lessons this client taught us are baked in: a bare Button gets no
-- text colour of its own, so every label carries a colour code; a fresh frame
-- is visible until told otherwise; and the window position is stored as an
-- absolute corner, never as an anchor pair.

local cfg, cfgRows, cfgTitle, cfgStats, cfgHint
local cfgScanBtn, cfgWorthBtn, cfgClearBtn
local mmButton
local ROW_H = 18

local function CfgFont(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  if not fs:GetFont() or fs:GetFont() == "" then
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "")
  end
  return fs
end

local function CfgButton(name, parent, width, handler)
  local b = CreateFrame("Button", name, parent)
  b:SetWidth(width)
  b:SetHeight(ROW_H)
  b:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  b:SetScript("OnClick", handler)
  return b
end

local function Mark(on)
  if on then return "|cff40ff40[x]|r " end
  return "|cff808080[  ]|r "
end

local function Pick(on)
  if on then return "|cff40ff40(*)|r " end
  return "|cff808080( )|r "
end

local UpdateCfg

-- Every switch is described here once: what it says, whether it is on, and
-- what a click does. Drawing and clicking both read this list, so the window
-- can never disagree with itself.
local function CfgItems()
  local items, n = {}, 0
  local function add(entry) n = n + 1 items[n] = entry end

  add({ kind = "check", text = L("cfgTooltip"), on = ItemLensDB.tooltip,
        click = function() ItemLensDB.tooltip = not ItemLensDB.tooltip end })
  add({ kind = "check", text = L("cfgCompare"), on = ItemLensDB.compare,
        click = function() ItemLensDB.compare = not ItemLensDB.compare end })
  add({ kind = "check", text = L("cfgAutosell"), on = ItemLensDB.autosell,
        click = function() ItemLensDB.autosell = not ItemLensDB.autosell end })
  add({ kind = "check", text = L("cfgLootChat"), on = ItemLensDB.lootchat,
        click = function() ItemLensDB.lootchat = not ItemLensDB.lootchat end })
  add({ kind = "check", text = L("cfgRepair"), on = ItemLensDB.repair,
        click = function() ItemLensDB.repair = not ItemLensDB.repair end })
  add({ kind = "check", text = L("cfgScanMsg"), on = ItemLensDB.scanmsg,
        click = function() ItemLensDB.scanmsg = not ItemLensDB.scanmsg end })

  add({ kind = "head", text = L("cfgMode") })
  add({ kind = "pick", text = L("modeVendor"), on = (ItemLensDB.mode == "vendor"),
        click = function() ItemLensDB.mode = "vendor" end })
  add({ kind = "pick", text = L("modeStack"), on = (ItemLensDB.mode == "stack"),
        click = function() ItemLensDB.mode = "stack" end })
  add({ kind = "pick", text = L("modeEach"), on = (ItemLensDB.mode == "each"),
        click = function() ItemLensDB.mode = "each" end })

  add({ kind = "head", text = L("cfgLootWait") })
  local waits = { 0.5, 1, 2, 3 }
  local i = 1
  while waits[i] do
    local w = waits[i]
    add({ kind = "pick", text = w .. " c", on = (ItemLensDB.lootwait == w),
          click = function() ItemLensDB.lootwait = w end })
    i = i + 1
  end

  add({ kind = "head", text = L("cfgCap") })
  local caps = { 0, 10000, 50000, 200000 }
  i = 1
  while caps[i] do
    local c = caps[i]
    add({ kind = "pick", text = (c == 0) and L("cfgNoCap") or FormatMoney(c),
          on = ((ItemLensDB.repairmax or 0) == c),
          click = function() ItemLensDB.repairmax = c end })
    i = i + 1
  end

  add({ kind = "head", text = L("cfgLang") })
  add({ kind = "pick", text = L("cfgAuto"), on = (ItemLensDB.lang == "auto"),
        click = function() ItemLensDB.lang = "auto" end })
  add({ kind = "pick", text = "Русский", on = (ItemLensDB.lang == "ru"),
        click = function() ItemLensDB.lang = "ru" end })
  add({ kind = "pick", text = "English", on = (ItemLensDB.lang == "en"),
        click = function() ItemLensDB.lang = "en" end })

  return items, n
end

local function CfgRowClick(self)
  self = self or this
  local i = nil
  if self.GetName then
    local nm = self:GetName()
    if nm and string.sub(nm, 1, 14) == "ItemLensCfgRow" then
      i = tonumber(string.sub(nm, 15))
    end
  end
  if not i then return end
  local items = CfgItems()
  local entry = items[i]
  if not entry or not entry.click then return end
  entry.click()
  UpdateCfg()
end

local function ApplyCfgPosition()
  if not cfg then return end
  cfg:ClearAllPoints()
  local x, y = ItemLensDB.cfgx, ItemLensDB.cfgy
  if type(x) == "number" and type(y) == "number" then
    cfg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
  else
    cfg:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

local function SaveCfgPosition()
  if not cfg or not cfg.GetLeft then return end
  local x, y = cfg:GetLeft(), cfg:GetBottom()
  if type(x) == "number" and type(y) == "number" then
    ItemLensDB.cfgx, ItemLensDB.cfgy = x, y
    ApplyCfgPosition()
  end
end

local function BuildCfg()
  if cfg then return end

  local _, rows = CfgItems()

  cfg = CreateFrame("Frame", "ItemLensCfg", UIParent)
  cfg:SetWidth(320)
  cfg:SetHeight(70 + rows * ROW_H + 36)
  cfg:SetFrameStrata("DIALOG")
  cfg:SetToplevel(true)
  cfg:SetMovable(true)
  cfg:EnableMouse(true)
  cfg:RegisterForDrag("LeftButton")
  cfg:SetScript("OnDragStart", function(self) (self or this):StartMoving() end)
  cfg:SetScript("OnMouseDown", function(self, button)
    self = self or this
    local b = button or arg1
    if b and b ~= "LeftButton" then return end
    self:StartMoving()
  end)
  cfg:SetScript("OnDragStop", function(self)
    self = self or this
    self:StopMovingOrSizing()
    SaveCfgPosition()
  end)
  cfg:SetScript("OnMouseUp", function(self)
    self = self or this
    self:StopMovingOrSizing()
    SaveCfgPosition()
  end)
  cfg:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })

  cfgTitle = cfg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if not cfgTitle:GetFont() or cfgTitle:GetFont() == "" then
    cfgTitle:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
  end
  cfgTitle:SetPoint("TOP", cfg, "TOP", 0, -16)

  local close
  local ok = pcall(function()
    close = CreateFrame("Button", "ItemLensCfgClose", cfg, "UIPanelCloseButton")
  end)
  if not ok or not close then
    close = CfgButton("ItemLensCfgClose", cfg, 20, function() cfg:Hide() end)
    close:SetText("|cffff6060X|r")
  end
  close:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -10, -8)
  close:SetScript("OnClick", function() cfg:Hide() end)

  cfgRows = {}
  local i = 1
  while i <= rows do
    local row = CfgButton("ItemLensCfgRow" .. i, cfg, 280, CfgRowClick)
    row:SetPoint("TOPLEFT", cfg, "TOPLEFT", 18, -40 - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -18, -40 - (i - 1) * ROW_H)
    cfgRows[i] = row
    i = i + 1
  end

  local bottom = 40 + rows * ROW_H + 6

  local scan = CfgButton("ItemLensCfgScan", cfg, 92, function() Harvest(false) end)
  scan:SetPoint("TOPLEFT", cfg, "TOPLEFT", 18, -bottom)
  cfgScanBtn = scan

  local worth = CfgButton("ItemLensCfgWorth", cfg, 92, function()
    SlashCmdList["ITEMLENS"]("worth")
  end)
  worth:SetPoint("TOPLEFT", cfg, "TOPLEFT", 114, -bottom)
  cfgWorthBtn = worth

  local clear = CfgButton("ItemLensCfgClear", cfg, 92, function()
    ItemLensDB.prices = {}
    Print(L("cleared"))
    UpdateCfg()
  end)
  clear:SetPoint("TOPLEFT", cfg, "TOPLEFT", 210, -bottom)
  cfgClearBtn = clear

  cfgStats = CfgFont(cfg, 11)
  cfgStats:SetPoint("BOTTOM", cfg, "BOTTOM", 0, 26)
  cfgStats:SetTextColor(0.6, 0.6, 0.6)

  cfgHint = CfgFont(cfg, 11)
  cfgHint:SetPoint("BOTTOM", cfg, "BOTTOM", 0, 13)
  cfgHint:SetTextColor(0.45, 0.45, 0.45)

  ApplyCfgPosition()
  cfg:Hide()          -- a fresh frame is visible by default
end

UpdateCfg = function()
  if not cfg then return end
  local items, n = CfgItems()

  cfgTitle:SetText(L("cfgTitle"))

  local i = 1
  while cfgRows[i] do
    local entry = items[i]
    local row = cfgRows[i]
    if entry then
      if entry.kind == "head" then
        row:SetText("|cffffd700" .. entry.text .. "|r")
      elseif entry.kind == "pick" then
        row:SetText("   " .. Pick(entry.on) .. "|cffe0e0e0" .. entry.text .. "|r")
      else
        row:SetText(Mark(entry.on) .. "|cffe0e0e0" .. entry.text .. "|r")
      end
      row:Show()
    else
      row:SetText("")
      row:Hide()
    end
    i = i + 1
  end

  local prices, keep = 0, 0
  for _ in pairs(ItemLensDB.prices) do prices = prices + 1 end
  for _ in pairs(ItemLensDB.keep) do keep = keep + 1 end
  cfgStats:SetText(Lf("cfgStats", prices, keep))
  cfgHint:SetText(L("cfgDrag"))

  if cfgScanBtn then cfgScanBtn:SetText("|cffffd700" .. L("cfgScan") .. "|r") end
  if cfgWorthBtn then cfgWorthBtn:SetText("|cffffd700" .. L("cfgWorth") .. "|r") end
  if cfgClearBtn then cfgClearBtn:SetText("|cffff8080" .. L("cfgClear") .. "|r") end
end

local function ToggleCfg()
  if not cfg then
    local ok, err = pcall(BuildCfg)
    if not ok or not cfg then
      Print("|cffff8080" .. tostring(err) .. "|r")
      return
    end
  end
  if cfg:IsShown() then
    cfg:Hide()
  else
    ApplyCfgPosition()
    UpdateCfg()
    cfg:Show()
  end
end

----------------------------------------------------------------------
-- the minimap button
----------------------------------------------------------------------

local function Atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  if x > 0 then return math.atan(y / x) end
  if x < 0 then
    if y >= 0 then return math.atan(y / x) + math.pi end
    return math.atan(y / x) - math.pi
  end
  if y > 0 then return math.pi / 2 end
  if y < 0 then return -math.pi / 2 end
  return 0
end

local function PlaceMinimapButton()
  if not mmButton or not Minimap then return end
  local angle = ItemLensDB.mmangle
  if type(angle) ~= "number" then angle = 160 end
  local rad = angle * math.pi / 180
  mmButton:ClearAllPoints()
  mmButton:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(rad), 80 * math.sin(rad))
end

local function ShiftHeld()
  return IsShiftKeyDown and IsShiftKeyDown()
end

local function StopDrag(self)
  self = self or this
  if self and self.SetScript then self:SetScript("OnUpdate", nil) end
end

local function DragButton(self)
  self = self or this
  -- let go the moment Shift is released, so a drag can never get stuck
  if not ShiftHeld() then StopDrag(self) return end
  if not GetCursorPosition or not Minimap.GetCenter then return end
  local mx, my = Minimap:GetCenter()
  if not mx then return end
  local scale = 1
  if Minimap.GetEffectiveScale then scale = Minimap:GetEffectiveScale() or 1 end
  if scale == 0 then scale = 1 end
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  ItemLensDB.mmangle = math.deg(Atan2(cy - my, cx - mx))
  PlaceMinimapButton()
end

local function BuildMinimapButton()
  if mmButton or not Minimap then return end

  mmButton = CreateFrame("Button", "ItemLensMinimapButton", Minimap)
  mmButton:SetWidth(31)
  mmButton:SetHeight(31)
  mmButton:SetFrameStrata("MEDIUM")
  mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mmButton:RegisterForDrag("LeftButton")

  local icon = mmButton:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("CENTER", mmButton, "CENTER", 0, 1)

  local border = mmButton:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53)
  border:SetHeight(53)
  border:SetPoint("TOPLEFT", mmButton, "TOPLEFT", 0, 0)

  mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  mmButton:SetScript("OnClick", function(self, button)
    local btn = button or arg1
    if btn == "RightButton" then
      ItemLensDB.minimap = false
      mmButton:Hide()
      Print(Lf("mmState", L("off")))
      return
    end
    ToggleCfg()
  end)

  mmButton:SetScript("OnDragStart", function(self)
    self = self or this
    if not ShiftHeld() then return end
    self:SetScript("OnUpdate", DragButton)
  end)
  mmButton:SetScript("OnDragStop", StopDrag)
  mmButton:SetScript("OnMouseUp", StopDrag)
  mmButton:SetScript("OnHide", StopDrag)

  mmButton:SetScript("OnEnter", function(self)
    self = self or this
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("ItemLens")
    GameTooltip:AddLine("|cff9d9d9d" .. L("mmOpenCfg") .. "|r")
    GameTooltip:AddLine("|cff9d9d9d" .. L("mmHide") .. "|r")
    GameTooltip:AddLine("|cff9d9d9d" .. L("mmMove") .. "|r")
    GameTooltip:Show()
  end)
  mmButton:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  PlaceMinimapButton()
end

local function ApplyMinimapButton()
  if ItemLensDB.minimap then
    local ok, err = pcall(BuildMinimapButton)
    if not ok then
      Print("|cffff8080" .. tostring(err) .. "|r")
      return
    end
    if mmButton then PlaceMinimapButton(); mmButton:Show() end
  elseif mmButton then
    mmButton:Hide()
  end
end

----------------------------------------------------------------------
-- what can we actually read back from a tooltip?
----------------------------------------------------------------------

-- Hover an item and type /il tiptest. Everything the duplicate protection
-- depends on is measured here: how many tooltip lines can be reached by name,
-- whether a line an addon appends shows up among them at all, and whether the
-- colour codes inside it survive being read back.
local function TipTest()
  if not GameTooltip or not GameTooltip.IsShown or not GameTooltip:IsShown() then
    Print("наведите курсор на предмет и повторите. / hover an item and try again.")
    return
  end

  local exists, lastText = 0, nil
  local i = 1
  while i <= 60 do
    local fs = getglobal("GameTooltipTextLeft" .. i)
    if not fs then break end
    exists = i
    local t = fs.GetText and fs:GetText()
    if t and t ~= "" then lastText = t end
    i = i + 1
  end
  local numLines = (GameTooltip.NumLines and GameTooltip:NumLines()) or -1
  Print("|cffffd700--- tiptest ---|r")
  Print("строк по именам: " .. exists .. ", NumLines: " .. tostring(numLines))
  Print("последняя непустая: " .. tostring(lastText))

  local probe = "|cff00ff00ItemLensProbe|r"
  GameTooltip:AddLine(probe, 1, 1, 1)
  GameTooltip:Show()

  local found, raw, at = false, nil, nil
  i = 1
  while i <= 60 do
    local fs = getglobal("GameTooltipTextLeft" .. i)
    if not fs then break end
    local t = fs.GetText and fs:GetText()
    if t and string.find(t, "ItemLensProbe", 1, true) then
      found, raw, at = true, t, i
      break
    end
    i = i + 1
  end

  Print("дописанная строка читается: " .. (found and ("да, строка " .. at) or "НЕТ"))
  if found then
    Print("как она выглядит при чтении: [" .. tostring(raw) .. "]")
    Print("цветовой код уцелел: " .. (string.find(raw, "|cff00ff00", 1, true) and "да" or "НЕТ"))
  end
  local after = (GameTooltip.NumLines and GameTooltip:NumLines()) or -1
  Print("NumLines после дописывания: " .. tostring(after) .. " (было " .. tostring(numLines) .. ")")
end

----------------------------------------------------------------------
-- slash commands
----------------------------------------------------------------------

local function HandleSlash(msg)
  msg = string.lower(msg or "")
  msg = string.gsub(msg, "^%s+", "")
  msg = string.gsub(msg, "%s+$", "")

  if msg == "scan" then
    Harvest(false)

  elseif msg == "worth" or msg == "" then
    local total, known, unknown = BagWorth()
    Print(Lf("worth", FormatMoney(total), known, unknown))

    local bankTotal, bankKnown, bankUnknown = BankWorth()
    local fresh = bankTotal ~= nil
    if not fresh and type(ItemLensDB.bank) == "table" then
      bankTotal = ItemLensDB.bank.total
      bankKnown = ItemLensDB.bank.known
      bankUnknown = ItemLensDB.bank.unknown
    end
    if bankTotal then
      Print(Lf("bankWorth", FormatMoney(bankTotal), bankKnown or 0, bankUnknown or 0,
        fresh and "" or L("bankOld")))
    else
      Print(L("bankNever"))
    end
    if msg == "" then
      Print(L("help"))
    end

  elseif msg == "probe" then
    probeTimer = 5
    Print(L("probeWait"))

  elseif msg == "autosell" then
    ItemLensDB.autosell = not ItemLensDB.autosell
    Print(Lf("autosellSet", ItemLensDB.autosell and L("on") or L("off")))

  elseif msg == "sell" then
    if not MerchantOpen() then
      Print(L("noMerchant"))
    else
      local n = BuildSellQueue()
      if n == 0 then
        Print(L("noGrey"))
      else
        sellStartMoney = GetMoney and GetMoney() or 0
        sellCount, sellReported, sellTimer = 0, false, SELL_STEP
        Print(Lf("selling", n))
      end
    end

  elseif string.sub(msg, 1, 4) == "keep" then
    local _, _, name = string.find(msg, "^keep%s+(.+)$")
    if name then
      ItemLensDB.keep[name] = true
      Print(Lf("keepAdd", name))
    else
      local list, n = "", 0
      for k in pairs(ItemLensDB.keep) do
        if n > 0 then list = list .. ", " end
        list = list .. k
        n = n + 1
      end
      Print(n > 0 and Lf("keepList", list) or L("keepEmpty"))
    end

  elseif string.sub(msg, 1, 6) == "unkeep" then
    local _, _, name = string.find(msg, "^unkeep%s+(.+)$")
    if name and ItemLensDB.keep[name] then
      ItemLensDB.keep[name] = nil
      Print(Lf("keepGone", name))
    else
      Print(L("keepMiss"))
    end

  elseif string.sub(msg, 1, 4) == "mode" then
    local _, _, want = string.find(msg, "^mode%s+(%a+)$")
    if want == "vendor" or want == "each" or want == "stack" then
      ItemLensDB.mode = want
    elseif want then
      Print(L("modeHelp"))
      return
    else
      local cycle = { vendor = "stack", stack = "each", each = "vendor" }
      ItemLensDB.mode = cycle[ItemLensDB.mode] or "vendor"
    end
    local human = { vendor = L("modeVendor"), stack = L("modeStack"), each = L("modeEach") }
    Print(Lf("modeSet", human[ItemLensDB.mode]))
    lastName, lastLines = nil, nil

  elseif msg == "scanmsg" then
    ItemLensDB.scanmsg = not ItemLensDB.scanmsg
    Print(Lf("scanmsgSet", ItemLensDB.scanmsg and L("on") or L("off")))

  elseif string.sub(msg, 1, 4) == "loot" then
    local _, _, secs = string.find(msg, "^loot%s+([%d%.]+)$")
    if secs then
      ItemLensDB.lootwait = tonumber(secs) or 1
      ItemLensDB.lootchat = true
      Print(Lf("lootSet", ItemLensDB.lootwait))
    else
      ItemLensDB.lootchat = not ItemLensDB.lootchat
      Print(Lf("lootState", ItemLensDB.lootchat and L("on") or L("off"), ItemLensDB.lootwait))
    end

  elseif msg == "config" or msg == "options" or msg == "cfg" then
    ToggleCfg()

  elseif msg == "minimap" then
    ItemLensDB.minimap = not ItemLensDB.minimap
    ApplyMinimapButton()
    Print(Lf("mmState", ItemLensDB.minimap and L("on") or L("off")))

  elseif msg == "tiptest" then
    TipTest()

  elseif string.sub(msg, 1, 6) == "repair" then
    local _, _, amount, unit = string.find(msg, "^repair%s+(%d+)%s*(%a?)$")
    if amount then
      local copper = tonumber(amount) or 0
      if unit == "g" then copper = copper * 10000
      elseif unit == "s" then copper = copper * 100 end
      ItemLensDB.repairmax = copper
      ItemLensDB.repair = true
      Print(Lf("repairCap", FormatMoney(copper)))
    else
      ItemLensDB.repair = not ItemLensDB.repair
      Print(Lf("repairSet", ItemLensDB.repair and L("on") or L("off")))
    end

  elseif msg == "compare" then
    ItemLensDB.compare = not ItemLensDB.compare
    Print(Lf("compareSet", ItemLensDB.compare and L("on") or L("off")))
    lastName, lastLines = nil, nil

  elseif string.sub(msg, 1, 4) == "lang" then
    local _, _, want = string.find(msg, "^lang%s+(%a+)$")
    if want == "ru" or want == "en" or want == "auto" then
      ItemLensDB.lang = want
      lastName, lastLines = nil, nil
      Print(Lf("langSet", want))
    else
      Print("/il lang ru | en | auto")
    end

  elseif msg == "tooltip" then
    ItemLensDB.tooltip = not ItemLensDB.tooltip
    Print(Lf("tooltipSet", ItemLensDB.tooltip and L("on") or L("off")))

  elseif msg == "clear" then
    ItemLensDB.prices = {}
    Print(L("cleared"))

  elseif msg == "debug" then
    ItemLensDB.debug = not ItemLensDB.debug
    local total = 0
    for _ in pairs(ItemLensDB.prices) do total = total + 1 end
    Print(Lf("debugSet", ItemLensDB.debug and L("on") or L("off"), total, tostring(source)))

  else
    Print(L("help"))
  end
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------

local function OnEvent(self, ev, a1)
  ev = ev or event

  if ev == "BANKFRAME_OPENED" then
    InitDB()
    bankOpen = true
    bankTimer = 0.5          -- the slots need a moment to arrive
    return
  end

  if ev == "BANKFRAME_CLOSED" then
    if bankOpen then RememberBank() end
    bankOpen = false
    bankTimer = 0
    return
  end

  if ev == "PLAYERBANKSLOTS_CHANGED" or ev == "BAG_UPDATE" then
    -- only interesting while the bank window is open: that is the one moment
    -- its contents can be counted
    if bankOpen then bankTimer = 0.5 end
    return
  end

  if ev == "CHAT_MSG_LOOT" then
    InitDB()
    NoteLoot(a1 or arg1)
    return
  end

  if ev == "VARIABLES_LOADED" or ev == "PLAYER_LOGIN" then
    InitDB()
    InstallTooltipHook()
    HookStockBags()
    BuildLootPatterns()
    ApplyMinimapButton()
    return
  end

  if ev == "MERCHANT_SHOW" then
    InitDB()
    merchantOpen = true
    InstallTooltipHook()
    HookStockBags()
    TryRepair()
    -- the merchant list may still be loading; sweep now and once more shortly
    Harvest(true)
    timer = 1.5
    StartSelling()
    return
  end

  if ev == "MERCHANT_CLOSED" then
    merchantOpen = false
    lastName = nil
    lastLines = nil
    StopSelling()
    return
  end
end

local function OnUpdate(self, elapsed)
  local e = elapsed or arg1 or 0

  SellTick(e)

  if lootTimer > 0 then
    lootTimer = lootTimer - e
    if lootTimer <= 0 then
      lootTimer = 0
      FlushLoot()
    end
  end

  if bankTimer > 0 then
    bankTimer = bankTimer - e
    if bankTimer <= 0 then
      bankTimer = 0
      RememberBank()
    end
  end

  if probeTimer > 0 then
    probeTimer = probeTimer - e
    if probeTimer <= 0 then
      probeTimer = 0
      RunProbe()
    end
  end

  if timer > 0 then
    timer = timer - e
    if timer <= 0 then
      timer = 0
      local found = Harvest(true)
      if found > 0 and ItemLensDB.scanmsg then
        local total = 0
        for _ in pairs(ItemLensDB.prices) do total = total + 1 end
        Print(Lf("caught", found, tostring(source), total))
      end
    end
  end

  Annotate()
end

InitDB()

driver = CreateFrame("Frame", "ItemLensDriver")
driver:SetScript("OnEvent", OnEvent)
driver:SetScript("OnUpdate", OnUpdate)
driver:RegisterEvent("VARIABLES_LOADED")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("MERCHANT_SHOW")
driver:RegisterEvent("MERCHANT_CLOSED")
driver:RegisterEvent("CHAT_MSG_LOOT")
driver:RegisterEvent("BANKFRAME_OPENED")
driver:RegisterEvent("BANKFRAME_CLOSED")
driver:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
driver:RegisterEvent("BAG_UPDATE")

SLASH_ITEMLENS1 = "/itemlens"
SLASH_ITEMLENS2 = "/il"
SLASH_ITEMLENS3 = "/ip"          -- short and familiar
SlashCmdList["ITEMLENS"] = HandleSlash
