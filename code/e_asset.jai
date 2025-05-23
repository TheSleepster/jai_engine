////////////////
// ASSET STUCT
////////////////

Asset_Slot_State :: enum u8
{
    UNLOADED;
    QUEUED;
    LOADED;
};

Asset_Type_Data :: enum u8
{
    NONE;
    TEXTURE;
    SPRITE;
    SOUNDFX;
    FONT;
};

Asset_Slot :: struct
{
    slot_state       : Asset_Slot_State;
    asset_type       : Asset_Type_Data;

    mod_time         : Apollo_Time;
    mod_size         : s64;
    modified         : bool;
    union
    {
        soundfx      : Loaded_Sound_Data;
        texture_data : Texture2D;
        sprite_data  : Sprite2D;
        shader       : Shader_Data;
        font_data    : Dynamic_Render_Font;
    }
};

// TODO(Sleepster): This "Asset_Data_Path" area is temporary. We will eventually use a custom asset file format.
Asset_Data_Path :: struct
{
    path       : string;
    file_count : s32;
}

Asset_Manager :: struct
{
    transient_state       : *Transient_State;

    hash_data_arena       :  Memory_Arena;
    texture_arena         :  Memory_Arena;
    sprite_arena          :  Memory_Arena;
    sound_arena           :  Memory_Arena;
    shader_arena          :  Memory_Arena;
    font_arena            :  Memory_Arena;

    max_font_size         :  s32;
    small_font_size       :  s32;
    medium_font_size      :  s32;
    large_font_size       :  s32;
    
    engine_texture_width  :  s32;
    engine_texture_height :  s32;

    // NOTE(Sleepster): This is an array of textures that are going to be put into an atlas
    transient_textures    :  [64]Texture2D;
    textures_to_insert    :  s32;

    data_paths            : [3]Asset_Data_Path;

    union
    {
        asset_data: [5]sl_Hash_Table;
        struct
        {
            texture_hash :  sl_Hash_Table;
            sprite_hash  :  sl_Hash_Table;
            sound_hash   :  sl_Hash_Table;
            shader_hash  :  sl_Hash_Table;
            font_hash    :  sl_Hash_Table;
        };
    };

    // TODO(Sleepster): Why is this here? Shouldn't this be in the sound manager??? 
    first_playing_sound      : *Playing_Sound;
    first_free_playing_sound : *Playing_Sound;
};

Visit_File_Data :: struct
{
    asset_manager: *Asset_Manager;
};

init_asset_manager_data :: (render_state: *Render_State, asset_manager: *Asset_Manager)
{
    stbi_set_flip_vertically_on_load(1);

    error := FT_Init_FreeType(*ft_library);
    assert(!error);

    asset_manager.texture_hash = hash_table_create(*asset_manager.hash_data_arena, 512);
    asset_manager.sprite_hash  = hash_table_create(*asset_manager.hash_data_arena, 512);
    asset_manager.sound_hash   = hash_table_create(*asset_manager.hash_data_arena, 512);
    asset_manager.shader_hash  = hash_table_create(*asset_manager.hash_data_arena, 512);
    asset_manager.font_hash    = hash_table_create(*asset_manager.hash_data_arena, 512);

    asset_manager.data_paths[0] = .{"../data/res/textures/", 0};
    asset_manager.data_paths[1] = .{"../data/res/sounds/", 0};
    asset_manager.data_paths[2] = .{"../data/res/fonts", 0};

    if is_directory("../data/res/textures")
    {
        file_data: Visit_File_Data;
        file_data.asset_manager = asset_manager;
        visit_files("../data/res/textures",
                    true,
                    cast(*void)*file_data,
                    init_asset_image_metadata_from_disk,
                    true);
    }
    if is_directory("../data/res/sounds")
    {
        file_data: Visit_File_Data;
        file_data.asset_manager = asset_manager;
        visit_files("../data/res/sounds",
                    true,
                    cast(*void)*file_data,
                    init_asset_sound_metadata_from_disk,
                    true);
    }
    if is_directory("../data/res/fonts")
    {
        file_data: Visit_File_Data;
        file_data.asset_manager = asset_manager;
        visit_files("../data/res/fonts",
                    true,
                    cast(*void)*file_data,
                    init_asset_font_metadata_from_disk,
                    true);
    }
    
    add_shader_to_hash(render_state, asset_manager, BASIC_SHADER_SOURCE_TEXT, "Basic_Shader",      xx Shader_Type.PIXEL);
    add_shader_to_hash(render_state, asset_manager, FONT_SHADER_SOURCE_TEXT,  "Font_Shader",       xx Shader_Type.PIXEL);
    add_shader_to_hash(render_state, asset_manager, NEW_BASIC_SHADER_TEXT,    "New_Basic_Shader",  xx Shader_Type.PIXEL);
}


////////////////
// SPRITES
////////////////

