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
};

setup_player_data :: (player: *Player)
{
    player.sprite_data = sprite_player;
    player.speed       = 10.0;
    player.friction    = 0.1;
    player.draw_color  = WHITE;
    player.render_size = .{8, 8};
}

setup_rock_data :: (entity: *Entity)
{
    entity.sprite_data = sprite_base_block;
    entity.draw_color  = WHITE;
    entity.render_size = .{8, 8};
}

Game_Camera :: struct
{
    current_position : Vector2;
    target_position  : Vector2;

    travel_rate      : float32;
    zoom_level       : float32;

    is_active        : bool;
};

game_camera_create :: (rate: float32, zoom: float32, active := true) -> Game_Camera
{
    result: Game_Camera;
    result.travel_rate = rate;
    result.zoom_level  = zoom;
    result.is_active   = active;

    return result;
}

set_screen_matrices :: inline (draw_frame: *Draw_Frame_Data, world_frame_data: *World_Frame_Data)
{
    draw_frame.active_view_matrix = *world_frame_data.screen_view;
    draw_frame.active_view_matrix = *world_frame_data.screen_projection;
}

set_world_matrices :: inline (draw_frame: *Draw_Frame_Data, world_frame_data: *World_Frame_Data)
{
    draw_frame.active_view_matrix = *world_frame_data.world_view;
    draw_frame.active_view_matrix = *world_frame_data.world_projection;
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

game_update_and_render :: (game_memory: *Game_Memory, window_data: *Window_Data, draw_frame: *Draw_Frame_Data, time: Time_Data)
{
    DEBUG_profile_function();
    
    game_state      :=  cast(*Game_State)game_memory.permanent_storage.block_data;
    transient_state :=  cast(*Transient_State)game_memory.transient_storage.block_data;
    asset_manager   :=  transient_state.asset_manager;
    input_manager   :=  game_state.input_manager;
    game_camera     := *game_state.primary_game_camera;

    world_frame     :  World_Frame_Data;

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

        player := create_player(game_state.entity_manager);
        setup_player_data(player);
        player.position.x = -30;
        player.speed      =  10;

        enemy := create_entity(game_state.entity_manager);
        setup_rock_data(enemy);

        game_state.primary_game_camera = game_camera_create(0.3, 0); 
        game_state.is_initialized = true;
    }

    check_movement_actions(game_state, time);
    for player_index: 0..game_state.entity_manager.active_entity_counter
    {
        player := *game_state.entity_manager.entities[player_index];
        if player.flags & xx IS_VALID
        {
            player.position += (game_state.input_axis * player.speed) * tick_rate;
            game_camera.target_position = player.position;
            break;
        }
    }

    push_render_layer(draw_frame, 10);
    size_data := (Vector3).{window_data.window_size.x / 160.0, window_data.window_size.y / 90.0, 1.0};
    v2_approach(*game_camera.current_position, game_camera.target_position, game_camera.travel_rate, tick_rate);

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
    draw_frame.active_view_matrix       = *world_frame.world_view;
    draw_frame.active_projection_matrix = *world_frame.world_projection;
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

#load "game_entity.jai";
