Consider an arc, i.e. a constraint between two variables x
and y. For a given value a in the domain of x, a value b in the domain of y is a support if **a** (x,y) is allowed by the the constraint, i.e. listed in the constraints table. If  doesn’t have a support, then we know it’s impossible for x to have that value, as it would _have_ to to violate the constraint between x and y. So if we find any value without a support, we can immediately remove it from the variable domain. But if the domain of x has changed, that may mean that some other values for other variables can now be removed, and so on. A constraint with no values removable on its variables is called **consistent**. Or explained another way, we look for values that can obviously be removed when considering a single constraint in isolation. If we’ve removed all such values, then everything is consistent. This is useful when trying to write a constraint solver. Recall that most solvers work by making a guess, propagating some consequences of that guess, and then repeating or backtracking. We can use “make everything arc consistent” as the propagation step – it strikes a nice balance that it can infer many useful consequences, but is quick enough to run to justify tring it. Using a solver in this way is called the **Maintaining Arc Consistency** (MAC) algorithm.

This information is from BorisTheBrave.com. Boris explains this concept exceptionally well:
https://www.boristhebrave.com/2021/08/30/arc-consistency-explained/

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
