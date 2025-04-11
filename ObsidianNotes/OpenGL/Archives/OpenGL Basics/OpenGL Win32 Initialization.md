Before You can create a context there are a few requirements. Most notably we must download the OpenGLExt files and the KHR Platform file from this site:
https://registry.khronos.org/OpenGL/index_gl.php
These files are `<GL/glext.h>`, `<GL/glcorearb.h>` and for Windows, `<GL/wglext.h>`. For Linux it is instead `<GL/glxext.h>`. Then lastly the KHR platform File. **IT MUST BE IN KHR/khrplatform.h

This will allow us to call OpenGL functions and create the rendering context *AFTER LINKING WITH OPENGL32.lib*.

After that, There are several (long and dumb) Steps to creating an OpenGL Rendering context on Windows, these steps are as follows:

- Create A fake window with a fake DC (device context)
This is needed because In order to get some OpenGL function pointers that allow you to create a more detailed OpenGL context, you need an already existing OpenGL context.
https://learn.microsoft.com/en-us/windows/win32/gdi/device-contexts

- Set the PixelFormat
In order to set a PixelFormat you must first create a DesiredPixelFormat (this is just a name I made). This is because you need to query Windows for a PixelFormat that is the **closest to the one you described**. Once you have a pixel format back from Windows you can set it. This Process of garbage looks like so:
![[Pasted image 20240520090409.png]]

After you have set the PixelFormat you need to create a temporary "dummy" OpenGL Rendering Context for the extraction of these OpenGL functions that are needed to create a more desirable context.

- Destroy this DC
After creating the fake DC You must Destroy the Window and release it's DC. This is because DC's in windows are coupled together with the window it is created FROM. After you have destroyed it's DC, you can then create another NEW window and establish a new Windows OpenGLRC for use. This whole Process looks like so:
![[Pasted image 20240520090614.png]]

Then in Main You create the new window with a new DC:
![[Pasted image 20240520090701.png]]
Now there's some stuff in that PixelAttributes Array. You can read the OpenGL docs for that because I'm too lazy. But this allows us to create a more desirable Context than we were able to previously. 

After that We Assign the context attributes for the OpenGLRC (Confusing I know but those previous Attribs were for the **PIXELS** not the RC itself). This is done like so here: 
![[Pasted image 20240520090903.png]]

After these Attribs are set, as you can see we can simply make a new OpenGLRC, make it the current RC with `wglMakeCurrent()`, and we will finally have a useable OpenGLRC that we can then draw too.