// NOTE(Sleepster): A sprite is essentially a texture-rect section of a bigger texture 
Sprite2D :: struct
{
    atlas_offset  : iVector2;
    atlas_size    : iVector2;

    frame_count   : u32;
    current_frame : u32;

    parent_texture : *Texture2D;
    atlas_texture  : *Texture2D;
};

subsprite :: (sprite: *Sprite2D, offset: Vector2, new_size: Vector2) -> Sprite2D
{
    assert(new_size.x > 0 && new_size.y > 0);
    assert(offset.x < xx sprite.atlas_size.x && offset.y < xx sprite.atlas_size.y);
    
    result: Sprite2D;
    result = sprite.*;

    result.atlas_offset += offset;
    result.atlas_size      = .{xx new_size.x, xx new_size.y};

    return result;
}

asset_get_sprite :: (asset_manager: *Asset_Manager, key: string) -> *Sprite2D
{
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.sprite_hash, key);
    if asset_slot != null
    {
        return *asset_slot.sprite_data;
    }
    else
    {
        load_textures_into_atlas(asset_manager, key);
        return *null_sprite;
    }
}


///////////////
// TEXTURES
///////////////

Texture2D :: struct
{
    texID          :  u32;
    bitmap_data    :  Bitmap;
    
    filepath       :  string;
    hash_name      :  string;

    is_loaded      :  bool;
    is_GPU_texture :  bool;

    original_index_before_sorting : s32;
};

init_asset_image_metadata_from_disk :: (info: *File_Visit_Info, user_data: *void)
{
    transient_state := (cast(*Visit_File_Data)user_data).asset_manager.transient_state;
    asset_manager   := transient_state.asset_manager;

    path, basename, ext := path_decomp(info.full_name);
    if ext == "png" && !info.is_directory
    {
        transient_state.filepath_temp_string = copy_string(info.full_name);
        transient_state.basename_temp_string = copy_string(basename);
        
        asset_data                       := push_struct(*asset_manager.texture_arena, Asset_Slot);
        asset_data.texture_data.filepath  = copy_string(transient_state.filepath_temp_string);
        asset_data.texture_data.hash_name = copy_string(transient_state.basename_temp_string);
        asset_data.asset_type = .TEXTURE;

        hash_insert_pair(*asset_manager.texture_hash, transient_state.basename_temp_string, cast(*void)asset_data);
        print("LOADED...\n");
        print("PATH: %\n", path);
        print("NAME: %\n\n\n", basename);
    }
}

asset_synchronous_load_texture_data :: inline (asset_slot: *Asset_Slot)
{
    if asset_slot.slot_state != .LOADED
    {
        asset_slot.slot_state = .LOADED;
        
        texture     := *asset_slot.texture_data;
        texture.bitmap.data = stbi_load(temp_c_string(texture.filepath),
                                        *texture.bitmap.width,
                                        *texture.bitmap.height,
                                        xx *texture.bitmap.channels,
                                        0);
        texture.bitmap.is_valid = true;
        texture.bitmap.is_dirty = true;
    }
    else
    {
        log("[WARNING]: Not loading asset '%' as it is already designated as loaded...\n", texture.filepath);
    }
}

asset_load_texture_from_path :: (asset_manager: *Asset_Manager, filepath: string, make_GPU_texture := false) -> *Texture2D, bool
{
    result: *Texture2D;
    allocated: bool;

    path, basename, ext := path_decomp(filepath);
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.texture_hash, basename);
    if asset_slot
    {
        manager_texture := *asset_slot.texture_data;
        if !manager_texture.is_loaded
        {
            manager_texture.bitmap_data.data = stbi_load(manager_texture.filepath.data,
                                                         *manager_texture.bitmap_data.width,
                                                         *manager_texture.bitmap_data.height,
                                                         *manager_texture.bitmap_data.channels, 0);
            manager_texture.is_loaded = true;

            allocated = true;
        }

        assert(manager_texture.bitmap_data.data != null);
        result = manager_texture;
    }
    else
    {
        log("[ERROR]: Failed to find filepath: '%' in the asset_hash...\n", filepath);
    }

    return result, allocated;
}

asset_load_texture_data :: (asset_manager: *Asset_Manager, result: *Texture2D,  make_GPU_texture := false) -> bool
{
    allocated: bool;

    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.texture_hash, result.hash_name);
    if asset_slot
    {
        manager_texture := *asset_slot.texture_data;
        if !manager_texture.is_loaded
        {
            manager_texture.bitmap_data.data = stbi_load(manager_texture.filepath.data,
                                                         *manager_texture.bitmap_data.width,
                                                         *manager_texture.bitmap_data.height,
                                                         *manager_texture.bitmap_data.channels, 0);

            result.is_loaded = true;
            allocated = true;
        }

        assert(manager_texture.bitmap_data.data != null);
        result.* = manager_texture.*;
    }
    else
    {
        log("[ERROR]: Failed to find the texture: '%' in the asset_hash...\n", result.hash_name);
    }

    return allocated;
}

