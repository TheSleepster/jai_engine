#if OS == .WINDOWS
{
    #load "platform_windows.jai";
}
#if OS == .LINUX
{
    #load "platform_linux.jai";
}

SLP_Thread :: struct
{
    thread_handle : *void;
    thread_id     : s32;
};
