Entity_Manager :: struct
{
    active_entity_counter : u32;
    entities              : [MAX_ENTITIES]Entity;
    players               : [20]Player;
};

using Entity_Flags : enum u64
{
    IS_VALID :: 1 << 0;
};

Entity :: struct
{
    entity_id     :  u32;
    flags         :  u64;

    prev_position : Vector2;
    position      :  Vector2;
    speed         :  float32;
    friction      :  float32;
    
    render_size   :  Vector2;
    draw_color    :  Vector4;

    sprite_data   : *Atlas_Sprite;
};

Player :: struct
{
    using entity: *Entity;
    is_camera_target: bool;
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

create_player :: (entity_manager: *Entity_Manager) -> *Player
{
    entity := create_entity(entity_manager);
    assert(entity != null);

    result: *Player;
    for player_index: 0..50 - 1
    {
        found := *entity_manager.players[player_index];
        if found.entity == null
        {
            result = found;
            break;
        }
    }
    result.entity = entity;

    assert(result && result.entity);
    return result;
}

destroy_entity :: (entity: *$T)
{
    memset(entity, 0, size_of(T));
}
