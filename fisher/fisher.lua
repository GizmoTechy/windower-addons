--[[
Copyright 2019-2020 Seth VanHeulen

This file is part of fisher.

fisher is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

fisher is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with fisher.  If not, see <https://www.gnu.org/licenses/>.
--]]

-- luacheck: std lua51, globals _addon windower

_addon.name = 'fisher'
_addon.author = 'Seth VanHeulen'
_addon.version = '5.1.0.0'
_addon.command = 'fisher'

-- built-in libraries
local coroutine = require('coroutine')
local io = require('io')
local math = require('math')
local os = require('os')
local string = require('string')
local table = require('table')
-- extra libraries
local bit = require('bit')
local config = require('config')
require('pack')
-- local libraries
local data = require('data')

local session
local settings
do
    local function initialize_session()
        session = {
            running=false, coroutine_key=math.random(),
            item_by_id={}, bait_by_id={},
            catch_monster=false, catch_unknown=false,
            catch_limit=0, no_hook=0,
            fishing_status={},
        }
    end

    local settings_cache = {}

    local defaults = {
        equip_delay=2, move_delay=0, cast_attempt_delay=3, cast_attempt_max=3,
        release_delay=3, catch_delay_min=3, catch_delay_override=0, recast_delay=3,
        fatigue_start=os.date('!%Y-%m-%d', os.time() + 9 * 60 * 60), fatigue_count=0,
        no_hook_max=20, debug_messages=false,
    }

    local function load_settings(character)
        character = character or windower.ffxi.get_player().name
        if not settings_cache[character] then
            local path = string.format('data/%s.xml', character)
            settings_cache[character] = config.load(path, defaults)
        end
        return settings_cache[character]
    end

    local function initialize(character)
        initialize_session()
        settings = load_settings(character)
    end

    windower.register_event('login', initialize)

    if windower.ffxi.get_info().logged_in then initialize() end
end

local MESSAGE_INFO = 207
local MESSAGE_WARN = 200
local MESSAGE_ERROR = 167
local MESSAGE_DEBUG = 160

local function message(text, level)
    local mode = level or MESSAGE_INFO
    if settings.debug_messages or mode ~= MESSAGE_DEBUG then
        windower.add_to_chat(mode, string.format('[%s] %s', _addon.name, text))
    end
end

local check_client_path
local check_message
do
    local message_id_by_zone = {}

    local client_path = config.load('data/client_path.xml', {client_path='C:/Program Files (x86)/PlayOnline/SquareEnix/FINAL FANTASY XI/'})

    local function join_path(...)
        return string.gsub(string.gsub(table.concat({...}, '/'), '\\', '/'), '/+', '/')
    end

    local function read_file(path)
        local handle = io.open(path, 'rb')
        if handle then
            local contents = handle:read('*a')
            handle:close()
            return contents
        end
    end

    local base_message = string.char(
        0xd9,0xef,0xf5,0xa0,0xe4,0xe9,0xe4,0xee,0xa7,0xf4,0xa0,0xe3,0xe1,0xf4,0xe3,
        0xe8,0xa0,0xe1,0xee,0xf9,0xf4,0xe8,0xe9,0xee,0xe7,0xae,0xff,0xb1,0x80,0x87
    )

    local function find_message_id()
        local zone_id = windower.ffxi.get_info().zone
        if not message_id_by_zone[zone_id] then
            local message_dat = data.message_dat_by_zone[zone_id]
            if message_dat then
                config.reload(client_path)
                local message_dat_path = join_path(client_path.client_path, message_dat)
                local message_dat_file = read_file(message_dat_path)
                if message_dat_file then
                    local offset = string.find(message_dat_file, base_message)
                    offset = string.pack('i', bit.bxor(offset - 5, 0x80808080))
                    offset = string.gsub(offset, '([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1')
                    local index = string.find(message_dat_file, offset)
                    message_id_by_zone[zone_id] = (index - 5) / 4
                    message('message id cache updated: ' .. zone_id, MESSAGE_DEBUG)
                else
                    message('error reading message dat file: ' .. zone_id, MESSAGE_DEBUG)
                end
            else
                message_id_by_zone[zone_id] = true
            end
        end
        return message_id_by_zone[zone_id]
    end

    function check_client_path()
        return find_message_id() ~= nil
    end

    local message_id_offsets = {no_hook=0, lost_skill=16, hooked_monster=48}

    function check_message(name, message_id)
        return find_message_id() == message_id - message_id_offsets[name]
    end
