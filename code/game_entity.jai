Entity_Manager :: struct
{
    active_entity_counter : u32;
    entities              : [MAX_ENTITIES]Entity;
};

using entity_flags: enum u64
{
    IS_VALID     :: 1 << 0;
    IS_GRABBABLE :: 1 << 1;
};

entity_archetype: enum u64
{
    NIL;
    PLAYER;
    CRATE;
};

Entity :: struct
{
    entity_id       :  u32;
    archetype       :  u32;
    flags           :  u64;

    prev_position   :  Vector2;
    position        :  Vector2;
    speed           :  float32;
    friction        :  float32;
    
    render_size     :  Vector2;
    draw_color      :  Vector4;
    sprite_data     : *Atlas_Sprite;

    attached_entity : *Entity;
    direction       :  Vector2;

    bounding_box    :  Range_V2;
};

create_entity :: (entity_manager: *Entity_Manager) -> *Entity
{
    result  : *Entity;
    success :  bool;
    for entity_index: 0..entity_manager.active_entity_counter
    {
        found := *entity_manager.entities[entity_index];
        if !(found.flags & xx IS_VALID)
        {
            result = found;
            result.flags |= xx IS_VALID;
            result.entity_id = entity_index;
            entity_manager.active_entity_counter += 1;

            success = true;
            break;
        }
    }
    assert(success);
    return result;
}

destroy_entity :: (entity: *$T)
{
    memset(entity, 0, size_of(T));
}

get_player :: (entity_manager: *Entity_Manager) -> *Entity
{
    player: *Entity;
    for entity_index: 0..entity_manager.active_entity_counter
    {
        found := *entity_manager.entities[entity_index];
        if (found.flags & xx IS_VALID) && found.archetype == xx entity_archetype.PLAYER
        {
            player = found;
            break;
        }
    }
    return player;
}
