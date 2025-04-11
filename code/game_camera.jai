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
