Render_Quad :: struct
{
    union
    {
        elements : [4]Vertex;
        struct
        {
            top_left     : Vertex;
            top_right    : Vertex;
            bottom_left  : Vertex;
            bottom_right : Vertex;
        };
    };
    
    position            : Vector2;
    render_size         : iVector2;
    rotation            : float;
    render_color        : Vector4;
    z_layer             : s32;
    
    is_transparent      : s32;
    required_texture_id : u32;
    
    model_matrix        : Matrix4;
};

add_quad_to_render_layer :: (draw_frame : *Draw_Frame_Data, quad : *Render_Quad)
{
    if quad.render_color.w == 1.0 then draw_frame.render_layer_info[quad.z_layer].layer_opaque_quad_counter += 1;
    else draw_frame.render_layer_info[quad.z_layer].layer_transparent_quad_counter += 1;
}

// NOTE(Sleepster): layers closer to zero render first.
push_render_layer :: inline (draw_frame : *Draw_Frame_Data, layer_index : s32) 
{
    draw_frame.current_active_z_layer = layer_index;
}

add_texture_to_draw_frame_list :: (draw_frame: *Draw_Frame_Data, texture_id: u32)
{
    for texID: draw_frame.bound_texture_ids
    {
        if texture_id == texID then return;
    }
    assert(draw_frame.textures_to_bind + 1 < MAX_TEXTURES_PER_DRAW);
    
    draw_frame.bound_texture_ids[draw_frame.textures_to_bind]  = texture_id;
    draw_frame.textures_to_bind += 1;
}

// NOTE(Sleepster): pass U32_MAX to the texture id if there is no texture
// NOTE(Sleepster): Also, make this defualt color to white, and the render_size to .{8, 8}
create_draw_quad :: (draw_frame          : *Draw_Frame_Data,
                     position            : Vector2,
                     render_size         : iVector2,
                     model_matrix        : Matrix4,
                     required_texture_id : u32,
                     atlas_offset        : iVector2,
                     sprite_size         : iVector2,
                     rotation            : float,
                     render_color        : Vector4) -> Render_Quad
{
    DEBUG_profile_function();
    
    assert(draw_frame.draw_frame_quad_counter + 1 < MAX_QUADS_PER_DRAW);
    top    := position.y;
    bottom := position.y + render_size.y;
    left   := position.x;
    right  := position.x + render_size.x;
    
    quad : Render_Quad;
    quad.top_left.vPosition     = make_vector4(.{left, top}, 0, 1);
    quad.bottom_right.vPosition = make_vector4(.{right, bottom}, 0, 1);
    quad.top_right.vPosition    = make_vector4(.{right, top}, 0, 1);
    quad.bottom_left.vPosition  = make_vector4(.{left, bottom}, 0, 1);
    
    quad.position       = position;
    quad.render_size    = render_size;
    quad.rotation       = rotation;
    quad.render_color   = render_color;
    quad.is_transparent = ifx render_color.w >= 1.0 then cast(s32)0 else cast(s32)1;
    quad.model_matrix   = model_matrix;
    quad.z_layer        = draw_frame.current_active_z_layer;
    if quad.z_layer > MAX_LAYERS
    {
        log("[ERROR]: Layer Index '%' is greater than the layer count of '%'.\n", quad.z_layer, MAX_LAYERS);
    }
    
    if required_texture_id != U32_MAX 
    {
        add_texture_to_draw_frame_list(draw_frame, required_texture_id);
        quad.required_texture_id = required_texture_id;
        
        quad.bottom_left.vUVData   = .{cast(float)atlas_offset.x,                            cast(float)atlas_offset.y + cast(float)sprite_size.y}; 
        quad.bottom_right.vUVData  = .{cast(float)atlas_offset.x + cast(float)sprite_size.x, cast(float)atlas_offset.y + cast(float)sprite_size.y};
        quad.top_right.vUVData     = .{cast(float)atlas_offset.x + cast(float)sprite_size.x, cast(float)atlas_offset.y};
        quad.top_left.vUVData      = .{cast(float)atlas_offset.x,                            cast(float)atlas_offset.y};
        for index : 0..3
        {
            quad.elements[index].vTexIndex = required_texture_id;
        }
    }
    
    for index : 0..3
    {
        quad.elements[index].vColor    = render_color;
    }
    
    return quad;
}

