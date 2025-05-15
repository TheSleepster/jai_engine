W :: #import "Windows";

platform_allocate_memory :: inline (size: u64) -> *void
{
    data := W.VirtualAlloc(null, xx size, W.MEM_COMMIT|W.MEM_RESERVE, W.PAGE_READWRITE);
    //log("[INFO]: Virtual alloc called with a size of: %mb\n", cast(float32)(size / 1048576.0));
    return data;
}

platform_deallocate_memory :: (data: *void, size: u64)
{
    W.VirtualFree(data, 0, W.MEM_RELEASE);
}
