iVector2 :: struct 
{
    x : s32;
    y : s32;
};

Vertex :: struct 
{
    vPosition     :  Vector4;
    vColor        :  Vector4;
    vUVData       :  Vector2;
    vTexIndex     :  u32;
    vRenderFlags  :  u32;
};

Visit_File_Data :: struct
{
    game_state      : *Game_State;
    render_state    : *Render_State;

    transient_state : *Transient_State;
};

Render_Layer_Info :: struct
{
    base_quad_index   : s32;
    ending_quad_index : s32;

    layer_opaque_quad_counter      : s32;
    layer_transparent_quad_counter : s32;
};

Draw_Frame_Data :: struct
{
    primary_vertex_buffer    : []Vertex;
    vertex_buffer_ptr        : *Vertex;
    
    primary_quad_buffer      : []Render_Quad;
    sorting_quad_buffer      : []Render_Quad;

    bound_texture_ids        : [32]u32;
    bound_texture_data       : [32]*Texture2D;

    render_layer_info        : [MAX_LAYERS]Render_Layer_Info;
    active_z_layer_counter   :  s32;
    
    textures_to_bind         :  s32;
    draw_frame_quad_counter  :  s32;

    active_shader            :  u32;

    z_sorting_active         :  bool;
    current_active_z_layer   :  s32;

    active_view_matrix       : *Matrix4;
    active_projection_matrix : *Matrix4;

    clear_color              :  Vector4;
};

// TODO(Sleepster): Make the array count in loaded_textures be that of the file count in the directory 
Render_State :: struct
{
    primary_VAOID : u32;
    primary_VBOID : u32;
    primary_EBOID : u32;

    render_arena  : Memory_Arena;

    vsync         : bool;
};

Filter_Type :: enum
{
    NEAREST;
    LINEAR;
};

update_texture_from_bitmap :: (bitmap: *Bitmap, texture: *Texture2D, has_AA := false, filter_type: Filter_Type = Filter_Type.NEAREST)
{
    glBindTexture(GL_TEXTURE_2D, texture.texID);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    if filter_type ==
    {
        case .NEAREST;
        {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        }
        case .LINEAR;
        {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        }
    }
    if has_AA then glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 1);
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, 
                 xx bitmap.width, xx bitmap.height, 0, 
                 GL_RGBA, GL_UNSIGNED_BYTE, bitmap.data.data);
    
    glBindTexture(GL_TEXTURE_2D, 0);
}

create_texture_from_data :: (texture: *Texture2D) -> bool
{
    if !texture.is_loaded
    {
        glGenTextures(1, *texture.texID);
        glBindTexture(GL_TEXTURE_2D, texture.texID);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        glTexImage2D(GL_TEXTURE_2D, 0, GL_SRGB8_ALPHA8, 
                     cast(u32)texture.width, cast(u32)texture.height, 0, 
                     GL_RGBA, GL_UNSIGNED_BYTE, texture.data);
        glBindTexture(GL_TEXTURE_2D, 0);

        texture.is_GPU_texture = true;
        return true;
    }
    else
    {
        log("The texture is already loaded...\n");
        return true;
    }
    return false;
}

// TODO(Sleepster): Why is this here? 
radix_sort :: (primary_buffer      : *void,
               sorting_buffer      : *void,
               item_count          :  s32,
               item_size           :  s32,
               offset_of_value     :  s32,
               bits_to_search      :  s32)
{
    radix_value      : u64 : 256;
    bits_per_pass    : s32 : 8;
    number_of_passes : s32 = (bits_to_search + bits_per_pass - 1) / bits_per_pass;

    half_range_of_value: s64 = cast(s64)((cast(u64)1) << (bits_to_search - 1));

    counter   : [radix_value]s64;
    digit_sum : [radix_value]s64;

    for pass_index: 0..number_of_passes - 1
    {
        shifted_value: s32 = pass_index * bits_per_pass;
        memset(cast(*void)counter.data, 0, counter.count * size_of(s64));
        for item_index: 0..item_count - 1
        {
            byte: *u8 = (cast(*u8)primary_buffer) + item_index * item_size;
            value_to_sort := <<cast(*u64)(byte + offset_of_value);
            value_to_sort += cast(u64)half_range_of_value;

            digit: u32 = cast(u32)((value_to_sort >> shifted_value) & (radix_value - 1));
            counter[digit] += 1;
        }

        digit_sum[0] = 0;
        for sum_index: 1..radix_value - 1
        {
            digit_sum[sum_index] = digit_sum[sum_index - 1] + counter[sum_index - 1];
        }

        for item_index: 0..item_count - 1
        {
            byte: *u8 = (cast(*u8)primary_buffer) + item_index * item_size;
            
            value_to_sort := <<cast(*u64)(byte + offset_of_value);
            value_to_sort += cast(u64)half_range_of_value;

            digit: u32 = cast(u32)((value_to_sort >> shifted_value) & (radix_value - 1));
            
            memcpy((cast(*u8)sorting_buffer + digit_sum[digit] * item_size), byte, item_size);
            digit_sum[digit] += 1;
        }
        memcpy(primary_buffer, sorting_buffer, item_count * item_size);
    }
}

