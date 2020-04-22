local tm_onInstalled = onInstalled
function onInstalled(seed, rarity, permanent)
	tm_onInstalled(seed, rarity, permanent)
end

local tm_onUninstalled = onUninstalled
function onUninstalled(seed, rarity, permanent)
	tm_onUninstalled(seed, rarity, permanent)
end

function gatherData()
  return TradingUtility.detectBuyableAndSellableGoods(_, _, true)
end

function collectSectorData()
  if not tradingData then return end
 	local sellable, buyable = gatherData()
	local debug = true


	-- don't run while the server is still starting up
	if not Galaxy().sectorLoaded or not Galaxy():sectorLoaded(Sector():getCoordinates()) then return end

	-- local sellable, buyable = TradingUtility.detectBuyableAndSellableGoods(_, _, true) -- only get station goods
	local sellkeys, buykeys = {}, {} -- indices for sorting the goods
	local selling,  buying  = {}, {}
	-- { good = {
	--		stations = station_count,
	-- 		avg_price = avg_price,
	-- 		best_price = best_price,
	-- 	 }
	-- }

	local coords = vec2(Sector():getCoordinates())
	-- print(Entity().name.." is collecting TradeMapping data in "..coords)

    for i, good in pairs(buyable) do
		-- good.good.price holds the base price
		local g = good.good.name
		local gdn = good.good:displayName(2)
		local data = selling[g]

		if (not data) then
			sellkeys[#sellkeys + 1] = g
			data = {
				name = gdn,
				stations = 0,
				avg_price = 0,
				best_price = 99999999,
			}
		end

		local avg = data.avg_price * data.stations
		data.stations = data.stations + 1
		data.avg_price = (avg + good.price) / data.stations
		data.best_price = math.min(good.price, data.best_price)
		selling[g] = data
	end

	if #sellkeys > 0 then
		if debug and false then
			table.sort(sellkeys)
			local sell_str = "Selling >> "..#sellkeys.." goods: "
			for i,v in ipairs(sellkeys) do
				sell_str = sell_str..(i > 1 and ", " or "")..(i % 10 == 0 and "\n" or "")..v.." x "..selling[v]
			end
			print(string.rep("-", 40))
			print(sell_str)
		end
	end

    for i, good in pairs(sellable) do
		local g = good.good.name
		local gdn = good.good:displayName(2)
		local data = buying[g]

		if (not data) then
			buykeys[#buykeys + 1] = g
			data = {
				name = gdn,
				stations = 0,
				avg_price = 0,
				best_price = 0,
			}
		end

		local avg = data.avg_price * data.stations
		data.stations = data.stations + 1
		data.avg_price = (avg + good.price) / data.stations
		data.best_price = math.max(good.price, data.best_price)
		buying[g] = data
	end

	if #buykeys > 0 then
		if debug and false then
			table.sort(buykeys)
			local buy_str = "Buying << "..#buykeys.." goods: "
			for i,v in ipairs(buykeys) do
				buy_str = buy_str..(i > 1 and ", " or "")..(i % 10 == 0 and "\n" or "")
				..v.." x "..buying[v].stations.." @ "..buying[v].avg_price
			end
			print(string.rep("-", 40))
			print(buy_str.."\n")
		end
	end

	local goods_data = {
		entity  = Entity().name, -- name of the ship which collected the data
		sector  = coords, -- sector where it collected the data
		buying  = buying,
		selling = selling,
	}

	if debug then
		-- printTable(sellable)
		-- printTable(buyable)
		printTable(goods_data)
		if callingPlayer then
			print(callingPlayer, Player(callingPlayer).index)
		else
			local entity = Entity()
			print(goods_data.entity, entity:getPilotIndices() )
		end
	end

	if callingPlayer then
		invokeFactionFunction(Player(callingPlayer).index, true, "data/scripts/player/trade_mapping.lua", "setData", goods_data)
	else
		local entity = Entity()
		local pilots = entity:getPilotIndices()
		if pilots == 1 then
			invokeFactionFunction(Player(pilots).index, true, "data/scripts/player/trade_mapping.lua", "setData", goods_data)
		elseif pilots > 1 then
			for i = 1,pilots.length do
				invokeFactionFunction(Player(pilots[i]).index, true, "data/scripts/player/trade_mapping.lua", "setData", goods_data)
			end
		end
	end

	if #buykeys > 0 or #sellkeys > 0 then
		tradingData:insert({sellable = sellable, buyable = buyable})
	-- else
		-- print("No TradeMapping data to save for "..coords)
	end

	updateTradingRoutes()
end
