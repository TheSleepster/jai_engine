#if OS == .WINDOWS
{
    #load "platform_windows.jai";
}
#if OS == .LINUX
{
    #load "platform_linux.jai";
}
#if OS == .MACOS
{
    #assert false "MacOSX is not a supported OS...\n";
}

interlocked_compare_exchange :: compare_and_swap;
interlocked_add              :: atomic_add;
interlocked_increment        :: atomic_increment;
interlocked_decrement        :: atomic_decrement;
interlocked_and              :: atomic_and;
interlocked_or               :: atomic_or;
interlocked_xor              :: atomic_xor;


SLP_Thread :: struct
{
    thread_handle : *void;
    thread_id     :  s32;
};

SLP_Work_Queue_Entry :: struct
{
    user_data : *void;
    callback  : (user_data: *void);
    is_valid  :  bool;
};

SLP_Work_Queue :: struct
{
    semaphore           : *void;
    threads_awake       :  s32;
    system_thread_count :  s32;
    
    entries_completed   :  u64;
    total_entries       :  u64;
    entries             : [256]SLP_Work_Queue_Entry;
};

slp_add_work_queue_entry :: (queue: *SLP_Work_Queue, callback: (user_data: *void), user_data: *void)
{
    new_entry := *queue.entries[queue.total_entries % queue.entries.count];
    new_entry.user_data = user_data;
    new_entry.callback  = callback;
    new_entry.is_valid  = true;

    interlocked_increment(*queue.total_entries);
    if queue.threads_awake < queue.system_thread_count
    {
        slp_thread_start(queue.semaphore, 1);
        queue.threads_awake += 1;
    }
}

slp_reset_work_queue :: (queue: *SLP_Work_Queue)
{
    queue.entries_completed = 0;
    queue.total_entries     = 0;
    for *entry: queue.entries
    {
        entry.* = .{};
    }
}