end

local function stop_fishing(reason)
    if session.running then
        session.running = false
        session.coroutine_key = math.random()
        if reason then
            message(string.format('stopped automated fishing (%s)', reason), MESSAGE_ERROR)
        else
            message('stopped automated fishing', MESSAGE_WARN)
        end
    end
end

local function get_equipped_item_id(slot_name, items)
    items = items or windower.ffxi.get_items()
    local bag = items.equipment[slot_name .. '_bag']
    local bag_name = data.bag_by_id[bag]
    local slot = items.equipment[slot_name]
    local item = items[bag_name][slot]
    if item then return item.id end
end

local function check_equipment()
    local items = windower.ffxi.get_items()
    local left_ring_id = get_equipped_item_id('left_ring', items)
    local right_ring_id = get_equipped_item_id('right_ring', items)
    if left_ring_id == 15556 or right_ring_id == 15556 then return false end
    local range_id = get_equipped_item_id('range', items)
    if range_id == 19319 then
        return windower.ffxi.get_info().zone == 86
    end
    return data.rod_modifier_by_id[range_id] ~= nil
end

local input_fish_command
do
    local function equip_bait(item, bag)
        if item.status == 0 and session.bait_by_id[item.id] then
            message(string.format('equipping item: %d, %d, %d', item.slot, 3, bag), MESSAGE_DEBUG)
            windower.ffxi.set_equip(item.slot, 3, bag)
            coroutine.sleep(settings.equip_delay)
            return true
        end
    end

    local function check_bait()
        local items = windower.ffxi.get_items()
        local ammo_id = get_equipped_item_id('ammo', items)
        if session.bait_by_id[ammo_id] then return true end
        for slot = 1, items.max_inventory do
            if equip_bait(items.inventory[slot], 0) then return true end
        end
        for slot = 1, items.max_wardrobe do
            if equip_bait(items.wardrobe[slot], 8) then return true end
        end
        for slot = 1, items.max_wardrobe2 do
            if equip_bait(items.wardrobe2[slot], 10) then return true end
        end
        if items.enabled_wardrobe3 then
            for slot = 1, items.max_wardrobe3 do
                if equip_bait(items.wardrobe3[slot], 11) then return true end
            end
        end
        if items.enabled_wardrobe4 then
            for slot = 1, items.max_wardrobe4 do
                if equip_bait(items.wardrobe4[slot], 12) then return true end
            end
        end
        return false
    end

    local function store_item(target_bag, source_item)
        message(string.format('moving item: %d, %d, %d', target_bag, source_item.slot, source_item.count), MESSAGE_DEBUG)
        windower.ffxi.put_item(target_bag, source_item.slot, source_item.count)
        coroutine.sleep(settings.move_delay)
        return true
    end

    local function check_inventory()
        local items = windower.ffxi.get_items()
        if items.count_inventory < items.max_inventory then return true end
        local moved = false
        for slot = 1, items.max_inventory do
            local source_item = items.inventory[slot]
            if source_item.status == 0 and session.item_by_id[source_item.id] then
                if items.enabled_satchel and items.count_satchel < items.max_satchel then
                    moved = store_item(5, source_item)
                elseif items.enabled_sack and items.count_sack < items.max_sack then
                    moved = store_item(6, source_item)
                elseif items.enabled_case and items.count_case < items.max_case then
                    moved = store_item(7, source_item)
                else
                    return moved
                end
            end
        end
        return moved
    end

    function input_fish_command(coroutine_key)
        local cast_attempt = 0
        while session.running and coroutine_key == session.coroutine_key and cast_attempt < settings.cast_attempt_max do
            if not check_client_path() then
                stop_fishing('incorrect client path')
            elseif not next(session.item_by_id) and not session.catch_monster and not session.catch_unknown then
                stop_fishing('nothing set to catch')
            elseif not next(session.bait_by_id) then
                stop_fishing('no bait set to use')
            elseif not check_equipment() then
                stop_fishing('invalid equipment')
            elseif not check_bait() then
                stop_fishing('out of bait')
            elseif not check_inventory() then
                stop_fishing('out of inventory space')
            else
                cast_attempt = cast_attempt + 1
                message(string.format('inputting fish command: %d, %d', cast_attempt, settings.cast_attempt_max), MESSAGE_DEBUG)
                windower.send_command('input /fish')
                coroutine.sleep(settings.cast_attempt_delay)
            end
        end
        if coroutine_key == session.coroutine_key and cast_attempt >= settings.cast_attempt_max then
            stop_fishing('unable to cast')
        end
    end