draw_quad_projected :: (draw_frame : *Draw_Frame_Data, quad : *Render_Quad, world_to_clip : Matrix4) -> *Render_Quad
{
    DEBUG_profile_function();
    
    assert(draw_frame.draw_frame_quad_counter + 1 < MAX_QUADS_PER_DRAW);
    
    quad.bottom_left.vPosition  = multiply(world_to_clip, quad.bottom_left.vPosition);
    quad.bottom_right.vPosition = multiply(world_to_clip, quad.bottom_right.vPosition);
    quad.top_right.vPosition    = multiply(world_to_clip, quad.top_right.vPosition);
    quad.top_left.vPosition     = multiply(world_to_clip, quad.top_left.vPosition);
    
    should_cull := (quad.bottom_left.vPosition.x < -1 && quad.top_left.vPosition.x < -1 && quad.bottom_right.vPosition.x < -1 && quad.top_right.vPosition.x < -1||
                    quad.bottom_left.vPosition.x >  1 && quad.top_left.vPosition.x >  1 && quad.bottom_right.vPosition.x > 1 && quad.top_right.vPosition.x > 1  ||
                    quad.bottom_left.vPosition.y < -1 && quad.top_left.vPosition.y < -1 && quad.bottom_right.vPosition.y < -1 && quad.top_right.vPosition.y < -1||
                    quad.bottom_left.vPosition.y >  1 && quad.top_left.vPosition.y >  1 && quad.bottom_right.vPosition.y > 1 && quad.top_right.vPosition.y > 1);
    if should_cull
    {
        null_quad : Render_Quad;
        return *null_quad;
    }
    add_quad_to_render_layer(draw_frame, quad);
    
    // TODO(Sleepster): do we want this? 
    // else add_texture_to_bound_list(draw_frame, quad.required_texture_id);
    
    render_quad := *draw_frame.primary_quad_buffer[draw_frame.draw_frame_quad_counter];
    draw_frame.draw_frame_quad_counter += 1;
    
    <<render_quad = quad;
    return render_quad;
}

// TODO(Sleepster): write my own damn math library because "transpose" pisses me the fuck off.
draw_quad_in_view :: (draw_frame : *Draw_Frame_Data, quad : *Render_Quad) -> *Render_Quad
{
    world_to_clip := multiply(draw_frame.active_view_matrix, draw_frame.active_projection_matrix);
    world_to_clip  = transpose(world_to_clip);
    
    return draw_quad_projected(draw_frame, quad, world_to_clip);
}

draw_quad :: (draw_frame          : *Draw_Frame_Data,
              position            : Vector2,
              render_size         : iVector2,
              required_texture_id : u32,
              atlas_offset        : iVector2,
              sprite_size         : iVector2,
              rotation            : float,
              render_color        : Vector4) -> *Render_Quad
{
    quad := create_draw_quad(draw_frame, position, render_size, null_matrix,
                             required_texture_id, atlas_offset, sprite_size,
                             rotation, render_color);
    return draw_quad_in_view(draw_frame, *quad);
}

draw_rect :: (draw_frame          : *Draw_Frame_Data,
              position            : Vector2,
              render_size         : iVector2,
              rotation            : float,
              render_color        : Vector4) -> *Render_Quad
{
    quad := create_draw_quad(draw_frame, position, render_size, null_matrix,
                             U32_MAX, .{}, .{},
                             rotation, render_color);
    return draw_quad_in_view(draw_frame, *quad);
}

draw_texture :: (draw_frame    : *Draw_Frame_Data,
                 position      :  Vector2,
                 render_size   :  iVector2,
                 sprite        : *Atlas_Sprite,
                 draw_color    :  Vector4) -> *Render_Quad
{
    if sprite == null
    {
        sprite = *null_sprite;
        if sprite.atlas_texture == null return null;
    }
    
    return draw_quad(draw_frame, position,
                     render_size,
                     sprite.atlas_texture.texID,
                     sprite.atlas_position,
                     sprite.atlas_size,
                     0,
                     draw_color);
}

