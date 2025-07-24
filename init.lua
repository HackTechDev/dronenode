local modname = minetest.get_current_modname()
local modprefix = modname .. ":"

-- Télécommande
minetest.register_craftitem(modprefix .. "remotecontrol", {
    description = "Remote control for Drone",
    inventory_image = "drone_remotecontrol.png",
})

-- Segment du drone
minetest.register_node(modprefix .. "segment", {
    description = "Drone Segment",
    tiles = {"drone_segment.png"},
    groups = {cracky = 1, not_in_creative_inventory = 1},
    drop = "",
    paramtype = "light",
    paramtype2 = "facedir",
})

-- Stockage des positions centrales pour chaque joueur
local drone_formspec_positions = {}

------------------------------------------------------------
-- Génère les positions d'un rectangle 3×5
------------------------------------------------------------
local function get_drone_positions(center_pos, param2)
    -- Directions
    local forward = minetest.facedir_to_dir(param2)
    local right = {x = forward.z, y = 0, z = -forward.x} -- rotation 90° à droite
    local positions = {}

    -- Le centre (bloc "blackdrone") est à la rangée 3, colonne 2
    -- On génère une matrice de -2 à +2 (avant/arrière) et -1 à +1 (gauche/droite)
    for dz = -2, 2 do -- avant/arrière
        for dx = -1, 1 do -- gauche/droite
            local pos = vector.add(center_pos, vector.add(vector.multiply(forward, dz), vector.multiply(right, dx)))
            table.insert(positions, {pos = pos, is_center = (dz == 0 and dx == 0)})
        end
    end

    return positions
end

------------------------------------------------------------
-- Tête du drone
------------------------------------------------------------
minetest.register_node(modprefix .. "blackdrone", {
    description = "Drone",
    tiles = {"drone.png"},
    groups = {cracky = 1},
    paramtype = "light",
    paramtype2 = "facedir",

    -- Quand on place le bloc central
    on_construct = function(pos)
        local node = minetest.get_node(pos)
        if not node.param2 then node.param2 = 0 end
        minetest.swap_node(pos, node)

        -- Place automatiquement le rectangle 3×5
        local positions = get_drone_positions(pos, node.param2)
        for _, p in ipairs(positions) do
            if not p.is_center and minetest.get_node(p.pos).name == "air" then
                minetest.set_node(p.pos, {name = modprefix .. "segment", param2 = node.param2})
            end
        end
    end,

    on_rightclick = function(pos, node, clicker, itemstack)
        if clicker:get_wielded_item():get_name() ~= modprefix .. "remotecontrol" then
            minetest.chat_send_player(clicker:get_player_name(), "Remote control needed")
            return
        end

        local player_name = clicker:get_player_name()
        drone_formspec_positions[player_name] = pos

        minetest.show_formspec(player_name, modprefix .. "control_formspec",
            "size[9,4]" ..
            "label[0,0;Click buttons to move the drone]" ..
            "button_exit[5,1;2,1;exit;Exit]" ..
            "image_button[1,1;1,1;arrow_up.png;up;]" ..
            "image_button[2,1;1,1;arrow_fw.png;forward;]" ..
            "image_button[1,2;1,1;arrow_left.png;turnleft;]"..
            "image_button[3,2;1,1;arrow_right.png;turnright;]" ..
            "image_button[1,3;1,1;arrow_down.png;down;]" ..
            "image_button[2,3;1,1;arrow_bw.png;backward;]"
        )
    end,
})

-- Rotation helpers
local function nextrangeright(x) return (x + 1) % 4 end
local function nextrangeleft(x) return (x + 3) % 4 end

------------------------------------------------------------
-- Déplacement et rotation du drone 3×5
------------------------------------------------------------
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= modprefix .. "control_formspec" then return end

    local player_name = player:get_player_name()
    local center_pos = drone_formspec_positions[player_name]
    if not center_pos then return end

    local head_node = minetest.get_node(center_pos)
    if head_node.name ~= modprefix .. "blackdrone" then
        drone_formspec_positions[player_name] = nil
        return
    end

    local param2 = head_node.param2 or 0
    local forward = minetest.facedir_to_dir(param2)

    -- === ROTATION ===
    if fields.turnright or fields.turnleft then
        local rotationPart = param2 % 32
        local preservePart = param2 - rotationPart
        local axisdir = math.floor(rotationPart / 4)
        local rotation = rotationPart - axisdir * 4
        local new_rotation = fields.turnright and nextrangeright(rotation) or nextrangeleft(rotation)
        local new_param2 = preservePart + axisdir * 4 + new_rotation
        head_node.param2 = new_param2

        -- Supprimer l'ancien rectangle
        local old_positions = get_drone_positions(center_pos, param2)
        for _, p in ipairs(old_positions) do
            if not p.is_center then
                minetest.remove_node(p.pos)
            end
        end

        -- Replacer la tête
        minetest.swap_node(center_pos, head_node)

        -- Générer le rectangle dans la nouvelle direction
        local new_positions = get_drone_positions(center_pos, new_param2)
        for _, p in ipairs(new_positions) do
            if not p.is_center then
                minetest.set_node(p.pos, {name = modprefix .. "segment", param2 = new_param2})
            end
        end

        minetest.sound_play("moveokay", {to_player = player_name, gain = 1.0})
        return
    end

    -- === DÉPLACEMENT ===
    local offset = {x=0, y=0, z=0}
    if fields.up then offset.y = 1 end
    if fields.down then offset.y = -1 end
    if fields.forward then offset = forward end
    if fields.backward then offset = vector.multiply(forward, -1) end

    if vector.equals(offset, {x=0, y=0, z=0}) then return end

    -- Vérifier que toutes les nouvelles positions sont libres
    local current_positions = get_drone_positions(center_pos, param2)
    for _, p in ipairs(current_positions) do
        local new_pos = vector.add(p.pos, offset)
        local check_node = minetest.get_node(new_pos)
        --if minetest.registered_nodes[check_node.name].walkable and check_node.name ~= modprefix.."segment" then
        --    minetest.sound_play("moveerror", {to_player = player_name, gain = 1.0})
        --    return
        --end
    end

    -- Supprimer tous les anciens blocs
    for _, p in ipairs(current_positions) do
        minetest.remove_node(p.pos)
    end

    -- Replacer le drone déplacé
    local new_center = vector.add(center_pos, offset)
    local new_positions = get_drone_positions(new_center, param2)
    for _, p in ipairs(new_positions) do
        local name = p.is_center and modprefix .. "blackdrone" or modprefix .. "segment"
        minetest.set_node(p.pos, {name = name, param2 = param2})
    end

    drone_formspec_positions[player_name] = new_center
    minetest.sound_play("moveokay", {to_player = player_name, gain = 1.0})
end)

