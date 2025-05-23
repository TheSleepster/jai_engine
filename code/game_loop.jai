Game_State :: struct
{
    game_arena            :  Memory_Arena;
    world_gen_arena       :  Memory_Arena;
    WFC_arena             :  Memory_Arena;
    
    input_manager         : *Input_Manager;
    entity_manager        : *Entity_Manager;
    game_data             :  Game_Data;
    
    input_axis            :  Vector2;

    primary_game_camera   :  Game_Camera;

    is_running            :  bool;
    is_initialized        :  bool;
};

World_Frame_Data :: struct
{
    world_projection      :  Matrix4;
    world_view            :  Matrix4;
    
    screen_projection     :  Matrix4;
    screen_view           :  Matrix4;

    player                : *Entity;
    active_hovered_entity : *Entity;
    entity_to_grab        : *Entity;

    screen_space_mouse    :  Vector2;
    world_space_mouse     :  Vector2;
};

using game_action_index :: enum u64
{
    MOVE_UP;
    MOVE_DOWN;
    MOVE_LEFT;
    MOVE_RIGHT;
    INTERACT;
    ATTACK;
};

check_movement_actions :: (game_state: *Game_State, time: Time_Data)
{
    game_state.input_axis = .{0, 0};
    
    using game_state;
    if game_action_is_down(input_manager, .MOVE_UP)
    {
        game_state.input_axis.y =  1;
    }
    if game_action_is_down(input_manager, .MOVE_DOWN)
    {
        game_state.input_axis.x = -1;
    }
    if game_action_is_down(input_manager, .MOVE_LEFT)
    {
        game_state.input_axis.y = -1;
    }
    if game_action_is_down(input_manager, .MOVE_RIGHT)
    {
        game_state.input_axis.x =  1;
    }

    // TODO(Sleepster): refine controller queries
    if input_manager.connected_controller_count > 0
    {
        left_stick_x, left_stick_y := read_controller_axis(input_manager, xx SDL_CONTROLLER_AXIS_LEFTX);
        game_state.input_axis.x = ifx (abs(left_stick_x) > input_manager.controller_input.axis_button_states[SDL_CONTROLLER_AXIS_LEFTX].button_deadzone) then left_stick_x / 32767.0 else 0;
        game_state.input_axis.y = ifx (abs(left_stick_y) > input_manager.controller_input.axis_button_states[SDL_CONTROLLER_AXIS_LEFTX].button_deadzone) then (left_stick_y / 32767.0) * -1 else 0;
    }

    game_state.input_axis = normalize(game_state.input_axis);
}

OLD_world_to_tile_pos :: inline (world_pos: Vector2) -> iVector2
{
    result: iVector2 = ---;
    result.x = cast(s32)floor(world_pos.x / TILE_SIZE);
    result.y = cast(s32)floor(world_pos.y / TILE_SIZE);

    return result;
}

OLD_tile_to_world_pos :: inline (tile_pos: iVector2) -> Vector2
{
    result: Vector2 = ---;
    result.x = cast(float32)tile_pos.x * cast(float32)TILE_SIZE;
    result.y = cast(float32)tile_pos.y * cast(float32)TILE_SIZE;

    return result;
}

OLD_round_to_nearest_tile :: inline (pos: Vector2) -> Vector2
{
    result: Vector2 = ---;
    result = OLD_tile_to_world_pos(OLD_world_to_tile_pos(pos));

    return result;
}

transform_mouse_coords :: (view_matrix: Matrix4, projection: Matrix4, mouse_vector: Vector2, window_size: iVector2) -> Vector2
{
    result: Vector2; 

    window_size_float := (Vector2).{cast(float32)window_size.x, cast(float32)window_size.y};
    mouse_ndc := (Vector2).{mouse_vector.x / (window_size_float.x * 0.5) - 1.0, 1.0 - (mouse_vector.y / (window_size_float.y * 0.5))};
    mouse_ndc_pos := make_vector4(mouse_ndc, 0.0, 1.0);

    inverse_projection := inverse(projection);
    inverse_view       := inverse(view_matrix);

    mouse_ndc_pos = mat4_transform(inverse_projection, mouse_ndc_pos);
    mouse_ndc_pos = mat4_transform(inverse_view,       mouse_ndc_pos);

    result = mouse_ndc_pos.xy;
    return result;
}