push_sprite_into_atlas :: (atlas: *Texture2D, sprite: *Sprite2D)
{
    for x: 0..sprite.atlas_size.x - 1
    {
        for y: 0..sprite.atlas_size.y -1
        {
            atlas_texture_data_offset := ((sprite.atlas_offset.y + y) * atlas.bitmap_data.width +
                                          (sprite.atlas_offset.x + x)) * atlas.bitmap_data.channels;

            sprite_texture_data_offset := (y * sprite.atlas_size.x + x) *
                                           sprite.parent_texture.bitmap_data.channels;
            for channel_index: 0..sprite.parent_texture.bitmap_data.channels - 1
            {
                atlas.bitmap_data.data[atlas_texture_data_offset + channel_index] =
                    sprite.parent_texture.bitmap_data.data[sprite_texture_data_offset + channel_index];
            }
        }
    }
}

move_images_into_atlas :: (asset_manager: *Asset_Manager, atlas_width: s32, atlas_height: s32) -> *Texture2D
{
    atlas_texture : *Texture2D = push_struct(*asset_manager.texture_arena, Texture2D);
    atlas_texture.bitmap_data.width        = atlas_width;
    atlas_texture.bitmap_data.height       = atlas_height;
    atlas_texture.bitmap_data.channels     = 4;
    if atlas_texture.bitmap_data.data == null
    {
        atlas_texture.bitmap_data.data     = push_size(*asset_manager.texture_arena,
                                                       size_of(u8) * ((atlas_width * atlas_height) * 4));
    }

    textures := asset_manager.transient_textures;

    sorted_textures: [64]Texture2D;
    memcpy(sorted_textures.data, textures.data, size_of(Texture2D) * asset_manager.textures_to_insert);
    quick_sort(sorted_textures, (x, y) => compare(x.bitmap_data.height, y.bitmap_data.height));

    x_position : s32 = 0;
    y_position : s32 = 0;
    largest_row_height : s32 = 0;
    for index : 0..asset_manager.textures_to_insert - 1
    {
        texture := *sorted_textures[index];
        if texture.bitmap_data.data != null
        {
            main_texture := *textures[texture.original_index_before_sorting];
            
            sprite_slot  := push_struct(*asset_manager.texture_arena, Asset_Slot);
            sprite_slot.slot_state = Asset_Slot_State.LOADED;
            sprite_slot.asset_type = Asset_Type_Data.SPRITE;

            texture_rect := *sprite_slot.sprite_data;
            texture_rect.atlas_size     = .{texture.bitmap_data.width, texture.bitmap_data.height};
            texture_rect.parent_texture =  main_texture;
            texture_rect.atlas_texture  =  atlas_texture;
            if x_position + texture_rect.atlas_size.x > atlas_width
            {
                y_position += (largest_row_height + 1);
                x_position  = 0;
                largest_row_height = 0;
            }

            if y_position + texture_rect.atlas_size.y > atlas_height
            {
                log("Atlas height has been reached, can no longer fill\n");
                return atlas_texture;
            }
            texture_rect.atlas_offset = .{x_position, y_position};
            x_position += texture_rect.atlas_size.x + 1;
            if texture_rect.atlas_size.y > largest_row_height then largest_row_height = texture_rect.atlas_size.y;

            push_sprite_into_atlas(atlas_texture, texture_rect);
            hash_insert_pair(*asset_manager.sprite_hash, texture.hash_name, sprite_slot);

            stbi_image_free(texture.bitmap_data.data);
            texture_rect.parent_texture.is_loaded            = false;
            texture_rect.parent_texture.bitmap_data.data     = null;
            texture_rect.parent_texture.bitmap_data.is_dirty = false;
            texture_rect.parent_texture.bitmap_data.is_valid = false;
        }
    }

    return atlas_texture;
}

load_texture_data_from_dir :: (info: *File_Visit_Info, data: *void)
{
    file_data := cast(*Visit_File_Data)data;
    transient_state := file_data.asset_manager.transient_state;

    path, basename, ext := path_decomp(info.full_name);
    if ext == "png" && !info.is_directory
    {
        texture_slot := cast(*Asset_Slot)hash_get_value(*transient_state.asset_manager.texture_hash, basename);
        texture_data := texture_slot.texture_data;
        texture_data.filepath  = path;
        texture_data.hash_name = basename;

        texture_slot.slot_state = Asset_Slot_State.LOADED;
        asset_load_texture_data(transient_state.asset_manager, *texture_data);
        
        {
            using transient_state.asset_manager;

            texture_data.original_index_before_sorting = textures_to_insert;
            transient_textures[textures_to_insert] = texture_data;
            textures_to_insert += 1;
        }
    }
}

