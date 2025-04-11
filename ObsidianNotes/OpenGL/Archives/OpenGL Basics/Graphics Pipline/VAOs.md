+ Vertex Array Objects or VAO's store vertex information to give to OpenGL

**In order to create a VAO we must first define one using an Array of vertices:

![[Pasted image 20240319115706.png]]

After an array of vertices has been defined we can then create a VAO by using 
```
glGenVertexArrays(int count, array);
```
you can find more information about them here: https://docs.gl/gl4/glGenVertexArrays.

After a Vertex Array Object has been created we must bind to it using:

```
glBindVertexArray(array);
```
We then have to create a buffer that will be filled with the vertex data so OpenGL can process and render our Vertices

```
glCreateBuffers(int count, &VBO);
```
This will create an empty Vertex Buffer Object (https://docs.gl/gl4/glCreateBuffers).

When this object is empty it will need to be filled with data about our vertices. This can be done by binding the buffer and then filling it with data about our object. Duplicates are dealt with using [[IBOs]]

```
glBindBuffers(GL_ARRAY_BUFFER, VBO);
glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
```
More information about these objects can be found here:

* ``glBindVertexArray();
	https://docs.gl/gl4/glBindVertexArray
* ``glCreateBuffers();
	https://docs.gl/gl4/glCreateBuffers
* ``glBindBuffer();
	https://docs.gl/gl4/glBindBuffer
* ``glBufferData();
	https://docs.gl/gl4/glBufferData

Now that we've done everything that we need to do in order to load our vertex data into a buffer. We now have to tell our buffer what KIND of data is there. Is it Vertex Positions? Colors? The buffer and OpenGL still does not know what kind of .

```
glEnableVertexAttrib(int index);

POSITION EXAMPLE 

glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, count * sizeof(float), (void*) 0);
```
We can fix this problem by applying what OpenGL calls "Vertex Attribute Pointers". These VAPs Tell OpenGL what kind of information is in the buffer. Starting from Index 0. Find more information here: 
* https://docs.gl/gl4/glEnableVertexAttribArray
* https://docs.gl/gl4/glVertexAttribPointer

In `glVertexAttribPointer` there's a lot of stuff. The number 0 is the Enum used by OpenGL to tell us exactly which pointer we are enabling, in this case 0 is position. 3 is the total number of components per vertex (must be 1, 2, 3, or 4). GL_FLOAT is the data type of the vertices previously mentioned. Then `count * sizeof(float)` is the stride between the current index `0` and the next one, for example color could be: `glVertexAttribPointer(1,...)` and this would tell OpenGL what the stride is between the two in bytes. Last one can just be zero, but this is what Docs.gl says:
![[Pasted image 20240321075536.png]]

A final important note about `glVertexAttribArrayPointer` is that we should only call this function AFTER `glBindBuffer` has been called so as to modify our buffer.

After we give these attributes to the buffer we have to clean them up.

```
glBindVertexArray(0);
```
~~this will free the associated memory: 
* https://docs.gl/gl4/glEnableVertexAttribArray

The above is unnecessary. We MUST unbind the vertex array so our draw function can look like so:
![[Pasted image 20240321075135.png]]

Remember that if you need to render an [[IBOs]], use the `glDrawElements` function instead.
# Error Checking

Error checking can be done in several ways in OpenGL. These are the ways I typically deal with it.

![[Pasted image 20240319151545.png]]![[Pasted image 20240319151602.png]]![[Pasted image 20240319151610.png]]![[Pasted image 20240319151731.png]]
