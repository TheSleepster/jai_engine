Wave function collapse is an algorithm that makes use of constraint satisfaction.  

Wave function collapse has different versions:
   - Overlapping Model.
   - Simple Tiled Model.
   
Both models take a sample of input data and use the dat to generate a random output resembling the contraints of the input data.

In the Overlapping mode, you provide a sample image. You can then define an NxN dimension with which to examine the image for patterns and natural constraints in the image. This works for both Tiles and Pixels.

The Simple Tiled Model takes a list of images and a set of constraints as it's input and uses those constrints to determine what the best values for each grid spot could be from the constraints.

Regardless of which one you pick, the path to completion is always the same. They all start with a grid that contains all possibilities in each tile, a "superposition" of sorts. Essentially every cell in the grid contains all states at the same time. Imagine a game of Sudoku, but the board starts empty. In Sudoku, your job is to solve the puzzle by filling every square following the game's required constraints, Wave function collapse is no different. 

In the Simple Tiled Model, you might say that a water tile cannot border a grass tile. However, it can in fact border itself and a sand tile. But in the Overlapping model, since you are providing an input image you would examine the tiles or pixels on an NxN basis. Then use the rules that the algorithm "detects" to output an image that is consistent with the input.

Wave Function Collapse much generate an output that is consistent with the constraints you pass it. If it fails too, we have a contradiction. I will talk about what to do in that case later. For now, that's the basic Idea.

# Inspiration for the algorithm

The algorithm was inspired by another one very similar to it. The algorithm that inspired Wave Function Collapse is known as "Model Synthesis" created by Paul Merrell. Paul was inspired by another set of algorithms known as texture synthesis, at the time of his thesis (2007) texture synthesis worked well! Except for when it didn't. Paul wanted to create an algorithm that was suitable for rigid structures and allowed for 3D generation.

When searching for such algorithm, Paul noted that objects with repetivie or self-similar structures tend to be procedurally modeled more easily. He also noted that Self-similarity is a common feature of both man-made and natural objects. By breaking down these objects into these repeatable components, rather than just thinking about pixels. Paul found that you could generate an image that was similar enough to satisfy contraints, but yeiled a brand new result.

Here's how it works:

  1. First you need components. These can be images with predefined constraints(sand only goes next to water, grass, and itself. Whilst grass can only go next to itself and sand). Or they can be derived from an input image.
	![[Pasted image 20250402155749.png]]
  2. Select a cell with the lowest possibilites left to collapse.
  
  3. Assign the cell a random Module (component) that matches it's domain. The modules can have weights to influence the result, making one or more modules more likely to be chosen over others.
	  ![[Pasted image 20250402155822.png]]
  
  4. Propogate the collapse to the affected domains of adjacent cells.
	  ![[Pasted image 20250402155904.png]]
  
  5. repeat steps 2, 3, and 4 until all cells are collapsed to an exact domain, or until there is a failure.
	![[Pasted image 20250402155947.png]]

It should be noted that in this basic instance, both Model Synthesis and Wave Function Collapse are essentially the same algorithm. However, Model Synthesis was more focused on 3D procedural generation while Wave Function Collapse was primarily focused on generation of 2D images. But that doesn't mean that Wave Function Collapse cannot support 3D generation, as many have written examples using 3D modules.

Note that if you chose to use the overlapping model of WFC, but only consider cells adjacent to the cell you pick, you are essentially using Discrete Model Synthesis. However, the minute you move to 2x2 or greater, you are now using Overlapping Wave Function Collapse.

However, once things get more complicated it is very easy to spot the difference in these algorithms.
![[Pasted image 20250402162407.png]]

Above is a table that shows the similarities and differences between Medel Synthesis and Wave Function Collapse.

Model Synthesis has 2 module types for generation, Discrete and continuous. 

## Getting Modules
Discrete Model Synthesis uses modules that are defined and passed as input to the generator. These can either be predefined and given after being created in an external tool like Blender or Aesprite, or they can be broken apart and analyzed from a sample image. 

