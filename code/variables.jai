Rendering_Options :: struct
{
    max_quads_per_draw    := 1;
    max_textures_per_draw := 1;
    max_render_layers     := 1;
    vsync                 := true;
};

Sound_Options :: struct
{
    samples_per_second    := 1;
    master_volume         := 0.0;
    soundfx_volume        := 0.0;
};

Asset_Settings :: struct
{
    engine_texture_width  := 1;
    engine_texture_height := 1;

    max_font_size         := 1;
    small_font_size       := 1;
    medium_font_size      := 1;
    large_font_size       := 1;

    default_text          := "blah";
};

Value_Container :: struct
{
    struct_info : *Type_Info_Struct;
    data        : *u8;
};

rendering_options : Rendering_Options;
sound_options     : Sound_Options;
asset_settings    : Asset_Settings;

add_value_container :: (container_pointer: *$T)
{
    container: Value_Container;
    info := type_info(T);
    if info.type != Type_Info_Tag.STRUCT
    {
        log("[ERROR]: Type passed to add_value_container() must be a struct!\n");
        return;
    }

    container.struct_info = cast(*Type_Info_Struct)info;
    container.data        = cast(*u8)container_pointer;

    // i := container.struct_info;
    // print("\n");
    // print("-----------STRUCT NAME: %\n", i.name);
    // for i.members
    // {
    //     print("MEMBER:             %\n", it.name);
    // }
    // print("\n");

    array_add(*containers, container);
}

init_variable_data :: (filepath       :  string,
                       render_state   : *Render_State,
                       draw_frame     : *Draw_Frame_Data,
                       sound_engine   : *Sound_Manager,
                       asset_manager  : *Asset_Manager,
                       entity_manager : *Entity_Manager)
{
    // GET CONTAINERS
    add_value_container(render_state);
    add_value_container(draw_frame);
    add_value_container(sound_engine);
    add_value_container(asset_manager);
    add_value_container(entity_manager);
    
    present: bool;
    for *DEBUG_variable_file_storage
    {
        if it.filepath == filepath
        {
            present = true;
            break;
        }
    }
    if !present
    {
        file_data: DEBUG_Variable_File_Data;
        file_data.filepath = filepath;
        file_data.mod_time, file_data.mod_size = file_modtime_and_size(filepath);

        array_add(*DEBUG_variable_file_storage, *file_data);
    }

    update_variable_data(filepath);
}

update_variable_data :: (filepath: string)
{
    // PARSE
    file_data, success := read_entire_file(filepath);
    defer free(file_data);
    if success
    {
        line_number := 1;
        parsing := true;

        current_container: *Value_Container;
        while parsing
        {
            defer line_number += 1;
            line, got_line := consume_next_line(*file_data);
            if !got_line break;
            if !line continue;

            if line[0] == #char ":"
            {
                if line.count < 2
                {
                    log("[ERROR]: Error in load_variable_file_data on line '%'. Any line starting with ':' must have a '/' and a name afterwards\n", line_number);
                }
                else 
                {
                    if line[1] != #char "/"
                    {
                        log("[ERROR]: Error on line '%', Expecting a '/' after ':'.\n", line_number);
                    }
                    else
                    {
                        advance(*line, 2);
                        storage_designator := line;

                        found: *Value_Container;
                        for *containers
                        {
                            if it.struct_info.name == storage_designator
                            {
                                current_container = it;
                                found             = it;
                                break;
                            }
                        }

                        if !found
                        {
                            log("[ERROR]: Line '%', the container '%' is not defined in the game code...\n", line_number, storage_designator);
                        }
                    }
                }
            }
            else if line[0] == #char "#"
            {
                // COMMENT
                continue;
            }
            else
            {
                value := line;
                while true
                {
                    if !value break;
                    if value[0] == #char " " break;
                    advance(*value, 1);
                }
                if !value
                {
                    log("[ERROR]: Error at line '%' Expected a space after the name of a variable...\n", line_number);
                }
                else
                {
                    name := line;
                    name.count -= value.count;

                    if current_container
                    {
                        // setting the value
                        value_member: *Type_Info_Struct_Member;
                        for current_container.struct_info.members
                        {
                            if it.name == name
                            {
                                value_member = *it;
                                break;
                            }
                        }

                        if value
                        {
                            update_struct_value(current_container, value_member, value, line_number);
                            
                            //log("[SUCCESS]: We found member '%', it is a part of the struct '%'!\n", name, current_container.struct_info.name);
                        }
                        else
                        {
                            log("[ERROR]: Line '%', member '%' is not a member of container '%'...\n", line_number, name, current_container.struct_info.name);
                        }
                    }
                    else
                    {
                        print("[ERROR]: Line '%' There cannot be a value without a container in the .variables file...\n", line_number);
                    }
                }
            }
        }
    }
    else
    {
        log("[ERROR]: Failed to read the file");
    }
}