push_screen_space_matrices :: (draw_frame: *Draw_Frame_Data, world_frame: *World_Frame_Data)
{
    draw_frame.active_view_matrix       = *world_frame.screen_view;
    draw_frame.active_projection_matrix = *world_frame.screen_projection;
}

push_world_space_matrices :: (draw_frame: *Draw_Frame_Data, world_frame: *World_Frame_Data)
{
    draw_frame.active_view_matrix       = *world_frame.world_view;
    draw_frame.active_projection_matrix = *world_frame.world_projection;
}

reload_asset_pointers :: (asset_manager: *Asset_Manager)
{
    default_sprite     = asset_get_sprite(asset_manager, "null_sprite");
    sprite_player      = asset_get_sprite(asset_manager, "player");
    sprite_furnace     = asset_get_sprite(asset_manager, "furnace");
    sprite_base_block  = asset_get_sprite(asset_manager, "block");
    sprite_workbench   = asset_get_sprite(asset_manager, "workbench");
    sprite_textureless = asset_get_sprite(asset_manager, "textureless_sprite");
    sprite_stone_node  = asset_get_sprite(asset_manager, "stone_node");
    sprite_coal_node   = asset_get_sprite(asset_manager, "coal_node");
    sprite_tree_00     = asset_get_sprite(asset_manager, "tree_00");
    sprite_stone_chunk = asset_get_sprite(asset_manager, "stone_chunk");
    sprite_coal_chunk  = asset_get_sprite(asset_manager, "coal_chunk");
    sprite_wood_chunk  = asset_get_sprite(asset_manager, "wood_chunk");
    sprite_WFC_input   = asset_get_sprite(asset_manager, "test_WFC_input");

    sprite_outline     = asset_get_sprite(asset_manager, "outline");

    game_atlas         = default_sprite.atlas_texture;
    game_font          = asset_get_font(asset_manager, "LiberationMono-Regular");
}

