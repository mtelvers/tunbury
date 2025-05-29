---
layout: post
title:  "Square Root"
date:   2020-04-19 13:41:29 +0100
categories: maths
usemathjax: true
image:
  path: /images/65000.png
  thumbnail: /images/thumbs/65000.png
---
As a first step in calculating a square root look at the order of magnitude of the number and this will quickly allow the determination of the number of digits in the solution. Consider squaring numbers less than 10; the solutions will be less than 100. Squaring numbers less than 100 gives solutions less than 10,000 and numbers less than 1,000 will square to numbers less than 1,000,000 etc. In general terms the square root of a number with an even number of digits will have half the number of digits as the original number. For numbers with an odd number of digits then the solution will have one more than half the number of digits.

The second point of note is that square root of a number 100 times larger gives a solution 10 times large.

$$10\sqrt{x}=\sqrt{100x}$$

To work through the method, let's consider calculating the square root of 65,000. From the above, we know that the solution will be a three digit number. We can think of the three digit solution as h hundreds, t tens and u units.

$$\sqrt{x}=h+t+u$$

Therefore

$$x=(h+t+u)^2$$

This can be visualised geometrically as a square:

![](/images/square3.svg)

The area of the *hundred* square is the largest *h* which satisfies

$$h^2<65000$$

Trying successive h values

$$200^2=40000$$

$$300^2=90000$$

Therefore *h* is 200

The can be written out using a form of long division

             2  0  0
            +-------
            |6 50 00
    200x200  4 00 00
             -------
             2 50 00

![](/images/square2.svg)

Now looking at the geometric representation we can write down the area of the *hundred* square and the two rectangles of sides *h* and *t* and a square with sides *t* as being less than the total area. This can be shown in this formula:

$$x>h^2+2ht+t^2$$

Substituting for *h* and rearranging:

$$65000-40000>2(200t)+t^2$$

$$25000>t(400+t)$$

Since *t* is a tens number, we are looking for the largest value which satisfies

$$25000>4\_0\times \_0$$

Trying possible numbers

$$440\times 40=17600$$

$$450\times 50=22500$$

$$460\times 60=27600$$

Therefore, *t* is 50

             2  5  0
            +-------
            |6 50 00
    200x200  4 00 00
             -------
             2 50 00
    450x50   2 25 00
             -------
               25 00

![](/images/sqaure.svg)

Returning to the geometric representation we can write down the area of the *hundred* square and the two rectangles of sides *h* and *t* the tens square as above and additionally include the two rectangles of sides *h + t* by *u* and the *units* square. This can be shown in this formula:

$$x>h^2+2ht+t^2+2(h+t)u+u^2$$

The first part of the formula is the same as above so the values are already known and additionally substituting for *h* and *t*:

$$65000>40000+22500+2(200+50)u+u^2$$

$$2500>u(500+u)$$

Since *u* is a units number, we are looking for the largest value which satisfies

$$2500>50\_\times \_$$

Trying possible numbers

$$503\times 3=1509$$

$$504\times 4=2016$$

$$505\times 5=2525$$

Therefore, *u* is 4

              2  5  4
             +-------
             |6 50 00
    200x200   4 00 00
              -------
              2 50 00
    450x50    2 25 00
              -------
                25 00
    504x4       20 16
                -----
                 4 84

We could extend this into fractions where f is 1/10:


$$x>h^2+2ht+t^2+2(h+t)u+u^2+2(h+t+u)f+f^2$$

However, this is unnecessary because realising that at each step we are using double the current solution it is evident that:

$$254\times 2=508$$

$$508.\_\times 0.\_$$

              2  5  4. 9
             +----------
             |6 50 00.00
    200x200   4 00 00.00
              ----------
              2 50 00.00
    450x50    2 25 00.00
              ----------
                25 00.00
    504x4       20 16.00
                --------
                 4 84.00
    508.9x0.9    4 58.01
                 -------
                   25.99

And once again, solving for:

$$254.9\times 2=509.8$$

$$509.8\_\times 0.0\_$$

              2  5  4. 9  5
             +-------------
             |6 50 00.00 00
    200x200   4 00 00.00 00
              -------------
              2 50 00.00 00
    450x50    2 25 00.00 00
              -------------
                25 00.00 00
    504x4       20 16.00 00
                -----------
                 4 84.00 00
    508.9x0.9    4 58.01 00
                 ----------
                   25.99 00
    509.85x0.05    25.49 25
                   --------
                     .49 75