end

local function schedule_cast()
    message(string.format('casting in %d seconds', settings.recast_delay))
    local coroutine_key = math.random()
    session.coroutine_key = coroutine_key
    coroutine.schedule(function () input_fish_command(coroutine_key) end, settings.recast_delay)
end

local function stop_cast_attempts()
    session.coroutine_key = math.random()
end

local function send_fishing_action(stamina_percent, gold_arrow_chance, coroutine_key)
    if session.running and coroutine_key == session.coroutine_key then
        local player = windower.ffxi.get_player()
        windower.packets.inject_outgoing(0x110, string.pack('IIIHHI', 0xB10, player.id, stamina_percent, player.index, 3, gold_arrow_chance))
    end
end

local schedule_catch
do
    local function calculate_catch_delay(fishing_parameters)
        -- TODO: tweak this algorithm
        if settings.catch_delay_override > 0 then
            return math.min(settings.catch_delay_override, fishing_parameters[7] - 3)
        end
        local gold_arrow_chance = math.min(fishing_parameters[9], 100) / 100
        local depletion_per_arrow = fishing_parameters[5] + fishing_parameters[5] * gold_arrow_chance
        local recovery_per_arrow = fishing_parameters[6] - (fishing_parameters[6] / 4 * 3) * gold_arrow_chance
        local correct_chance = fishing_parameters[2] / (fishing_parameters[2] + 1)
        local regen_per_arrow = recovery_per_arrow * (1 - correct_chance) - depletion_per_arrow * correct_chance
        local arrows_per_second = (fishing_parameters[4] + 5) / 25
        local regen_per_second = (fishing_parameters[3] - 128) * 60 + arrows_per_second * regen_per_arrow
        local catch_delay = fishing_parameters[7] - 5
        if regen_per_second < 0 then
            catch_delay = math.min(math.abs(fishing_parameters[1] / regen_per_second), catch_delay)
        end
        return math.max(settings.catch_delay_min, catch_delay)
    end

    function schedule_catch(fishing_parameters)
        local delay = calculate_catch_delay(fishing_parameters)
        message(string.format('catching in %d seconds', delay))
        local gold_arrow_chance = fishing_parameters[9]
        local coroutine_key = math.random()
        session.coroutine_key = coroutine_key
        coroutine.schedule(function () send_fishing_action(0, gold_arrow_chance, coroutine_key) end, delay)
    end
end

local function schedule_release()
    message(string.format('releasing in %d seconds', settings.release_delay))
    local coroutine_key = math.random()
    session.coroutine_key = coroutine_key
    coroutine.schedule(function () send_fishing_action(200, 0, coroutine_key) end, settings.release_delay)
end

