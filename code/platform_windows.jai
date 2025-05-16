W :: #import "Windows";

slp_allocate_memory :: inline (size: u64) -> *void
{
    data := W.VirtualAlloc(null, xx size, W.MEM_COMMIT|W.MEM_RESERVE, W.PAGE_READWRITE);
    return data;
}

slp_deallocate_memory :: inline (data: *void, size: u64)
{
    W.VirtualFree(data, 0, W.MEM_RELEASE);
}

slp_get_cpu_count :: inline () -> s64 
{
    system_info: W.SYSTEM_INFO;
    W.GetSystemInfo(*system_info);

    return system_info.dwNumberOfProcessors;
}

slp_create_semaphore :: inline (initial_thread_count: s32, max_thread_count: s32, semaphore_name: string) -> *void
{
    assert(initial_thread_count >= max_thread_count);

    semaphore := W.CreateSemaphoreA(null, initial_thread_count, max_thread_count, temp_c_string(semaphore_name));
    if semaphore == null
    {
        log("[ERROR]: Failed to acquire the Windows platform Semaphore Object...\n");
        return null;
    }
    
    return semaphore;
}

slp_create_thread :: inline (user_data     : *void,
                             thread_proc   : (data: *void) -> s32 #c_call,
                             stack_size    :  s64,
                             close_handle  : bool = true) -> SLP_Thread
{
    result: SLP_Thread;
    
    assert(stack_size >= 0);
    result.thread_handle = W.CreateThread(null, stack_size, cast(*void)thread_proc, user_data, 0, *result.thread_id);
    if result.thread_handle != null
    {
        if close_handle
        {
            W.CloseHandle(result.thread_handle);
        }
    }
    else
    {
        log("[ERROR]: CreateThread (Windows) failed...\n");
        return .{};
    }

    return result;
}

slp_close_thread_handle :: (thread_data: SLP_Thread) -> bool
{
    result := W.CloseHandle(thread_data.thread_handle);
    if result == 0
    {
        log("[ERROR]: Failed to close thread handle...\n");
        return false;
    }
    return true;
}
