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
    IMAGE;
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
        sprite_data  : Atlas_Sprite;
        shader       : Shader_Data;
        font_data    : Dynamic_Render_Font;
    }
};

Asset_Data_Path :: struct
{
    path       : string;
    file_count : s32;
}

Asset_Manager :: struct
{
    transient_state       : *Transient_State;
    asset_arena           :  Memory_Arena;

    // NOTE(Sleepster): This is an array of textures that are going to be put into an atlas
    transient_textures    :  [64]Texture2D;
    textures_to_insert    :  s32;

    max_font_size         : s32;
    small_font_size       : s32;
    medium_font_size      : s32;
    large_font_size       : s32;
    
    engine_texture_width  : s32;
    engine_texture_height : s32;
    
    data_paths            : [3]Asset_Data_Path;

    textures              :  sl_Hash_Table;
    sprites               :  sl_Hash_Table;
    soundfx               :  sl_Hash_Table;
    shaders               :  sl_Hash_Table;
    fonts                 :  sl_Hash_Table;

    first_playing_sound      : *Playing_Sound;
    first_free_playing_sound : *Playing_Sound;
};

init_asset_manager_data :: (render_state: *Render_State, asset_manager: *Asset_Manager)
{
    error := FT_Init_FreeType(*ft_library);
    assert(!error);

    asset_manager.data_paths[0] = .{"../data/res/textures/", 0};
    asset_manager.data_paths[1] = .{"../data/res/sounds/", 0};
    asset_manager.data_paths[2] = .{"../data/res/fonts", 0};

    if is_directory("../data/res/textures/DEBUG")
    {
        file_data: Visit_File_Data;
        file_data.transient_state = asset_manager.transient_state;
        visit_files("../data/res/textures/DEBUG", true, cast(*void)*file_data, init_asset_image_metadata_from_disk);
    }
    if is_directory("../data/res/sounds")
    {
        file_data: Visit_File_Data;
        file_data.transient_state = asset_manager.transient_state;
        visit_files("../data/res/sounds", true, cast(*void)*file_data, init_asset_sound_metadata_from_disk);
    }
    if is_directory("../data/res/fonts")
    {
        file_data: Visit_File_Data;
        file_data.transient_state = asset_manager.transient_state;
        visit_files("../data/res/fonts", true, cast(*void)*file_data, init_asset_font_metadata_from_disk);
    }
    
    add_shader_to_hash(render_state, asset_manager, BASIC_SHADER_SOURCE_TEXT, "Basic_Shader",      xx Shader_Type.PIXEL);
    add_shader_to_hash(render_state, asset_manager, FONT_SHADER_SOURCE_TEXT,  "Font_Shader",       xx Shader_Type.PIXEL);
    add_shader_to_hash(render_state, asset_manager, NEW_BASIC_SHADER_TEXT,    "New_Basic_Shader",  xx Shader_Type.PIXEL);
}


////////////////
// SPRITES
////////////////
Atlas_Sprite :: struct
{
    atlas_position : iVector2;
    atlas_size     : iVector2;

    parent_texture : *Texture2D;
    atlas_texture  : *Texture2D;
};


///////////////
// TEXTURES
///////////////

Texture2D :: struct
{
    texID     :  u32;
    width     :  s32;
    height    :  s32;
    channels  :  s32;

    data      : *u8;
    filepath  :  string;
    hash_name :  string;

    is_loaded :  bool;

    original_index_before_sorting : s32;
};