game_update_and_render :: (game_memory: *Game_Memory, window_data: *Window_Data, draw_frame: *Draw_Frame_Data, time: Time_Data)
{
    DEBUG_profile_function();
    
    game_state      :=  game_memory.game_state;
    transient_state :=  game_memory.transient_state;

    asset_manager   :=  transient_state.asset_manager;
    input_manager   :=  game_state.input_manager;
    entity_manager  :=  game_state.entity_manager;
    game_camera     := *game_state.primary_game_camera;
    game_data       := *game_state.game_data;

    // NOTE(Sleepster): INIT WORLD FRAME
    world_frame:  World_Frame_Data;

    // NOTE(Sleepster): CREATE MATRICES
    //                                                  180                                 120
    //size_data := (Vector3).{window_data.window_size.x / (3840.0 * 4), window_data.window_size.y / (2880.0 * 4), 1.0};
    size_data := (Vector3).{window_data.window_size.x / 960.0, window_data.window_size.y / 720.0, 1.0};
    //size_data := (Vector3).{window_data.window_size.x / 180, window_data.window_size.y / 120, 1.0};
    v2_approach(*game_camera.current_position, game_camera.target_position, game_camera.travel_rate, time.delta_time);

    scale_matrix       := mat4_make_scale(size_data);
    translation_matrix := mat4_make_translation((Vector3).{-game_camera.current_position.x,
                                                           -game_camera.current_position.y, 0});
    world_frame.world_view       = Matrix4_Identity;
    world_frame.world_view       = multiply(world_frame.world_view, translation_matrix);
    world_frame.world_view       = multiply(world_frame.world_view, scale_matrix);
    world_frame.world_projection = orthographic_projection_matrix(window_data.window_size.x * -0.5,
                                                                  window_data.window_size.x *  0.5,
                                                                  window_data.window_size.y * -0.5,
                                                                  window_data.window_size.y *  0.5,
                                                                 -1.0,
                                                                  1.0);

    world_frame.screen_view       = Matrix4_Identity;
    world_frame.screen_projection = orthographic_projection_matrix(window_data.window_size.x * -0.5,
                                                                   window_data.window_size.x *  0.5,
                                                                   window_data.window_size.y * -0.5,
                                                                   window_data.window_size.y *  0.5,
                                                                  -1.0,
                                                                   1.0);

    // NOTE(Sleepster): MATRIX ASSIGNMENT
    draw_frame.active_view_matrix       = *world_frame.world_view;
    draw_frame.active_projection_matrix = *world_frame.world_projection;

    world_frame.world_space_mouse  = transform_mouse_coords(draw_frame.active_view_matrix,
                                                            draw_frame.active_projection_matrix,
                                                            input_manager.keyboard_input.current_mouse_pos,
                                                            window_data.window_size);
    world_frame.screen_space_mouse = transform_mouse_coords(world_frame.screen_view,
                                                            world_frame.screen_projection,
                                                            input_manager.keyboard_input.current_mouse_pos,
                                                            window_data.window_size);
    if !game_state.is_initialized
    {
        reload_asset_pointers(asset_manager);
        init_game_data(game_data);

        entity_manager.entities = push_array(*game_state.game_arena, Entity, MAX_ENTITIES);

        // NOTE(Sleepster): replace game_state.game_arena here...
        modules := push_array(*game_state.game_arena, WFC_Module, 6);

        // BLACK BACKGROUND
        modules[0].sprite = subsprite(sprite_WFC_input, .{32, 32}, .{16, 16});
        modules[0].weight = 0.01;
        for *constraint: modules[0].constraints
        {
            constraint.* = bitset_create(*game_state.game_arena, modules.count);
        }

        bitset_set_bit(*modules[0].constraints[NORTH], 0);
        bitset_set_bit(*modules[0].constraints[NORTH], 4);
        bitset_set_bit(*modules[0].constraints[NORTH], 2);
        bitset_set_bit(*modules[0].constraints[NORTH], 3);

        bitset_set_bit(*modules[0].constraints[SOUTH], 0);
        bitset_set_bit(*modules[0].constraints[SOUTH], 1);
        bitset_set_bit(*modules[0].constraints[SOUTH], 2);
        bitset_set_bit(*modules[0].constraints[SOUTH], 3);

        bitset_set_bit(*modules[0].constraints[EAST], 0);
        bitset_set_bit(*modules[0].constraints[EAST], 3);
        bitset_set_bit(*modules[0].constraints[EAST], 4);

        bitset_set_bit(*modules[0].constraints[WEST], 0);
        bitset_set_bit(*modules[0].constraints[WEST], 2);
        bitset_set_bit(*modules[0].constraints[WEST], 4);

        // WALL TOP
        modules[1].sprite = subsprite(sprite_WFC_input, .{16, 32}, .{16, 16});
        modules[1].weight = 2.0;
        for *constraint: modules[1].constraints
        {
            constraint.* = bitset_create(*game_state.game_arena, modules.count);
        }

        bitset_set_bit(*modules[1].constraints[NORTH], 0);

        bitset_set_bit(*modules[1].constraints[SOUTH], 5);

        bitset_set_bit(*modules[1].constraints[EAST], 1);
        bitset_set_bit(*modules[1].constraints[EAST], 2);

        bitset_set_bit(*modules[1].constraints[WEST], 1);
        bitset_set_bit(*modules[1].constraints[WEST], 3);


        // WALL EAST SIDE 
        modules[2].sprite = subsprite(sprite_WFC_input, .{32, 16}, .{16, 16});
        modules[2].weight = 0.50;
        for *constraint: modules[2].constraints
        {
            constraint.* = bitset_create(*game_state.game_arena, modules.count);
        }

        bitset_set_bit(*modules[2].constraints[NORTH], 0);
        bitset_set_bit(*modules[2].constraints[NORTH], 2);

        bitset_set_bit(*modules[2].constraints[SOUTH], 0);
        bitset_set_bit(*modules[2].constraints[SOUTH], 2);

        bitset_set_bit(*modules[2].constraints[EAST], 0);

        bitset_set_bit(*modules[2].constraints[WEST], 5);
        bitset_set_bit(*modules[2].constraints[WEST], 1);
        bitset_set_bit(*modules[2].constraints[WEST], 4);

        // WALL WEST SIDE
        modules[3].sprite = subsprite(sprite_WFC_input, .{ 0, 16}, .{16, 16});
        modules[3].weight = 0.50;
        for *constraint: modules[3].constraints
        {
            constraint.* = bitset_create(*game_state.game_arena, modules.count);
        }
        
        bitset_set_bit(*modules[3].constraints[NORTH], 0);
        bitset_set_bit(*modules[3].constraints[NORTH], 3);

        bitset_set_bit(*modules[3].constraints[SOUTH], 0);
        bitset_set_bit(*modules[3].constraints[SOUTH], 3);

        bitset_set_bit(*modules[3].constraints[EAST], 5);
        bitset_set_bit(*modules[3].constraints[EAST], 4);
        bitset_set_bit(*modules[3].constraints[EAST], 1);

        bitset_set_bit(*modules[3].constraints[WEST], 0);

        // WALL BOTTOM SIDE
        modules[4].sprite = subsprite(sprite_WFC_input, .{16,  0}, .{16, 16});
        modules[4].weight = 2.0;
        for *constraint: modules[4].constraints
        {
            constraint.* = bitset_create(*game_state.game_arena, modules.count);
        }

        bitset_set_bit(*modules[4].constraints[NORTH], 5);

        bitset_set_bit(*modules[4].constraints[SOUTH], 0);
        bitset_set_bit(*modules[4].constraints[SOUTH], 1);

        bitset_set_bit(*modules[4].constraints[EAST], 0);
        bitset_set_bit(*modules[4].constraints[EAST], 2);
        bitset_set_bit(*modules[4].constraints[EAST], 4);

        bitset_set_bit(*modules[4].constraints[WEST], 0);
        bitset_set_bit(*modules[4].constraints[WEST], 3);
        bitset_set_bit(*modules[4].constraints[WEST], 4);

        // FLOOR 
        modules[5].sprite = subsprite(sprite_WFC_input, .{16, 16}, .{16, 16});
        modules[5].weight = 8.0;
        for *constraint: modules[5].constraints
        {
            constraint.* = bitset_create(*game_state.game_arena, modules.count);
        }

        bitset_set_bit(*modules[5].constraints[NORTH], 5);
        bitset_set_bit(*modules[5].constraints[NORTH], 1);

        bitset_set_bit(*modules[5].constraints[SOUTH], 5);
        bitset_set_bit(*modules[5].constraints[SOUTH], 4);

        bitset_set_bit(*modules[5].constraints[EAST], 5);
        bitset_set_bit(*modules[5].constraints[EAST], 2);

        bitset_set_bit(*modules[5].constraints[WEST], 5);
        bitset_set_bit(*modules[5].constraints[WEST], 3);

        filepath :: "../data/res/textures/DEBUG/OLM_test_input2.png";
        test_modules := WFC_analyze(*game_state.game_arena, asset_manager, filepath);

        // generation_size := (iVector2).{30, 30};
        // generate_enclosed_room(game_state, test_modules, generation_size);

        floorplan = generate_dungeon_floorplan(*game_state.world_gen_arena, .{5, 5}, .{35, 40}, 150.0, 250.0);

        map_color1 = hex_to_rgba(0x202e37);
        map_color2 = hex_to_rgba(0x151d28);

        // TODO(Sleepster): make a better way of indexing into these 
        move_up    := game_action_set_action(input_manager, xx SDL_SCANCODE_W,        xx SDL_CONTROLLER_AXIS_LEFTX);
        move_left  := game_action_set_action(input_manager, xx SDL_SCANCODE_A,        xx SDL_CONTROLLER_AXIS_LEFTX);
        move_down  := game_action_set_action(input_manager, xx SDL_SCANCODE_S,        xx SDL_CONTROLLER_AXIS_LEFTX);
        move_right := game_action_set_action(input_manager, xx SDL_SCANCODE_D,        xx SDL_CONTROLLER_AXIS_LEFTX);
        interact   := game_action_set_action(input_manager, xx SDL_SCANCODE_E,        xx SDL_CONTROLLER_BUTTON_A);
        attack     := game_action_set_action(input_manager, xx SDL_LEFT_MOUSE_BUTTON, xx SDL_CONTROLLER_BUTTON_X);

        array_add(*input_manager.game_actions, *move_up);
        array_add(*input_manager.game_actions, *move_left);
        array_add(*input_manager.game_actions, *move_down);
        array_add(*input_manager.game_actions, *move_right);
        array_add(*input_manager.game_actions, *interact);
        array_add(*input_manager.game_actions, *attack);

        draw_frame.clear_color = .{0.05, 0.05, 0.05, 1.0};

        game_state.is_initialized = true;
        game_state.primary_game_camera = game_camera_create(0.1, 0); 
    }
    if is_key_pressed(input_manager, xx SDL_SCANCODE_H)
    {
        reload_asset_pointers(asset_manager);
    }

    WFC_render(*new_chunk, draw_frame);

    //finished := simulate_generation(*game_state.world_gen_arena, draw_frame, time);
    draw_generation(draw_frame, *floorplan);

    if is_key_pressed(input_manager, xx SDL_SCANCODE_R)
    {
        reset_arena(*game_state.world_gen_arena);
        floorplan = generate_dungeon_floorplan(*game_state.world_gen_arena, .{5, 5}, .{35, 40}, 150.0, 250.0);
    }

    // NOTE(Sleepster): UPDATE PLAYER
    world_frame.player = get_player(game_state.entity_manager);
    check_movement_actions(game_state, time);
    for player_index: 0..game_state.entity_manager.active_entity_counter
    {
        player := *game_state.entity_manager.entities[player_index];
        if player.flags & xx IS_VALID
        {
            new_pos := (game_state.input_axis * player.speed) * time.delta_time;
            if new_pos != .{}
            {
                entity_check_direction(player, new_pos);
            }

            player.position += new_pos;
            game_camera.target_position = player.position;
            break;
        }
    }

    // NOTE(Sleepster): UPDATE ENTITY COLLISION BOUNDING BOXES
    {
        for index: 0..entity_manager.active_entity_counter
        {
            entity := *entity_manager.entities[index];
            if entity.flags & xx IS_VALID
            {
                // I am a bad person.
                entity.bounding_box = AABB_create(entity.position, entity.position + entity.render_size);
            }
        }
    }

    // NOTE(Sleepster): CHECK FOR COLLISIONS
    {
    }

    // NOTE(Sleepster): WORLD FRAME GET TARGET GRABBABLE ENTITY
    player := world_frame.player;
    if player
    {
        player.max_slots = 20;
        {
            max_grab_dist := 16.0;
            min_dist: float32 = max_grab_dist;
            closest_entity: *Entity;

            for index: 0..entity_manager.active_entity_counter
            {
                entity := *entity_manager.entities[index];
                if (entity.flags & xx IS_VALID) && (entity.flags & xx IS_GRABBABLE)
                {
                    dist := distance(player.position, entity.position);
                    if dist < min_dist
                    {
                        min_dist = dist;
                        closest_entity = entity;
                    }
                }
            }
            if closest_entity
            {
                world_frame.entity_to_grab = closest_entity;
            }

            // NOTE(Sleepster): PLAYER GRAB
            if game_action_is_pressed(game_state.input_manager, .INTERACT)
            {
                if !player.attached_entity
                {
                    if world_frame.entity_to_grab && distance(player.position, world_frame.entity_to_grab.position) < max_grab_dist
                    {
                        player.attached_entity = world_frame.entity_to_grab;
                    }
                }
                else
                {
                    // NOTE(Sleepster): PLAYER BUILDING
                    collision: bool;
                    position_to_place := OLD_round_to_nearest_tile(player.attached_entity.position + (.{4, 8} * player.direction)); 
                    for index: 0..entity_manager.active_entity_counter
                    {
                        entity := *entity_manager.entities[index];
                        if (entity.flags & xx IS_VALID)
                        {
                            entity.bounding_box.min -= .{4, 2};
                            entity.bounding_box.max -= .{4, 2};
                            if AABB_is_point_within(position_to_place, entity.bounding_box)
                            {
                                collision = true;
                            }
                        }
                    }
                    
                    if !collision
                    {
                        offset_x: float32 = 0;
                        offset_y: float32 = 0;
                        if player.direction.x != 0
                        {
                            offset_x = 4 * player.direction.x;
                        }

                        if player.direction.y != 0
                        {
                            offset_y = 8 * player.direction.y;
                        }

                        player.attached_entity.position = OLD_round_to_nearest_tile(player.attached_entity.position + .{offset_x, offset_y}); 
                        player.attached_entity = null;
                    }
                }
            }

            entity := player.attached_entity;
            if entity
            {
                // TODO(Sleepster): mutiply this by the player's direction. 
                grab_offset := player.position + ((Vector2).{8, 4} * player.direction);
                entity.position = grab_offset;
            }
        }
    }

    // NOTE(Sleepster): WORLD FRAME GET HOVERED OVER ENTITY
    {
        reach_dist     := 14.0;
        min_dist       := reach_dist;

        closest_targetable_entity: *Entity;
        for index: 0..entity_manager.active_entity_counter
        {
            entity := *entity_manager.entities[index];
            if (entity.flags & xx IS_VALID)     &&
              !(entity.flags & xx IS_GRABBABLE) &&
              !(entity.flags & xx IS_ITEM)      &&
               (entity.archetype != xx entity_archetype.PLAYER)
            {
                dist := distance(player.position, entity.position);
                if dist <= min_dist
                {
                    min_dist = dist;
                    closest_targetable_entity = entity;
                }
            }
        }
        if closest_targetable_entity
        {
            distance_from_cursor := distance(world_frame.world_space_mouse, closest_targetable_entity.position);
            if distance_from_cursor <= reach_dist
            {
                world_frame.active_hovered_entity = closest_targetable_entity;
            }
        }
    }

    // NOTE(Sleepster): DAMAGE AND DESTROY TARGET ENTITY
    {
        if world_frame.active_hovered_entity
        {
            using world_frame;
            if active_hovered_entity.flags & xx CAN_BE_DAMAGED
            {
                if game_action_is_pressed(input_manager, .ATTACK)
                {
                    active_hovered_entity.current_health -= 1;
                }
            }
        }
    }

    // NOTE(Sleepster): UPDATE ENTITY LIFE STATUS
    {
        for index: 0..entity_manager.active_entity_counter
        {
            entity := *entity_manager.entities[index];
            if (entity.flags & xx IS_VALID) && (entity.flags & xx CAN_BE_DAMAGED)
            {
                if entity.current_health <= 0
                {
                    entity.flags |= xx IS_DEAD;
                }
            }
        }
    }

    // NOTE(Sleepster): HANDLE ITEMS
    {
        for index: 0..entity_manager.active_entity_counter
        {
            entity := *entity_manager.entities[index];
            if (entity.flags & xx IS_VALID) &&
               (entity.flags & xx IS_ITEM)
            {
                if entity.pickup_delay && entity.pickup_timer > 0
                {
                    entity.pickup_timer -= 0.001;
                }

                if entity.pickup_timer <= 0
                {
                    entity.flags |= xx CAN_BE_PICKED_UP;
                }
            }
        }
    }

    // NOTE(Sleepster): PICKUP ITEMS IN RANGE
    {
        for index: 0..entity_manager.active_entity_counter
        {
            entity := *entity_manager.entities[index];
            if (entity.flags & xx IS_VALID) &&
               (entity.flags & xx CAN_BE_PICKED_UP)
            {
                player := world_frame.player;
                max_pickup_dist :: 20;
                epsilon := 2.0;

                dist := distance(player.position, entity.position);
                if dist <= max_pickup_dist
                {
                    entity.target_position = player.position;
                    v2_approach(*entity.position, entity.target_position, 0.1, time.delta_time);

                    if dist <= epsilon
                    {
                        if add_to_entity_inventory(game_state, player, entity.drop_id, 1)
                        {
                            entity.flags |= xx IS_DEAD;
                        }
                        else
                        {
                            entity.target_position = entity.position;
                        }
                    }
                }
            }
        }
    }

    // NOTE(Sleepster): HANDLE DEAD ENTITIES 
    {
        for index: 0..entity_manager.active_entity_counter
        {
            entity := *entity_manager.entities[index];
            if(entity.flags & xx IS_VALID) && (entity.flags & xx IS_DEAD)
            {
                if entity.flags & xx DROPS_ITEMS_ON_DEATH
                {
                    for drop: entity.drop_list
                    {
                        for 0..drop.amount_to_drop
                        {
                            random_drop_position := (Vector2).{random_get_within_range(-entity.max_drop_radius, entity.max_drop_radius),
                                                               random_get_within_range(-entity.max_drop_radius, entity.max_drop_radius)};

                            new_entity := spawn_item(game_state, drop.dropped_item);
                            new_entity.position = entity.position + random_drop_position;
                            new_entity.drop_id = drop.dropped_item;

                            destroy_entity(entity);
                        }
                    }
                }
                else
                {
                    destroy_entity(entity);
                }
            }
        }
    }

    // // NOTE(Sleepster): DEBUG TILES
    // push_render_layer(draw_frame, 8);
    // tile_offset := world_to_tile_pos(world_frame.player.position);
    // tile_radius := (iVector2).{20, 12};

    // initial_x := tile_offset.x - tile_radius.x;
    // initial_y := tile_offset.y - tile_radius.y;
    // for x_index: initial_x .. (tile_offset.x + tile_radius.x) - 1
    // {
    //     for y_index: initial_y .. (tile_offset.y + tile_radius.y) - 1
    //     {
    //         tile_x := x_index * cast(float32)TILE_SIZE;
    //         tile_y := y_index * cast(float32)TILE_SIZE;
    //         if (x_index + cast(s32)(y_index % 2 == 0)) % 2 == 0
    //         {
    //             draw_texture(draw_frame, .{tile_x, (tile_y - TILE_SIZE) - TILE_SIZE}, .{8, 8}, sprite_textureless, map_color1);
    //         }
    //         else
    //         {
    //             draw_texture(draw_frame, .{tile_x, (tile_y - TILE_SIZE) - TILE_SIZE}, .{8, 8}, sprite_textureless, map_color2);
    //         }
    //     }
    // }

    // NOTE(Sleepster): ENTITY RENDERING 
    push_render_layer(draw_frame, 10);
    for entity_index: 0..game_state.entity_manager.active_entity_counter
    {
        entity := *game_state.entity_manager.entities[entity_index];
        if entity.flags & xx IS_VALID
        {
            draw_texture(draw_frame,
                         entity.position,
                         entity.render_size,
                         entity.sprite_data,
                         entity.draw_color);
            if entity == world_frame.active_hovered_entity
            {
                push_render_layer(draw_frame, 9);
                draw_texture(draw_frame, entity.position, entity.render_size, sprite_textureless, FADED_GRAY);
            }
            push_render_layer(draw_frame, 10);
        }
    }

    draw_frame.active_view_matrix       = *world_frame.screen_view;
    draw_frame.active_projection_matrix = *world_frame.screen_projection;

    push_render_layer(draw_frame, 1);
    draw_text(draw_frame, game_font, "Testing, some commas and shit", .{400, -100}, asset_manager.small_font_size, WHITE);
    push_render_layer(draw_frame, 0);
}