load_textures_into_atlas :: (asset_manager: *Asset_Manager, key: string)
{
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.texture_hash, key);
    if asset_slot
    {
        if asset_slot.slot_state == Asset_Slot_State.UNLOADED && asset_slot.texture_data.filepath.data != null
        {
            path, name, ext := path_decomp(asset_slot.texture_data.filepath);

            file_data : Visit_File_Data;
            file_data.asset_manager = asset_manager;
            visit_files(path, true, cast(*void)*file_data, load_texture_data_from_dir);

            atlas := move_images_into_atlas(asset_manager, ENGINE_TEXTURE_WIDTH,  ENGINE_TEXTURE_HEIGHT);
            create_texture_from_data(atlas);

            asset_manager.textures_to_insert = 0;
        }
    }
    else
    {
        log("[ERROR]: Unable to find texture key '%'. not rendering...\n", key);
    }
}

asset_get_texture :: (asset_manager: *Asset_Manager, key: string) -> *Texture2D
{
    result: *Texture2D = null;
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.textures, key);
    if asset_slot
    {
        texture := *asset_slot.texture_data;
        if !texture.data
        {
            texture = asset_load_texture_from_path(asset_manager, texture.filepath);
        }
    }
    else
    {
        log("[ERROR]: Unable to find texture key '%'... are you sure this the right name?\n", key);
    }
    
    result = *asset_slot.texture_data;
    return result;
}

asset_release_texture :: (texture: *Texture2D)
{
    stbi_image_free(texture.bitmap_data.data);
    texture.bitmap_data.data      = null;
    texture.bitmap_data.is_valid  = false;
    texture.bitmap_data.is_dirty  = false;
    texture.is_loaded             = false;
}

//////////////
// SOUND
//////////////

Loaded_Sound_Data :: struct
{
    sample_data   : *s16;
    sample_count  :  s32;
    channel_count :  s32;
    filepath      :  string;

    hash_name     :  string;
    ready_to_use  :  bool;
};

Playing_Sound :: struct
{
    sound_tag       : string;
    play_cursor     : float32;
    is_playing      : bool;

    current_volume  : Vector2;
    target_volume   : Vector2;
    volume_delta    : float32;
    pitch           : float32;
    
    next_sound      : *Playing_Sound;
};

init_asset_sound_metadata_from_disk :: (info: *File_Visit_Info, user_data: *void)
{
    transient_state := (cast(*Visit_File_Data)user_data).asset_manager.transient_state;
    asset_manager   := transient_state.asset_manager;

    path, basename, ext := path_decomp(info.full_name);
    if ext == "wav" && !info.is_directory
    {
        transient_state.filepath_temp_string = copy_string(info.full_name);
        transient_state.basename_temp_string = copy_string(basename);

        asset_data := push_struct(*asset_manager.sound_arena, Asset_Slot);
        asset_data.soundfx.filepath  = copy_string(transient_state.filepath_temp_string);
        asset_data.soundfx.hash_name = copy_string(transient_state.basename_temp_string);
        asset_data.asset_type = Asset_Type_Data.SOUNDFX;

        hash_insert_pair(*asset_manager.sound_hash, transient_state.basename_temp_string, cast(*void)asset_data);
        print("LOADED...\n");
        print("PATH: %\n", path);
        print("NAME: %\n\n\n", basename);
    }
}

asset_load_sound_from_disk :: inline (asset_manager: *Asset_Manager, sound_slot: *Asset_Slot, key: string)
{
    sound := *sound_slot.soundfx;
    if sound.filepath.data != null && sound_slot.slot_state == Asset_Slot_State.UNLOADED 
    {
        sound.* = load_wav_file(*asset_manager.sound_arena, sound.filepath);
        sound.hash_name = key;
        sound_slot.slot_state = Asset_Slot_State.LOADED;
    }
}

asset_get_sound :: (asset_manager: *Asset_Manager, key: string) -> *Loaded_Sound_Data
{
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.sound_hash, key);
    if asset_slot != null
    {
        if asset_slot.soundfx.sample_data != null && !asset_slot.modified then return *asset_slot.soundfx;
        else asset_load_sound_from_disk(asset_manager, asset_slot, key);

        return *asset_slot.soundfx;
    }
    else
    {
        log("[ERROR]: Sound Key: % is not a valid entry...\n", key);
        return *null_soundfx;
    }
}

play_sound :: (sound_manager: *Sound_Manager, key: string, left_channel_volume: float32 = 1.0, right_channel_volume: float32 = 1.0) -> *Playing_Sound
{
    if !sound_manager.first_free_playing_sound
    {
        sound_manager.first_free_playing_sound = push_struct(*sound_manager.sound_arena, Playing_Sound);
        sound_manager.first_free_playing_sound.next_sound = null;
    }
    new_sound := sound_manager.first_free_playing_sound;
    sound_manager.first_free_playing_sound = new_sound.next_sound;

    new_sound.sound_tag      = copy_string(key);
    new_sound.is_playing     = true;
    new_sound.current_volume = .{left_channel_volume, right_channel_volume};
    new_sound.target_volume  = new_sound.current_volume;
    new_sound.volume_delta   = 0.0;
    new_sound.pitch          = 1.0;
    new_sound.play_cursor    = 0;

    new_sound.next_sound = sound_manager.first_playing_sound;
    sound_manager.first_playing_sound = new_sound;

    return new_sound;
}