draw_quad_xform :: (draw_frame    : *Draw_Frame_Data,
                    xform         :  Matrix4,
                    sprite        : *Atlas_Sprite,
                    draw_color    :  Vector4 = .{1, 1, 1, 1}) -> *Render_Quad
{
    if sprite == null
    {
        sprite = *null_sprite;
        if sprite.atlas_texture == null return null;
    }
    world_position : Vector4 = xform.v[3];
    render_quad := create_draw_quad(draw_frame,
                                    world_position.xy,
                                    .{1, 1},
                                    xform,
                                    sprite.atlas_texture.texID,
                                    sprite.atlas_position,
                                    sprite.atlas_size,
                                    0,
                                    draw_color);
    return draw_quad_xform_in_view(draw_frame, *render_quad, xform);
}

draw_quad_xform_in_view :: (draw_frame : *Draw_Frame_Data, quad : *Render_Quad, xform : Matrix4) -> *Render_Quad
{
    world_to_clip := Matrix4_Identity;
    world_to_clip  = multiply(world_to_clip, draw_frame.active_projection_matrix);
    world_to_clip  = multiply(world_to_clip, draw_frame.active_view_matrix);
    world_to_clip  = multiply(world_to_clip, xform);
    
    return draw_quad_projected(draw_frame, quad, world_to_clip);
}

prepare_string :: (page : *Font_Page, text: string) -> s32 
{
    result: s32;
    
    temp := text.data;
    while temp < text.data + text.count
    {
        char: string;
        char.data = temp; 
        char.count = 1;
        
        glyph     := get_utf8_glyph(page, temp);
        result    += glyph.glyph_data.atlas_size.x + glyph.advance;
        
        temp       = unicode_next_character(temp);
    }
    
    if page.bitmap_modified
    {
        if page.texture.texID == 0
        {
            glGenTextures(1, *page.texture.texID);
            print("Font Texture Generated\n");
        }
        
        glBindTexture(GL_TEXTURE_2D, page.texture.texID);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 1);
        
        glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, 
                     xx page.bitmap.width, xx page.bitmap.height, 0, 
                     GL_RGBA, GL_UNSIGNED_BYTE, page.bitmap.data.data);
        
        glBindTexture(GL_TEXTURE_2D, 0);
        page.bitmap_modified = false;
    }
    return result;
}

draw_text :: (draw_frame   : *Draw_Frame_Data,
              dynamic_font : *Dynamic_Render_Font,
              text         :  string,
              center_pos   :  Vector2,
              font_scale   :  s32,
              color        :  Vector4)
{
    font_page := asset_get_font_at_size(dynamic_font, font_scale);
    if font_page != null && font_page.is_valid == true
    {
        // TODO(Sleepster): Hey maybe don't draw spaces and such  
        total_width  : s32 = prepare_string(font_page, text);
        starting_pos := (Vector2).{center_pos.x - (total_width * 0.5), center_pos.y};
        render_pos   := starting_pos;
        
        temp := text.data;
        while temp < text.data + text.count
        {
            char: string;
            char.data = temp; 
            char.count = 1;

            glyph     := get_utf8_glyph(font_page, temp);
            if temp == " "
            {
                render_pos.x += glyph.advance;
                continue;
            }
            glyph.glyph_data.atlas_texture = *glyph.page.texture;
            draw_texture(draw_frame,
                         (Vector2).{floor(render_pos.x + glyph.offset_x), floor(render_pos.y + (glyph.ascent - glyph.glyph_data.atlas_size.y))},
                         .{xx glyph.glyph_data.atlas_size.x, xx glyph.glyph_data.atlas_size.y},
                         *glyph.glyph_data, color);
            
            render_pos.x += glyph.advance;
            temp          = unicode_next_character(temp);
        }
    }
    else
    {
        log_error("Failed to get the font page data back from the asset system...\n");
    }
}

set_clear_color :: inline (draw_frame: *Draw_Frame_Data, clear_color: Vector4)
{
    draw_frame.clear_color = clear_color;
}
