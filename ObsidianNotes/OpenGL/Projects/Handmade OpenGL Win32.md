## TODO LIST:
- [x] Shader and Texture Reloading
- [x] DeltaTime (Half done, we just need to implement interactions with it)
- [x] ECS?
- [x] CreateEntity API function
- [x] Basic shape Collision
- [x] BumpFree method
- [x] Custom Array manager
- [x] Proper ECS

- [ ] Custom std::Vector Manager
- [x] SelectEntity API function
- [x] RemoveEntity API function
## ON HOLD
- [ ] Animations
- [ ] Camera
- [ ] Audio
- [ ] Font
- [ ] GUI

LDTK Importing is too complicated and takes up too much storage. A very crude tile editor that just uses a file of characters to modify the map would likely be a better option. Array of ints that stores the level and such. All the editor would do is just change an integer.