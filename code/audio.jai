Square_Wave :: struct
{
    tone_frequency       : s32;
    amplitude            : float;
    sample_rate          : s32;
    running_sample_index : s32;
};

Audio_Buffer_Data :: struct
{
    sample_rate             :  s32;
    bytes_per_sample        :  s32;
    running_sample_index    :  u32;
    sample_latency          :  s32;
    samples_to_output       :  u32;

    primary_sample_buffer   : *s16;
    secondary_sample_buffer : *s16;
    sample_buffer_size      :  u32;

    play_cursor             :  s32;
    write_cursor            :  s32;
};

Sound_Manager :: struct
{
    master_volume            : float32;
    soundfx_volume           : float32;

    asset_manager            : *Asset_Manager;
    sound_arena              :  Memory_Arena;
    
    default_device           :  string;
    device_id                :  u32;
    manager_spec             :  SDL_AudioSpec;
    device_spec              :  SDL_AudioSpec;
    manager_buffer_info      :  Audio_Buffer_Data;

    audio_stream             : *SDL_AudioStream;

    first_playing_sound      : *Playing_Sound;
    first_free_playing_sound : *Playing_Sound;
};

Wave_Header :: struct
{
    RIFF_ID : u32;
    size    : u32;
    WAVE_ID : u32;
}#no_padding;

Wave_Chunk :: struct
{
    ID         : u32;
    chunk_size : s32;
}#no_padding;

Wave_FMT :: struct
{
    wFormatTag          : u16;
    nChannels           : u16;
    nSamplesPerSec      : u32;
    nAvgBytesPerSec     : u32;
    nBlockAlign         : u16;
    wBitsPerSample      : u16;
    cbSize              : u16;
    wValidBitsPerSample : u16;
    dwChannelMask       : u32;
    SubFormat           : [16]u8;
}#no_padding;

RIFF_CODE :: (incode : string) -> u32
{
    A : u32 = incode.data[0];
    B : u32 = incode.data[1];
    C : u32 = incode.data[2];
    D : u32 = incode.data[3];
    return((cast(u32)(A) << 0) | (cast(u32)(B) << 8) | (cast(u32)(C) << 16) | (cast(u32)(D) << 24));
}

fmt_code_id  :: #run RIFF_CODE("fmt ");
riff_code_id :: #run RIFF_CODE("RIFF");
wave_code_id :: #run RIFF_CODE("WAVE");
data_code_id :: #run RIFF_CODE("data");

WAVE_Chunk_ID :: enum u32
{
    fmt     :: fmt_code_id;
    RIFF_ID :: riff_code_id;
    WAVE_ID :: wave_code_id;
    data    :: data_code_id;
};

Riff_Iterator :: struct
{
    at_cursor  : *u8;
    end_cursor : *u8;
}

parse_chunk_at :: inline (at : *u8, end : *u8) -> Riff_Iterator
{
    result : Riff_Iterator;
    result.at_cursor  = at;
    result.end_cursor = end;

    return result;
}

get_next_chunk :: inline (chunk : Riff_Iterator) -> Riff_Iterator
{
    chunk_data := cast(*Wave_Chunk)chunk.at_cursor;
    chunk_size := (chunk_data.chunk_size + 1) & ~1;
    new_chunk := chunk;
    new_chunk.at_cursor += size_of(Wave_Chunk) + chunk_size;
    return new_chunk;
}

is_chunk_valid :: inline (chunk : Riff_Iterator) -> bool
{
    return(chunk.at_cursor < chunk.end_cursor);
}

get_chunk_type :: inline (chunk : Riff_Iterator) -> WAVE_Chunk_ID
{
    chunk_data := cast(*Wave_Chunk)chunk.at_cursor;
    result := cast(WAVE_Chunk_ID)chunk_data.ID;
    return result;
}

get_chunk_data :: inline (chunk : Riff_Iterator) -> *void
{
    result := cast(*void)(chunk.at_cursor + size_of(Wave_Chunk));
    return result;
}

get_chunk_data_size :: inline (chunk : Riff_Iterator) -> s32
{
    data := cast(*Wave_Chunk)chunk.at_cursor;
    return data.chunk_size;
}

