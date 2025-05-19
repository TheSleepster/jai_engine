#import "Basic";
#import "String";
#import "Atomics";
#import "File_Utilities";

#import "SDL";

#if DEBUG == 0
{
    #load   "game_main.jai";
}

#if DEBUG == 1
{
    #import "Math";
    #load   "util.jai";
    #load   "platform_data.jai";

    game_main :: (window_data: *Window_Data, library: *SLP_Dynamic_Library) -> bool #elsewhere;
}

/*
TODO:

RENDERER:
  - [ ] Rewrite the renderer and shaders to support both texelFetch and texture (support both AA and non-AA textures).
  - [ ] Rendering options for the renderer
  - [ ] Add Lighting to the renderer.
  - [ ] Rewrite the drawing API so that it can better support XForms without needing seperate functions
  - [ ] Allow the renderer to support pivots (left, center, right, top left, top right)
  - [ ] Make the renderer follow what the GAME demands, not what the renderer independently decides to do (clear the screen, draw now, etc.)
  - [ ] Make the drawing API ACTUALLY allow rotations. Right now it's like a "pass the rotation but we won't do anything with it lol" thing
  - [ ] (optional) Allow the drawing API to draw simple lines. Idk why this HAS to be here.

ASSET MANAGER:
  - [ ] Revise the asset manager
  - [ ] When we revise the manager, properly fix the font system
  - [ ] Hotreloading of the game file??? 
  - [ ] Improve hot reloading of the assets???
  - [ ] Break shaders into hot reloadable systems?
  - [ ] Asset file format on par with that the .WAD file format used in DOOM
  - [ ] Change how textures are thrown into the atlas 
  - [ ] Allow textures to be evicted from both memory and the texture atlas. 
        We can do this by adding a bitmap to the atlas and storing in the texture itself the beginning and end 
        pointers into the texture atlas' data buffer.

FIXES:
  - [ ] Radix sort might be bugged
  - [ ] Fix the sound mixer to not explode and die when the framerate drops

BACKBURNER:
    // NOTE(Sleepster): mostly looking at Vulkan, not D3D11. However, Vulkan bindings for Jai don't exist it seems
  - [ ] Look for other rendering options beyond that of OpenGL (most likely D3D11, but that defeats the point of ever using SDL...)

DONE:
  - [x] Fix the asset loader image path so that images are only loaded when needed (search the hash before loading).
  - [x] Create "win32_engine.jai" and "linux_engine.jai" for platform dependant systems (memory allocation)
  - [x] Multithreading API
  - [x] Fix game_action_* api so that you can do things like so: game_action_is_pressed(game_state.input_manager, .INTERACT);
  - [x] Platform indepedent networking API, jai's module isn't too great me thinks. 
  - [x] Fix the dynamic font loader so that it actually works as intended and doesn't crash when we run out of atlas space
*/

#if OS == .WINDOWS
{
    lib_filepath      :: "../build/game_lib.dll";
    lib_filepath_copy :: "../build/game_lib_COPY.dll";
}

#if OS == .LINUX
{
    lib_filepath      :: "../build/game_lib.so";
    lib_filepath_copy :: "../build/game_lib_COPY.so";
}

Window_Data :: struct
{
    window      : *SDL_Window;
    gl_context  :  SDL_GLContext;
    window_size :  iVector2;
};

load_game_code :: (filepath: string) -> ((window_data: *Window_Data, library: *SLP_Dynamic_Library) -> bool, SLP_Dynamic_Library)
{
    copy_file(filepath, lib_filepath_copy);
    library := slp_load_dynamic_library(lib_filepath_copy);
    if library.is_valid
    {
        game_main: (window_data: *Window_Data, library: *SLP_Dynamic_Library) -> bool;
        game_main = slp_get_proc_address(*library, "game_main");
        if game_main != null
        {
            return game_main, library;
        }
        else
        {
            log("[ERROR]: Failed to get the 'game_main' function from the game lib...\n");
        }
    }
    return null, library;
}

unload_game_code :: (library: *SLP_Dynamic_Library, proc: (window_data: *Window_Data, library: *SLP_Dynamic_Library) -> bool)
{
    if library.is_valid
    {
        slp_unload_dynamic_library(library);
        proc = null;
    }
}

main :: ()
{
    result := SDL_Init(SDL_INIT_EVERYTHING);
    if result == 0
    {
        window_data: Window_Data;
        window_data.window_size = .{1920, 1080};
        window_data.window = SDL_CreateWindow("Hello, Sailor",
                                              SDL_WINDOWPOS_CENTERED,
                                              SDL_WINDOWPOS_CENTERED,
                                              cast(s32)window_data.window_size.x,
                                              cast(s32)window_data.window_size.y,
                                              SDL_WINDOW_OPENGL|SDL_WINDOW_SHOWN|SDL_WINDOW_RESIZABLE);
        if window_data.window != null
        {
            #if DEBUG == 0
            {
                game_main(*window_data);
            }
            #if DEBUG == 1
            {
                should_close := false;
                while !should_close
                {
                    game_main, library := load_game_code(lib_filepath);
                    should_close = game_main(*window_data, *library);
                    
                    unload_game_code(*library, game_main);
                    SDL_Delay(250);
                }
            }
        }
        else
        {
            log("[ERROR]:  'SDL_InitWindow()' failed... error code: %\n", to_string(SDL_GetError()));
        }
    }
    else
    {
        log("SDL Failed to init, error code: %", to_string(SDL_GetError()));
    }
}
