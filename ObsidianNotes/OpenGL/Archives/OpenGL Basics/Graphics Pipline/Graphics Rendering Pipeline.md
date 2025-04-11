# The first stage of the Graphics Rendering Pipeline

1. The first stage of the GRP is the Vertex Shading this takes the VBOs and the [[VAOs]] and combines them with a vertex shader to start the pipeline.

# The final stage of the GRP
2. You really only need to worry about the fragment and vertex shaders due to the fact that in the world of game programming the rest are optional and wasteful. 

fragments are made from the [[Shader Files]] that you load

# The rest?
The rest of the pipeline consists of things like the Geometry shader and the tessellation shader. These are not as important in interactive platforms like Video games as they tend to slow down the rate at which the image can be created and rendered to the screen.

see reference:
![[Pasted image 20240319172357.png]]