default_sprite        : *Sprite2D;
sprite_furnace        : *Sprite2D;
sprite_player         : *Sprite2D;
sprite_base_block     : *Sprite2D;
sprite_fire           : *Sprite2D;
sprite_workbench      : *Sprite2D;
sprite_textureless    : *Sprite2D;
sprite_stone_node     : *Sprite2D; 
sprite_coal_node      : *Sprite2D;  
sprite_tree_00        : *Sprite2D;

sprite_stone_chunk    : *Sprite2D;
sprite_coal_chunk     : *Sprite2D;
sprite_wood_chunk     : *Sprite2D;
sprite_outline        : *Sprite2D;

sprite_WFC_input      : *Sprite2D;

game_atlas            : *Texture2D;
game_font             : *Dynamic_Render_Font;

WHITE :: (Vector4).{1, 1, 1, 1};
RED   :: (Vector4).{1, 0, 0, 1};
GREEN :: (Vector4).{0, 1, 0, 1};
BLUE  :: (Vector4).{0, 0, 1, 1};
BLACK :: (Vector4).{0, 0, 0, 1};

ORANGE :: #run hex_to_rgba(0xFFAD00FF);
PURPLE :: #run hex_to_rgba(0xFF00FFFF);
CYAN   :: #run hex_to_rgba(0x03AB9EFF);

LIGHT_GRAY :: (Vector4).{0.8, 0.8, 0.8, 1.0};

// TODO(Sleepster): There is currently a bug with the transparency
//                  setup. Either "radix_sort" is not actually sorting properly, or the
//                  indices into the array are wrong. Either way, it's bugged. Fix it.
FADED_GRAY :: (Vector4).{0.7, 0.7, 0.7, 0.05};

MAX_ENTITIES :: 1000;

TILE_SIZE  :: 8;
MAP_WIDTH  :: 100;
MAP_HEIGHT :: 100;

tick_rate  :: 1.0/60.0;

map_color1: Vector4;
map_color2: Vector4;

new_chunk: WFC_Gen_Chunk;

#load "game_camera.jai";
#load "game_entity.jai";
#load "game_aabb.jai";
#load "game_data.jai";
#load "game_world_gen.jai";

floorplan: Dungeon_Floorplan_Generator; 
