_addon.name = 'voidwatch'
_addon.author = 'Mojo/eRUPT'
_addon.version = '2.0'
_addon.commands = {'vw'}

require('logger')
require('coroutine')
packets = require('packets')
res = require('resources')

local handlers = {}
local choice = {}
local conditions = {
    receive = false,
    box = false,
    rift = false,
    running = false,
    escape = false,
    trade = true,
}
local busy = false

local bags = {
    'inventory',
    'safe',
    'safe2',
    'storage',
    'locker',
    'satchel',
    'sack',
    'case',
    'wardrobe',
    'wardrobe2',
    'wardrobe3',
    'wardrobe4',
}

local pulse_items = {
    [18457] = 'Murasamemaru',
    [18542] = 'Aytanri',
    [18904] = 'Ephemeron',
    [19144] = 'Coruscanti',
    [19145] = 'Asteria',
    [19174] = 'Borealis',
    [19794] = 'Delphinius',
}

local cells = {
    ['Cobalt Cell'] = 3434,
    ['Rubicund Cell'] = 3435,
    ['Phase Displacer'] = 3853,
}



--[[
Target 17739951
Option Index 2
_unknown1: 769 = 12 , 193 = 3, 65 = 1
Target Index: 175
Automated Message: false
_unknown2: 0
Menu ID: 9



--]]

cell_indexes = {
    cobalt = {
        [1] = {Name = "Cobalt Cell", Option = 2, Index = 65},
        [3] = {Name = "Cobalt Cell", Option = 2, Index = 193},
        [12] = {Name = "Cobalt Cell", Option = 2, Index = 769},
    },
    rubicund = {
        [1] = {Name = "Rubicund Cell", Option = 2, Index = 66},
        [3] = {Name = "Rubicund Cell", Option = 2, Index = 194},
        [12] = {Name = "Rubicund Cell", Option = 2, Index = 770},
    },
}

valid_zones = {
    [235] = {npc = "Voidwatch Officer", menu = 9}
}

local loot_all = false


local material_names = {}
-- table.insert(material_names, 'crystal petrifact')
table.insert(material_names, 'riftdross')
table.insert(material_names, 'riftcinder')
table.insert(material_names, 'heavy metal pouch')
table.insert(material_names, 'heavy metal')
table.insert(material_names, 'angel skin')
table.insert(material_names, 'ancient beastcoin')
-- table.insert(material_names, 'kaggen\'s cuticle')
-- table.insert(material_names, 'platinum ingot')
-- table.insert(material_names, 'steel ingot')
-- table.insert(material_names, 'phoenix feather')
-- table.insert(material_names, 'malboro fiber')
-- table.insert(material_names, 'beetle blood')
-- table.insert(material_names, 'damascene cloth')
-- table.insert(material_names, 'oxblood')
-- table.insert(material_names, 'darksteel ingot')
-- table.insert(material_names, 'gold ingot')

local materials = {}

function search_item(name)
    items = res.items
    for i = 1, #items, 1 do
        if items[i] then
            if items[i].en:lower() == name or items[i].enl == name then
                return i
            end
        end
    end
    return false
end
--One time load for materials[] to avoid res.items spamming.
if #material_names > 0 then
    for i = 1, #material_names, 1 do
        sid = search_item(material_names[i]:lower())
        if not sid then
            log('Material '..material_names[i]..' not found in database')
        else
            log('Adding MAterial['..sid..']: '..res.items[sid].enl)
            materials[sid] = res.items[sid].enl
        end
    end
end

local function escape()
    conditions['escape'] = true
    while conditions['escape'] do
        log('escaping')
        windower.send_command('setkey escape down')
        coroutine.sleep(.2)
        windower.send_command('setkey escape up')
        coroutine.sleep(1)
        --		conditions['escape'] = false
    end
end

local function leader()
    local self = windower.ffxi.get_player()
    local party = windower.ffxi.get_party()
    return (party.alliance_leader == self.id) or ((party.party1_leader == self.id) and (not party.alliance_leader)) or (not party.party1_leader)
end