load_wav_file :: (arena : *Memory_Arena, filepath : string) -> Loaded_Sound_Data 
{
    result : Loaded_Sound_Data;
    audio_file_data := read_entire_file(filepath);
    if audio_file_data.count > 0
    {
        header_data : *Wave_Header  = cast(*Wave_Header)audio_file_data.data;
        assert(header_data.RIFF_ID == cast(u32)WAVE_Chunk_ID.RIFF_ID);
        assert(header_data.WAVE_ID == cast(u32)WAVE_Chunk_ID.WAVE_ID);

        audio_file_channel_count := 0;
        sample_data_chunk_size   := 0;
        file_sample_data         : *s16;

        wave_file_iter := parse_chunk_at(cast(*u8)(header_data + 1), cast(*u8)(header_data + 1) + header_data.size - 4);
        while(is_chunk_valid(wave_file_iter))
        {
            defer wave_file_iter = get_next_chunk(*wave_file_iter);
            if get_chunk_type(wave_file_iter) ==
            {
                case WAVE_Chunk_ID.fmt;
                {
                    format_data : *Wave_FMT = cast(*Wave_FMT)get_chunk_data(wave_file_iter);
                    assert(format_data.wFormatTag     == 1);
                    assert(format_data.nSamplesPerSec == 48000);
                    assert(format_data.nBlockAlign    == (2 * format_data.nChannels));

                    audio_file_channel_count = format_data.nChannels;
                }
                case WAVE_Chunk_ID.data;
                {
                    file_sample_data       = cast(*s16)get_chunk_data(wave_file_iter);
                    sample_data_chunk_size = get_chunk_data_size(wave_file_iter);
                }
            }
        }
        assert(audio_file_channel_count != 0 && file_sample_data != null);

        result.channel_count = cast(s32)audio_file_channel_count;
        result.sample_count  = cast(s32)(sample_data_chunk_size / size_of(u8));
        result.sample_count  = cast(s32)((result.sample_count + 1) & ~1);
        assert(result.channel_count == 1 || result.channel_count == 2);

        result.sample_data  = file_sample_data;
        result.filepath     = filepath;
        result.ready_to_use = true;
    }
    else
    {
        log("Failed to load the file... file was %\n", filepath);
    }
    return result;
}

create_sine_wave :: (buffer_data : *Audio_Buffer_Data)
{
    using buffer_data;

    amplitude := 30000;
    tone_hz   := 140;

    for sample_index : 0..samples_to_output - 1
    {
        time := sample_index / cast(float32)SAMPLES_PER_SECOND;
        primary_sample_buffer[sample_index] = cast(s16)((amplitude * sin(2.0 * PI * tone_hz * time)) / 250);
        running_sample_index += 1;
    }
}

fill_sound_buffer :: (primary_stream_buffer : *SDL_AudioStream, buffer_data : *Audio_Buffer_Data, device_id : u32)
{
    using buffer_data;

    bytes_to_write := buffer_data.samples_to_output * cast(u32)buffer_data.bytes_per_sample;
    SDL_AudioStreamPut(primary_stream_buffer, buffer_data.primary_sample_buffer, cast(s32)bytes_to_write);

    queued_size    := SDL_GetQueuedAudioSize(device_id);
    target_latency := buffer_data.sample_latency * bytes_per_sample;
    max_queue_size := target_latency;
    if queued_size < xx max_queue_size
    {
        bytes_to_fulfill := max_queue_size - xx queued_size; 
        bytes_avaliable  := SDL_AudioStreamAvailable(primary_stream_buffer);
        bytes_to_queue   := min(bytes_avaliable, bytes_to_fulfill);
        if bytes_to_queue > 0
        {
            bytes_read := SDL_AudioStreamGet(primary_stream_buffer, buffer_data.secondary_sample_buffer, bytes_to_queue);
            if bytes_read > 0 
            {
                SDL_QueueAudio(device_id, buffer_data.secondary_sample_buffer, cast(u32)bytes_read);
            }
        }
    }
}

clear_sound_buffer :: (buffer_data : *Audio_Buffer_Data)
{
    using buffer_data;

    for sample_index : 0..sample_buffer_size - 1
    {
        primary_sample_buffer[sample_index] = 0;
    }
}

sound_set_fade_volume :: inline (playing_sound: *Playing_Sound, left_channel_target: float32, right_channel_target: float32, rate: float32)
{
    playing_sound.target_volume = .{left_channel_target, right_channel_target};
    playing_sound.volume_delta  = rate;
}

