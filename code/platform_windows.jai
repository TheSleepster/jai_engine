#import "Windows";
#load "../misc/deps/generated_windows_networking.jai";

#scope_file
System :: #import "System";
#scope_export

Socket :: SOCKET;
WINSOCK_VERSION: u16 : 0x0202;


slp_allocate_memory :: inline (size: u64) -> *void
{
    data := VirtualAlloc(null, xx size, MEM_COMMIT|MEM_RESERVE, PAGE_READWRITE);
    return data;
}

slp_deallocate_memory :: inline (data: *void, size: u64)
{
    VirtualFree(data, 0, MEM_RELEASE);
}

slp_get_cpu_count :: inline () -> s64 
{
    system_info: SYSTEM_INFO;
    GetSystemInfo(*system_info);

    return system_info.dwNumberOfProcessors;
}

slp_create_semaphore :: inline (initial_thread_count: s32, max_thread_count: s32, semaphore_name: string = "") -> *void
{
    assert(initial_thread_count <= max_thread_count);

    semaphore := CreateSemaphoreA(null, initial_thread_count, max_thread_count, temp_c_string(semaphore_name));
    if semaphore == null
    {
        log("[ERROR]: Failed to acquire the Windows platform Semaphore Object...\n");
        assert(false);

        semaphore = null;
    }
    
    return semaphore;
}

slp_release_semaphore :: inline (semaphore: *void)
{
    CloseHandle(semaphore);
}

slp_thread_wait :: inline (semaphore: *void, duration_ms: u32)
{
    if duration_ms == 0 duration_ms = INFINITE;
    WaitForSingleObject(semaphore, INFINITE);
}

slp_thread_start :: (semaphore: *void, to_release: s32) -> s32
{
    threads_released: s32;
    W_success: BOOL;

    W_success = ReleaseSemaphore(semaphore, to_release, *threads_released);
    if W_success == 0
    {
        log("[ERROR]: Failure to release '%' threads on the Windows Semaphore...\n", to_release);
        assert(false);

        threads_released = 0;
    }

    return threads_released;
}

slp_create_thread :: inline (user_data     : *void,
                             thread_proc   : (data: *void) -> s32 #c_call,
                             stack_size    :  s64,
                             close_handle  : bool = true) -> SLP_Thread
{
    result: SLP_Thread;
    
    assert(stack_size >= 0);
    result.thread_handle = CreateThread(null, stack_size, cast(*void)thread_proc, user_data, 0, *result.thread_id);
    if result.thread_handle != null
    {
        if close_handle
        {
            CloseHandle(result.thread_handle);
        }
    }
    else
    {
        log("[ERROR]: CreateThread (Windows) failed...\n");
        assert(false);

        result = .{};
    }

    return result;
}

slp_close_thread_handle :: (thread_data: SLP_Thread) -> bool
{
    result := CloseHandle(thread_data.thread_handle);
    if result == 0
    {
        log("[ERROR]: Failed to close thread handle...\n");
        assert(false);

        return false;
    }
    return true;
}

slp_socket_get_last_error :: inline () -> OS_Error_Code
{
    return WSAGetLastError();
}

slp_init_socket_system :: () -> bool
{
    wsa_data: WSADATA;
    error := WSAStartup(WINSOCK_VERSION, *wsa_data);
    if error != 0
    {
        log_error("Could not initialize Winsock: % %", error, System.get_error_string(cast (OS_Error_Code)error));
        return false;
    }

    return true;
}

slp_socket_create :: (ip_type: Socket_IP_Type, protocol: Socket_Protocol) -> SLP_Socket
{
    return .{};
}

slp_socket_bind :: (socket: *SLP_Socket, port: u16) -> bool
{
    return true;
}

slp_socket_set_nonblocking :: (socket: *SLP_Socket) -> bool
{
    return true;
}

slp_socket_send_data :: (socket: *SLP_Socket, buffer: string, address: string) -> s64
{
    return 0;
}

slp_socket_read_from :: (socket: *SLP_Socket) -> string, s64
{
    return .{}, 0;
}
