---
layout: post
title:  "Pentominoes"
date:   2016-08-25 13:41:29 +0100
categories: c
permalink: /pentominoes/
---
One day I was clearing out some old papers and I came across this programming assignment from university. I can’t recall which of the problems I tackled at the time, after all it was twenty-five years ago, but glancing over it now the pentomino problem caught my eye

> 5 The Pentomino Problem
> There are twelve different (ie. non-congruent) pentominos, shown below left. The pentomino problem is to fit them into a tray of dimensions 6 x 10 without overlapping. Some of the 2339 possible solutions are shown below right. Write a program to find a solution to the pentomino problem. {Note. Pretty output is not required.)

![](/images/pentomino-graphic.png)

Looking on [Wikipedia](https://en.wikipedia.org/wiki/Pentomino) it seems that the shapes have been named by [Golomb](https://en.wikipedia.org/wiki/Solomon_W._Golomb) so I’m going to use those names too.

I started out by creating some data structures to hold the definition of each pentomino.

So laying out on a x, y co-ordinate system I’m create a point_t structure containing values

    typedef struct {
            int x, y;
    } point_t;

Any pentomino will have exactly five points

    typedef struct {
            point_t point[5]; /* 5 points in each */
    } pentomino_t;

Considering the ‘F’ pentomino it may be rotated and reflected in different ways – a maximum of 8 different versions may exist. Some, such as ‘X’, only have one.

![](/images/F.svg)

I have created a structure to hold the pentomino name along with a count of the number of unique rotations/reflections of the shape and an array to hold the co-ordinates

    typedef struct {
            char ch; /* name of the shape by letter */
            int count; /* number of unique rotations */
            pentomino_t rotation[8]; /* max of 4 possible rotations and then double for the mirrors */
    } pentominoRotations_t;

The 6×10 board that we will try to place them on is as simple as this

    char board[60];

The algorithm couldn’t be simpler really, take the first pentomino in the first rotation and put it on the board in the top left corner, if that works try the second pentomino in the second position in the first rotation and repeat.  At each step check no parts of any pentomino are outside the board area and that nothing is on top of anything else.  If it is, remove the last piece added and try to add it again in the next rotation.  Based upon the assignment the key here is to recognise that this is a recursive algorithm – in pseudo code it looks like this

    function calculate(pentomino p, board)
            for each position on the board
                    for each pentomino rotation
                            let shape_ok = true
                            for each point in pentomino shape
                                    if the co-ordinate is out of bound then shape_ok = false
                                    if the board position is already used then shape_ok = false
                            next
                            if shape_ok is true then
                                    draw the shape on the current board
                                    if p < 12 then
                                            calculate(p + 1, current board layout)
                                    else
                                            we have a solution!
                    next
            next

Here is the first solution that it generates given the order of shapes as I have them

![](/images/solution-1.svg)

The big problem with this is it takes a very long time!  The main reason for this is that it algorithm wastes masses of time trying to fit all 12 pieces in even when the early piece positions have given a board which can’t possibly be solved.  In the example below there is no point trying to place the other 11 pentominos including all their rotations when there is an isolated single square.

![](/images/F-bad-placement.svg)

My initial solution to this is to add a check after drawing the shape to look for regions which have an area of less than 5.  However this can extended to check for regions that have areas which are not multiples of 5 as clearly all pentominos have an area of 5!

Take a look at the example below.  This has two regions, on the left the area is 13 and on the right the area is 22.  This is can’t be solved as we will never be able to pack objects with an area of 5 into a region of area 13.

![](/images/small-region.svg)

I was quite surprised how easy it was to calculate the area of the regions.  I’ve always thought that the fill/flood tools on paint programs were cool and here we are just doing the same thing.  Here’s some pseudo code to explain it.  I presume I’d get twice the marks for this assignment for having two recursive functions!

    Create a copy of the board
    Loop through all squares on the board
            if the square is empty
                    call the flood function with starting at these co-ordinates
                    if the returned value modulus 5 is not zero then the board cannot be solved

    function flood(start co-ordinates)
            let r = 1 and for that to be the size of the region
            mark the current co-ordinate position as filled
            if the square to the left is empty then call the flood function with those co-ordinates and add the returned value to r
            if the square to the right is empty then call the flood function with those co-ordinates and add the returned value to r
            if the square above is empty then call the flood function with those co-ordinates and add the returned value to r
            if the square below is empty then call the flood function with those co-ordinates and add the returned value to r
            return r

If you let these run to completion you find that you have 9356 solutions – exactly 4 times the number we should.  This is because the board has rotation symmetry and both vertical and horizontal symmetry.  We could check each solution against the ones already created for possible duplicates but we could also amend the algorithm so at the first level we only consider start position in the first quarter of the board.

With this amended algorithm my average computer produced all 2339 solutions in around twenty minutes.