///////////////////
// SHADERS
///////////////////

Shader_Type :: enum
{
    UNDEFINED;
    PIXEL;
    COMPUTE;
};

Shader_Data :: struct
{
    hash_name     : string;

    shader_type   : u8;
    program_id    : u32;
    source_string : string;
};

add_shader_to_hash :: (render_state: *Render_State, asset_manager: *Asset_Manager, shader_source: string, hash_key: string, type: Shader_Type)
{
    // TODO(Sleepster): Investigate why this happens
    asset_slot  := cast(*Asset_Slot)push_struct(*render_state.render_arena, Asset_Slot);
    //asset_slot  := New(Asset_Slot);
    shader_data := *asset_slot.shader;

    shader_data.shader_type   = xx type;
    shader_data.hash_name     = hash_key;
    shader_data.source_string = copy_string(shader_source);

    hash_insert_pair(*asset_manager.shader_hash, hash_key, asset_slot);
}
    
make_shader_object :: (shader: *string, prefix: string, shader_type: GLenum) -> GLuint
{
    LOG_BUFFER_SIZE :: 512;
    shader_object := glCreateShader(shader_type);
    
    shaders: [2] *u8;
    lengths: [2] s32;
    
    shaders[0] = prefix.data;
    shaders[1] = shader.data;
    lengths[0] = xx prefix.count;
    lengths[1] = xx shader.count;
    
    glShaderSource(shader_object, 2, shaders.data, lengths.data);
    glCompileShader(shader_object);
    
    success : GLint;
    glGetShaderiv(shader_object, GL_COMPILE_STATUS, *success);
    
    if !success then
    {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetShaderInfoLog(shader_object, log_data.count, null, log_data.data);
        log("%", to_string(log_data.data), flags=.ERROR);
        return 0;
    }
    
    return shader_object;
}

compile_pixel_shader :: (shader_text: *string) -> GLuint
{
    LOG_BUFFER_SIZE :: 512;
    
    PREFIX_V :: #string END
        #version 430 core
        #define VERTEX_SHADER
    END

    PREFIX_F :: #string END
        #version 430 core
        #define FRAGMENT_SHADER
    END
        
    VertexShader   := make_shader_object(shader_text, PREFIX_V, GL_VERTEX_SHADER);
    FragmentShader := make_shader_object(shader_text, PREFIX_F, GL_FRAGMENT_SHADER);
    Program        := glCreateProgram();
    
    glAttachShader(Program, VertexShader);
    glAttachShader(Program, FragmentShader);
    glLinkProgram(Program);
    
    success: GLint = 0;
    glGetProgramiv(Program, GL_LINK_STATUS, *success);
    
    if !success
    {
        log_data: [LOG_BUFFER_SIZE] u8;
        glGetProgramInfoLog(Program, log_data.count, null, log_data.data);
        log_error("%", to_string(log_data.data));
        return 0;
    }
    
    glDeleteShader(VertexShader);
    glDeleteShader(FragmentShader);
    
    return(Program);
}

compile_shader_source :: (asset_manager: *Asset_Manager, shader_slot: *Asset_Slot)
{
    shader := *shader_slot.shader;
    if shader.shader_type ==
    {
        case xx Shader_Type.PIXEL;
        {
            shader.program_id = compile_pixel_shader(*shader.source_string);
        }
        case xx Shader_Type.COMPUTE;
        {
            log("Might wanna add compute shader support brother...\n");
        }
        case xx Shader_Type.UNDEFINED;
        {
            log("BROTHER HOW DID YOU GET HERE??\n\ncompile_shader_source();");
        }
    }
    shader_slot.slot_state = Asset_Slot_State.LOADED;
}

asset_get_shader :: (asset_manager: *Asset_Manager, key: string) -> *Shader_Data
{
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.shader_hash, key);
    if asset_slot != null
    {
        if asset_slot.slot_state == Asset_Slot_State.UNLOADED
        {
            compile_shader_source(asset_manager, asset_slot);
        }
        return *asset_slot.shader;
    }
    else
    {
        log("[ERROR]: Shader key: %s is not a valid entry...\n", key);
        return(*null_shader);
    }
}

set_shader :: (asset_manager: *Asset_Manager, draw_frame: *Draw_Frame_Data, key: string)
{
    shader := asset_get_shader(asset_manager, key);
    draw_frame.active_shader = shader.program_id;
}

//////////////////
// BITMAPS
//////////////////

