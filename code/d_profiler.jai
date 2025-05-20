DEBUG_profile_timer :: struct
{
    current_tsc  : u64;
    last_tsc     : u64;
    delta_tsc    : u64;
    
    entry_index  : u64;

    label        : string;
};

// NEW
DEBUG_get_unique_timer_index :: (loc := #caller_location) -> u64
{
    assert(#compile_time);

    DEBUG_active_timer_counter += 1;
    index := DEBUG_active_timer_counter;

    return index;
}

DEBUG_init_new_timer :: (label: string, loc := #caller_location) -> *DEBUG_profile_timer #expand
{
    perf_count_frequency = SDL_GetPerformanceFrequency();
    
    index := #run DEBUG_get_unique_timer_index(loc);
    timer := *DEBUG_timers[index];
    timer.entry_index = index;
    timer.label = label;

    return timer;
}

DEBUG_start_profile :: (timer: *DEBUG_profile_timer)
{
    timer.last_tsc = SDL_GetPerformanceCounter();
}

DEBUG_stop_profile :: (timer: *DEBUG_profile_timer)
{
    timer.current_tsc = SDL_GetPerformanceCounter();
    timer.delta_tsc   = timer.current_tsc - timer.last_tsc;
    timer.last_tsc    = timer.current_tsc;
}

DEBUG_profile_function :: (loc := #caller_location) #expand
{
    timer := DEBUG_init_new_timer(#procedure_name(), loc);
    DEBUG_start_profile(timer);
    `defer DEBUG_stop_profile(timer);
}

DEBUG_report_timing_info :: ()
{
    print("[DEBUG]: -----PROFILER_STATS-----\n");
    for timer_index: 1..DEBUG_active_timer_counter
    {
        timer := *DEBUG_timers[timer_index];
        time_in_ms := cast(float32)(timer.delta_tsc * 100 / cast(float32)perf_count_frequency);
        
        print("         FUNCTION:   %\n", timer.label);
        print("         TIME IN MS: %ms\n", time_in_ms);
        print("         CYCLES:     %\n\n",   timer.delta_tsc);
    }
}

DEBUG_stop_and_report :: (timer: *DEBUG_profile_timer)
{
    DEBUG_stop_profile(timer);

    time_in_ms := cast(float32)(timer.delta_tsc * 100 / cast(float32)perf_count_frequency);

    print("[DEBUG]: -----TIMER_STATS-----\n");
    print("         FUNCTION:   %\n", timer.label);
    print("         TIME IN MS: %ms\n", time_in_ms);
    print("         CYCLES:     %\n\n",   timer.delta_tsc);
}

DEBUG_profile_and_report :: (loc := #caller_location) #expand
{
    timer := DEBUG_init_new_timer(#procedure_name(), loc);
    DEBUG_start_profile(timer);

    `defer DEBUG_stop_and_report(timer);
}

#scope_file 
DEBUG_timers: [1024]DEBUG_profile_timer;

#no_reset DEBUG_active_timer_counter: u64;

perf_count_frequency : u64;
global_timer         : DEBUG_profile_timer;
#import "SDL";