init_opengl :: (game_memory: *Game_Memory, window_data: *Window_Data,
                render_state: *Render_State, game_state: *Game_State, draw_frame: *Draw_Frame_Data)
{
    // SDL STATE
    {
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, xx SDL_GL_CONTEXT_PROFILE_CORE);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
        SDL_GL_SetAttribute(SDL_GL_FRAMEBUFFER_SRGB_CAPABLE, 1);
        SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
        
        window_data.gl_context = SDL_GL_CreateContext(window_data.window);
        SDL_GL_MakeCurrent(window_data.window, window_data.gl_context);
        gl_load(*gl, SDL_GL_GetProcAddress);
        
        gl_enable_debug_output();
        SDL_GL_SetSwapInterval(0);

        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_GREATER);

        glEnable(GL_FRAMEBUFFER_SRGB);
        
        print("GL Vendor: %\n", to_string(glGetString(GL_VENDOR)));
        print("GL Version: %\n", to_string(glGetString(GL_VERSION)));
    }
    
    // VERTEX DATA
    {
        index_buffer : [MAX_INDICES]u32;
        index        : s32;
        index_offset : u32;
        while index < MAX_INDICES
        {
            index_buffer[index + 0] = index_offset + 0;
            index_buffer[index + 1] = index_offset + 1;
            index_buffer[index + 2] = index_offset + 2;
            index_buffer[index + 3] = index_offset + 2;
            index_buffer[index + 4] = index_offset + 3;
            index_buffer[index + 5] = index_offset + 0;
            index        += 6;
            index_offset += 4;
        }
        
        using render_state;
        
        glGenVertexArrays(1, *primary_VAOID);
        glBindVertexArray(primary_VAOID);
        
        glGenBuffers(1, *primary_VBOID);
        glBindBuffer(GL_ARRAY_BUFFER, primary_VBOID);
        glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * MAX_VERTICES_PER_DRAW, null, GL_STREAM_DRAW);
        
        glGenBuffers(1, *primary_EBOID);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, primary_EBOID);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, size_of(u32) * MAX_INDICES, index_buffer.data, GL_STATIC_DRAW);

        T :: Vertex;
        offset: *T: null;

        glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, size_of(Vertex), xx *offset.vPosition);
        glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, size_of(Vertex), xx *offset.vColor);
        glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, size_of(Vertex), xx *offset.vUVData);

        glVertexAttribIPointer(3, 1, GL_UNSIGNED_INT, size_of(Vertex), xx *offset.vTexIndex);
        
        glEnableVertexAttribArray(0);
        glEnableVertexAttribArray(1);
        glEnableVertexAttribArray(2);
        glEnableVertexAttribArray(3);

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    draw_frame.clear_color = .{0.0, 0.0, 0.0, 1.0};
}

