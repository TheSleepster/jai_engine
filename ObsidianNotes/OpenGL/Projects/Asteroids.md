Basics
## GET THIS DONE BY APRIL 17TH

- [x] Get a player moving on screen
- [x] Create a method of rotating the sprite
- [x] Refine movement and add acceleration and friction 
- [x] Add edge collisions
- [x] Create a method of creating and drawing asteroids
- [x] Add collision detection with the bounds of the map
- [x] (optional) add health to test the destruction and reconstruction of asteroids
- [x] Add collision with the player
- [x] Add shooting
- [x] Make the Asteroids die when shot several times
- [x] Adjust the spawning logic so as to limit their spawning to only the edges of the screen
- [x] Make them kill the player on contact
- [ ] Add gameState to allow the game to restart on Player Death
- [ ] Add score
- [ ] Add basic Enemy AI (hostile ships)
- [ ] Add powerups and have them modify the player's state on pickup
- [ ] Add the chance of them splitting based on their size (hard)
- [ ] (optional) Menu's and settings
- [ ] Update the art (please)
- [ ] (optional) Particle system for enemies or objects on death??
- [ ] Release

"
      real32 radians = (real32)toRadian(projectiles[i]->rotation - 90);

      projectiles[i]->pos.x += (real32)(projectiles[i]->speed * cos(radians)); 
      projectiles[i]->pos.y += (real32)(projectiles[i]->speed * sin(radians)); 

      Rectangle projectileRect = {projectiles[i]->pos.x, projectiles[i]->pos.y, 10, 20};

      DrawRectanglePro(projectileRect, {0, 0}, projectiles[i]->rotation, RED);


"