Continuous Model Synthesis is magic. You define vertices, faces, and edges in continuous space instead of using discrete modules in a fixed grid. Essentially, this is fully generative and breaks away from the standard grid limitation. But it comes with much more complexity.

Wave Function Collapse uses a system identical to that of Discrete Model Synthesis known as the Simple Tiled Method. You provide modules and their constriants to the system in the same way as you would in Discrete Model Synthesis.

Wave Function Collapse also has another, unique model known as the Overlapping Model. In this model, an input image is required. It analyzes the input image on an NxN basis. Either in pixel dimensions or tile dimensions. The larger N is, the more of the image is analyzed for generation. Leading to different results.

## Cell Selection Methods

Generating and iterating over cells in Model Synthesis typically follows a linear interation method. Linear scanline iteration moves cell to cell collapsing it to it's matching domain and repeating for each cell until the next row. Typically iteration direction can be changed when using different methods of flattening an array. 

The problem with Model Synthesis' Linear Iteration is that it can cause linear artifacting, decreasing the believability of the output image.
![[Pasted image 20250402165833.png]]

This is typically unavoidable in 2D Model Synthesis implementations, but can be lessened using a method we will talk about later.

Wave Function Collapse however, selects a cell based off of it's Entropy. Meaning, the cell with the lowest uncertainty is picked and then collapsed. The result of this collapse is then propagated to nearby cells. If any of the cells reach an entropy of zero, they are also collapsed, further propogating those results. The lowest entropy approach generally improves the believability of the image, but is a bit slower. In practice, the speed is not noticable. More importantly the lowest entropy approach is more likely to fail. If a cell has been collapsed to a cell it shouldn't have been able to be collapsed too then the algorithm will fail. These are called contradictions in the algorithm. In the event that there is a contradiction there are methods such as backtracking that can help remedy and recover from such events but can be complicated to implement.

Both Wave Function Collapse and Model Synthesis support module weights and preset grid values. Allowing Generation to continue around these preset values. See Below:
![[constrained.gif]]

## Propagation
Both Model Synthesis and Wave Function Collapse use a propagation method known as "Arc Consistency". Arc Consistency is a family of solver algorithms that used to help solve Constraint Satisfaction Problems, which in this case is exactly what both Model Synthesis and Wave Function Collapse are.

So what is a constraint solver meant to do? How does it work? How does Arc Consistency help us here? why is it the chosen propagator?

As stated before, We are attempting to solve a Constraint Satisfaction Problem, where we have a goal we want to achieve, a set of data with which to achieve it, and the rules, or constraints, of where this data can be placed. Thing of a Constraint Satisfaction Problem like this:
https://youtu.be/zIRTOgfsjl0?si=h3asJPWzASyWr9xg&t=175

A Constraint Satisfaction Problem is where you have a finite set of variables. You know the possible range of values for each variable, called its domain, but you don’t yet know what value each variable should be. The problem contains a series of constraints.

Each constraint links together some variables, and asserts about what values are allowed in those variables. One of the many ways we can track our constraints is called a table constraint (aka an extensional constraint). These constraints have no underlying logic about what values are allowed or not, instead, they are simply defined by a table of tuples (aka relations), where each tuple defines one possible combination of values. For example, if we had variables x, y, and z, and just one table constraint which is on (x,y, z) with tuples (1, 2, 3) and (1, 5, 6), then a solution might be x=1, y=2, z=3 or x=1, y=5, z=6. But x=1, y=2, z=6 would not be solution, as (1, 2, 6) is not a tuple in the table.
# What is Arc Consistency?

Consider an arc, i.e. a constraint between two variables x
and y. For a given value a in the domain of x, a value b in the domain of y is a support if **a** (x,y) is allowed by the the constraint, i.e. listed in the constraints table. If  doesn’t have a support, then we know it’s impossible for x to have that value, as it would _have_ to to violate the constraint between x and y. So if we find any value without a support, we can immediately remove it from the variable domain. But if the domain of x has changed, that may mean that some other values for other variables can now be removed, and so on. A constraint with no values removable on its variables is called **consistent**. Or explained another way, we look for values that can obviously be removed when considering a single constraint in isolation. If we’ve removed all such values, then everything is consistent. This is useful when trying to write a constraint solver. Recall that most solvers work by making a guess, propagating some consequences of that guess, and then repeating or backtracking. We can use “make everything arc consistent” as the propagation step – it strikes a nice balance that it can infer many useful consequences, but is quick enough to run to justify tring it. Using a solver in this way is called the **Maintaining Arc Consistency** (MAC) algorithm.