init_asset_image_metadata_from_disk :: (info: *File_Visit_Info, user_data: *void)
{
    transient_state := (cast(*Visit_File_Data)user_data).transient_state;
    asset_manager   := transient_state.asset_manager;

    path, basename, ext := path_decomp(info.full_name);
    if ext == "png"
    {
        transient_state.filepath_temp_string = copy_string(info.full_name);
        transient_state.basename_temp_string = copy_string(basename);
        
        asset_data                       := push_element(*asset_manager.asset_arena, Asset_Slot);
        asset_data.texture_data.filepath  = copy_string(transient_state.filepath_temp_string);
        asset_data.texture_data.hash_name = copy_string(transient_state.basename_temp_string);
        asset_data.asset_type = Asset_Type_Data.IMAGE;

        hash_insert_pair(*asset_manager.textures, transient_state.basename_temp_string, cast(*void)asset_data);
        print("LOADED...\n");
        print("PATH: %\n", path);
        print("NAME: %\n\n\n", basename);
    }
}

asset_load_texture_data :: (texture: *Texture2D, load_automatically := false) -> bool
{
    stbi_set_flip_vertically_on_load(1);

    texture.data = stbi_load(texture.filepath.data, *texture.width, *texture.height, *texture.channels, 0);
    if texture.data != null
    {
        loaded: bool;
        if load_automatically then loaded = create_texture_from_data(texture);
        else loaded = true;

        return loaded;
    }
    return false;
}

push_sprite_into_atlas :: (atlas: *Texture2D, sprite: *Atlas_Sprite)
{
    for x: 0..sprite.atlas_size.x - 1
    {
        for y: 0..sprite.atlas_size.y -1
        {
            atlas_texture_data_offset := ((sprite.atlas_position.y + y) * atlas.width +
                                          (sprite.atlas_position.x + x)) * atlas.channels;

            sprite_texture_data_offset := (y * sprite.atlas_size.x + x) *
                                           sprite.parent_texture.channels;
            for channel_index : 0..sprite.parent_texture.channels
            {
                atlas.data[atlas_texture_data_offset + channel_index] =
                    sprite.parent_texture.data[sprite_texture_data_offset + channel_index];
            }
        }
    }
}

move_images_into_atlas :: (asset_manager: *Asset_Manager, atlas_width: s32, atlas_height: s32) -> *Texture2D
{
    atlas_texture : *Texture2D = push_element(*asset_manager.asset_arena, Texture2D);
    atlas_texture.width        = atlas_width;
    atlas_texture.height       = atlas_height;
    atlas_texture.channels     = 4;
    atlas_texture.data         = alloc(size_of(u8) * ((atlas_width * atlas_height) * 4));

    textures := asset_manager.transient_textures;

    log("UNSORTED\n");
    for *texture : textures
    {
        if texture.filepath.data != null
        {
            log("TEXTURE IS: %\n", texture.filepath);
        }
    }
    log("\n\n");

    sorted_textures: [64]Texture2D;
    memcpy(sorted_textures.data, textures.data, size_of(Texture2D) * asset_manager.textures_to_insert);
    quick_sort(sorted_textures, (x, y) => compare_s32(x.height, y.height));

    log("SORTED\n");
    for *texture : sorted_textures
    {
        if texture.filepath.data != null
        {
            log("TEXTURE IS: %\n", texture.filepath);
        }
    }
    log("\n\n");

    x_position : s32 = 0;
    y_position : s32 = 0;
    largest_row_height : s32 = 0;
    for index : 0..asset_manager.textures_to_insert - 1
    {
        texture := *sorted_textures[index];
        if texture.data != null
        {
            main_texture := *textures[texture.original_index_before_sorting];
            
            sprite_slot  := push_element(*asset_manager.asset_arena, Asset_Slot);
            sprite_slot.slot_state = Asset_Slot_State.LOADED;
            sprite_slot.asset_type = Asset_Type_Data.SPRITE;

            texture_rect := *sprite_slot.sprite_data;
            texture_rect.atlas_size     = .{texture.width, texture.height};
            texture_rect.parent_texture =  main_texture;
            texture_rect.atlas_texture  =  atlas_texture;
            if x_position + texture_rect.atlas_size.x > atlas_width
            {
                y_position += largest_row_height;
                x_position  = 0;
                largest_row_height = 0;
            }

            if y_position + texture_rect.atlas_size.y > atlas_height
            {
                log("Atlas height has been reached, can no longer fill\n");
                return atlas_texture;
            }
            texture_rect.atlas_position = .{x_position, y_position};
            x_position += texture_rect.atlas_size.x;
            if texture_rect.atlas_size.y > largest_row_height then largest_row_height = texture_rect.atlas_size.y;

            push_sprite_into_atlas(atlas_texture, texture_rect);
            hash_insert_pair(*asset_manager.sprites, texture.hash_name, sprite_slot);

            stbi_image_free(texture.data);
        }
    }

    return atlas_texture;
}

