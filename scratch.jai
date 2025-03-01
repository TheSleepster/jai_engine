iVector2  :: struct 
{
    x : s32;
    y : s32;
};

Texture2D :: struct
{
    texID    :  u32;
    width    :  s32;
    height   :  s32;
    channels :  s32;

    data      : *u8;
    is_loaded : bool;
    is_packed : bool;
};

Vertex :: struct 
{
    vPosition : Vector4;
    vColor    : Vector4;
    vUVData   : Vector2;
};

Render_State :: struct
{
    primary_VAOID  : u32;
    primary_VBOID  : u32;
    primary_EBOID  : u32;
    default_shader : u32;

    render_arena          : Memory_Arena;
    primary_vertex_buffer : []Vertex;

    test_atlas : Texture2D;
};

Atlas_Sprite :: struct
{
    atlas_position : iVector2;
    atlas_size     : iVector2;

    parent_texture : *Texture2D;
};

Atlas_Packer :: struct
{
    atlas_width  : s32;
    atlas_height : s32;

    skyline       : []s32;
    skyline_count : s32 = 1;
};

place_sprite_in_atlas :: (sprite : *Atlas_Sprite, atlas_position : Vector2)
{
}

find_best_packed_position :: (packer : *Atlas_Packer, sprite : *Atlas_Sprite) -> Vector2
{
    idx_best  := S32_MAX;
    idx_best2 := S32_MAX;

    best_x    := S32_MAX;
    best_y    := S32_MAX;

    skyline_data := cast(*iVector2)packer.skyline.data;
    for index : 0..packer.skyline_count - 1
    {
        x := skyline_data[index].x;
        y := skyline_data[index].y;

        if sprite.atlas_size.x > packer.atlas_width - x then break;
        if y >= best_y then continue;

        max_x := x + sprite.atlas_size.x;

        index2 := index + 1;
        for index2..packer.skyline_count - 1
        {
            index2 = it;
            if max_x <= skyline_data[index2].x then break;
            if y < skyline_data[index2].y then y = skyline_data[index2].y;
        }

        if y >= best_y then continue;

        if sprite.atlas_size.y >= packer.atlas_height - y then continue;
        idx_best  = index;
        idx_best2 = index2;

        best_x = x;
        best_y = y;
    }

    if idx_best == S32_MAX
    {
        log("Failed to find a place in the atlas\n");
        return .{0, 0};
    }
    removed_count := idx_best2 - idx_best;
    
    new_top_left     : Vector2;
    new_bottom_right : Vector2;

    new_top_left.x = cast(float)best_x;
    new_top_left.y = cast(float)best_y + sprite.atlas_size.y;

    new_bottom_right.x = cast(float)best_x + sprite.atlas_size.x;
    new_bottom_right.y = cast(float)skyline_data[idx_best2 - 1].y;

    bottom_right_point : bool = ifx (idx_best2 < packer.skyline_count) then
                                    (new_bottom_right.x < cast(float)skyline_data[idx_best2].x) else
                                    (new_bottom_right.x < cast(float)packer.atlas_width);

    inserted_count : s32 = 1 + cast(s32)bottom_right_point;
    if inserted_count > removed_count
    {
        idx  := packer.skyline_count - 1;
        idx2 := idx + (inserted_count - removed_count);
        for #v2 < idx_best2..idx
        {
            idx  = idx - 1;
            idx2 = idx2 - 1;

            skyline_data[idx2] = skyline_data[idx];
        }
        packer.skyline_count = packer.skyline_count + (inserted_count - removed_count);
    }
    else if inserted_count < removed_count
    {
        idx  := idx_best2;
        idx2 := idx - (removed_count - inserted_count);
        for idx..packer.skyline_count
        {
            idx = idx + 1;
            idx2 = idx2 + 1;

            skyline_data[idx2] = skyline_data[idx];
        }
        packer.skyline_count = packer.skyline_count - (inserted_count - removed_count);
    }

    skyline_data[idx_best] = cast,force(iVector2)new_top_left;
    if bottom_right_point then skyline_data[idx_best + 1] = cast,force(iVector2)new_bottom_right;

    result := cast(Vector2).{cast(float)best_x, cast(float)best_y};
    return result;
}

// NOTE(Sleepster): This should be used with the temporary pool
pack_texture_sprites :: (arena :*Memory_Arena, textures : []Texture2D, atlas_width : s32, atlas_height : s32) -> Texture2D 
{
    // packer init
    atlas_packer : Atlas_Packer;
    atlas_packer.atlas_width  = atlas_width;
    atlas_packer.atlas_height = atlas_height;
    atlas_packer.skyline      = push_array(arena, s32, atlas_width * 2); 

    // texture init
    texture_atlas : Texture2D;
    texture_atlas.width    = atlas_width;
    texture_atlas.height   = atlas_height;
    texture_atlas.channels = 4;
    texture_atlas.data     = push_array(arena, u8, atlas_width * atlas_height).data;

    // insert
    for *texture : textures
    {
        texture_rect : Atlas_Sprite;
        texture_rect.atlas_size     = .{texture.width, texture.height};
        texture_rect.parent_texture = texture;

        best_atlas_position := find_best_packed_position(*atlas_packer, *texture_rect);
        place_sprite_in_atlas(*texture_rect, best_atlas_position);
    }

    return texture_atlas;
}
