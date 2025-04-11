Index Buffer Objects are objects that use the INDEX of our Vertex Array Object. For example we have this array of data:
![[Pasted image 20240321103540.png]]

our Index buffer pulls it's indices from that given vertex array. This is generally preferred to just using the vertices as is due to the fact that it cuts down the amount of duplicates there are in a given model or image.

An `IndexBufferObject` or IBO is created in much the same way you would create a VAO. The difference is the way that you initialize them:
![[Pasted image 20240321104309.png]]

Indices are initialized with the `GL_ELEMENT_ARRAY_BUFFER` enumeration rather than the standard `GL_ARRAY_BUFFER` for our [[VAOs]]. View docs below:
* https://www.khronos.org/opengl/wiki/Buffer_Object

There is also a key difference in how you draw shapes using an index buffer. You can find the details for these commands further down:
![[Pasted image 20240321104533.png]]

Instead of `glDrawArrays` we have to instead draw `glDrawElements` since we are not drawing an array, we are drawing only specific elements. the details for the functions is here:
* https://docs.gl/gl4/glDrawElements