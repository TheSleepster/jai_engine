////////////////
// ENTITY STUFF
////////////////
entity_id :: s32;

Entity :: struct
{
    ID       : entity_id;
    is_valid : bool;
};

Entity_Manager :: struct
{
    entities                : [MAX_ENTITIES]Entity;
    entity_counter          : s32;

    position_components     : Component_Set_Position;
    sprite_components       : Component_Set_Sprite;
    player_data_components  : Component_Set_Player_Data;
    physics_data_components : Component_Set_Physics_Data;
};

entity_create :: (entity_manager: *Entity_Manager) -> *Entity
{
    result: *Entity;
    for entity_index: 0..entity_manager.entities.count - 1
    {
        found := *entity_manager.entities[entity_index];
        if !found.is_valid
        {
            result          = found;
            result.is_valid = true;

            entity_manager.entity_counter += 1;
            break;
        }
    }
    assert(result.is_valid == true);
    return result;
}

entity_destroy :: inline (entity_manager: *Entity_Manager, entity: *Entity)
{
    entity_remove_position(entity_manager, entity.ID);
    entity_remove_sprite(entity_manager, entity.ID);
    entity_remove_player_data(entity_manager, entity.ID);
    entity_remove_physics_data(entity_manager, entity.ID);

    entity.ID = -1;
    entity.is_valid = false;
}

get_entity_from_id :: inline (entity_manager: *Entity_Manager, entity_id: s32) -> *Entity
{
    return *entity_manager.entities[entity_id];
}

//////////////
// COMPONENTS
//////////////

Component_Position :: struct
{
    pos      : Vector2;
    last_pos : Vector2;
};

Component_Sprite :: struct
{
    sprite      : *Atlas_Sprite;
    draw_color  : Vector4;
    render_size : Vector2;
};

Component_Player_Data :: struct
{
    is_camera_target : bool;
};

Component_Physics_Data :: struct
{
    velocity       : Vector2;
    speed          : float32;
    friction_value : float32;
};

Component_Set_Position :: struct
{
    entity_table  : [MAX_ENTITIES]entity_id;
    component_map : [MAX_ENTITIES]s32;
    positions     : [MAX_ENTITIES]Component_Position;

    comp_count    : s32;
};

Component_Set_Sprite :: struct
{
    entity_table  : [MAX_ENTITIES]entity_id;
    component_map : [MAX_ENTITIES]s32;
    sprites       : [MAX_ENTITIES]Component_Sprite;

    comp_count    : s32;
};

Component_Set_Player_Data :: struct
{
    entity_table  : [MAX_ENTITIES]entity_id;
    component_map : [MAX_ENTITIES]s32;
    player_data   : [MAX_ENTITIES]Component_Player_Data;

    comp_count    : s32;
};

Component_Set_Physics_Data :: struct
{
    entity_table  : [MAX_ENTITIES]entity_id;
    component_map : [MAX_ENTITIES]s32;
    physics_data  : [MAX_ENTITIES]Component_Physics_Data;

    comp_count    : s32;
}

///////////////////////
// COMPONENT UTILITIES
///////////////////////

entity_add_position :: (entity_manager: *Entity_Manager, entity: s32, initial_position := (Vector2).{0, 0})
{
    using entity_manager;
    index := sprite_components.comp_count;

    position_components.entity_table[index]   = entity;
    position_components.component_map[entity] = index;
    position_components.positions[index]      = .{initial_position, (Vector2).{0, 0}};

    position_components.comp_count += 1;
}

entity_add_sprite :: (entity_manager : *Entity_Manager,
                      entity         :  s32,
                      initial_sprite : *Atlas_Sprite,
                      render_size    := (Vector2).{10, 10},
                      draw_color     := (Vector4).{1, 1, 1 , 1})
{
    using entity_manager;
    if initial_sprite == null
    {
        log("[ERROR]: initial_sprite is null\n");
        return;
    }

    index := sprite_components.comp_count;
    sprite_components.entity_table[index]   = entity;
    sprite_components.component_map[entity] = index;
    sprite_components.sprites[index]  = .{initial_sprite, draw_color, render_size};

    sprite_components.comp_count += 1;
}

entity_add_player_data :: (entity_manager: *Entity_Manager, entity: s32, is_camera_target := false)
{
    using entity_manager;
    index := player_data_components.comp_count;

    player_data_components.entity_table[index]   = entity;
    player_data_components.component_map[entity] = index;
    player_data_components.player_data[index]    = .{is_camera_target};

    player_data_components.comp_count += 1;
}

entity_add_physics_data :: (entity_manager: *Entity_Manager, entity: s32, speed := 0.0, friction_value := 0.0)
{
    using entity_manager;
    index := physics_data_components.comp_count;

    physics_data_components.entity_table[index]   = entity;
    physics_data_components.component_map[entity] = index;
    physics_data_components.physics_data[index]   = .{null_vector2, speed, friction_value};

    physics_data_components.comp_count += 1;
}

entity_remove_position :: (entity_manager: *Entity_Manager, entity: s32)
{
    using entity_manager;
    index := position_components.component_map[entity];
    if index != -1
    {
        position_components.comp_count -= 1;
        last_index  := position_components.comp_count;
        last_entity := position_components.entity_table[last_index];
        
        position_components.entity_table[index] = last_entity;
        position_components.component_map[last_entity] = index;
        position_components.component_map[entity] = -1;
    }
}

