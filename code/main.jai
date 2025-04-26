#if OS == .WINDOWS
{
    W :: #import "Windows";
    platform_allocate_memory :: inline (size: u64) -> *void
    {
        data := W.VirtualAlloc(null, xx size, W.MEM_COMMIT|W.MEM_RESERVE, W.PAGE_READWRITE);
        //log("[INFO]: Virtual alloc called with a size of: %mb\n", cast(float32)(size / 1048576.0));
        return data;
    }

    platform_deallocate_memory :: (data: *void, size: u64)
    {
        W.VirtualFree(data, 0, W.MEM_RELEASE);
    }
}
#if OS == .LINUX
{
    P :: #import "POSIX";

    platform_allocate_memory :: inline (size: u64) -> *void
    {
        data := P.mmap(null, size, P.PROT_READ|P.PROT_WRITE, P.MAP_PRIVATE|P.MAP_ANONYMOUS, -1, 0);
        log("[INFO]: mmap called with a size of: %mb\n", cast(float32)(size / 1048576.0));
        return data;
    }

    platform_deallocate_memory :: inline (data: *void, size: u64)
    {
        P.munmap(data, size);
    }
}

#import "Basic";
#import "Math";
#import "String";

#import "SDL";
#import "GL";
#import "Sort";
#import "File";
#import "File_Utilities";
#import "freetype-2.12.1";
#import "Unicode";
#import "Text_File_Handler";
#import "Compiler";
#import "Random";
#import "Bit_Operations";
#import "Machine_X64";

// Bitmap loading and saving:
#import "stb_image";
#import "stb_image_write";
#import "stb_image_resize";


// ENGINE LOADS
#load   "util.jai";
#load   "memory.jai";
#load   "sl_hash_table.jai";
#load   "asset.jai";
#load   "shaders.jai";
#load   "drawing.jai";
#load   "audio.jai";
#load   "opengl_renderer.jai";
#load   "input.jai";
#load   "variables.jai";
#load   "hotloading.jai";
#load   "profiler.jai";

// GAME LOADS
#load   "game_entry.jai";

/*
TODO:
  - [ ] Rewrite the renderer and shaders to support texelFetch.
  - [ ] Rendering options for the renderer
  - [ ] Multithreading API
  - [ ] Revise the asset manager
  - [ ] Add Lighting to the renderer.
  - [ ] Rewrite the drawing API so that it can better support XForms without needing seperate functions
  - [ ] Fix the dynamic font loader so that it actually works as intended and doesn't crash when we run out of atlas space
  - [ ] Hotreloading of the game file??? 
  - [ ] Improve hot reloading of the assets???
  - [ ] Break shaders into hot reloadable systems
  - [ ] Create "win32_engine.jai" and "win32_linux.jai"
  - [ ] Allow textures to be evicted from both memory and the texture atlas. 
        We can do this by adding a bitmap to the atlas and storing in the texture itself the beginning and end 
        pointers into the texture atlas' data buffer.
  - [ ] Change how textures are thrown into the atlas 
  - [ ] Fix the sound mixer to not explode and die when the framerate drops
  - [ ] Fix game_action_* api so that you can do things like so: game_action_is_pressed(game_state.input_manager, .INTERACT
  - [ ] Allow the renderer to support pivots (left, center, right, top left, top right)

BACKBURNER:
  - [ ] Platform indepedant networking API, jai's module isn't too great me thinks. 
  - [ ] Look for other rendering options beyond that of OpenGL (most likely D3D11, but that defeats the point of ever using SDL...)

DONE:
  - [x] Fix the asset loader image path so that images are only loaded when needed (search the hash before loading).
*/

DEBUG :: 0;

SAMPLES_PER_SECOND    :: 48000;

MAX_QUADS_PER_DRAW    :: 20000;
MAX_VERTICES_PER_DRAW :: MAX_QUADS_PER_DRAW * 4;
MAX_INDICES           :: MAX_QUADS_PER_DRAW * 6;
MAX_TEXTURES_PER_DRAW :: 32;

MAX_LAYERS            :: 16;

ENGINE_TEXTURE_WIDTH  :: 2048;
ENGINE_TEXTURE_HEIGHT :: 2048;