local function update_fatigue(relative, value)
    local now = os.time() + 9 * 60 * 60
    local today = os.date('!%Y-%m-%d', now)
    now = os.date('!*t', now)
    if settings.fatigue_start ~= today then
        settings.fatigue_start = today
        settings.fatigue_count = 0
        config.save(settings, 'all')
    end
    if value then
        if relative then
            settings.fatigue_count = math.max(settings.fatigue_count + value, 0)
        else
            settings.fatigue_count = value
        end
        config.save(settings, 'all')
    end
    local reset = (24 * 60) - (now.hour * 60 + now.min)
    message(string.format('fishing fatigue = %d/200, resets in %dh%dm', settings.fatigue_count, math.floor(reset / 60), reset % 60))
end

local function start_fishing(catch_limit)
    if not session.running and windower.ffxi.get_player().status == 0 then
        session.running = true
        local coroutine_key = math.random()
        session.coroutine_key = coroutine_key
        session.catch_limit = tonumber(catch_limit) or 0
        session.no_hook = 0
        if session.catch_limit > 0 then
            message(string.format('started automated fishing (catch limit = %d)', session.catch_limit), MESSAGE_WARN)
        else
            message('started automated fishing', MESSAGE_WARN)
        end
        update_fatigue()
        coroutine.schedule(function () input_fish_command(coroutine_key) end, 0)
    end
end

local identify_hooked_item
do
    local item_by_rod_and_uid = {}

    local function find_item(stamina_base, fishing_parameters)
        local range_id = get_equipped_item_id('range')
        if not item_by_rod_and_uid[range_id] then
            local item_by_uid = {}
            local rod_modifier = data.rod_modifier_by_id[range_id]
            for i = 1, #data.item_fishing_parameters do
                local item = data.item_fishing_parameters[i]
                local uid = rod_modifier(item)
                if not item_by_uid[uid] then item_by_uid[uid] = {} end
                table.insert(item_by_uid[uid], item)
            end
            item_by_rod_and_uid[range_id] = item_by_uid
            message('item uid cache updated: ' .. range_id, MESSAGE_DEBUG)
        end
        local uid = table.concat({stamina_base, fishing_parameters[2], fishing_parameters[4], fishing_parameters[5]}, ',')
        return item_by_rod_and_uid[range_id][uid]
    end

    function identify_hooked_item(fishing_parameters)
        local zone = windower.ffxi.get_info().zone
        local identified = {}
        for i = 95, 105 do
            if fishing_parameters[1] % i == 0 then
                local item = find_item(math.floor(fishing_parameters[1] / i), fishing_parameters)
                if item then
                    for j = 1, #item do
                        if not item[j].continent or bit.band(item[j].continent, data.continent_by_zone[zone] or 1) ~= 0 then
                            table.insert(identified, item[j])
                        end
                    end
                end
            end
        end
        return identified
    end
end

windower.register_event('action', function (action)
    if session.running then
        local player_id = windower.ffxi.get_player().id
        for _, target in pairs(action.targets) do
            if target.id == player_id then stop_fishing('targeted by action') end
        end
    end
end)

