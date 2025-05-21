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
#import "Atomics";
#import "Remap_Context";

// Bitmap loading and saving:
#import "stb_image";
#import "stb_image_write";
#import "stb_image_resize";

// ENGINE LOADS
#load   "s_platform_data.jai";
#load   "e_util.jai";
#load   "e_memory.jai";
#load   "e_hash_table.jai";
#load   "e_asset.jai";
#load   "e_audio.jai";
#load   "e_variable_reloading.jai";
#load   "i_drawing.jai";
#load   "i_input.jai";
#load   "r_opengl_renderer.jai";
#load   "r_shaders.jai";
#load   "d_hotloading.jai";
#load   "d_profiler.jai";

HOTLOAD :: 0;

#if DEBUG == 1
{
    Window_Data :: struct
    {
        window      : *SDL_Window;
        gl_context  :  SDL_GLContext;
        window_size :  iVector2;
    };

    #if OS == .WINDOWS
    {
        lib_filepath :: "../build/game_lib.dll";
    }

    #if OS == .LINUX
    {
        lib_filepath :: "../build/game_lib.so";
    }
}

#load   "game_loop.jai";
#add_context garbage_arena: Memory_Arena;

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
null_sprite    : Sprite2D            = .{parent_texture = *null_texture, atlas_texture = *null_texture};
null_shader    : Shader_Data         = .{shader_type = xx Shader_Type.UNDEFINED}; 
null_vector2   : Vector2             = .{};


GAME_NETWORK_PORT :: 30000;

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

Test_Thread_Data :: struct
{
    thread_id     : s32;
    thread_string : string;
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

    reset_arena(*context.garbage_arena);
    reset_temporary_storage();
}

do_next_work_queue_entry :: (queue: *SLP_Work_Queue) -> bool 
{
    should_sleep: bool;
    
    entry_to_read      : u64 = queue.entries_completed;
    next_entry_to_read := (entry_to_read + 1) % (queue.entries.count - 1);

    success, next_work_index := interlocked_compare_exchange(*queue.entries_completed,
                                                              entry_to_read,
                                                              next_entry_to_read);
    if next_work_index == entry_to_read
    {
        entry := *queue.entries[next_work_index];
        if entry.is_valid
        {
            interlocked_increment(*queue.entries_completed);

            entry.is_valid = false;
            entry.callback(entry.user_data);
        }
    }
    else
    {
        should_sleep = true;
    }

    return should_sleep;
}

flush_work_queue_entries :: (queue: *SLP_Work_Queue)
{
    while true
    {
        if !do_next_work_queue_entry(queue)
        {
            return;
        }
    }
}

thread_proc :: (data: *void) -> s32 #c_call
{
    push_context
    {
        assert(data != null);
        queue := cast(*SLP_Work_Queue)data;
        while true
        {
            if !do_next_work_queue_entry(queue)
            {
                queue.threads_awake -= 1;
                slp_thread_wait(queue.semaphore, 0);
            }
        }
        return 0;
    }
}

test_work_callback :: (user_data: *void)
{
    work_data := cast(*Test_Thread_Data)user_data;

    print("[INFO]: %\n", work_data.thread_string);
    print("[INFO] job index is: %\n", work_data.thread_id);
    print("\n");
}

create_server :: ()
{
    socket := slp_socket_create(.IPv4, .DGRAM);
    bound  := slp_socket_bind(*socket, 30000);
    if bound
    {
        buffer_message := "Hello, Client!\n";
        address        := "127.0.0.1";

        bytes_read: s64;
        buffer: string;

        log("[INFO]: Server Started...\n");
        while bytes_read == 0
        {
            buffer, bytes_read = slp_socket_read_from(*socket);
        }

        if bytes_read > 0
        {
            log("[INFO]: data recieved: %\n", buffer);
        }
        else
        {
            log("[ERROR]: Failed to recieve data...\n");
        }
    }
    else
    {
        error := slp_socket_get_last_error();
        log("[ERROR]: Failed to bind the socket...\n");
        log("Error code is: %\n", error);
    }
}

