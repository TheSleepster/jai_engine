#import "POSIX";
#load "../misc/deps/generated_linux_networking.jai";

Socket :: s32;

//////////////////////
// MEMORY ALLOCATION
//////////////////////

slp_allocate_memory :: inline (size: u64) -> *void
{
    data := mmap(null, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    //log("[INFO]: mmap called with a size of: %mb\n", cast(float32)(size / 1048576.0));
    return data;
}

slp_deallocate_memory :: inline (data: *void, size: u64)
{
    munmap(data, size);
}

//////////////
// THREADING
//////////////

slp_get_cpu_count :: inline () -> s64 
{
    return sysconf(._SC_NPROCESSORS_ONLN);
}

slp_create_semaphore :: (initial_thread_count : s32,
                         max_thread_count     : s32,
                         semaphore_name       : string = "") -> *void
{
    result: *sem_t = New(sem_t);
    
    if semaphore_name != ""
    {
        result = sem_open(temp_c_string(semaphore_name), O_CREAT, S_IRUSR | S_IWUSR, 0);
        if result == null 
        {
            perror("[ERROR]: sem_open failed...\n");
            assert(false);
        }
    }
    else
    {
        success := sem_init(result, 0, 0);
        if success != 0
        {
            perror("[ERROR]: sem_init failed...\n");
            assert(false);
        }
    }

    return result;
}

slp_release_semaphore :: inline (semaphore: *void)
{
    sem_destroy(semaphore);
    free(semaphore);
}

slp_thread_wait :: inline (semaphore: *void, duration_ms: u32)
{
    if duration_ms == 0
    {
        sem_wait(semaphore);
        return;
    }

    time_data: timespec;

    // NOTE(Sleepster): for some reason the compiler wouldn't find this otherwise 
    CLOCK_MONOTONIC :: 1;
    if clock_gettime(CLOCK_MONOTONIC, *time_data) == -1
    {
        perror("[ERROR]: Failure to get time for 'timed_wait'...\n");
        assert(false);

        sem_wait(semaphore);
        return;
    }

    time_data.tv_sec  += duration_ms / 1000;
    time_data.tv_nsec += (duration_ms % 1000) * 1000000;
    
    sem_timedwait(semaphore, *time_data);
}

slp_thread_start :: (semaphore: *void, to_release: s32) -> s32
{
    started: s32;
    for thread_index: 0..to_release - 1
    {
        success := sem_post(semaphore);
        if success != 0
        {
            perror("[ERROR]: Failure to call 'sem_post'...\n");
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
    linux_thread_handle: *pthread_t = New(pthread_t);

    if stack_size != 0
    {
        thread_attributes  : pthread_attr_t;
        if pthread_attr_init(*thread_attributes) != 0
        {
            perror("[ERROR]: Failed to initialize Linux thread attributes...\n");
            pthread_attr_destroy(*thread_attributes);
            return result;
        }

        if pthread_attr_setstacksize(*thread_attributes, xx stack_size) != 0
        {
            perror("[ERROR]:  failed to set the pthread_attr stack size...\n");
            pthread_attr_destroy(*thread_attributes);
            return result;
        }

        error := pthread_create(linux_thread_handle, *thread_attributes, xx thread_proc, user_data);
        if error != 0
        {
            perror("[ERROR]: Cannot 'pthread_create' failed...\n");
            pthread_attr_destroy(*thread_attributes);
            assert(false);

            return result;
        }
        pthread_attr_destroy(*thread_attributes);
    }
    else
    {
        error := pthread_create(linux_thread_handle, null, xx thread_proc, user_data);
        if error != 0
        {
            perror("[ERROR]: Cannot 'pthread_create' failed...\n");
            assert(false);

            return result;
        }
    }

    // NOTE(Sleepster): Couldn't be bothered to find a simple way to keep track of the thread id on Linux... 
    result.thread_handle = linux_thread_handle;
    result.thread_id     = -1;
    if close_handle
    {
        error := pthread_detach(linux_thread_handle.*);
        if error != 0
        {
            perror("[ERROR]: Failure to close the linux thread handle...\n");
        }
        
        free(linux_thread_handle);
    }

    return result;
}

slp_close_thread_handle :: (thread_data: SLP_Thread) -> bool
{
    linux_thread_handle: u64 = (cast(*u64)thread_data.thread_handle).*;
    
    error := pthread_detach(linux_thread_handle);
    if error != 0
    {
        perror("[ERROR]: Failure to close the linux thread handle...\n");
        return false;
    }
    
    free(thread_data.thread_handle);
    return true;
}

///////////////
// NETWORKING
///////////////

// NOTE(Sleepster): THIS IS UDP ONLY!!!!!  

slp_socket_get_last_error :: inline () -> OS_Error_Code
{
    return errno();
}

slp_socket_create :: (ip_type: Socket_IP_Type, protocol: Socket_Protocol) -> SLP_Socket
{
    result: SLP_Socket;
    
    socket_handle := socket(AF_INET, .SOCK_DGRAM, .IPPROTO_UDP);
    if socket_handle != -1
    {
        result.handle   = socket_handle;
        result.ip_type  = ip_type;
        result.protocol = protocol;
    }
    else
    {
        perror("[ERROR]: Failed to create the UDP socket...");
    }

    return result;
}

slp_socket_bind :: (socket: *SLP_Socket, port: u16) -> bool
{
    result: bool;
    if port > 0
    {
        port = htons(port);
    }
    
    socket_address: sockaddr_in;
    socket_address.sin_family      = AF_INET;
    socket_address.sin_addr.s_addr = INADDR_ANY;
    socket_address.sin_port        = port;

    error := bind(socket.handle, cast(*sockaddr)*socket_address, size_of(sockaddr_in));
    if error != -1
    {
        socket.port             = port;
        socket.is_bound_to_addr = true;
    }
    else
    {
        perror("[ERROR]: Failed to bind the socket...\n");
    }

    result = (error != -1);
    return result;
}

slp_socket_set_nonblocking :: (socket: *SLP_Socket) -> bool
{
    result: bool;

    should_block: s32 = 1;
    error := fcntl(socket.handle, F_SETFL, O_NONBLOCK, should_block);
    if error != -1
    {
        socket.is_non_blocking = true;
    }
    else
    {
        perror("[ERROR]: Failed to set the socket to be nonblocking...\n");
    }

    result = (error != -1);
    return result;
}

slp_socket_send_data :: (socket: *SLP_Socket, buffer: string, address: string) -> s64
{
    c_address   := temp_c_string(address);
    net_address := inet_addr(c_address);
    
    socket_address: sockaddr_in;
    socket_address.sin_family      = AF_INET;
    socket_address.sin_addr.s_addr = net_address;
    socket_address.sin_port        = socket.port;

    bytes_sent := sendto(socket.handle,
                         buffer.data,
                         xx buffer.count,
                         0,
                         cast(*sockaddr)*socket_address,
                         size_of(sockaddr_in));
    return bytes_sent;
}

slp_socket_read_from :: (socket: *SLP_Socket) -> string, s64
{
    buffer: string;
    buffer.data  = alloc(size_of(u8) * 512);
    buffer.count = 512;

    from: sockaddr_in;
    from_size: u32 = size_of(sockaddr_in);

    bytes_read := recvfrom(socket.handle,
                           buffer.data,
                           xx(buffer.count * size_of(u8)),
                           0,
                           cast(*sockaddr)*from,
                           *from_size);
    return buffer, bytes_read;
}
