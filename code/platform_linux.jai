P :: #import "POSIX";

slp_allocate_memory :: inline (size: u64) -> *void
{
    data := P.mmap(null, size, P.PROT_READ|P.PROT_WRITE, P.MAP_PRIVATE|P.MAP_ANONYMOUS, -1, 0);
    //log("[INFO]: mmap called with a size of: %mb\n", cast(float32)(size / 1048576.0));
    return data;
}

slp_deallocate_memory :: inline (data: *void, size: u64)
{
    P.munmap(data, size);
}

slp_get_cpu_count :: inline () -> s64 
{
    return P.sysconf(P._SC_NPROCESSORS_ONLN);
}

slp_create_semaphore :: (initial_thread_count: s32, max_thread_count: s32, semaphore_name: string = "") -> *void
{
    result: *P.sem_t = New(P.sem_t);
    
    if semaphore_name != ""
    {
        result = P.sem_open(temp_c_string(semaphore_name), P.O_CREAT, P.S_IRUSR | P.S_IWUSR, 0);
        if result == null 
        {
            log("[ERROR]: sem_open failed... Error code: %\n", P.errno);
            assert(false);
        }
    }
    else
    {
        success := P.sem_init(result, 0, 0);
        if success != 0
        {
            log("[ERROR]: sem_init failed... Error code: %\n", P.errno);
            assert(false);
        }
    }

    return result;
}

slp_release_semaphore :: inline (semaphore: *void)
{
    P.sem_destroy(semaphore);
    free(semaphore);
}

slp_thread_wait :: inline (semaphore: *void, duration_ms: u32)
{
    if duration_ms == 0
    {
        P.sem_wait(semaphore);
        return;
    }

    time_data: P.timespec;

    // NOTE(Sleepster): for some reason the compiler wouldn't find this otherwise 
    CLOCK_MONOTONIC :: 1;
    if P.clock_gettime(CLOCK_MONOTONIC, *time_data) == -1
    {
        log("[ERROR]: Failure to get time for 'timed_wait'...\n");
        assert(false);

        P.sem_wait(semaphore);
        return;
    }

    time_data.tv_sec  += duration_ms / 1000;
    time_data.tv_nsec += (duration_ms % 1000) * 1000000;
    
    P.sem_timedwait(semaphore, *time_data);
}

slp_thread_start :: (semaphore: *void, to_release: s32) -> s32
{
    started: s32;
    for thread_index: 0..to_release - 1
    {
        success := P.sem_post(semaphore);
        if success != 0
        {
            log("[ERROR]: Failure to call 'sem_post'...\n");
            assert(false);
        }
        started += 1;
    }

    if started > to_release
    {
        log("[WARNING]: More threads awoken than are valid on the machine...\n");
    }

    return started;
}

slp_create_thread :: (user_data    : *void,
                      thread_proc  :  (data: *void) -> s32 #c_call,
                      stack_size   :  s64,
                      close_handle :  bool = true) -> SLP_Thread 
{
    result             : SLP_Thread;
    linux_thread_handle: *P.pthread_t = New(P.pthread_t);

    if stack_size != 0
    {
        thread_attributes  : P.pthread_attr_t;
        if P.pthread_attr_init(*thread_attributes) != 0
        {
            log("[ERROR]: Failed to initialize Linux thread attributes...\n");
            P.pthread_attr_destroy(*thread_attributes);
            return result;
        }

        if P.pthread_attr_setstacksize(*thread_attributes, xx stack_size) != 0
        {
            log("[ERROR]:  failed to set the pthread_attr stack size...\n");
            P.pthread_attr_destroy(*thread_attributes);
            return result;
        }

        error := P.pthread_create(linux_thread_handle, *thread_attributes, xx thread_proc, user_data);
        if error != 0
        {
            log("[ERROR]: Cannot 'pthread_create' failed...\n");
            P.pthread_attr_destroy(*thread_attributes);
            assert(false);

            return result;
        }
        P.pthread_attr_destroy(*thread_attributes);
    }
    else
    {
        error := P.pthread_create(linux_thread_handle, null, xx thread_proc, user_data);
        if error != 0
        {
            log("[ERROR]: Cannot 'pthread_create' failed...\n");
            assert(false);

            return result;
        }
    }

    // NOTE(Sleepster): Couldn't be bothered to find a simple way to keep track of the thread id on Linux... 
    result.thread_handle = linux_thread_handle;
    result.thread_id     = -1;
    if close_handle
    {
        error := P.pthread_detach(linux_thread_handle.*);
        if error != 0
        {
            log("[ERROR]: Failure to close the linux thread handle...\n");
        }
        
        free(linux_thread_handle);
    }

    return result;
}

slp_close_thread_handle :: (thread_data: SLP_Thread) -> bool
{
    linux_thread_handle: u64 = (cast(*u64)thread_data.thread_handle).*;
    
    error := P.pthread_detach(linux_thread_handle);
    if error != 0
    {
        log("[ERROR]: Failure to close the linux thread handle...\n");
        return false;
    }
    
    free(thread_data.thread_handle);
    return true;
}