Bitmap_Formats :: enum s32
{
    FORMAT_R    :: 1;
    FORMAT_B    :: 1;
    FORMAT_RGB  :: 3;
    FORMAT_BGR  :: 3;
    FORMAT_RGBA :: 4;
    FORMAT_BGRA :: 4;
};

Bitmap :: struct
{
    data     :  *u8;
    format   :   u8;
    channels :   s32;
    
    stride   :   s32;
    is_dirty :   bool;
    is_valid :   bool;

    width    :   s32;
    height   :   s32;
};

init_bitmap_data :: (arena: *Memory_Arena, width: s32, height: s32, format: Bitmap_Formats) -> Bitmap
{
    result: Bitmap;
    result.format = xx format;
    result.width  = width;
    result.height = height;
    result.stride = (1 * result.format);
    result.format = xx format;
    result.data   = push_size(arena, size_of(u8) * cast(u32)(result.width * result.height) * result.format);

    return result;
}

//////////////////
// FONTS
//////////////////

Font_Glyph_Data :: struct
{
    glyph_data : Sprite2D;
    glyph_key  : u32;

    offset_x   : s32;
    offset_y   : s32;
    advance    : s32;
    ascent     : s32;

    owner_page : *Dynamic_Render_Font_Page;
};

Dynamic_Render_Font_Page :: struct
{
    page_full       : bool;
    page_dirty      : bool;

    glyph_lookup    : sl_Hash_Table;
    texture_data    : Texture2D;
    bitmap          : Bitmap;

    bitmap_cursor_x : s32;
    bitmap_cursor_y : s32;

    parent_varient  : *Dynamic_Render_Font_Varient;
    next_page       : *Dynamic_Render_Font_Page;
};

Dynamic_Render_Font_Varient :: struct
{
    pixel_size        : s32;

    character_height  : int;
    line_spacing      : int;
    max_ascender      : int;
    max_descender     : int;
    y_center_offset   : int;
    typical_ascender  : int;
    typical_descender : int;
    em_width          : int;

    default_unknown_character :  u32;
    utf32_unknown_character   := 0xfffd;

    parent_font : *Dynamic_Render_Font;
    first_page  : *Dynamic_Render_Font_Page;
};

Dynamic_Render_Font :: struct
{
    font_face     :  FT_Face;
    font_name     :  string;
    filepath      :  string;
    raw_font_data :  string;

    font_arena    : *Memory_Arena;
    pixel_sizes   :  [..]Dynamic_Render_Font_Varient;
};

init_asset_font_metadata_from_disk :: (info: *File_Visit_Info, user_data: *void)
{
    visit_file_info := cast(*Visit_File_Data)user_data;
    transient_state := visit_file_info.asset_manager.transient_state;
    asset_manager   := transient_state.asset_manager;

    path, basename, ext := path_decomp(info.full_name);
    if ext == "ttf"
    {
        transient_state.filepath_temp_string = copy_string(info.full_name);
        transient_state.basename_temp_string = copy_string(basename);

        font_slot_data := push_struct(*asset_manager.font_arena, Asset_Slot);
        font_slot_data.font_data.filepath  = copy_string(transient_state.filepath_temp_string);
        font_slot_data.font_data.font_name = copy_string(transient_state.basename_temp_string);
        font_slot_data.asset_type = Asset_Type_Data.FONT;

        hash_insert_pair(*asset_manager.font_hash, transient_state.basename_temp_string, cast(*void)font_slot_data);
        print("FONT LOADED: %\n", basename);
        print("FONT PATH  : %\n", transient_state.filepath_temp_string);
        print("\n\n");
    }
    else
    {
        print("File % found, but it is not a ttf file, only ttf files are supported...\n", basename);
    }
}

convert_to_utf32 :: inline (s: *u8) -> u32 {
    utf32 := character_utf8_to_utf32(s, IDIOT_CONSTANT); // god I sure hope we don't need more 
    return utf32;
}

is_char_latin :: (utf32: u32) -> bool {
    if utf32 > 0x24F {  // 0x24F is the end of Latin Extended-B
        if (utf32 >= 0x2000) && (utf32 <= 0x218F) {  // General punctuation, currency symbols, number forms, etc.
        } else {
            return false;
        }
    }

    return true;
}

font_find_next_atlas_line :: inline (page: *Dynamic_Render_Font_Page, width: u32, height: u32) -> iVector2
{
    bitmap := *page.bitmap;
    desired_x := page.bitmap_cursor_x + xx width;
    if desired_x > bitmap.width
    {
        page.bitmap_cursor_x = 0;
        page.bitmap_cursor_y += xx page.parent_varient.max_ascender;
        return .{0, xx page.bitmap_cursor_y};
    }
    else
    {
        return .{xx page.bitmap_cursor_x, xx page.bitmap_cursor_y};
    }
}

