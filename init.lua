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

-- Position du drone contrôlé par chaque joueur
local drone_formspec_positions = {}

-- Tête du drone
minetest.register_node(modprefix .. "blackdrone", {
    description = "Drone",
    tiles = {"drone.png"},
    groups = {cracky = 1},
    paramtype = "light",
    paramtype2 = "facedir",

    on_construct = function(pos)
        local node = minetest.get_node(pos)
        if not node.param2 then node.param2 = 0 end
        minetest.swap_node(pos, node)

        -- Place les segments derrière
        local dir = minetest.facedir_to_dir(node.param2)
        for i = 1, 3 do
            local seg_pos = vector.subtract(pos, vector.multiply(dir, i))
            if minetest.get_node(seg_pos).name == "air" then
                minetest.set_node(seg_pos, {name = modprefix .. "segment", param2 = node.param2})
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

-- Traitement de la télécommande
minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= modprefix .. "control_formspec" then return end

    local player_name = player:get_player_name()
    local head_pos = drone_formspec_positions[player_name]
    if not head_pos then return end

    local head_node = minetest.get_node(head_pos)
    if head_node.name ~= modprefix .. "blackdrone" then
        drone_formspec_positions[player_name] = nil
        return
    end

    local param2 = head_node.param2 or 0
    local dir = minetest.facedir_to_dir(param2)

    -- Rotation
    if fields.turnright or fields.turnleft then
        local rotationPart = param2 % 32
        local preservePart = param2 - rotationPart
        local axisdir = math.floor(rotationPart / 4)
        local rotation = rotationPart - axisdir * 4
        local new_rotation = fields.turnright and nextrangeright(rotation) or nextrangeleft(rotation)
        local new_param2 = preservePart + axisdir * 4 + new_rotation
        head_node.param2 = new_param2

        -- Supprimer anciens segments
        for i = 1, 3 do
            local seg_pos = vector.subtract(head_pos, vector.multiply(dir, i))
            minetest.remove_node(seg_pos)
        end

        minetest.swap_node(head_pos, head_node)

        -- Placer les segments dans la nouvelle direction
        dir = minetest.facedir_to_dir(new_param2)
        for i = 1, 3 do
            local seg_pos = vector.subtract(head_pos, vector.multiply(dir, i))
            minetest.set_node(seg_pos, {name = modprefix .. "segment", param2 = new_param2})
        end

        minetest.sound_play("moveokay", {to_player = player_name, gain = 1.0})
        return
    end

    -- Déplacement
    local offset = {x=0, y=0, z=0}
    if fields.up then offset.y = 1 end
    if fields.down then offset.y = -1 end
    if fields.forward then offset = vector.multiply(dir, -1) end
    if fields.backward then offset = vector.multiply(dir, 1) end

    if vector.equals(offset, {x=0, y=0, z=0}) then return end

    -- Vérification de toutes les nouvelles positions
    local future_positions = {}
    for i = 0, 3 do
        local old_pos = vector.subtract(head_pos, vector.multiply(dir, i))
        local new_pos = vector.add(old_pos, offset)
        local check_node = minetest.get_node(new_pos)
        --if minetest.registered_nodes[check_node.name].walkable then
        --   minetest.sound_play("moveerror", {to_player = player_name, gain = 1.0})
        --    minetest.chat_send_player(player_name, "Direction actuelle: x="..dir.x.." z="..dir.z)
        --   return
        --end
        table.insert(future_positions, {old = old_pos, new = new_pos})
    end

    -- Supprimer les anciens
    for _, p in ipairs(future_positions) do
        minetest.remove_node(p.old)
    end

    -- Placer les nouveaux
    for i, p in ipairs(future_positions) do
        local name = (i == 1) and modprefix .. "blackdrone" or modprefix .. "segment"
        minetest.set_node(p.new, {name = name, param2 = param2})
    end

    drone_formspec_positions[player_name] = future_positions[1].new
    minetest.sound_play("moveokay", {to_player = player_name, gain = 1.0})
end)