create_client :: ()
{
    socket := slp_socket_create(.IPv4, .DGRAM);

    buffer_message := "Hello, Server!\n";
    address        := "127.0.0.1";

    log("[INFO]: Client Started...\n");
    bytes_sent := slp_socket_send_data(*socket, buffer_message, address, GAME_NETWORK_PORT);
    if bytes_sent == 0
    {
        log("[ERROR]: Failed to send data down the network...\n");
    }
}

#program_export
game_main :: (window_data: *Window_Data, library: *SLP_Dynamic_Library = null) -> bool
{
    Remap_Context();
    
    slp_init_socket_system();

    args := get_command_line_arguments();
    if args.count >= 2
    {
        server_status := args[1];
        if server_status == "-Client" || server_status == "-client"
        {
            create_client();
        }
        else if server_status == "-Server" || server_status == "-server"
        {
            create_server();
        }
        else
        {
            log("[ERROR]: Invalid command line args, please only use: '-client' or '-server'");
        }
    }

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

    input_manager.keyboard_input.SDL_keys = SDL_GetKeyboardState(null);
    random_seed(rdtsc());
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
        
        asset_manager.hash_data_arena = init_arena(MB(100));
        asset_manager.texture_arena   = init_arena(MB(100));
        asset_manager.sprite_arena    = init_arena(MB(100));
        asset_manager.sound_arena     = init_arena(MB(100));
        asset_manager.shader_arena    = init_arena(MB(100));
        asset_manager.font_arena      = init_arena(MB(100));

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

        game_state.input_manager  = *input_manager;
        game_state.entity_manager = *entity_manager;
    }

    // THREADING INIT
    work_queue: SLP_Work_Queue;
    {
        system_thread_count           := (slp_get_cpu_count()) - 1;
        work_queue.semaphore           = slp_create_semaphore(0, xx(system_thread_count));
        work_queue.system_thread_count = xx system_thread_count;
        work_queue.threads_awake       = 0;

        for thread_index: 0..work_queue.entries.count - 2
        {
            string2 := "This is a simple test of our callback job queue";
            
            test_thread_data: *Test_Thread_Data = New(Test_Thread_Data);
            test_thread_data.thread_id     = xx thread_index;
            test_thread_data.thread_string = string2;
            slp_add_work_queue_entry(*work_queue, test_work_callback, test_thread_data);
        }
        
        if system_thread_count != -1
        {
            for 0..system_thread_count - 1
            {
                thread_info := slp_create_thread(*work_queue, thread_proc, 0);
            }
        }
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
        for device_index: 0..SDL_GetNumAudioDevices(0) - 1
        {
            device_name   := SDL_GetAudioDeviceName(device_index, 0);
            print("DEVICE FOUND... %\n", to_string(device_name));
        }

        sound_manager.device_id = SDL_OpenAudioDevice(sound_manager.default_device.data,
                                                      0,
                                                      *sound_manager.manager_spec,
                                                      *sound_manager.device_spec,
                                                      SDL_AUDIO_ALLOW_ANY_CHANGE);
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

    init_opengl(*game_memory, window_data, *render_state, game_state, *draw_frame_data);
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
        handle_sdl_window_input(window_data, game_state, *input_manager);

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
        game_update_and_render(*game_memory, window_data, *draw_frame_data, time);
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
            // print("DELTA_TIME: %ms\n", time.delta_time * 10);
            accumulator = 0.0;
        }

        // TEST HOTLOADING
        #if HOTLOAD == 1
        {
            // IMPORTANT(Sleepster): WARNING THIS FUNCTION IS SLOW AS BALLS 
            hotload_assets(*asset_manager);
            hotload_variable_file_data("../data/res");
        }
        if library != null
        {
            old_last_mod_time := library.last_mod_time;
            old_last_mod_size := library.last_mod_size;
            
            library.last_mod_time, library.last_mod_size = file_modtime_and_size(lib_filepath);
            if library.last_mod_size != old_last_mod_size &&
                library.last_mod_time != old_last_mod_time
            {
                return false;
            }
        }
        reset_frame_data(transient_state, *draw_frame_data, window_data);
    }
    DEBUG_report_timing_info();
    SDL_Delay(10);

    slp_exit_process();
    return true;
}
