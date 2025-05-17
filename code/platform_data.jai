#if OS == .WINDOWS
{
    #load "platform_windows.jai";
}
#if OS == .LINUX
{
    #load "platform_linux.jai";
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
    job_proc  : (user_data: *void);
    is_valid  :  bool;
};

SLP_Work_Queue :: struct
{
    semaphore         : *void;
    entries_completed :  u64;
    entry_queue       : [256]SLP_Work_Queue_Entry;
};

slp_add_work_queue_entry :: (queue: *SLP_Work_Queue, callback: (user_data: *void), user_data: *void)
{
}

slp_flush_work_queue :: (queue: *SLP_Work_Queue)
{
}


