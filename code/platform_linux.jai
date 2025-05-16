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

slp_create_semaphore :: ()
{
    semaphore: P.sem_t;
    result := P.sem_init(*semaphore, 0, 0);
    if result == -1
    {
        log("[ERROR]: sem_init failed... Error code: %\n", P.errno);
    }
}

slp_create_thread :: () -> Platform_Thread_Data
{
    // thread_info: P.pthread_t;
    // P.pthread_create(*thread_info, );

    return .{};
}