windower.register_event('incoming chunk', function (id, original)
    if id == 0x00B then
        if string.byte(original, 5) == 1 then
            stop_fishing('log out')
        else
            stop_fishing('zone change')
        end
    elseif id == 0x017 then
        if string.byte(original, 6) % 2 == 1 then
            stop_fishing('chat message from gm')
        end
    elseif id == 0x036 then
        local message_id = string.unpack(original, 'H', 11)
        message_id = message_id % 0x8000
        if check_message('hooked_monster', message_id) then
            session.fishing_status.hooked_monster = true
        elseif check_message('lost_skill', message_id) then
            session.fishing_status.lost_skill = true
        elseif session.running and check_message('no_hook', message_id) then
            session.no_hook = session.no_hook + 1
            message(string.format('no item hooked: %d, %d', session.no_hook, settings.no_hook_max), MESSAGE_DEBUG)
            if settings.no_hook_max > 0 and session.no_hook >= settings.no_hook_max then
                stop_fishing('no hook limit')
            end
        end
    elseif id == 0x037 then
        local player_status = windower.ffxi.get_player().status
        if session.player_status == player_status then return end
        session.player_status = player_status
        message(string.format('player status update: %d, %d', player_status, string.byte(original, 75)), MESSAGE_DEBUG)
        if player_status == 56 then
            session.fishing_status = {}
        elseif player_status == 57 then
            session.no_hook = 0
        elseif player_status == 58 or player_status == 61 then
            update_fatigue('+', 1)
            if session.running and session.catch_limit > 0 then
                session.catch_limit = session.catch_limit - 1
                if session.catch_limit > 0 then
                    message(string.format('remaining catch limit = %d', session.catch_limit))
                else
                    stop_fishing('catch limit')
                end
            end
        elseif player_status == 60 and session.fishing_status.lost_skill then
            update_fatigue('+', 0.5)
        end
        if session.running then
            if player_status == 0 then
                schedule_cast()
            elseif player_status == 56 then
                stop_cast_attempts()
            elseif not (player_status >= 56 and player_status <= 62 or player_status == 0) then
                stop_fishing('invalid player status')
            end
        end
    elseif id == 0x115 then
        local fishing_parameters = {string.unpack(original, 'HHHHHHHHI', 5)}
        message(string.format('fishing parameters: ' .. table.concat(fishing_parameters, ', ')), MESSAGE_DEBUG)
        if not check_client_path() then
            if session.running then
                stop_fishing('incorrect client path')
            else
                message('unable to identify hooked item (incorrect client path)', MESSAGE_ERROR)
            end
        elseif check_equipment() then
            local catch = false
            if session.fishing_status.hooked_monster then
                message('hooked = monster', MESSAGE_WARN)
                catch = session.catch_monster
            else
                local identified = identify_hooked_item(fishing_parameters)
                if #identified == 0 then
                    message('hooked = unknown item', MESSAGE_WARN)
                    catch = session.catch_unknown
                end
                for i = 1, #identified do
                    local item = identified[i]
                    message(string.format('hooked = %s x%d', item.name, item.count or 1), MESSAGE_WARN)
                    if session.running and not catch then
                        if session.item_by_id[item.id] then catch = true end
                    end
                end
            end
            if session.running then
                if catch then schedule_catch(fishing_parameters) else schedule_release() end
            end
        elseif session.running then
            stop_fishing('invalid equipment')
        else
            message('unable to identify hooked item (invalid equipment)', MESSAGE_ERROR)
        end
    end
end)

windower.register_event('outgoing chunk', function (id, original, _, injected)
    if id == 0x01A then
        local action_category = string.byte(original, 11)
        if action_category ~= 14 then stop_fishing('performed another action') end
    elseif id == 0x110 then
        local _, stamina_percent, _, action_type, gold_arrow_chance = string.unpack(original, 'IIHHI', 5)
        message('fishing action: ' .. table.concat({stamina_percent, action_type, gold_arrow_chance}, ', '), MESSAGE_DEBUG)
        if action_type == 3 then
            if stamina_percent == 300 then
                stop_fishing('fishing timed out')
            elseif not injected then
                stop_fishing('manual fishing action')
            end
        end
    end
end)