test_render :: (render_state : *Render_State, draw_frame_data : *Draw_Frame_Data, asset_manager : *Asset_Manager)
{
    DEBUG_profile_function();
    
    draw_frame_data.z_sorting_active = true;
    if draw_frame_data.draw_frame_quad_counter > 0
    {
        T :: Render_Quad;
        offset: *T: null;

        if draw_frame_data.z_sorting_active
        {
            radix_sort(cast(*u8)draw_frame_data.primary_quad_buffer.data,
                       cast(*u8)draw_frame_data.sorting_quad_buffer.data,
                       draw_frame_data.draw_frame_quad_counter,
                       size_of(Render_Quad),
                       xx *offset.z_layer,
                       21);
        }

        quad_buffer_layer_offset : s32;
        for layer_index : 0..MAX_LAYERS - 1
        {
            current_layer : *Render_Layer_Info = *draw_frame_data.render_layer_info[layer_index];
            using current_layer;

            base_quad_index = quad_buffer_layer_offset;
            if layer_opaque_quad_counter > 0
            {
                ending_quad_index = base_quad_index + layer_opaque_quad_counter - 1;
                quad_buffer_layer_offset += layer_opaque_quad_counter;
            }

            if layer_transparent_quad_counter > 0
            {
                ending_quad_index = base_quad_index + layer_transparent_quad_counter - 1;
                quad_buffer_layer_offset += layer_transparent_quad_counter;

                radix_sort(draw_frame_data.primary_quad_buffer.data + (base_quad_index + layer_opaque_quad_counter),
                           draw_frame_data.sorting_quad_buffer.data,
                           layer_transparent_quad_counter + layer_opaque_quad_counter,
                           size_of(Render_Quad),
                           xx *offset.is_transparent,
                           21);
            }
            if layer_transparent_quad_counter > 0 || layer_opaque_quad_counter > 0 then draw_frame_data.active_z_layer_counter += 1;
        }
        
        for index : 0..draw_frame_data.draw_frame_quad_counter
        {
            quad := *draw_frame_data.primary_quad_buffer[index];

            bottom_left  : *Vertex = draw_frame_data.vertex_buffer_ptr + 0;
            top_left     : *Vertex = draw_frame_data.vertex_buffer_ptr + 1;
            top_right    : *Vertex = draw_frame_data.vertex_buffer_ptr + 2;
            bottom_right : *Vertex = draw_frame_data.vertex_buffer_ptr + 3;
            draw_frame_data.vertex_buffer_ptr += 4; 

            bottom_left.vPosition  = quad.bottom_left.vPosition;
            top_left.vPosition     = quad.top_left.vPosition;
            top_right.vPosition    = quad.top_right.vPosition;
            bottom_right.vPosition = quad.bottom_right.vPosition;

            bottom_left.vColor  = quad.bottom_left.vColor;
            top_left.vColor     = quad.top_left.vColor;
            top_right.vColor    = quad.top_right.vColor;
            bottom_right.vColor = quad.bottom_right.vColor;

            bottom_left.vUVData  = quad.bottom_left.vUVData;
            top_left.vUVData     = quad.top_left.vUVData;
            top_right.vUVData    = quad.top_right.vUVData;
            bottom_right.vUVData = quad.bottom_right.vUVData;
            
            bottom_left.vTexIndex  = quad.bottom_left.vTexIndex;
            top_left.vTexIndex     = quad.top_left.vTexIndex;
            top_right.vTexIndex    = quad.top_right.vTexIndex;
            bottom_right.vTexIndex = quad.bottom_right.vTexIndex;
        }
    }

    glBindVertexArray(render_state.primary_VAOID);
    glBindBuffer(GL_ARRAY_BUFFER, render_state.primary_VBOID);
    glBufferSubData(GL_ARRAY_BUFFER,
                    0,
                   (draw_frame_data.draw_frame_quad_counter * 4) * size_of(Vertex),
                    draw_frame_data.primary_vertex_buffer.data);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, render_state.primary_EBOID);

    basic_shader := asset_get_shader(asset_manager, "New_Basic_Shader");
    ifx basic_shader.shader_type == xx Shader_Type.PIXEL then glUseProgram(basic_shader.program_id);
    for texture_index: 0..draw_frame_data.textures_to_bind
    {
        texture_id := draw_frame_data.bound_texture_ids[texture_index];
        glActiveTexture(GL_TEXTURE0 + texture_id);
        glBindTexture(GL_TEXTURE_2D, texture_id);
    }

    loc := glGetUniformLocation(basic_shader.program_id, "AtlasArray");
    if loc != -1
    {
        samplerUnits: [32]s32;
        for i: 0..32 - 1
        {
            samplerUnits[i] = xx i;
        }
        glUniform1iv(loc, 32, samplerUnits.data);
    }

    glEnable(GL_BLEND);        
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glBlendEquation(GL_FUNC_ADD);

    // TODO(Sleepster): maybe we can use multidraw? Stuff each one of
    // these ordered calls into a draw_indirect. Enable blending and
    // leave it.
    glDisable(GL_CULL_FACE);
    for *current_render_layer: draw_frame_data.render_layer_info
    {
        using current_render_layer;
        if layer_opaque_quad_counter > 0
        {
            glEnable(GL_DEPTH_TEST);
            glDrawElements(GL_TRIANGLES,
                           cast(u32)layer_opaque_quad_counter * 6,
                           GL_UNSIGNED_INT,
                           cast(*void)((base_quad_index * 6) * size_of(u32)));
        }

        if layer_transparent_quad_counter > 0
        {
            glDisable(GL_DEPTH_TEST);
            glDrawElements(GL_TRIANGLES,
                           cast(u32)layer_transparent_quad_counter * 6,
                           GL_UNSIGNED_INT,
                           cast(*void)(((base_quad_index + layer_opaque_quad_counter) * 6) * size_of(u32)));
        }
    }
}
