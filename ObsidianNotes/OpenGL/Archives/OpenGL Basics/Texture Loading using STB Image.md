In order to load textures in OpenGL you need a method of loading them from their native format. for this we will use STB Image because it's easy.

You include it like so:
![[Pasted image 20240521040309.png]]

STB_IMAGE_IMPLEMENTATION **MUST ONLY BE INCLUDED ONCE**

After you are able to include the header, you can call a function that will return you a pointer to the data of the image, `stbi_load()`.
You can find the documentation for this library here: 
- https://github.com/nothings/stb/blob/master/stb_image.h

`stbi_load()` is used like so:
![[Pasted image 20240521040526.png]]

First you create some values that will be passed to the function. These are the Image's Width, Height, Channels of the image, and the last parameter is it's color channels (Ex. RGBA). These values do not have to be initialized as the function will return the data and fill them in for you.

After you have gotten the data You can use `glGenTextures()` to create a texture from it's data and activate it so that it can be used somewhere.
- https://docs.gl/gl4/glGenTextures
- https://docs.gl/gl4/glActiveTexture

After the Texture is created we have to BIND to it to apply attributes to it. In OpenGL you pretty much just have to bind to everything in order for it to work. I mean come on, it is a state machine after all.
- https://docs.gl/gl4/glBindTexture
- https://docs.gl/gl4/glTexParameter

Once the Texture has been bound to and had attributes applied to it, we can then turn the texture into an image using `glTexImage2D()`. You can read about this functions parameters and it's function here:
- https://docs.gl/gl4/glTexImage2D
![[Pasted image 20240521045341.png]]
After this is all done our image won't look EXACTLY the same, therefore we must enable `GL_FRAMEBUFFER_SRGB`. Since that is what format our image is in anyway.