sound_set_pitch :: inline (playing_sound: *Playing_Sound, pitch: float32)
{
    playing_sound.pitch = pitch;
}

pause_sound :: inline (playing_sound: *Playing_Sound)
{
    playing_sound.is_playing = false;
}

mixer_handle_all_playing_sounds :: (sound_manager : *Sound_Manager, time: Time_Data)
{
    transient_state := sound_manager.asset_manager.transient_state;
    using sound_manager;

    scratch_arena := begin_temporary_block(*sound_manager.sound_arena);
    mixer_buffer_00 : *float32 = cast(*float32)push_size(*sound_manager.sound_arena, size_of(float32) * manager_buffer_info.samples_to_output);
    mixer_buffer_01 : *float32 = cast(*float32)push_size(*sound_manager.sound_arena, size_of(float32) * manager_buffer_info.samples_to_output);

    dest_00 : *float32 = mixer_buffer_00;
    dest_01 : *float32 = mixer_buffer_01;

    if manager_buffer_info.samples_to_output != 0
    {
        for 0..manager_buffer_info.samples_to_output - 1
        {
            defer dest_00 += 1;
            defer dest_01 += 1;
            
                <<dest_00 = 0;
                <<dest_01 = 0;
        }

        playing_sound_ptr : **Playing_Sound = *sound_manager.first_playing_sound;
        while(<<playing_sound_ptr != null)
        {
            sound_finished : bool;
            current_sound := <<playing_sound_ptr;
            dest_00 = mixer_buffer_00;
            dest_01 = mixer_buffer_01;
            if current_sound.is_playing
            {
                sample_count_to_mix := manager_buffer_info.samples_to_output;
                sound_asset_data := asset_get_sound(sound_manager.asset_manager, current_sound.sound_tag);
                if sound_asset_data.sample_data != null && sound_asset_data.ready_to_use
                {
                    mixing_count := sample_count_to_mix;
                    sample_index := current_sound.play_cursor;
                    samples_remaining_in_sound := cast(s32)floor(sound_asset_data.sample_count - (sample_index / current_sound.pitch)); 
                    if mixing_count > xx samples_remaining_in_sound
                    {
                        mixing_count = xx samples_remaining_in_sound;
                    }
                    
                    for 0..mixing_count - 1
                    {
                        defer dest_00 += 1;
                        defer dest_01 += 1;
                        
                        floored_index: s32 = cast(s32)floor(sample_index);
                        sample_offset: s32 = floored_index % (sound_asset_data.sample_count);

                        left_sample_value  : float32 = cast(float32)(sound_asset_data.sample_data[sample_offset * 2])      * current_sound.current_volume.x;
                        right_sample_value : float32 = cast(float32)(sound_asset_data.sample_data[(sample_offset * 2) + 1] * current_sound.current_volume.y);
                            <<dest_00 += left_sample_value;
                            <<dest_01 += right_sample_value;

                        sample_index += current_sound.pitch;

                    }
                    v2_approach(*current_sound.current_volume, current_sound.target_volume, current_sound.volume_delta, time.delta_time);
                    
                    current_sound.play_cursor = sample_index; 
                    sample_count_to_mix      -= mixing_count;
                    if current_sound.play_cursor >= xx sound_asset_data.sample_count
                    {
                        sound_finished = true;
                    }
                }
            }
            if sound_finished
            {
                    <<playing_sound_ptr                    = current_sound.next_sound;
                current_sound.next_sound               = sound_manager.first_free_playing_sound;
                sound_manager.first_free_playing_sound = current_sound;
            }
            else
            {
                playing_sound_ptr = *current_sound.next_sound;
            }
        }
        dest_00 = mixer_buffer_00;
        dest_01 = mixer_buffer_01;

        sample_buffer: *s16 = *manager_buffer_info.primary_sample_buffer[0];
        for 0..manager_buffer_info.samples_to_output - 1
        {
            defer dest_00 += 1;
            defer dest_01 += 1;

                <<sample_buffer += cast(s16)((<<dest_00 * sound_manager.master_volume) + 0.5);
            sample_buffer   += 1;

                <<sample_buffer += cast(s16)((<<dest_01 * sound_manager.master_volume) + 0.5);
            sample_buffer   += 1;

            manager_buffer_info.running_sample_index += 1;
        }
    }

    end_temporary_block(*scratch_arena);
}