update_struct_value :: (container: *Value_Container, member: *Type_Info_Struct_Member, value_string: string, line_number: int)
{
    value_type := member.type.type;
    if value_type ==
    {
        case .INTEGER;
        {
            value := string_to_int(value_string);
            info  := cast(*Type_Info_Integer)member.type;
            if info.runtime_size ==
            {
                case 1;
                {
                    pointer   := cast(*s8)(container.data + member.offset_in_bytes);
                    <<pointer  = cast(s8)value;
                }
                case 2;
                {
                    pointer   := cast(*s16)(container.data + member.offset_in_bytes);
                    <<pointer  = cast(s16)value;
                }
                case 4;
                {
                    pointer   := cast(*s32)(container.data + member.offset_in_bytes);
                    <<pointer  = cast(s32)value;
                }
                case 8;
                {
                    pointer   := cast(*s64)(container.data + member.offset_in_bytes);
                    <<pointer  = cast(s64)value;
                }
            }
            log("[SUCCESS]: Value '%' has been updated to %", member.name, value);
        }
        case .FLOAT;
        {
            info  := cast(*Type_Info_Integer)member.type;
            if info.runtime_size ==
            {
                case 4;
                {
                    value := string_to_float(value_string);
                    pointer   := cast(*float32)(container.data + member.offset_in_bytes);
                    <<pointer  = cast(float32)value;
                    log("[SUCCESS]: Value '%' has been updated to %", member.name, value);
                }
                case 8;
                {
                    value := string_to_float64(value_string);
                    pointer   := cast(*float64)(container.data + member.offset_in_bytes);
                    <<pointer  = cast(float64)value;
                    log("[SUCCESS]: Value '%' has been updated to %", member.name, value);
                }
            }
        }
        case .BOOL;
        {
            pointer   := cast(*bool)(container.data + member.offset_in_bytes);
            if value_string[0] == #char "t" || value_string[0] == #char "T"
            {
                <<pointer  = true;
                log("[SUCCESS]: Value '%' has been updated to true", member.name);
            }
            else if value_string[0] == #char "f" || value_string[0] == #char "F"
            {
                <<pointer  = false;
                log("[SUCCESS]: Value '%' has been updated to false", member.name);
            }
        }
        case .STRING;
        {
            y := 0;
            new_value := eat_spaces(value_string);
            if new_value[0] == #char "\""
            {
                advance(*value_string, 1);
                until_quote, found := find_character_from_left(new_value, #char "\"");
                if found
                {
                    pointer := cast(*string)(container.data + member.offset_in_bytes);
                    pointer.count = new_value.count;
                    pointer = *copy_string(new_value);
                    X := 0;

                    log("[SUCCESS]: Value '%' has been set to '%'!\n", member.name, <<pointer);
                }
                else
                {
                    log("[ERROR]: String Values must end with a quote!\n");
                }
            }
            else
            {
                log("[ERROR]: String Values must start with a quote!\n");
            }
        }
    }
}

hotload_variable_file_data :: (path: string)
{
    files := file_list(path, false);
    new_file_count := xx files.count;

    for *DEBUG_variable_file_storage 
    {
         new_mod_time, new_mod_size := file_modtime_and_size(it.filepath);
         if new_mod_time != it.mod_time || new_mod_size != it.mod_size
         {
             it.mod_size = new_mod_size;
             it.mod_time = new_mod_time;
             SDL_Delay(10);
             update_variable_data(it.filepath);
         }

     }
}

#scope_file
DEBUG_Variable_File_Data :: struct
{
    filepath : string;
    mod_time : Apollo_Time;
    mod_size : s64;
}

containers                  : [..]Value_Container;
DEBUG_variable_file_storage : [..]DEBUG_Variable_File_Data;

