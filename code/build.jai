#import "Compiler";
#import "Basic";

build_debug :: (exe_workspace: Workspace)
{
    // NOTE(Sleepster): BUILD EXE
    {
        set_build_options_dc(.{do_output=false});

        options := get_build_options(exe_workspace);
        copy_commonly_propagated_fields(get_build_options(), *options);

        options.output_executable_name           = "game_DEBUG";
        options.output_type                      = .EXECUTABLE;
        options.output_path                      = "../build/";
        options.use_visual_studio_message_format = true;
        options.use_natvis_compatible_types      = true;
        options.dead_code_elimination            = .ALL;

        set_optimization(*options, .VERY_DEBUG);
        set_build_options(options, exe_workspace);

        compiler_begin_intercept(exe_workspace);
        add_build_file("main.jai", exe_workspace);
        add_build_string("DEBUG :: 1;", exe_workspace);
        compiler_end_intercept(exe_workspace);
    }

    // NOTE(Sleepster): BUILD DLL 
    {
        set_build_options_dc(.{do_output=false});

        workspace := compiler_create_workspace("DLL");
        options   := get_build_options(workspace);
        copy_commonly_propagated_fields(get_build_options(), *options);

        options.output_executable_name           = "game_lib";
        options.output_type                      = .DYNAMIC_LIBRARY;
        options.output_path                      = "../build/";
        options.use_visual_studio_message_format = true;
        options.use_natvis_compatible_types      = true;
        options.dead_code_elimination            = .ALL;
        options.enable_bytecode_inliner          = false;


        set_optimization(*options, .VERY_DEBUG);
        set_build_options(options, workspace);

        compiler_begin_intercept(workspace);
        add_build_file("game_main.jai", workspace);
        add_build_string("DEBUG :: 1;", workspace);
        compiler_end_intercept(workspace);
    }
}

build_release :: (workspace: Workspace)
{
    options := get_build_options(workspace);
    copy_commonly_propagated_fields(get_build_options(), *options);

    options.output_executable_name           = "game_DEBUG";
    options.output_type                      = .EXECUTABLE;
    options.output_path                      = "../build/";
    options.use_visual_studio_message_format = true;
    options.use_natvis_compatible_types      = true;
    options.dead_code_elimination            = .ALL;

    set_optimization(*options, .VERY_OPTIMIZED, false);
    set_build_options(options, workspace);

    compiler_begin_intercept(workspace);
    add_build_file("main.jai", workspace);
    add_build_string("DEBUG :: 0;", workspace);
    compiler_end_intercept(workspace);

    set_build_options_dc(.{do_output=false});
}

build :: ()
{
    workspace := compiler_create_workspace("EXE");
    options   := get_build_options(workspace);

    args      := options.compile_time_command_line;
    release   := array_find(args, "-release");
    if release
    {
        build_release(workspace);
    }
    else
    {
        build_debug(workspace);
    }
}

#run build();