do
    local function command_add(item_name)
        if item_name == 'monster' then
            session.catch_monster = true
            message('enabled catching monsters')
        elseif item_name == 'unknown' then
            session.catch_unknown = true
            message('enabled catching unknown items')
        elseif item_name == 'all' then
            command_add('all fish')
            command_add('all item')
            command_add('all bait')
        elseif item_name == 'all fish' then
            for name, id in pairs(data.fish_by_name) do
                session.item_by_id[id] = name
            end
            message('added all fishes to catch')
        elseif item_name == 'all item' then
            for name, id in pairs(data.item_by_name) do
                session.item_by_id[id] = name
            end
            message('added all items to catch')
        elseif item_name == 'all bait' then
            for name, id in pairs(data.bait_by_name) do
                session.bait_by_id[id] = name
            end
            message('added all baits to use')
        elseif data.fish_by_name[item_name] then
            local item_id = data.fish_by_name[item_name]
            session.item_by_id[item_id] = item_name
            message(string.format('added fish to catch = %s (%d)', item_name, item_id))
        elseif data.item_by_name[item_name] then
            local item_id = data.item_by_name[item_name]
            session.item_by_id[item_id] = item_name
            message(string.format('added item to catch = %s (%d)', item_name, item_id))
        elseif data.bait_by_name[item_name] then
            local item_id = data.bait_by_name[item_name]
            session.bait_by_id[item_id] = item_name
            message(string.format('added bait to use = %s (%d)', item_name, item_id))
        else
            message('invalid fish, item or bait name', MESSAGE_ERROR)
        end
    end

    local function command_remove(item_name)
        local item_id = tonumber(item_name)
        item_id = item_id or data.fish_by_name[item_name]
        item_id = item_id or data.item_by_name[item_name]
        item_id = item_id or data.bait_by_name[item_name]
        if item_name == 'monster' then
            session.catch_monster = false
            message('disabled catching monsters')
        elseif item_name == 'unknown' then
            session.catch_unknown = false
            message('disabled catching unknown items')
        elseif item_name == 'all' then
            command_remove('all fish')
            command_remove('all item')
            command_remove('all bait')
        elseif item_name == 'all fish' then
            for _, id in pairs(data.fish_by_name) do
                session.item_by_id[id] = nil
            end
            message('removed all fishes to catch')
        elseif item_name == 'all item' then
            for _, id in pairs(data.item_by_name) do
                session.item_by_id[id] = nil
            end
            message('removed all items to catch')
        elseif item_name == 'all bait' then
            session.bait_by_id = {}
            message('removed all baits to use')
        elseif session.item_by_id[item_id] then
            item_name = session.item_by_id[item_id]
            session.item_by_id[item_id] = nil
            if data.fish_by_name[item_name] then
                message(string.format('removed fish to catch = %s (%d)', item_name, item_id))
            else
                message(string.format('removed item to catch = %s (%d)', item_name, item_id))
            end
        elseif session.bait_by_id[item_id] then
            item_name = session.bait_by_id[item_id]
            session.bait_by_id[item_id] = nil
            message(string.format('removed bait to use = %s (%d)', item_name, item_id))
        else
            message('invalid fish, item or bait', MESSAGE_ERROR)
        end
    end

    local function command_list()
        if session.catch_monster then
            message('catching monsters is enabled')
        end
        if session.catch_unknown then
            message('catching unknown items is enabled')
        end
        for item_id, item_name in pairs(session.item_by_id) do
            if data.fish_by_name[item_name] then
                message(string.format('fish to catch = %s (%d)', item_name, item_id))
            else
                message(string.format('item to catch = %s (%d)', item_name, item_id))
            end
        end
        if not next(session.item_by_id) and not session.catch_monster and not session.catch_unknown then
            message('nothing set to catch', MESSAGE_ERROR)
        end
        for item_id, item_name in pairs(session.bait_by_id) do
            message(string.format('bait to use = %s (%d)', item_name, item_id))
        end
        if not next(session.bait_by_id) then
            message('no bait set to use', MESSAGE_ERROR)
        end
    end

    local function command_fatigue(value)
        if not value then
            update_fatigue()
        else
            local operation = string.sub(value, 1, 1)
            update_fatigue(operation == '+' or operation == '-', tonumber(value))
        end
    end

    windower.register_event('addon command', function (command, ...)
        command = string.lower(command)
        local argument = string.lower(table.concat({...}, ' '))
        if #argument == 0 then argument = nil end
        if command == 'start' then
            start_fishing(argument)
        elseif command == 'stop' then
            stop_fishing()
        elseif command == 'add' then
            command_add(argument)
        elseif command == 'remove' then
            command_remove(argument)
        elseif command == 'list' then
            command_list()
        elseif command == 'fatigue' then
            command_fatigue(argument)
        end
    end)
end

