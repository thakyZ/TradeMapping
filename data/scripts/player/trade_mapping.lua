include("utility")

-- namespace TradeMapping
TradeMapping = {}

function sortSectorGoods(sectorData)
	if not sectorData then return nil end

	local buySort = {}
	for g, _ in pairs(sectorData.buying) do
		buySort[#buySort + 1] = g
	end
	table.sort(buySort)
	sectorData.buyingSorted = buySort

	local sellSort = {}
	for g, _ in pairs(sectorData.selling) do
		sellSort[#sellSort + 1] = g
	end
	table.sort(sellSort)
	sectorData.sellingSorted = sellSort

	return sectorData
end

function toSector(s) -- modified version of https://stackoverflow.com/a/37601779/1025177
	if type(s) ~= "string" then return s end
	local t = {}
	for m in s:gmatch("[^ ,()]+") do
		t[#t+1] = tonumber(m)
	end
	return ivec2(t[1], t[2])
end

function distanceA(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

----- client code -----
if onClient() then
	-- the following mess is because I named the variables not well
	-- and need to "translate" them for the ui so they make sense
	local uiTranslate = { buying = "Sell Goods", selling = "Buy Goods" , splitter = ("-"):rep(20) }
	uiTranslate[uiTranslate.buying] = "buying"   -- buying refers to all goods that the stations in the sector are buying
	uiTranslate[uiTranslate.selling] = "selling" -- this made sense in the internal context, but it's confusing for users
	uiTranslate[uiTranslate.splitter] = "splitter"

	local lastX, lastY
	local container, resolution
	local filterCombo, selectedFilter
  local sectorList, listContainer, listRender, listLabels
	local lastData, sectorGoodsSorted, knownGoods
	local lineHeight = 11

	local listBG  = ColorARGB(0.5, 0.2, 0.2, 0.2)
	local colBuy  = ColorARGB(0.9, 0.8, 0.2, 0.2)
	local colSell = ColorARGB(0.9, 0.2, 0.8, 0.2)
	local colBoth = ColorARGB(0.9, 0.8, 0.8, 0.2)
	local colNone = ColorARGB(0.9, 0.2, 0.4, 0.8)
	local colList = ColorRGB(0.88, 0.88, 0.88)

	function addLastY(num) -- joke alternative to the common ++ which lua doesn't even remotely support
		lastY = lastY + num
		return lastY
	end

	function discoveredGoods()
		if not lastData then return nil end

		local result = { all = {}, allSorted = {}, buying = {}, selling = {} }

		for sector, goods in pairs(lastData) do
			for good, data in pairs(goods.buying) do
				result.all[good] = 1

				if not result.buying[good] then
					result.buying[good] = {
						name = data.name,
						stations = data.stations,
						avg_price = data.avg_price,
						best_price = data.best_price,
						best_sector = sector,
					}
				else
					result.buying[good].stations = result.buying[good].stations + data.stations
					result.buying[good].avg_price = result.buying[good].avg_price + data.avg_price

					if data.best_price > result.buying[good].best_price then
						result.buying[good].best_price = data.best_price
						result.buying[good].best_sector = sector
					end
				end
			end

			for good, data in pairs(goods.selling) do
				result.all[good] = 1

				if not result.selling[good] then
					result.selling[good] = {
						name = data.name,
						stations = data.stations,
						avg_price = data.avg_price,
						best_price = data.best_price,
						best_sector = sector,
					}
				else
					result.selling[good].stations = result.selling[good].stations + data.stations
					result.selling[good].avg_price = result.selling[good].avg_price + data.avg_price

					if data.best_price < result.selling[good].best_price then
						result.selling[good].best_price = data.best_price
						result.selling[good].best_sector = sector
					end
				end
			end
		end

		for good, _ in pairs(result.all) do
			result.allSorted[#result.allSorted + 1] = good

			if result.buying[good] then
				result.buying[good].avg_price = result.buying[good].avg_price / result.buying[good].stations
			end

			if result.selling[good] then
				result.selling[good].avg_price = result.selling[good].avg_price / result.selling[good].stations
			end
		end
		table.sort(result.allSorted)

		-- printTable(result)

		return sortSectorGoods(result)
	end

	function sortSectorDist(sectorV2)
		local testsectorV2 = nil
		if not sectorV2 then
			testsectorV2 = GalaxyMap():getSelectedCoordinates()
		else
			testsectorV2 = toSector(sectorV2)
		end
		table.sort(sectorList, function(a, b)
			return distanceA(testsectorV2, a.sector) < distanceA(testsectorV2, b.sector)
		end)
	end

	function altDown()
		return Keyboard():keyPressed(KeyboardKey.LAlt) or Keyboard():keyPressed(KeyboardKey.RAlt)
	end

	function str2version(strVersion)
		local v = {}
		for n in strVersion:gmatch("%d+") do
			v[#v + 1] = tonumber(n)
		end

		return Version(v[1] or 0, v[2] or 0, v[3] or 0)
	end


	--== class functions ==--
	function TradeMapping.initialize()
		print("TradeMapping client init")

		TradeMapping.initUI()

		local player = Player()
		player:registerCallback("onShowGalaxyMap", "onShowGalaxyMap")
		-- player:registerCallback("onHideGalaxyMap", "onHideGalaxyMap")
		player:registerCallback("onSelectMapCoordinates", "onSelectMapCoordinates")
		player:registerCallback("onMapRenderAfterLayers", "onMapRenderAfterLayers")
	end

	function TradeMapping.initUI()
		local gm = GalaxyMap()
		container = gm:createContainer()

		resolution = getResolution()

		lastX = 5
		lastY = 220

		filterCombo = container:createComboBox(Rect(lastX, lastY, 220, addLastY(25)), "onFilterComboChanged")
		filterCombo:addEntry(uiTranslate.selling)
		filterCombo:addEntry(uiTranslate.buying)
		filterCombo:setSelectedIndexNoCallback(1)

		listContainer = container:createScrollFrame(Rect(lastX, addLastY(20), 300, resolution.y - 5))
		listContainer.paddingBottom = 5
		listContainer.paddingTop = 3
	end

	function TradeMapping.onShowGalaxyMap()
		resolution = getResolution()
		invokeServerFunction("getData", Player().index)
		TradeMapping.updateFilter()
	end

	function TradeMapping.updateFilter()
		if lastData and knownGoods then
			filterCombo:clear()
			filterCombo:addEntry(uiTranslate.selling)
			filterCombo:addEntry(uiTranslate.buying)
			filterCombo:addEntry(uiTranslate.splitter)

			for _, good in ipairs(knownGoods.allSorted) do
				filterCombo:addEntry(good, good.name)
			end

			local found = false
			for idx = 0, #knownGoods.allSorted + 2 do
				if filterCombo:getEntry(idx) == selectedFilter then
					filterCombo:setSelectedIndexNoCallback(idx)
					found = true
					break
				end
			end

			if not found then
				filterCombo:setSelectedIndexNoCallback(1)
			end
		end
	end

	-- function TradeMapping.onHideGalaxyMap()
		-- print("map closed")
	-- end

	function TradeMapping.onSelectMapCoordinates()
		if lastData then
			local coords = vec2(GalaxyMap():getSelectedCoordinates())
			sectorGoodsSorted = sortSectorGoods(lastData[tostring(coords)])
		else
			invokeServerFunction("getData", Player().index)
			return
		end
		TradeMapping.onFilterComboChanged()
	end

	function TradeMapping.onMapRenderAfterLayers()
		if listRender ~= nil and next(listRender) then
			local renderer = UIRenderer()
			local map = GalaxyMap()

			for i, sec in pairs(listRender) do
				local sx, sy = map:getCoordinatesScreenPosition(sec.pos)
				-- local n = vec2(sx, sy - 10)
				-- local e = vec2(sx + 10, sy)
				-- local s = vec2(sx, sy + 10)
				-- local w = vec2(sx - 10, sy)
				-- renderer:renderLine(n, e, sec.color, 1)
				-- renderer:renderLine(s, e, sec.color, 1)
				-- renderer:renderLine(n, w, sec.color, 1)
				-- renderer:renderLine(s, w, sec.color, 1)
				renderer:renderTargeter(vec2(sx, sy), 21, sec.color, 1)
			end

			renderer:display()
		end
	end

	function TradeMapping.onSectorListClick(btn)
		local sector = listRender[btn.index]
		GalaxyMap():setSelectedCoordinates(sector.x, sector.y)
	end

	function TradeMapping.onFilterComboChanged()
		selectedFilter = filterCombo.selectedEntry
		local selection = uiTranslate[selectedFilter]
		local coords = ivec2(GalaxyMap():getSelectedCoordinates())

		if not lastData then return end

		listLabels = {}
		listRender = {}

		local list = UIVerticalLister(Rect(vec2(4, 0), vec2(270, lineHeight)), 5, 0)
		list:nextRect(lineHeight)

		listContainer:show()
		listContainer:clear()

		local coords = ivec2(GalaxyMap():getSelectedCoordinates())
		sortSectorDist(coords)

		if selection and selection ~= "splitter" then
			if not sectorGoodsSorted then listContainer:hide() return end

			local goods = sectorGoodsSorted[selection.."Sorted"]
			for i,g in ipairs(goods) do
				local rect = list:nextRect(lineHeight)
				local lbl = listContainer:createLabel(rect, g, lineHeight)
				lbl.mouseDownFunction = "onListSelected"
				lbl.color = colList
				listLabels[lbl.index] = lbl

				rect.lower = rect.lower + vec2(list.inner.width * 0.75, 0)
				local lbl = listContainer:createLabel(rect, lastData[tostring(coords)][selection][g].best_price, lineHeight)
				lbl.color = colList
				lbl:setRightAligned()
			end

			if not next(listLabels) then listContainer:hide() end
		else

			TradeMapping.markSectorsWith(selectedFilter)
			listContainer:hide()
		end

		listContainer:scroll(-3)
	end

	function TradeMapping.markSectorsWith(goodName)
		listRender = {}
		for i,sec in ipairs(sectorList) do
			local buying  = sec.buying[goodName]
			buying = buying and buying.stations or 0

			local selling = sec.selling[goodName]
			selling = selling and selling.stations or 0

			if buying > 0 or selling > 0 or goodName == uiTranslate.splitter then
				listRender[#listRender + 1] = {
					pos = ivec2(sec.sector.x, sec.sector.y),
					color = ((buying > 0 and selling > 0) and colBoth) or
						(buying > 0 and colSell or selling > 0 and colBuy or colNone)
				}
			end
		end
	end

	function TradeMapping.onListSelected(index, button)
		if button ~= 1 then return end

		for i,lbl in pairs(listLabels) do
			lbl.color = (i == index and colSell or colList)
			if i == index then
				TradeMapping.markSectorsWith(lbl.caption)
			end
		end
	end

	function TradeMapping.sectorHas(sector, good, buyingFromSector)
		return lastData and lastData[sector] and
			lastData[sector][(buyingFromSector and "selling" or "buying")][good] ~= nil

		-- buyingFromSector means if 'we' want to buy, but the data is saved as what the sector 'sells / buys', hence the inversion
	end

	function TradeMapping.getData(data) -- called from the server after asking for the data package with all sectors
		if not data then return end

		lastData = data

		sectorList = {}
		for sec, gds in pairs(data) do
			gds.sector = toSector(sec)
			sectorList[#sectorList + 1] = gds
		end

		knownGoods = discoveredGoods()

		TradeMapping.updateFilter()
			TradeMapping.onSelectMapCoordinates() -- update the list
	end
	callable(TradeMapping, "getData")

end
----- client end -----


----- server code -----
if onServer() then
	local Azimuth = include("azimuthlib-basic")
	local next = next -- for checking if a table is empty

	local pid = Player().id.id
	local config = "TradeMapping_"..pid
	local data = Azimuth.loadConfig(config, {})
	-- {
	--   sector : coords,
	--   buying : { good : {
	--		stations = station_count,
	-- 		avg_price = avg_price,
	-- 		best_price = best_price,
	-- 	 },
	--   selling : { good : {
	--		stations = station_count,
	-- 		avg_price = avg_price,
	-- 		best_price = best_price,
	-- 	 }
	-- }

	print("TradeMapping init for "..Player().baseName.." ("..pid..")")
	local dataNum = tablelength(data)
	print(Player().baseName.." has mapped "..dataNum.." sector"..(dataNum == 1 and "" or "s"))
	-- print(config)

	-- local sectors = "Data: "
	-- for k,v in pairs(data) do
		-- sectors = sectors..k..", "
	-- end
	-- print(sectors)

	-- API --
	-- setValue(key, value)
	--[[ Set variable.
	Example: Player():invokeFunction("azimuthlib-clientdata.lua", "setValue", "MyMod", { myModSettingsVar = 5 })
	]]
	function TradeMapping.setData(newData)
		newData.sector = tostring(vec2(newData.sector.x, newData.sector.y))
		if next(newData.buying) ~= nil or next(newData.selling) ~= nil then
			-- only save if the sector actually sells something
			data[newData.sector] = { buying = newData.buying, selling = newData.selling }
			Azimuth.saveConfig(config, data)
			print(newData.entity.." collected TradeMapping data for "..newData.sector)
		else
			print("No TradeMapping data to save for "..newData.sector)
		end
	end

	-- getValue(key)
	--[[ Get single variable.
	Example: local _, value = Player():invokeFunction("azimuthlib-clientdata.lua", "getValue", "MyMod")
	]]
	function TradeMapping.getSectorData(playerIndex, sector)
		local player = Player(callingPlayer)
		if not player or player.index ~= playerIndex then
			eprint("received an unmatching player call: "..playerIndex.." vs calling "..(player and player.index or "nil"))
			return
		end

		sector = tostring(sector)
		local result = data[sector]
		if result then
			result.sector = sector
		end
		invokeClientFunction(player, "getSectorData", result)
	end
	callable(TradeMapping, "getSectorData")

	-- Get all saved values as table.
	function TradeMapping.getData(playerIndex)
		local player = Player(callingPlayer)
		if not player or player.index ~= playerIndex then
			print("received an unmatching player call: "..playerIndex.." vs calling "..(player and player.index or "nil"))
			return
		end
		invokeClientFunction(player, "getData", data)
	end
	callable(TradeMapping, "getData")

end
----- server end -----


return TradeMapping