load_texture_data_from_dir :: (info: *File_Visit_Info, data: *void)
{
    file_data := cast(*Visit_File_Data)data;
    transient_state := file_data.transient_state;

    path, basename, ext := path_decomp(info.full_name);
    if ext == "png"
    {
        texture_slot := cast(*Asset_Slot)hash_get_value(*transient_state.asset_manager.textures, basename);
        texture_data := texture_slot.texture_data;
        texture_data.filepath  = path;
        texture_data.hash_name = basename;

        texture_slot.slot_state = Asset_Slot_State.LOADED;
        asset_load_texture_data(*texture_data);
        
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
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.textures, key);
    if asset_slot.slot_state == Asset_Slot_State.UNLOADED && asset_slot.texture_data.filepath.data != null
    {
        path, name, ext := path_decomp(asset_slot.texture_data.filepath);

        file_data : Visit_File_Data;
        file_data.transient_state = asset_manager.transient_state;
        visit_files(path, true, cast(*void)*file_data, load_texture_data_from_dir);

        atlas := move_images_into_atlas(asset_manager, ENGINE_TEXTURE_WIDTH,  ENGINE_TEXTURE_HEIGHT);
        create_texture_from_data(atlas);

        asset_manager.textures_to_insert = 0;
    }
}

asset_get_sprite :: (asset_manager: *Asset_Manager, key: string) -> *Atlas_Sprite
{
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.sprites, key);
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
    transient_state := (cast(*Visit_File_Data)user_data).transient_state;
    asset_manager   := transient_state.asset_manager;

    path, basename, ext := path_decomp(info.full_name);
    if ext == "wav"
    {
        transient_state.filepath_temp_string = copy_string(info.full_name);
        transient_state.basename_temp_string = copy_string(basename);

        asset_data := push_element(*asset_manager.asset_arena, Asset_Slot);
        asset_data.soundfx.filepath  = copy_string(transient_state.filepath_temp_string);
        asset_data.soundfx.hash_name = copy_string(transient_state.basename_temp_string);
        asset_data.asset_type = Asset_Type_Data.SOUNDFX;

        hash_insert_pair(*asset_manager.soundfx, transient_state.basename_temp_string, cast(*void)asset_data);
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
        <<sound = load_wav_file(*asset_manager.asset_arena, sound.filepath);
        sound.hash_name = key;
        sound_slot.slot_state = Asset_Slot_State.LOADED;
    }
}

asset_get_sound :: (asset_manager: *Asset_Manager, key: string) -> *Loaded_Sound_Data
{
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.soundfx, key);
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
        sound_manager.first_free_playing_sound = push_element(*sound_manager.sound_arena, Playing_Sound);
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

Shader_Type : enum u8
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

add_shader_to_hash :: (render_state: *Render_State, asset_manager: *Asset_Manager, shader_source: string, hash_key: string, type: u8)
{
    // TODO(Sleepster): Investigate why this happens
    asset_slot  := cast(*Asset_Slot)push_element(*render_state.render_arena, Asset_Slot);
    //asset_slot  := New(Asset_Slot);
    shader_data := *asset_slot.shader;

    shader_data.shader_type   = xx type;
    shader_data.hash_name     = hash_key;
    shader_data.source_string = copy_string(shader_source);

    hash_insert_pair(*asset_manager.shaders, hash_key, asset_slot);
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
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.shaders, key);
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
    format :   u8;
    width  :   s32;
    height :   s32;
    stride :   s32;
    data   : []u8;
};