local function calculate_time_offset()
    local self = windower.ffxi.get_player().name
    local members = {}
    for k, v in pairs(windower.ffxi.get_party()) do
        if type(v) == 'table' then
            members[#members + 1] = v.name
        end
    end
    table.sort(members)
    for k, v in pairs(members) do
        if v == self then
            return (k - 1) * .4
        end
    end
end

local function get_mob_by_name(name)
    local mobs = windower.ffxi.get_mob_array()
    for i, mob in pairs(mobs) do
        if (mob.name == name) and (math.sqrt(mob.distance) < 6) then
            return mob
        end
    end
end

local function poke_thing(thing)
    local npc = get_mob_by_name(thing)
    if npc then
        local p = packets.new('outgoing', 0x1a, {
            ['Target'] = npc.id,
            ['Target Index'] = npc.index,
        })
        packets.inject(p)
    end
end

local function poke_rift()
    conditions['rift'] = true
    while conditions['rift'] do
        log('poke rift')
        poke_thing('Planar Rift')
        coroutine.sleep(4)
    end
end

local function poke_box()
    conditions['box'] = true
    while conditions['box'] do
        log('poke box')
        poke_thing('Riftworn Pyxis')
        coroutine.sleep(4)
    end
end

local function trade_cells()
    log('trade cells')
    local npc = get_mob_by_name('Planar Rift')
    if npc then
        local trade = packets.new('outgoing', 0x36, {
            ['Target'] = npc.id,
            ['Target Index'] = npc.index,
        })
        local remaining = {
            cobalt = 1,
            rubicund = 1,
            phase = 5,
        }
        local idx = 1
        local n = 0
        local inventory = windower.ffxi.get_items(0)
        for index = 1, inventory.max do
            if (remaining.cobalt > 0) and (inventory[index].id == cells['Cobalt Cell']) then
                trade['Item Index %d':format(idx)] = index
                trade['Item Count %d':format(idx)] = 1
                idx = idx + 1
                remaining.cobalt = 0
                n = n + 1
            elseif (remaining.rubicund > 0) and (inventory[index].id == cells['Rubicund Cell']) then
                trade['Item Index %d':format(idx)] = index
                trade['Item Count %d':format(idx)] = 1
                idx = idx + 1
                remaining.rubicund = 0
                n = n + 1
            elseif (remaining.phase > 0) and (inventory[index].id == cells['Phase Displacer']) then
                local count = 0
                if (inventory[index].count >= remaining.phase) then
                    count = remaining.phase
                else
                    count = inventory[index].count
                end
                trade['Item Index %d':format(idx)] = index
                trade['Item Count %d':format(idx)] = count
                idx = idx + 1
                remaining.phase = remaining.phase - count
                n = n + count
            end
        end
        trade['Number of Items'] = n
        conditions['trade'] = false
        packets.inject(trade)
        if leader() then
            coroutine.schedule(poke_rift, 2)
        end
    end
end

local function observe_box_spawn(id, data)
    if (id == 0x38) and conditions['running'] then
        local p = packets.parse('incoming', data)
        local mob = windower.ffxi.get_mob_by_id(p['Mob'])
        if not mob then elseif (mob.name == 'Riftworn Pyxis') then
            if p['Type'] == 'deru' then
                log('box spawn')
                log('time offset %f':format(calculate_time_offset()))
                --                coroutine.schedule(poke_box, calculate_time_offset())
                box_spawned = true
            elseif p['Type'] == 'kesu' then
                log('box despawn')
                conditions['trade'] = true
                conditions['box'] = false
                box_spawned = false
            end
        end
    end
end

local function observe_rift_spawn(id, data)
    if (id == 0xe) and conditions['running'] and conditions['trade'] then
        local p = packets.parse('incoming', data)
        local npc = windower.ffxi.get_mob_by_id(p['NPC'])
        if not npc then elseif (npc.name == 'Planar Rift') then
            log('rift spawn')
            coroutine.schedule(trade_cells, 1)
        end
    end
end

local function start_fight(id, data)
    if (id == 0x5b) and conditions['rift'] then
        log('start fight')
        local p = packets.parse('outgoing', data)
        p['Option Index'] = 0x51
        p['_unknown1'] = 0
        conditions['rift'] = false
        conditions['escape'] = false
        last_action_type = 'fight'
        last_action = os.clock()
        return packets.build(p)
    end
end


local function obtain_item(id, data)
    if (id == 0x5b) and conditions['box'] then
        log('obtain item')
        local p = packets.parse('outgoing', data)
        p['Option Index'] = choice.option
        log('Option: '..choice.option)
        if pulse_items[choice.item] then
            p['_unknown1'] = 1
        else
            p['_unknown1'] = 0
        end
        conditions['escape'] = false
        if choice.last then
            conditions['box'] = false
        end
        last_action_type = 'chest'
        last_action = os.clock()
        return packets.build(p)
    end
end

local function examine_rift(id, data)
    if (id == 0x34) and conditions['rift'] then
        coroutine.schedule(escape, 0)
    end
end

local function is_item_rare(id)
    if res.items[id].flags['Rare'] then
        return true
    end
    return false
end

local function has_rare_item(id)
    local items = windower.ffxi.get_items()
    log("Searching for rare item %s":format(res.items[id].en))
    for k, v in pairs(bags) do
        for index = 1, items["max_%s":format(v)] do
            if items[v][index].id == id then
                return true
            end
        end
    end
    return false
end

local function examine_box(id, data)
    if (id == 0x34) and conditions['box'] then
        local p = packets.parse('incoming', data)
        local count = 0
        local rare = false
        choice = {
            last = false,
        }
        for i = 1, 8 do
            local item = p['Menu Parameters']:unpack('I', 1 + (i - 1) * 4)
            if not (item == 0) then
                log('Examining: '..item..' / '..i)
                if pulse_items[item] then
                    choice.option = i
                    choice.item = item
                end
                if materials[item] or loot_all then
                    choice.option = i
                    choice.item = item

                end
                count = count + 1
            end
        end
        if not choice.option then
            choice.option = 9
        end
        coroutine.schedule(escape, 0)
        last_action_type = 'chest'
        last_action = os.clock()
    end
end

function validate(cell, count)
    local zone = windower.ffxi.get_info()['zone']
    local me, target_index, target_id, distance
    local result = {}

    if valid_zones[zone] then
        for i, v in pairs(windower.ffxi.get_mob_array()) do
            if v['name'] == windower.ffxi.get_player().name then
                result['me'] = i
            elseif v['name'] == valid_zones[zone].npc then
                target_index = i
                target_id = v['id']
                npc_name = v['name']
                result['Menu ID'] = valid_zones[zone].menu
                distance = windower.ffxi.get_mob_by_id(target_id).distance
            end
        end

        if math.sqrt(distance) < 6 then
            local item_info = cell_indexes[cell][count]
            if item_info then
                result['Target'] = target_id
                result['Option Index'] = item_info['Option']
                result['_unknown1'] = item_info['Index']
                result['Target Index'] = target_index
                result['Zone'] = zone
            end
        else
            windower.add_to_chat(10, "Too far from npc")
        end
    else
        windower.add_to_chat(10, "Not in npc's zone")
    end
    if result['Zone'] == nil then result = nil end
    return result
end

function poke_npc(npc, target_index)
    if npc and target_index then
        local packet = packets.new('outgoing', 0x01A, {
            ["Target"] = npc,
            ["Target Index"] = target_index,
            ["Category"] = 0,
            ["Param"] = 0,
        ["_unknown1"] = 0})
        packets.inject(packet)
    end
end

local function start()
    conditions['running'] = true
    trade_cells()
end

local function stop()
    conditions['running'] = false
end

local function buy(cell_type, cell_count)
    cell_count = tonumber(cell_count)
    if not cell_type then
        windower.add_to_chat(2, "Did not specify cell type")
        return
    end
    if not cell_count then
        windower.add_to_chat(2, "Did not specify a cell count")
        return
    end
    local currentzone = windower.ffxi.get_info()['zone']
    if currentzone == 235 then
        windower.add_to_chat(2, "Going to buy: "..cell_count.." "..cell_type.." Cells")
        local currentloop = 0
        while cell_count > 0 do
            print("Current Cells: "..cell_count)
            if cell_count > 11 then
                pkt = validate(cell_type, 12)
                cur_count = 12
            elseif cell_count > 2 then
                pkt = validate(cell_type, 3)
                cur_count = 3
            elseif cell_count > 0 then
                pkt = validate(cell_type, 1)
                cur_count = 1
            end
            windower.add_to_chat(8, "Buying Item: "..cell_type.." Count: "..cur_count)
            if not busy then
                if pkt then
                    print('Inside packet maker')
                    cell_count = cell_count - cur_count
                    busy = true
                    poke_npc(pkt['Target'], pkt['Target Index'])
                else
                    windower.add_to_chat(2, "Can't find item in menu")
                end
            else
                windower.add_to_chat(2, "Still buying last item")
            end
            sleepcounter = 0
            while busy and sleepcounter < 5 do
                coroutine.sleep(1)
                sleepcounter = sleepcounter + 1
                if sleepcounter == "4" then
                    windower.add_to_chat(2, "Probably lost a packet, waited too long!")
                end
            end
        end
    else
        windower.add_to_chat(2, "You are not currently in Mhaura")
    end
end
handlers['start'] = start
handlers['stop'] = stop
handlers['buy'] = buy

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)

    if id == 0x034 or id == 0x032 then

    if busy == true and pkt then

        local packet = packets.new('outgoing', 0x05B)

        -- request item
        packet["Target"] = pkt['Target']
        packet["Option Index"] = pkt['Option Index']
        packet["_unknown1"] = pkt['_unknown1']
        packet["Target Index"] = pkt['Target Index']
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        packet["Zone"] = pkt['Zone']
        packet["Menu ID"] = pkt['Menu ID']
        packets.inject(packet)
        -- send exit menu
        packet["Target"] = pkt['Target']
        packet["Option Index"] = 0
        packet["_unknown1"] = 16384
        packet["Target Index"] = pkt['Target Index']
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        packet["Zone"] = pkt['Zone']
        packet["Menu ID"] = pkt['Menu ID']
        packets.inject(packet)

        --[[		-- print(npc_name)
		print(pkt['Target'])
		print(pkt['Option Index'])
		print(pkt['_unknown1'])
		print(pkt['Target Index'])
		print(pkt['Zone'])
		print(pkt['Menu ID'])
		print("sent")
--]]

        local packet = packets.new('outgoing', 0x016, {["Target Index"] = pkt['me'], })
        packets.inject(packet)
        busy = false
        lastpkt = pkt
        pkt = {}
        return true
    end