MOUSE_BUTTON_COUNT    :: 5;

null_matrix   :: Matrix4.{};
null_texture   : Texture2D           = .{};
null_soundfx   : Loaded_Sound_Data   = .{};
null_font      : Dynamic_Render_Font = .{}; 
null_font_page : Font_Page           = .{};
null_sprite    : Atlas_Sprite        = .{parent_texture = *null_texture, atlas_texture = *null_texture};
null_shader    : Shader_Data         = .{shader_type = xx Shader_Type.UNDEFINED}; 
null_vector2   : Vector2             = .{};

Window_Data :: struct
{
    window      : *SDL_Window;
    gl_context  :  SDL_GLContext;
    window_size :  iVector2;
};

Game_Memory :: struct
{
    game_state      : *Game_State;
    transient_state : *Transient_State;
};

Transient_State :: struct
{
    tran_arena           : Memory_Arena;
    garbage_arena        : Memory_Arena;
    asset_manager        : *Asset_Manager;

    basename_temp_string : string;
    filepath_temp_string : string;
};

Time_Data :: struct
{
    last_time    : u64;
    current_time : u64;
    delta_time   : float32;
    fps          : s32;

    performance_counter_frequency : u64;
};

reset_frame_data :: (transient_state: *Transient_State, draw_frame: *Draw_Frame_Data, window_data: *Window_Data)
{
    using draw_frame;

    textures_to_bind = 0;
    draw_frame_quad_counter = 0;
    current_active_z_layer = 0;
    vertex_buffer_ptr = *draw_frame.primary_vertex_buffer[0];

    for *layer: draw_frame.render_layer_info 
    {
        layer.* = .{};
    }

    for value: bound_texture_ids
    {
        value = 0;
    }

    reset_temporary_storage();
}