entity_remove_sprite :: (entity_manager: *Entity_Manager, entity: s32)
{
    using entity_manager;
    index := sprite_components.component_map[entity];
    if index != -1
    {
        position_components.comp_count -= 1;
        last_index  := sprite_components.comp_count;
        last_entity := sprite_components.entity_table[last_index];
        
        sprite_components.entity_table[index] = last_entity;
        sprite_components.component_map[last_entity] = index;
        sprite_components.component_map[entity] = -1;
    }
}

entity_remove_player_data :: (entity_manager: *Entity_Manager, entity: s32)
{
    using entity_manager;
    index := player_data_components.component_map[entity];
    if index != -1
    {
        player_data_components.comp_count -= 1;
        last_index  := player_data_components.comp_count;
        last_entity := player_data_components.entity_table[last_index];
        
        player_data_components.entity_table[index] = last_entity;
        player_data_components.component_map[last_entity] = index;
        player_data_components.component_map[entity] = -1;
    }
}

entity_remove_physics_data :: (entity_manager: *Entity_Manager, entity: s32)
{
    using entity_manager;
    index := physics_data_components.component_map[entity];
    if index != -1
    {
        physics_data_components.comp_count -= 1;
        last_index  := physics_data_components.comp_count;
        last_entity := physics_data_components.entity_table[last_index];
        
        physics_data_components.entity_table[index] = last_entity;
        physics_data_components.component_map[last_entity] = index;
        physics_data_components.component_map[entity] = -1;
    }
}

component_get_position :: inline (position_set: *Component_Set_Position, entity: s32) -> *Component_Position
{
    result: *Component_Position;
    index :=  position_set.component_map[entity];
    if index != -1
    {
        result = *position_set.positions[index];
        return result;
    }
    else
    {
        return null;
    }
}

component_get_sprite :: inline (sprite_set: *Component_Set_Sprite, entity: s32) -> *Component_Sprite
{
    result: *Component_Sprite;
    index :=  sprite_set.component_map[entity];
    if index != -1
    {
        result = *sprite_set.sprites[index];
        return result;
    }
    else
    {
        return null;
    }
}

component_get_player_data :: inline (player_data_set: *Component_Set_Player_Data, entity: s32) -> *Component_Player_Data
{
    result: *Component_Player_Data;
    index :=  player_data_set.component_map[entity];
    if index != -1
    {
        result = *player_data_set.player_data[index];
        return result;
    }
    else
    {
        return null;
    }
}

component_get_physics_data :: inline (physics_data_set: *Component_Set_Physics_Data, entity: s32) -> *Component_Physics_Data
{
    result: *Component_Physics_Data;
    index :=  physics_data_set.component_map[entity];
    if index != -1
    {
        result = *physics_data_set.physics_data[index];
        return result;
    }
    else
    {
        return null;
    }
}

has_component_sprite :: inline (sprite_set: *Component_Set_Sprite, entity: s32) -> bool
{
    return sprite_set.component_map[entity] != -1;
}

has_component_position :: inline (position_set: *Component_Set_Position, entity: s32) -> bool
{
    return position_set.component_map[entity] != -1;
}

has_component_player_data :: inline (player_data_set: *Component_Set_Player_Data, entity: s32) -> bool
{
    return player_data_set.component_map[entity] != -1;
}

has_component_physics_data :: inline (physics_data_set: *Component_Set_Physics_Data, entity: s32) -> bool
{
    return physics_data_set.component_map[entity] != -1;
}

///////////
// SYSTEMS
///////////

update_sprite_components :: (draw_frame   : *Draw_Frame_Data,
                             sprite_set   : *Component_Set_Sprite,
                             position_set : *Component_Set_Position)
{
    for loop_index: 0..sprite_set.comp_count - 1
    {
        entity := sprite_set.entity_table[loop_index];

        if has_component_position(position_set, entity)
        {
            assert(has_component_position(position_set, entity));

            position_data := component_get_position(position_set, entity);
            sprite         := sprite_set.sprites[loop_index];
            draw_texture(draw_frame, position_data.pos, sprite.render_size, sprite.sprite, sprite.draw_color);
        }
    }
}

update_position_components :: (draw_frame   : *Draw_Frame_Data,
                               position_set : *Component_Set_Position,
                               physics_set  : *Component_Set_Physics_Data)
{
    for loop_index: 0..physics_set.comp_count
    {
        entity := physics_set.entity_table[loop_index];
        if has_component_position(position_set, entity)
        {
            assert(has_component_position(position_set, entity));

            position_data := component_get_position(position_set, entity);
            physics_data  := physics_set.physics_data[loop_index];
            position_data.pos += physics_data.velocity;
        }
    }
}

////////////
// ECS INIT
////////////

init_sparse_array :: (IDs: []s32)
{
    for index: 0..IDs.count - 1
    {
        IDs[index] = -1;
    }
}

init_ecs_data :: (entity_manager: *Entity_Manager)
{
    init_sparse_array(entity_manager.position_components.component_map);
    init_sparse_array(entity_manager.sprite_components.component_map);
    init_sparse_array(entity_manager.player_data_components.component_map);
    init_sparse_array(entity_manager.physics_data_components.component_map);
}