init_bitmap_data :: (arena: *Memory_Arena, width: s32, height: s32, format: Bitmap_Formats) -> Bitmap
{
    result: Bitmap;
    result.format = xx format;
    result.width  = width;
    result.height = height;
    result.stride = (1 * result.format);
    result.data   = push_array(arena, u8, (result.width * result.height) * cast(s32)result.format);
    //result.data   = NewArray(width * height * cast(s32)format, u8);

    return result;
}

//////////////////
// FONTS
//////////////////

Font_Glyph_Data :: struct
{
    glyph_data : Atlas_Sprite;
    glyph_key  : u32;

    offset_x   : s32;
    offset_y   : s32;
    advance    : s32;
    ascent     : s32;

    page       : *Font_Page;
};

// TODO(Sleepster): Come back and fix this, currently if the atlas is full, we simply just keep writing into it... obviously not ideal
// TODO(Sleepster): Sometimes It doesn't load the font correctly on demand like it should. Probably a hash collision
Font_Page :: struct
{
    master_font       : *Dynamic_Render_Font;
    is_valid          : bool;
    
    texture           : Texture2D;
    bitmap            : Bitmap;
    bitmap_modified   : bool;
    
    glyph_lookup      : sl_Hash_Table;

    bitmap_cursor_x   : s32;
    bitmap_cursor_y   : s32;

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
};

Font_Varient :: struct
{
    pixel_size : s32;
    page_data  : [..]Font_Page;
};

// TODO(Sleepster): Implement this 
Dynamic_Render_Font :: struct
{
    font_name        :  string;
    filepath         :  string;
    font_face        :  FT_Face;
    raw_font_data    :  string;

    asset_arena      : *Memory_Arena;

    pixel_sizes      :  [..]Font_Page;
};

