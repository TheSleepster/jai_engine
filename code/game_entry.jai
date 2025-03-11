Game_State :: struct
{
    input_manager         : *Input_Manager;
    entity_manager        : *Entity_Manager;
    input_axis            :  Vector2;

    primary_game_camera   :  Game_Camera;

    is_running            :  bool;
    is_initialized        :  bool;
};

World_Frame_Data :: struct
{
    world_projection  : Matrix4;
    world_view        : Matrix4;
    
    screen_projection : Matrix4;
    screen_view       : Matrix4;

    player            : *Entity;
    selected_entity   : *Entity;
};

setup_entity_player :: (player: *Entity)
{
    player.sprite_data  = sprite_player;
    player.archetype    = xx entity_archetype.PLAYER;
    player.speed        = 10.0;
    player.friction     = 0.1;
    player.draw_color   = WHITE;
    player.render_size  = .{8, 8};
    player.bounding_box = range_v2_create(player.position, player.position + player.render_size);
}

setup_entity_build_crate :: (entity: *Entity)
{
    entity.sprite_data  = sprite_base_block;
    entity.archetype    = xx entity_archetype.CRATE;
    entity.draw_color   = WHITE;
    entity.render_size  = .{8, 8};
    entity.flags       |= xx IS_GRABBABLE;
    entity.bounding_box = range_v2_create(entity.position, entity.position + entity.render_size);
}

entity_check_direction :: (entity: *Entity, new_pos: Vector2)
{
    // NOTE(Sleepster): If you look here in the future and
    // go "what idiot made the x's flipped?" it's actually no
    // one's fault. This is just the way it works.

    // TODO(Sleepster): maybe replace atan2 
    direction := atan2(new_pos.y, new_pos.x);
    if direction == 0.0 then direction = -PI;

    half_pi := PI * 0.5;
    if abs(direction) == half_pi 
    {
        ifx direction == half_pi then entity.direction = .{0, 1} else entity.direction = .{0, -1};
    }
    else if abs(direction) == PI
    {
        ifx direction == PI then entity.direction = .{-1, 0} else entity.direction = .{1, 0};
    }
}