copy_glyph_to_page_bitmap :: (page: *Dynamic_Render_Font_Page, glyph: *Font_Glyph_Data)
{
    if page.bitmap.data == null
    {
        page.bitmap = init_bitmap_data(page.parent_varient.parent_font.font_arena,
                                       ENGINE_TEXTURE_WIDTH,
                                       ENGINE_TEXTURE_HEIGHT,
                                      .FORMAT_RGBA);
    }
    assert(page.bitmap.data != null);
    
    face := page.parent_varient.parent_font.font_face;
    b    := face.glyph.bitmap;

    glyph.offset_x                = cast,trunc(s16)face.glyph.bitmap_left;
    glyph.offset_y                = cast,trunc(s16)face.glyph.bitmap_top;
    glyph.advance                 = cast,trunc(s16)(face.glyph.advance.x >> 6);

    metrics := *face.glyph.metrics;
    glyph.ascent = cast,trunc(s16)(metrics.horiBearingY >> 6);

    atlas_dest := font_find_next_atlas_line(glyph.owner_page, b.width, b.rows);

    dest_x: s32 = xx atlas_dest.x;
    dest_y: s32 = xx atlas_dest.y;

    glyph.glyph_data.atlas_size.x = xx b.width;
    glyph.glyph_data.atlas_size.y = xx b.rows;

    glyph.glyph_data.atlas_offset.x = dest_x;
    glyph.glyph_data.atlas_offset.y = dest_y;

    bitmap := *glyph.owner_page.bitmap;

    rows  := cast(s32)b.rows; 
    width := cast(s32)b.width;
    for j : 0..rows-1 {
        for i : 0..width-1 {
            source_pixel := b.buffer[(rows - 1 - j) * b.pitch + i];

            dest_pixel := bitmap.data + ((dest_y + j) * bitmap.width + (dest_x + i)) * 4;
            dest_pixel[0] = source_pixel;
            dest_pixel[1] = source_pixel;
            dest_pixel[2] = source_pixel;
            dest_pixel[3] = source_pixel;
        }
    }
    glyph.owner_page.bitmap_cursor_x += cast(s16) b.width;
}

get_utf8_glyph :: (font_varient: *Dynamic_Render_Font_Varient, char: *u8) -> *Font_Glyph_Data
{
    result     : *Font_Glyph_Data;
    found_page : *Dynamic_Render_Font_Page;

    utf32_char := convert_to_utf32(char);
    if utf32_char
    {
        temp := tprint("%", utf32_char);

        page_ptr := font_varient.first_page;
        while page_ptr != null
        {
            result = cast(*Font_Glyph_Data)hash_get_value(*page_ptr.glyph_lookup, temp);
            if result
            {
                found_page = page_ptr; 
                break;
            }
            page_ptr = page_ptr.next_page;
        }

        if !result && !found_page
        {
            new_page: *Dynamic_Render_Font_Page = font_varient.first_page;
            while new_page
            {
                if !new_page.page_full
                {
                    found_page = new_page;
                    break;
                }
                new_page = new_page.next_page;
            }

            if !found_page
            {
                new_page = font_varient.first_page;
                while new_page
                {
                    if new_page.next_page == null
                    {
                        new_page.next_page                = push_struct(font_varient.parent_font.font_arena, Dynamic_Render_Font_Page);
                        new_page.next_page.glyph_lookup   = hash_table_create(font_varient.parent_font.font_arena, 1024);
                        new_page.next_page.parent_varient = font_varient;
                        new_page.next_page.next_page      = null;

                        found_page = new_page;
                        break;
                        
                    }
                    new_page = new_page.next_page;
                }
            }

            error := FT_Set_Pixel_Sizes(found_page.parent_varient.parent_font.font_face,
                                        0,
                                        xx found_page.parent_varient.character_height);
            assert(!error);

            glyph_index : u32;
            if utf32_char
            {
                glyph_index = FT_Get_Char_Index(found_page.parent_varient.parent_font.font_face, utf32_char);
                if !glyph_index
                {
                    log_error("UTF32 character '%' cannot be found", utf32_char);
                    glyph_index = found_page.parent_varient.default_unknown_character;
                }

                if glyph_index
                {
                    error = FT_Load_Glyph(found_page.parent_varient.parent_font.font_face, glyph_index, FT_LOAD_RENDER);
                    assert(!error);
                }
            }
            else
            {
                assert(glyph_index >= 0);
                error = FT_Load_Glyph(found_page.parent_varient.parent_font.font_face, glyph_index, FT_LOAD_RENDER);
                assert(!error);
            }

            data := push_struct(found_page.parent_varient.parent_font.font_arena, Font_Glyph_Data);
            data.glyph_key  = glyph_index;
            data.owner_page = found_page;

            copy_glyph_to_page_bitmap(found_page, data);
            found_page.page_dirty = true;

            hash_insert_pair(*found_page.glyph_lookup, copy_string(temp), cast(*void)data);
            result = data;
        }
    }
    else
    {
        log("[ERROR]: Character '%s' does not return a valid utf32 character...", char);
    }
    return result;
}