init_asset_font_metadata_from_disk :: (info: *File_Visit_Info, user_data: *void)
{
    visit_file_info := cast(*Visit_File_Data)user_data;
    transient_state := visit_file_info.transient_state;
    asset_manager   := transient_state.asset_manager;

    path, basename, ext := path_decomp(info.full_name);
    if ext == "ttf"
    {
        transient_state.filepath_temp_string = copy_string(info.full_name);
        transient_state.basename_temp_string = copy_string(basename);

        font_slot_data := push_element(*asset_manager.asset_arena, Asset_Slot);
        font_slot_data.font_data.filepath  = copy_string(transient_state.filepath_temp_string);
        font_slot_data.font_data.font_name = copy_string(transient_state.basename_temp_string);
        font_slot_data.asset_type = Asset_Type_Data.FONT;

        hash_insert_pair(*asset_manager.fonts, transient_state.basename_temp_string, cast(*void)font_slot_data);
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

font_find_next_atlas_line :: inline (page: *Font_Page, width: u32, height: u32) -> iVector2
{
    bitmap := *page.bitmap;
    desired_x := page.bitmap_cursor_x + xx width;
    if desired_x > bitmap.width
    {
        page.bitmap_cursor_x = 0;
        page.bitmap_cursor_y += xx page.max_ascender;
        return .{0, xx page.bitmap_cursor_y};
    }
    else
    {
        return .{xx page.bitmap_cursor_x, xx page.bitmap_cursor_y};
    }
}

copy_glyph_to_page_bitmap :: (face: FT_Face, glyph: *Font_Glyph_Data) -> FT_Face
{
    if glyph.page.bitmap.data.data == null
    {
        glyph.page.bitmap = init_bitmap_data(glyph.page.master_font.asset_arena, ENGINE_TEXTURE_WIDTH, ENGINE_TEXTURE_HEIGHT, Bitmap_Formats.FORMAT_RGBA);
    }
    
    b := face.glyph.bitmap;

    glyph.offset_x                = cast,trunc(s16)face.glyph.bitmap_left;
    glyph.offset_y                = cast,trunc(s16)face.glyph.bitmap_top;
    glyph.advance                 = cast,trunc(s16)(face.glyph.advance.x >> 6);

    metrics := *face.glyph.metrics;
    glyph.ascent = cast,trunc(s16) (metrics.horiBearingY >> 6);

    atlas_dest := font_find_next_atlas_line(glyph.page, b.width, b.rows);

    dest_x: s32 = xx atlas_dest.x;
    dest_y: s32 = xx atlas_dest.y;

    glyph.glyph_data.atlas_size.x = xx b.width;
    glyph.glyph_data.atlas_size.y = xx b.rows;

    glyph.glyph_data.atlas_position.x = dest_x;
    glyph.glyph_data.atlas_position.y = dest_y;

    bitmap := *glyph.page.bitmap;

    rows  := cast(s32) b.rows; // FreeType has changed the rows and width types to unsigned, and they may be zero
    width := cast(s32) b.width;
    for j : 0..rows-1 {
        for i : 0..width-1 {
            source_pixel := b.buffer[(rows - 1 - j) * b.pitch + i];

            dest_pixel := bitmap.data.data + ((dest_y + j) * bitmap.width + (dest_x + i)) * 4;
            dest_pixel[0] = source_pixel;
            dest_pixel[1] = source_pixel;
            dest_pixel[2] = source_pixel;
            dest_pixel[3] = source_pixel;
        }
    }
    glyph.page.bitmap_cursor_x += cast(s16) b.width;

    if glyph.page.texture.data == null
    {
        using glyph.page;
        texture.data   = bitmap.data.data;
        texture.width  = bitmap.width;
        texture.height = bitmap.height;
    }
    
    return face;
}

get_utf8_glyph :: (font_page: *Font_Page, char: *u8) -> *Font_Glyph_Data
{
    utf32_char := convert_to_utf32(char);
    //find_or_create_glyph(font, utf32, 0, utf32);

    test := tprint("%", utf32_char);
    glyph := cast(*Font_Glyph_Data)hash_get_value(*font_page.glyph_lookup, test);
    if glyph != null
    {
        return glyph;
    }
    else
    {
        error := FT_Set_Pixel_Sizes(font_page.master_font.font_face, 0, xx font_page.character_height);
        //error := FT_Set_Char_Size(font_page.master_font.font_face, xx (font_page.character_height * 64), 0, 360, 0);
        assert(!error);

        glyph_index : u32;
        if utf32_char
        {
            glyph_index = FT_Get_Char_Index(font_page.master_font.font_face, utf32_char);
            if !glyph_index
            {
                log_error("UTF32 character '%' cannot be found", utf32_char);
                glyph_index = font_page.default_unknown_character;
            }

            if glyph_index
            {
                error = FT_Load_Glyph(font_page.master_font.font_face, glyph_index, FT_LOAD_RENDER);
                assert(!error);
            }
        }
        else
        {
            assert(glyph_index >= 0);
            error = FT_Load_Glyph(font_page.master_font.font_face, glyph_index, FT_LOAD_RENDER);
            assert(!error);
        }

        data := push_element(font_page.master_font.asset_arena, Font_Glyph_Data);
        data.glyph_key = glyph_index;
        data.page      = font_page;

        copy_glyph_to_page_bitmap(font_page.master_font.font_face, data);
        font_page.bitmap_modified = true;

        hash_insert_pair(*font_page.glyph_lookup, copy_string(test), cast(*void)data);
        return data;
    }
}

asset_load_font_at_size :: (dynamic_font: *Dynamic_Render_Font, pixel_size: s32) -> *Font_Page
{
    using dynamic_font;

    raw_font_data = read_entire_file(dynamic_font.filepath);
    if raw_font_data.data != null
    {
        error := FT_New_Memory_Face(ft_library, raw_font_data.data, xx raw_font_data.count, 0, *font_face);
        if !error
        {
            result  := cast(*Font_Page)push_size(dynamic_font.asset_arena, size_of(Font_Page));
            //result  := New(Font_Page);
            success := FT_Set_Pixel_Sizes(font_face, 0, xx pixel_size);
            //success := FT_Set_Char_Size(font_face, pixel_size * 64, 0, 360, 0);
            assert(!success);

            font_scale_to_pixels := font_face.size.metrics.y_scale / (64.0 * 65536.0); 
            result.character_height = pixel_size;
            result.line_spacing     = cast(int)floor(font_scale_to_pixels * font_face.height + 0.5);
            result.max_ascender     = cast(int)floor(font_scale_to_pixels * font_face.bbox.yMax + 0.5);
            result.max_descender    = cast(int)floor(font_scale_to_pixels * font_face.bbox.yMin + 0.5);
            result.master_font      = dynamic_font;

            glyph_index := FT_Get_Char_Index(font_face, #char "m");
            if glyph_index {
                FT_Load_Glyph(font_face, glyph_index, FT_LOAD_DEFAULT);
                result.y_center_offset = xx (0.5 * FT_ROUND(font_face.glyph.metrics.horiBearingY) + 0.5);
            }

            glyph_index  = FT_Get_Char_Index(font_face, #char "M");
            if glyph_index {
                FT_Load_Glyph(font_face, glyph_index, FT_LOAD_DEFAULT);
                result.em_width = FT_ROUND(font_face.glyph.metrics.width);
            }

            glyph_index  = FT_Get_Char_Index(font_face, #char "T");
            if glyph_index {
                FT_Load_Glyph(font_face, glyph_index, FT_LOAD_DEFAULT);
                result.typical_ascender = FT_ROUND(font_face.glyph.metrics.horiBearingY);
            }

            glyph_index  = FT_Get_Char_Index(font_face, #char "g");
            if glyph_index {
                FT_Load_Glyph(font_face, glyph_index, FT_LOAD_DEFAULT);
                result.typical_descender = FT_ROUND(font_face.glyph.metrics.horiBearingY - font_face.glyph.metrics.height);
            }

            error := FT_Select_Charmap(font_face, .UNICODE);
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

            result.is_valid = true;
            array_add(*pixel_sizes, result);
            return(result);
        }
        else
        {
            log("[ERROR]: FT_New_Memory_Face() has failed...\n");
        }
    }
    else
    {
        log("[ERROR]: Failed to read the font file, filepath: %\n", dynamic_font.filepath);
    }
    return null;
}

asset_get_font_at_size :: inline (using dynamic_font: *Dynamic_Render_Font, font_scale: s32) -> *Font_Page
{
    result : *Font_Page = null;
    for pixel_sizes
    {
        if it.character_height == font_scale then result = *it;
    }

    if result == null then
    result = asset_load_font_at_size(dynamic_font, font_scale);

    return result;
}

asset_get_font :: (asset_manager: *Asset_Manager, name: string) -> *Dynamic_Render_Font
{
    asset_slot := cast(*Asset_Slot)hash_get_value(*asset_manager.fonts, name);
    result: *Dynamic_Render_Font = *null_font;
    if asset_slot != null
    {
        result = *asset_slot.font_data;
        result.asset_arena = *asset_manager.asset_arena;
    }
    else
    {
        log("[ERROR]: Font name % does not appear to be in the preloaded hash...\n", name);
    }
    return result;
}

#scope_file
ft_library: FT_Library;

set_unknown_character :: (using font_page: *Font_Page, utf32: u32) -> bool {
    index := FT_Get_Char_Index(master_font.font_face, utf32);
    if !index return false;

    default_unknown_character = index;
    return true;
}

FT_ROUND :: inline (x: int) -> int {
    if x >= 0 return (x + 0x1f) >> 6;
    return -(((-x) + 0x1f) >> 6);
}

IDIOT_CONSTANT :: 1000; // this is fucking stupid
