WFC_Chunk_Cell :: struct
{
    is_collapsed   : bool;
};

WFC_Chunk_Data :: struct
{
    chunk_size   : u32;
    cells        : []WFC_Chunk_Cell;
};

#scope_file
num_states :: 4;