main :: ()
{
    result := SDL_Init(SDL_INIT_EVERYTHING);
    if result == 0
    {
        window_data     : Window_Data;
        game_memory     : Game_Memory;
        render_state    : Render_State;
        draw_frame_data : Draw_Frame_Data;
        input_manager   : Input_Manager;
        asset_manager   : Asset_Manager;
        sound_manager   : Sound_Manager;
        time            : Time_Data;

        game_state      : *Game_State;
        transient_state : *Transient_State;

        // TODO(Sleepster): Why is this here? 
        entity_manager  :  Entity_Manager;

        
        window_data.window_size = .{1920, 1080};
        window_data.window = SDL_CreateWindow("Hello, Sailor",
                                              SDL_WINDOWPOS_CENTERED,
                                              SDL_WINDOWPOS_CENTERED,
                                              cast(s32)window_data.window_size.x,
                                              cast(s32)window_data.window_size.y,
                                              SDL_WINDOW_OPENGL|SDL_WINDOW_SHOWN|SDL_WINDOW_RESIZABLE);
        if window_data.window != null
        {
            input_manager.keyboard_input.SDL_keys = SDL_GetKeyboardState(null);
            random_seed(*context.random_state, rdtsc());
            // ARENA INIT
            {
                // POOL INIT
                {
                    game_memory.game_state =
                        cast(*Game_State)bootstrap_allocate_struct(Game_State, offset_of(Game_State, #code game_arena), xx MB(100));

                    game_memory.transient_state =
                        cast(*Transient_State)bootstrap_allocate_struct(Transient_State, offset_of(Transient_State, #code tran_arena)); 
                    
                    game_state      = game_memory.game_state;
                    transient_state = game_memory.transient_state;

                    game_state.is_running = true;
                    game_state.is_initialized = false;
                }
                
                asset_manager.asset_arena      = init_arena(MB(100));
                render_state.render_arena      = init_arena(MB(100));
                sound_manager.sound_arena      = init_arena(MB(100));
                transient_state.garbage_arena  = init_arena(MB(100));

                // RENDERER MEMORY
                {
                    draw_frame_data.primary_vertex_buffer =  push_array(*render_state.render_arena, Vertex, MAX_VERTICES_PER_DRAW);
                    draw_frame_data.primary_quad_buffer   =  push_array(*render_state.render_arena, Render_Quad, MAX_QUADS_PER_DRAW);
                    draw_frame_data.sorting_quad_buffer   =  push_array(*render_state.render_arena, Render_Quad, MAX_QUADS_PER_DRAW);
                    draw_frame_data.vertex_buffer_ptr     = *draw_frame_data.primary_vertex_buffer[0];
                }

                // GAME MEMORY 
                {
                    //game_state.game_arena = init_arena(*game_memory.permanent_storage, xx MB(200));
                }

                game_state.input_manager  = *input_manager;
                game_state.entity_manager = *entity_manager;
            }

            // ASSET INIT
            {
                transient_state.asset_manager = *asset_manager;
                sound_manager.asset_manager   = *asset_manager;
                asset_manager.transient_state =  transient_state;
                init_asset_manager_data(*render_state, *asset_manager);
            }

            // NOTE(Sleepster): Audio init 
            {
                sound_manager.manager_spec.freq     = 48000;
                sound_manager.manager_spec.format   = AUDIO_S16LSB;
                sound_manager.manager_spec.channels = 2;
                sound_manager.manager_spec.samples  = 128;
                for device_index : 0..SDL_GetNumAudioDevices(0) - 1
                {
                    device_name   := SDL_GetAudioDeviceName(device_index, 0);
                    print("DEVICE FOUND... %\n", to_string(device_name));
                    // if(!compare_strings(to_string(device_name), "Speakers (3- I'm Fulla Schiit)"))
                    // {
                    //     sound_manager.default_device = to_string(device_name); 
                    // }
                }

                sound_manager.device_id =
                    SDL_OpenAudioDevice(sound_manager.default_device.data, 0, *sound_manager.manager_spec, *sound_manager.device_spec, SDL_AUDIO_ALLOW_ANY_CHANGE);
                if sound_manager.device_id
                {
                    log("Audio device opened: %\n", to_string(SDL_GetAudioDeviceName(cast(s32)sound_manager.device_id, 0)));
                    sound_manager.audio_stream = SDL_NewAudioStream(sound_manager.manager_spec.format,
                                                                    sound_manager.manager_spec.channels,
                                                                    sound_manager.manager_spec.freq,
                                                                    sound_manager.device_spec.format,
                                                                    sound_manager.device_spec.channels,
                                                                    sound_manager.device_spec.freq);
                    if sound_manager.audio_stream == null
                    {
                        print("Failure\n");
                    }
                    SDL_PauseAudioDevice(sound_manager.device_id, 0);
                }
                else
                {
                    log("Failure to open the SDL audio device: %\nError Code: %\n",
                        to_string(SDL_GetAudioDeviceName(cast(s32)sound_manager.device_id, 0)),
                        SDL_GetError());
                }
                sound_manager.manager_buffer_info.sample_rate             = SAMPLES_PER_SECOND;
                // NOTE(Sleepster): in stereo, it is 4 bytes per sample because each s16 is a part of a sample.
                // The sample would be s16 * channel_count
                sound_manager.manager_buffer_info.bytes_per_sample        = size_of(s16) * sound_manager.manager_spec.channels;
                sound_manager.manager_buffer_info.sample_buffer_size      = cast(u32)((SAMPLES_PER_SECOND) * sound_manager.manager_spec.channels);
                sound_manager.manager_buffer_info.primary_sample_buffer   = cast(*s16)push_array(*sound_manager.sound_arena, s16, sound_manager.manager_buffer_info.sample_buffer_size).data;
                sound_manager.manager_buffer_info.secondary_sample_buffer = cast(*s16)push_array(*sound_manager.sound_arena, s16, sound_manager.manager_buffer_info.sample_buffer_size).data;
                sound_manager.manager_buffer_info.sample_latency          = SAMPLES_PER_SECOND / 5;
            }
            init_opengl(*game_memory, *window_data, *render_state, game_state, *draw_frame_data);

            // TIME INIT
            {
                time.performance_counter_frequency = SDL_GetPerformanceFrequency();
                time.last_time                     = SDL_GetPerformanceCounter();
            }

            // VARIABLE FILE INIT
            {
                init_variable_data("../data/res/engine.variables",
                                   *render_state,
                                   *draw_frame_data,
                                   *sound_manager,
                                   *asset_manager,
                                   *entity_manager);
            }

            accumulator: float32;
            while game_state.is_running
            {
                DEBUG_profile_function();
                
                clear_sound_buffer(*sound_manager.manager_buffer_info);
                // AUDIO BUFFER MANAGEMENT
                {
                    using sound_manager;
                    bytes_to_write: u32;
                    target_cursor : s32 = manager_buffer_info.sample_latency * manager_buffer_info.bytes_per_sample;
                    bytes_queued  : u32 = SDL_GetQueuedAudioSize(sound_manager.device_id);
                    if bytes_queued < xx target_cursor then bytes_to_write = cast(u32)(target_cursor - xx bytes_queued);
                    if bytes_to_write > 0
                    {
                        manager_buffer_info.samples_to_output = (bytes_to_write / cast(u32)manager_buffer_info.bytes_per_sample) / 5;
                    }
                }

                reset_key_states(*input_manager);
                handle_sdl_window_input(*window_data, game_state, *input_manager);

                glViewport(0, 0, xx window_data.window_size.x, xx window_data.window_size.y);
                glClearColor(draw_frame_data.clear_color.x,
                             draw_frame_data.clear_color.y,
                             draw_frame_data.clear_color.z,
                             draw_frame_data.clear_color.w);
                glClearDepth(-1.0);
                glClear(GL_DEPTH_BUFFER_BIT|GL_COLOR_BUFFER_BIT);
                if is_key_pressed(*input_manager, xx SDL_LEFT_MOUSE_BUTTON)
                {
                    //test_sound := play_sound(*sound_manager, "Test2");
                }

                // GAME UPDATE
                game_update_and_render(*game_memory, *window_data, *draw_frame_data, time);
                // GAME UPDATE

                mixer_handle_all_playing_sounds(*sound_manager, time);
                fill_sound_buffer(sound_manager.audio_stream, *sound_manager.manager_buffer_info, sound_manager.device_id);
                test_render(*render_state, *draw_frame_data, *asset_manager);

                SDL_GL_SwapWindow(window_data.window);

                time.current_time = SDL_GetPerformanceCounter();
                time.delta_time   = cast(float32)((time.current_time - time.last_time) * 100 / cast(float32)time.performance_counter_frequency);
                time.last_time    = time.current_time;

                accumulator += time.delta_time * 10;
                if accumulator > 1000
                {
//                    print("DELTA_TIME: %ms\n", time.delta_time * 10);
                    accumulator = 0.0;
                }

                // TEST HOTLOADING
                #if DEBUG == 1
                {
                    // IMPORTANT(Sleepster): WARNING THIS FUNCTION IS SLOW AS BALLS 
                    hotload_assets(*asset_manager);
                    hotload_variable_file_data("../data/res/");
                }
                reset_frame_data(transient_state, *draw_frame_data, *window_data);
            }
            DEBUG_report_timing_info();
            SDL_Delay(10);
        }
    }
    else
    {
        log("SDL Failed to init, error code: %", to_string(SDL_GetError()));
    }
}


build :: ()
{
    #import "Compiler";
    #import "Basic";
    
    set_build_options_dc(.{do_output=false});

    workspace := compiler_create_workspace();

    intercept_flags: Intercept_Flags;
    compiler_begin_intercept(workspace, intercept_flags);

    options := get_build_options(workspace);
    copy_commonly_propagated_fields(get_build_options(), *options);

    options.output_executable_name           = "game_DEBUG";
    options.output_type                      = .EXECUTABLE;
    options.output_path                      = "../build/";
    options.text_output_flags                = .OUTPUT_LINK_LINE;
    options.use_visual_studio_message_format = true;
    options.use_natvis_compatible_types      = true;
    options.dead_code_elimination            = .ALL;

    args := options.compile_time_command_line;
    release := array_find(args, "release");

    if release set_optimization(*options, .VERY_OPTIMIZED, false);
    else set_optimization(*options, .VERY_DEBUG);

    set_build_options(options, workspace);
    compiler_end_intercept(workspace);

    print("Compilation Complete...\n");
}

//#run build();
