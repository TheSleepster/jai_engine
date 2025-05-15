#if OS == .WINDOWS
{
    #load "platform_windows.jai";
}
#if OS == .LINUX
{
    #load "platform_linux.jai";
}

Platform_Thread_Handler :: struct
{
    system_cpu_count          : s64;
    created_threads           : s64;
    platform_semaphore_handle : *void;
};

Platform_Thread_Data :: struct
{
    thread_id: u64;
};