This information is from BorisTheBrave.com. Boris explains this concept exceptionally well:
[[https://www.boristhebrave.com/2021/08/30/arc-consistency-explained/]]

There are different types of Arc Consistency. The types used in Wave Function Collapse and older versions of Model Synthesis use AC-3. AC-3 Is older, but when compared to it's bigger and occasionally faster brother AC-4 it can be found that AC-3 handles smaller datasets better than AC-4. AC-4 can be better for larger datasets but also has a startup cost.

So Arc Consistency algorithms are responsible for making every constraint in a problem consistent. A very simple algorithm for doing so might be as follows:

`AC1 Listing`

- Loop forever:
    - For each constraint:
        - For each variable of that constraint:
            - For each value in the domain of that variable:
                - Search for a support of that value on the constraint
                - If no support is found:
                    - remove the value from the domain
    - If nothing has been removed in this loop, exit

In other words, search everything for a value to remove, and keep doing so until there’s nothing left. This approach works, but it is extremely inefficient – there may be many constraints, and many values in each variable.

While AC-3 looks like so:
`AC-3 Loop Listing`

- Start with a worklist containing two arcs for each constraint.
- While the worklist is non-empty:
    - Remove an arc from the worklist, say from x to y- .
    - For each value in the domain of y:
		- Search for a support of that value on the constraint of the arc
		    - If no support is found:
		        - Remove the value from the domain of the variable
		        - Add arcs from y to any other variables it’s constrainted with (excluding x).
This is better. Now, we examine each constraint once, and only re-examine a constraint if one of the variables of that constraint has actually changed. This is the essence of **Arc Consistency 3**.

In fact, AC3 is slightly smarter. It considers the direction of the arc, so that (x, y) is a different arc from (y, x). We can use this to avoid double-checking variables we’ve just checked:

`AC-3 Loop Listing`

- Start with a worklist containing two arcs for each constraint.
- While the worklist is non-empty:
    - Remove an arc from the worklist, say from x

to y- .
- For each value in the domain of y:
	- Search for a support of that value on the constraint of the arc
	    - If no support is found:
	        - Remove the value from the domain of the variable
	        - Add arcs from y to any other variables it’s constrainted with (excluding x).

AC-3 was first described by [Mackworth and Mohr in 1977](https://www.cs.ubc.ca/~mack/Publications/AI77.pdf), and didn’t recieve any significant improvements until a decade later, with AC-4. Information about AC-4 specifically is better found in the same blog post by BorisTheBrave from earlier.

## Error Handling

Model Synthesis and Wave Function Collapse have different methods you can use to solve problems that involve errors. Typically in Discrete Model Synthesis, you would generate the environment or image with a "modifying in blocks" approach. Performing modification in a series of N x N spaces for generation as this removes the typical linear biases that Model Synthesis usually has. If the generation fails, you can simply restart the generation inside of the chunk that failed. Thus allowing to work on a block-by-block basis.

Wave Function Collapse on the other hand has no easy native way of handling contraditions and failures. Typically developers that use Wave Function Collapse add a list or queue for cells during generation so that if there is a failure, the algorithm can backtrack and try again. Another method is the same "Modify in blocks" example that is used in Model Synthesis. Much like Model Synthesis this also helps some of the inherent issues that Wave Function Collapse has. One of those issues is that too big of environments typically ends with the algorithm failing MANY times before generation could actually be achieved. Using the modify in blocks method allows us to simply generate "sectors" accross the output, that way if there is a failure we just simply regenerate that sector exactly like we do in Model Synthesis. The last method is simply regenerate the entire output on failure. This is typically fine for smaller examples, however once the output grows in size it will cause the algorithm to generate outputs quite slowly.