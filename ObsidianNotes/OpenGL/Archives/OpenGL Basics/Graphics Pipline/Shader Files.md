Shade files are what tell the Graphics card how to create and render your image. There are two 
types of shaders that you need to worry about. Vertex and Fragment shaders.

1. Vertex Shaders tell the GPU how it should place vertices in the image and how the properties of these vertices should be processed.

2. The Fragment Shader is performed on the "fragments" of the image before they are finally rendered. "Fragments" are the name of the pixels that are drawn to the screen.

Fragment and Vertex shaders are the two most important since the rest are mostly optional. These two however are necessary for images to be rendered by OpenGL.

Vertex shaders Intake the information from our Vertex Buffer Object ([[VAOs]]) and translate them to the screen. These can include buffers that our Vertex Attribute Pointers give access to.

A simple Vertex Shader is looks like so:
```
#version <OpenGL Shading Language version>

layout (location = 0) in vec3 aPos; //location must be specified

layout (location = 1) in vec3 aColor;

out vec4 color; //this part is optional and will only work if color is active

int main() {
	glPostion = vec4(anyinputvalue);
}
```

This is very simplified, but for the earliest of shaders. This is adequate. A real example looks like so:

![[Pasted image 20240319173129.png]]
As you can see they are very similar to that of a normal C language function. There is a tiny difference however. And that is the `in` and `out` syntax. These are used to specify what information goes too and from the shader. 

* The `In` data stems from the information we passed from our [[VAOs]]. This data is then read to the shader and processed as needed. The `location` specifier stems from our `VertexArrayAttribPointer` that we provided too. In this case, `location 0` contains position data for the vertex and `location 1` contains color information about our vertex.

Fragment shaders intake the color information from the vertex shader. These shaders are run for every "fragment" or pixel, of our screen this allows us to modify the pixel however we wish too. This is the final stage before the image gets pushed to our screen.
![[Pasted image 20240319175653.png]]

The `in` data comes from our vertex shader. There looks like there's a problem though. We're passing color as a vec3, even though it has 4 components. RGBA. The reason is we're only controlling the RGB data, and then explicitly configuring the alpha of the color.

Shaders are necessary to the rendering pipeline. Unfortunately, OpenGL can only read the shaders in as strings. You can read Shaders in like so:
![[Pasted image 20240320080931.png]]

This is obviously very annoying. There is fortunately a "better" way. 
![[Pasted image 20240320081217.png]]
This way reads it in as a file. Although this may look very intimidating, It's actually rather simple because all it does is intakes a filepath that you pass and turns it into a readable shader for OpenGL.