end

end)


local function handle_command(...)
local cmd = (...) and (...):lower()
local args = {select(2, ...)}
if handlers[cmd] then
    local msg = handlers[cmd](unpack(args))
    if msg then
        error(msg)
    end
else
    error("unknown command %s":format(cmd))
end
end

windower.register_event('addon command', handle_command)
windower.register_event('outgoing chunk', obtain_item)
windower.register_event('incoming chunk', examine_box)
windower.register_event('outgoing chunk', start_fight)
windower.register_event('incoming chunk', examine_rift)
windower.register_event('incoming chunk', observe_box_spawn)
windower.register_event('incoming chunk', observe_rift_spawn)

nexttime = os.clock()
last_action = os.clock()
last_action_type = ''
delay = 1.2
poke_timer = 0
--box_spawned = true
windower.register_event('prerender', function()
local curtime = os.clock()
if nexttime + delay <= curtime and conditions['running'] then
    nexttime = curtime
    delay = 2.5
    local chest = windower.ffxi.get_mob_by_name('Riftworn Pyxis')

    if chest and box_spawned then
        log('poking '..chest.id)
        delay = 60
        poke_box()
        last_action = curtime
        poke_timer = 0
    else
        conditions['box'] = false
    end
end
end)

windower.register_event('zone change', stop)