check_movement_actions :: (game_state: *Game_State, time: Time_Data)
{
    game_state.input_axis = .{0, 0};
    
    using game_state;
    if game_action_is_down(input_manager, *input_manager.game_actions.data[0])
    {
        game_state.input_axis.y =  1;
    }
    if game_action_is_down(input_manager, *input_manager.game_actions.data[1])
    {
        game_state.input_axis.x = -1;
    }
    if game_action_is_down(input_manager, *input_manager.game_actions.data[2])
    {
        game_state.input_axis.y = -1;
    }
    if game_action_is_down(input_manager, *input_manager.game_actions.data[3])
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

world_to_tile_pos :: inline (world_pos: Vector2) -> iVector2
{
    result: iVector2 = ---;
    result.x = cast(s32)floor(world_pos.x / TILE_SIZE);
    result.y = cast(s32)floor(world_pos.y / TILE_SIZE);

    return result;
}

tile_to_world_pos :: inline (tile_pos: iVector2) -> Vector2
{
    result: Vector2 = ---;
    result.x = cast(float32)tile_pos.x * cast(float32)TILE_SIZE;
    result.y = cast(float32)tile_pos.y * cast(float32)TILE_SIZE;

    return result;
}

round_to_nearest_tile :: inline (pos: Vector2) -> Vector2
{
    result: Vector2 = ---;
    result = tile_to_world_pos(world_to_tile_pos(pos));

    return result;
}

game_update_and_render :: (game_memory: *Game_Memory, window_data: *Window_Data, draw_frame: *Draw_Frame_Data, time: Time_Data)
{
    DEBUG_profile_function();
    
    game_state      :=  cast(*Game_State)game_memory.permanent_storage.block_data;
    transient_state :=  cast(*Transient_State)game_memory.transient_storage.block_data;
    asset_manager   :=  transient_state.asset_manager;
    input_manager   :=  game_state.input_manager;
    entity_manager  :=  game_state.entity_manager;
    game_camera     := *game_state.primary_game_camera;

    if !game_state.is_initialized
    {
        game_font          = asset_get_font(asset_manager, "LiberationMono-Regular");

        default_sprite     = asset_get_sprite(asset_manager, "null_sprite");
        sprite_01          = asset_get_sprite(asset_manager, "sprite01");
        sprite_player      = asset_get_sprite(asset_manager, "player");
        sprite_furnace     = asset_get_sprite(asset_manager, "furnace");
        sprite_base_block  = asset_get_sprite(asset_manager, "block");
        sprite_workbench   = asset_get_sprite(asset_manager, "workbench");
        sprite_textureless = asset_get_sprite(asset_manager, "textureless_sprite");

        map_color1 = hex_to_rgba(0x202e37);
        map_color2 = hex_to_rgba(0x151d28);

        move_up    := game_action_set_action(game_state.input_manager, xx SDL_SCANCODE_W, xx SDL_CONTROLLER_AXIS_LEFTX);
        move_left  := game_action_set_action(game_state.input_manager, xx SDL_SCANCODE_A, xx SDL_CONTROLLER_AXIS_LEFTX);
        move_down  := game_action_set_action(game_state.input_manager, xx SDL_SCANCODE_S, xx SDL_CONTROLLER_AXIS_LEFTX);
        move_right := game_action_set_action(game_state.input_manager, xx SDL_SCANCODE_D, xx SDL_CONTROLLER_AXIS_LEFTX);

        array_add(*input_manager.game_actions, *move_up);
        array_add(*input_manager.game_actions, *move_left);
        array_add(*input_manager.game_actions, *move_down);
        array_add(*input_manager.game_actions, *move_right);

        player := create_entity(entity_manager);
        setup_entity_player(player);
        player.position.x = -30;
        player.speed      =  0.8;

        enemy := create_entity(entity_manager);
        setup_entity_build_crate(enemy);

        for 0..20 - 1
        {
            seed := random_get();
            random_seed(seed);

            crate := create_entity(entity_manager);
            setup_entity_build_crate(crate);
            crate.position = .{random_get_within_range(*context.random_state, -100.0, 100.0), random_get_within_range(*context.random_state, -100.0, 100.0)};
            crate.position = round_to_nearest_tile(crate.position);
        }

        game_state.primary_game_camera = game_camera_create(0.1, 0); 
        game_state.is_initialized = true;
    }

    // NOTE(Sleepster): INIT WORLD FRAME
    world_frame:  World_Frame_Data;
    world_frame.player = get_player(game_state.entity_manager);

    // NOTE(Sleepster): UPDATE PLAYER
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

    // NOTE(Sleepster): CREATE MATRICES
    size_data := (Vector3).{window_data.window_size.x / 240.0, window_data.window_size.y / 120.0, 1.0};
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

    // NOTE(Sleepster): UPDATE ENTITY COLLISION BOUNDING BOXES
    {
        for index: 0..entity_manager.active_entity_counter
        {
            entity := *entity_manager.entities[index];
            if entity.flags & xx IS_VALID
            {
                // I am a bad person.
                entity.bounding_box = range_v2_create(entity.position, entity.position + entity.render_size);
            }
        }
    }

    // NOTE(Sleepster): WORLD FRAME SELECTED ENTITY
    {
        player        := world_frame.player;
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
            world_frame.selected_entity = closest_entity;
        }

        // NOTE(Sleepster): PLAYER GRAB
        if is_key_pressed(game_state.input_manager, xx SDL_SCANCODE_E)
        {
            if !player.attached_entity
            {
                if world_frame.selected_entity && distance(player.position, world_frame.selected_entity.position) < max_grab_dist
                {
                    player.attached_entity = world_frame.selected_entity;
                }
            }
            else
            {
                // NOTE(Sleepster): PLAYER BUILDING
                collision: bool;
                position_to_place := round_to_nearest_tile(player.attached_entity.position + (.{4, 8} * player.direction)); 
                for index: 0..entity_manager.active_entity_counter
                {
                    entity := *entity_manager.entities[index];
                    if (entity.flags & xx IS_VALID)
                    {
                        entity.bounding_box.min -= .{4, 2};
                        entity.bounding_box.max -= .{4, 2};
                        if range_v2_is_within(position_to_place, entity.bounding_box)
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

                    player.attached_entity.position = round_to_nearest_tile(player.attached_entity.position + .{offset_x, offset_y}); 
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


    // NOTE(Sleepster): DEBUG TILES
    push_render_layer(draw_frame, 15);
    tile_offset := world_to_tile_pos(world_frame.player.position);
    tile_radius := (iVector2).{20, 12};

    initial_x := tile_offset.x - tile_radius.x;
    initial_y := tile_offset.y - tile_radius.y;
    for x_index: initial_x .. (tile_offset.x + tile_radius.x) - 1
    {
        for y_index: initial_y .. (tile_offset.y + tile_radius.y) - 1
        {
            tile_x := x_index * cast(float32)TILE_SIZE;
            tile_y := y_index * cast(float32)TILE_SIZE;
            if (x_index + cast(s32)(y_index % 2 == 0)) % 2 == 0
            {
                draw_texture(draw_frame, .{tile_x, (tile_y - TILE_SIZE) - TILE_SIZE}, .{8, 8}, sprite_textureless, map_color1);
            }
            else
            {
                draw_texture(draw_frame, .{tile_x, (tile_y - TILE_SIZE) - TILE_SIZE}, .{8, 8}, sprite_textureless, map_color2);
            }
        }
    }

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
        }
    }

    draw_frame.active_view_matrix       = *world_frame.screen_view;
    draw_frame.active_projection_matrix = *world_frame.screen_projection;

    push_render_layer(draw_frame, 1);
    draw_text(draw_frame, game_font, "This is a test of drawing the correct text", .{400, -100}, asset_manager.small_font_size, WHITE);
    push_render_layer(draw_frame, 0);
}

default_sprite        : *Atlas_Sprite;
sprite_01             : *Atlas_Sprite;
sprite_furnace        : *Atlas_Sprite;
sprite_player         : *Atlas_Sprite;
sprite_base_block     : *Atlas_Sprite;
sprite_fire           : *Atlas_Sprite;
sprite_workbench      : *Atlas_Sprite;
sprite_textureless    : *Atlas_Sprite;

game_font             : *Dynamic_Render_Font;

WHITE :: (Vector4).{1, 1, 1, 1};
RED   :: (Vector4).{1, 0, 0, 1};
GREEN :: (Vector4).{0, 1, 0, 1};
BLUE  :: (Vector4).{0, 0, 1, 1};

MAX_ENTITIES :: 1000;

TILE_SIZE  :: 8;
MAP_WIDTH  :: 100;
MAP_HEIGHT :: 100;

tick_rate  :: 1.0/60.0;

map_color1: Vector4;
map_color2: Vector4;

#load "game_camera.jai";
#load "game_entity.jai";
#load "game_aabb.jai";
