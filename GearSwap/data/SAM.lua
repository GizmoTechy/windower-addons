time_start = os.time()
player_state = "Idle"

function get_sets()
    mote_include_version = 2

    -- Load and initialize the include file.
    include("Mote-Include.lua")
end

function user_setup()
    state.OffenseMode:options("Normal", "Acc", "TP")
    state.HybridMode:options("Normal", "Acc", "TP")
    state.AutoSC = M(false, "Auto Skillchain")
    state.CP = M(false, "CP")

    send_command("bind !end gs c toggle AutoSC")
    send_command("bind ^end gs c toggle CP")

    select_default_macro_book()
    send_command("wait 3;input /lockstyleset 96")
end

function file_unload()
    send_command("unbind !end")
    send_command("unbind ^end")
end

function init_gear_sets()
    Artifact = {}
    Artifact.Head = "Wakido Kabuto +3"
    Artifact.Body = "Wakido Domaru +3"
    Artifact.Hands = "Wakido Kote +3"
    Artifact.Legs = "Wakido Haidate +3"
    Artifact.Feet = "Wakido Sune-Ate +3"

    Relic = {}
    Relic.Head = "Sakonji Kabuto +3"
    Relic.Body = "Sakonji Domaru +3"
    Relic.Hands = "Sakonji Kote +3"
    Relic.Legs = "Sakonji Haidate +3"
    Relic.Feet = "Sakonji Sune-Ate +3"

    Empyrean = {}
    Empyrean.Head = "Kasuga Kabuto +1"
    Empyrean.Body = "Kasuga Domaru +1"
    Empyrean.Hands = "Kasuga Kote +1"
    Empyrean.Legs = "Kasuga Haidate +1"
    Empyrean.Feet = "Kasuga Sune-Ate +1"

    Flamma = {}
    Flamma.Head = "Flamma Zucchetto +2"
    Flamma.Body = "Flamma Korazin +2"
    Flamma.Hands = "Flamma Manopolas +2"
    Flamma.Legs = "Flamma Dirs +1"
    Flamma.Feet = "Flamma Gambieras +2"
    Flamma.Ring = "Flamma Ring"

    Valorous = {}
    Valorous.Head = {
        name = "Valorous Mask",
        augments = {'Weapon Skill Acc.+4', 'STR+10', 'Accuracy+14', 'Attack+14'}
    }
    Valorous.Body = "Valorous Mail"
    Valorous.Hands = {
        name = "Valorous Mitts",
        augments = {'Weapon Skill Acc.+11', 'STR+11', 'Accuracy+7', 'Attack+11'}
    }
    Valorous.Legs = "Valorous Hose"
    Valorous.Feet = {
        name = "Valorous Greaves",
        augments = {'Accuracy+30', 'Crit.hit rate+1', 'STR+12', 'Attack+12'}
    }

    Fotia = {}
    Fotia.Neck = "Fotia Gorget"
    Fotia.Waist = "Fotia Belt" --weaponskill belt

    Weapon = {}
    Weapon.Empy = "Masamune"
    Weapon.Aeonic = "Dojikiri Yasutsuna"
    Weapon.Def = "Umaru" --weapon pre REMA

    Ring = {}
    Ring.Niq = "Niqmaddu Ring"
    Ring.Reg = "Regal Ring"
    Ring.Def = "Defending Ring"
    Ring.Gel = "Gelatinous Ring +1"
    Ring.Epa = "Epaminonda's Ring"
    Ring.Apa = "Apate Ring"

    Earring = {}
    Earring.Ded = "Dedition Earring"
    Earring.Cess = "Cessance Earring"
    Earring.Tel = "Telos Earring"
    Earring.Bru = "Brutal Earring"
    Earring.Digni = "Dignitary's Earring"
    Earring.Moon = "Moonshade Earring"
    Earring.Ish = "Ishvara Earring"
    Earring.Gen = "Genmei Earring"
    Earring.Eti = "Etiolation Earring"
    Earring.Mac = "Mache Earring"

    Waist = {}
    Waist.TP = "Ioskeha Belt"
    Waist.DT = "Flume Belt +1"

    Ammo = {}
    Ammo.TP = "Ginsen"
    Ammo.DT = "Staunch Tathlum +1"
    Ammo.WS = "Knobkierrie"

    Grip = {}
    Grip.Utu = "Utu Grip"
    Grip.Dilet = "Dilet.'s Grip +1"

    Neck = {}
    Neck.Def = "Samurai's Nodowa"

    Back = {}
    Back.CP = "Mecisto. Mantle"

    sets.idle = {
        sub = Grip.Dilet,
        range = empty,
        -- ammo = empty,
        ammo = Ammo.TP,
        head = Flamma.Head,
        body = Flamma.Body,
        hands = Flamma.Hands,
        legs = "Hiza. Hizayoroi +2",
        feet = Flamma.Feet,
        neck = Neck.Def,
        waist = Waist.TP,
        left_ear = Earring.Cess,
        right_ear = Earring.Bru,
        left_ring = Flamma.Ring,
        right_ring = Ring.Niq,
        back = "Smertrios's Mantle"
    }

    sets.engaged = set_combine(sets.idle, {})

    sets.precast.WS = {
        sub = Grip.Dilet,
        range = empty,
        -- ammo = empty,
        ammo = Ammo.TP,
        head = Valorous.Head,
        body = Flamma.Body,
        hands = Valorous.Hands,
        legs = "Hiza. Hizayoroi +2",
        feet = Valorous.Feet,
        neck = Neck.Def,
        waist = Waist.TP,
        left_ear = Earring.Moon,
        right_ear = Earring.Bru,
        left_ring = Flamma.Ring,
        right_ring = Ring.Niq,
        back = "Smertrios's Mantle"
    }

    sets.precast.RA = {
        range = "Cibitshavore",
        ammo = "Beetle Arrow"
    }

end

function user_status_change(newStatus, oldStatus)
    if newStatus == "Engaged" and state.AutoSC.value == true then
        send_command("wait 5; input //autosc start")
    elseif newStatus ~= "Engaged" and state.AutoSC.value == true then
        send_command("input //autosc stop")
    end

    if newStatus == "Engaged" then
        player_state = "Engaged"
    else
        player_state = "Idle"
        enable("back")
    end
end

windower.register_event(
    "prerender",
    function()
        if os.time() > time_start then
            time_start = os.time()

            if player_state == "Engaged" and state.CP.value == true then
                monsterToCheck = windower.ffxi.get_mob_by_target("t")
                if monsterToCheck then -- Sanity Check

                    if monsterToCheck.hpp < 15 then --Check mobs HP Percentage if below 15 then equip CP cape
                        equip({ back = Back.CP })
                        disable("back") --Lock back till we disengage
                    else
                        enable("back") --Else make sure the back is enabled
                    end

                end
            end
        end
    end
)

-- Select default macro book on initial load or subjob change.
function select_default_macro_book()
    -- Default macro set/book
    if player.sub_job == "WAR" then
        set_macro_page(1, 4)
    elseif player.sub_job == "DNC" then
        set_macro_page(2, 4)
    else
        set_macro_page(1, 4)
    end
end