asset_create_font_at_size :: (font: *Dynamic_Render_Font, size: s32) -> *Dynamic_Render_Font_Varient
{
    result: *Dynamic_Render_Font_Varient;
    
    font.raw_font_data = read_entire_file(font.filepath);
    if font.raw_font_data.data != null
    {
        error := FT_New_Memory_Face(ft_library, font.raw_font_data.data, xx font.raw_font_data.count, 0, *font.font_face);
        if !error
        {
            result                         = push_struct(font.font_arena, Dynamic_Render_Font_Varient);
            result.first_page              = push_struct(font.font_arena, Dynamic_Render_Font_Page);
            result.first_page.glyph_lookup = hash_table_create(font.font_arena, 1024);

            result.first_page.next_page = null;
            result.first_page.parent_varient = result;
            result.pixel_size = size;

            success := FT_Set_Pixel_Sizes(font.font_face, 0, xx size);
            assert(!success);

            font_scale_to_pixels := font.font_face.size.metrics.y_scale / (64.0 * 65536.0); 
            result.character_height = size;
            result.line_spacing     = cast(int)floor(font_scale_to_pixels * font.font_face.height + 0.5);
            result.max_ascender     = cast(int)floor(font_scale_to_pixels * font.font_face.bbox.yMax + 0.5);
            result.max_descender    = cast(int)floor(font_scale_to_pixels * font.font_face.bbox.yMin + 0.5);
            result.parent_font      = font;

            glyph_index := FT_Get_Char_Index(font.font_face, #char "m");
            if glyph_index {
                FT_Load_Glyph(font.font_face, glyph_index, FT_LOAD_DEFAULT);
                result.y_center_offset = xx (0.5 * FT_ROUND(font.font_face.glyph.metrics.horiBearingY) + 0.5);
            }

            glyph_index  = FT_Get_Char_Index(font.font_face, #char "M");
            if glyph_index {
                FT_Load_Glyph(font.font_face, glyph_index, FT_LOAD_DEFAULT);
                result.em_width = FT_ROUND(font.font_face.glyph.metrics.width);
            }

            glyph_index  = FT_Get_Char_Index(font.font_face, #char "T");
            if glyph_index {
                FT_Load_Glyph(font.font_face, glyph_index, FT_LOAD_DEFAULT);
                result.typical_ascender = FT_ROUND(font.font_face.glyph.metrics.horiBearingY);
            }

            glyph_index  = FT_Get_Char_Index(font.font_face, #char "g");
            if glyph_index {
                FT_Load_Glyph(font.font_face, glyph_index, FT_LOAD_DEFAULT);
                result.typical_descender = FT_ROUND(font.font_face.glyph.metrics.horiBearingY - font.font_face.glyph.metrics.height);
            }

            error := FT_Select_Charmap(font.font_face, .UNICODE);
            if error
            {
                log_error("Font does not support UNICODE...\n");
            }

            {
                success := set_unknown_character(result, 0xfffd);  // replacement_character
                if !success  success = set_unknown_character(result, 0x2022);  // bullet
                if !success  success = set_unknown_character(result, #char "?");
                if !success {
                    log_error("unable to set unknown character for font '%'.\n", basename);
                }
            }

            array_add(*font.pixel_sizes, result);
        }
        else
        {
            log("[ERROR]: FT_New_Memory_Face() has failed...\n");
        }
    }
    else
    {
        log("[ERROR]: Failed to read the font file, filepath: %\n", font.filepath);
    }

    return result;
}

asset_get_font_at_size :: (font: *Dynamic_Render_Font, size: s32) -> *Dynamic_Render_Font_Varient
{
    result: *Dynamic_Render_Font_Varient;
    for *pixel_size: font.pixel_sizes
    {
        if pixel_size.pixel_size == size
        {
            result = pixel_size;
        }
    }

    if !result
    {
        result = asset_create_font_at_size(font, size);
    }

    return result;
}

asset_get_font :: (asset_manager: *Asset_Manager, name: string) -> *Dynamic_Render_Font
{
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.font_hash, name);
    result: *Dynamic_Render_Font = *null_font;
    if asset_slot != null
    {
        result = *asset_slot.font_data;
        result.font_arena = *asset_manager.font_arena;
    }
    else
    {
        log("[ERROR]: Font name % does not appear to be in the preloaded hash...\n", name);
    }
    return result;
}

#scope_file
ft_library: FT_Library;

set_unknown_character :: (font_varient: *Dynamic_Render_Font_Varient, utf32: u32) -> bool {
    index := FT_Get_Char_Index(font_varient.parent_font.font_face, utf32);
    if !index return false;

    font_varient.default_unknown_character = index;
    return true;
}

FT_ROUND :: inline (x: int) -> int {
    if x >= 0 return (x + 0x1f) >> 6;
    return -(((-x) + 0x1f) >> 6);
}

IDIOT_CONSTANT :: 1000; // this is fucking stupid
