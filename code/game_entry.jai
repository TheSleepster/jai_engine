Game_State :: struct
{
    input_manager         : *Input_Manager;
    //entity_manager        :  Entity_Manager;

    world_camera_position :  Vector2;
    input_axis            :  Vector2;

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
}

game_update_and_render :: (game_memory: *Game_Memory, window_data: *Window_Data, draw_frame: *Draw_Frame_Data, time: Time_Data)
{
    DEBUG_profile_function();
    
    game_state      := cast(*Game_State)game_memory.permanent_storage.block_data;
    transient_state := cast(*Transient_State)game_memory.transient_storage.block_data;
    asset_manager   := transient_state.asset_manager;
    input_manager   := game_state.input_manager;

    world_frame     :  World_Frame_Data;

    if !game_state.is_initialized
    {
        game_font      = asset_get_font(asset_manager, "LiberationMono-Regular");

        default_sprite        = asset_get_sprite(asset_manager, "null_sprite");
        sprite_01             = asset_get_sprite(asset_manager, "sprite01");
        sprite_player         = asset_get_sprite(asset_manager, "player");
        sprite_furnace        = asset_get_sprite(asset_manager, "furnace");
        sprite_base_block     = asset_get_sprite(asset_manager, "block");
        sprite_workbench      = asset_get_sprite(asset_manager, "workbench");
        sprite_textureless    = asset_get_sprite(asset_manager, "textureless_sprite");

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

        game_state.is_initialized = true;
    }

    // left_stick_value, right_stick_value := read_controller_axis(input_manager, xx SDL_CONTROLLER_AXIS_LEFTX);
    // print("====== STICK VALUES ======\n");
    // print("STICK X: %\n", left_stick_value);
    // print("STICK Y: %\n", right_stick_value);

    size_data := (Vector3).{window_data.window_size.x / 160.0, window_data.window_size.y / 90.0, 1};

    world_frame.world_view       = Matrix4_Identity;
    world_frame.world_view       = translate(world_frame.world_view, (Vector3).{-game_state.world_camera_position.x,
                                                                                -game_state.world_camera_position.y, 0});

    world_frame.world_view       = mat4_scale(world_frame.world_view, size_data);
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

    check_movement_actions(game_state, time);

    draw_frame.active_view_matrix       = *world_frame.screen_view;
    draw_frame.active_projection_matrix = *world_frame.screen_projection;

    draw_text(draw_frame, game_font, "This is a test of drawing the correct text", .{400, -100}, 16, WHITE);
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

TILE_SIZE :: 8;

MAP_WIDTH  :: 100;
MAP_HEIGHT :: 100;

map_color1: Vector4;
map_color2: Vector4;

//#load "game_ecs.jai";
