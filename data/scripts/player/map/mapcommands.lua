if onClient() then
  local windowsPresent = false
  local lastSell, lastBuy

  local tm_initUI = MapCommands.initUI
  function MapCommands.initUI()
    tm_initUI()

	  sellFilterTextBox.clearOnClick = true
	  sellAmountTextBox.clearOnClick = true

	  buyFilterTextBox.clearOnClick = true
    buyAmountTextBox.clearOnClick = true

    windowsPresent = MapCommands.addWindow ~= nil
  end

  function MapCommands.onBuyGoodsPressed()
	  enqueueNextOrder = MapCommands.isEnqueueing()

	  MapCommands.fillTradeCombo(buyCombo, buyFilterTextBox.text)

    if windowsPresent then
	  MapCommands.hideWindows()
      buyWindow:show()
    else
      escortWindow:hide()
      sellWindow:hide()
      buyWindow:show()
    end
  end

  function MapCommands.onSellGoodsPressed()
    enqueueNextOrder = MapCommands.isEnqueueing()

    MapCommands.fillTradeCombo(sellCombo, sellFilterTextBox.text)

    if windowsPresent then
      MapCommands.hideWindows()
      sellWindow:show()
    else
      buyWindow:hide()
      escortWindow:hide()
      sellWindow:show()
    end
  end

  local tm_onBuyPressed = MapCommands.onBuyWindowOKButtonPressed
  function MapCommands.onBuyWindowOKButtonPressed()
    enqueueNextOrder = enqueueNextOrder or MapCommands.isEnqueueing()
    tm_onBuyPressed()
    lastBuy = buyCombo.selectedValue
    print("lastBuy", lastBuy)
  end

  local tm_onSellPressed = MapCommands.onSellWindowOKButtonPressed
  function MapCommands.onSellWindowOKButtonPressed()
    enqueueNextOrder = enqueueNextOrder or MapCommands.isEnqueueing()
    tm_onSellPressed()
    lastSell = sellCombo.selectedValue
    print("lastSell", lastSell)
  end

  function MapCommands.fillTradeCombo(combo, filter)
    combo:clear()
    local isBuying = (combo == buyCombo)

    local values = {}
    local highlighted = {}
    local highlights = {} -- prevent cargo being highlighted multiple times in case of multiple ships being selected
    local sVec

    if filter and filter ~= "" then
      for _, good in pairs(goods) do
        local displayName = good:good():displayName(1)
        if not string.match(string.lower(displayName), filter) then
          goto continue
        end

        table.insert(values, { name = good.name, displayName = displayName })

        ::continue::
      end
    else
      -- add all goods that are on board of the selected crafts
      local selected = MapCommands.getSelectedPortraits()
      for _, portrait in pairs(selected) do
        local cargos
        if portrait.alliance then
          cargos = Alliance(portrait.owner):getShipCargos(portrait.name)
        else
          cargos = Player(portrait.owner):getShipCargos(portrait.name)
        end

        for good, amount in pairs(cargos) do
          if not highlights[good.name] and amount >= 1 then
            table.insert(highlighted, { name = good.name, displayName = good:displayName(1) })
            highlights[good.name] = true
          end
        end

        if not sVec then
          if enqueueNextOrder then
            local chain = portrait.info.chain
            sVec = tostring(ivec2(chain[#chain].x, chain[#chain].y))
          else
            sVec = tostring(ivec2(portrait.coordinates.x, portrait.coordinates.y))
          end
        end
      end

      -- no filter for normal goods: add all
      for _, good in pairs(goods) do
        table.insert(values, { name = good.name, displayName = good:good():displayName(1) })
      end
    end

    -- sort goods by name
    table.sort(highlighted, function(a, b) return a.name < b.name end)
    table.sort(values, function(a, b) return a.name < b.name end)

    local setIndex
    local comboIndex = 0 -- these indexes are 0-based for whatever reason
    -- add goods to the combo box
    if #highlighted > 0 then
      for _, v in pairs(highlighted) do
        if sVec then
          local err, has = Player():invokeFunction("data/scripts/player/trade_mapping", "sectorHas", sVec, v.name, isBuying)
          combo:addEntry(v.name, v.displayName, (err == 0 and has and ColorRGB(0.2, 0.8, 0.2) or nil))
          if err > 0 then eprint("[TM] sectorHas:", err) end
        else
          combo:addEntry(v.name, v.displayName)
        end

        if isBuying and v.name == lastBuy or not isBuying and v.name == lastSell then
          setIndex = comboIndex
          print(comboIndex, isBuying)
        end
        comboIndex = comboIndex + 1
      end

      if #values > 0 then
        combo:addEntry("", "-------------")
        comboIndex = comboIndex + 1
      end
    end

    for _, v in pairs(values) do
      combo:addEntry(v.name, v.displayName)

      if isBuying and v.name == lastBuy or not isBuying and v.name == lastSell then
        setIndex = comboIndex
        print(comboIndex, isBuying)
      end
      comboIndex = comboIndex + 1
    end

    if setIndex and setIndex >= 0 then
      combo:setSelectedIndexNoCallback(setIndex)
    end
  end
end
