---
layout: post
title:  "Mandelbrot Set"
date:   2015-01-19 13:41:29 +0100
categories: perl
usemathjax: true
image:
  path: /images/mandelbrot-set-5.png
  thumbnail: /images/thumbs/mandelbrot-set-5.png
redirect_from:
  - /mandlebrot-set/
---

The Mandelbrot set is created from this very simple formula in which both Z and C are complex numbers.

$$Z_{n+1}=Z_n^2+c$$

The formula is iterated to determine whether Z is bounded or tends to infinity.  To demonstrate this assume a test case where the imaginary part is zero and focus just on the real part.  In this case, the formula is trivial to evaluate starting with Z = 0.  The table below shows the outcome at C=0.2 and C=0.3 and where one is clearly bounded and the other is not!

| **Iteration** | **C = 0.2** | **C = 0.3** |
| ------------- | ----------- | ----------- |
|               | 0           | 0           |
| 1             | 0.2         | 0.3         |
| 2             | 0.24        | 0.39        |
| 3             | 0.2576      | 0.4521      |
| 4             | 0.266358    | 0.504394    |
| 5             | 0.270946    | 0.554414    |
| 6             | 0.273412    | 0.607375    |
| 7             | 0.274754    | 0.668904    |
| 8             | 0.27549     | 0.747432    |
| 9             | 0.275895    | 0.858655    |
| 10            | 0.276118    | 1.037289    |
| 11            | 0.276241    | 1.375968    |
| 12            | 0.276309    | 2.193288    |
| 13            | 0.276347    | 5.110511    |
| 14            | 0.276368    | 26.41732    |
| 15            | 0.276379    | 698.1747    |
| 16            | 0.276385    | 487448.2    |
| 17            | 0.276389    | 2.38E+11    |
| 18            | 0.276391    | 5.65E+22    |

C=0.2 is said to be part of the set where C=0.3 is not.  Typical this point is coloured by some arbitrary function of the number of iterations it took for the modulus of Z to exceed 2.

The set is plotted on the complex number plane with the real part using the x-axis and the imaginary part using the y-axis, thus:

![](/images/complex-plane.svg)

Given that computers don't natively work with complex numbers we need to break the formula down into manageable pieces.  Firstly write the formula including both the real and complex parts then expand the brackets and group the terms.

$$Z_{n+1}=Z_n^2+c$$

$$Z_{n+1}=(Z_{re}+Z_{im}i)^2+c_{re}+c_{im}i$$

$$Z_{n+1}=Z_{re}^2-Z_{im}^2+2Z_{re}Z_{im}i+c_{re}+c_{im}i$$

$$\mathbb R(Z_{n+1})=Z_{re}^2-Z_{im}^2+c_{re}$$

$$\mathbb I(Z_{n+1})=2Z_{re}Z_{im}+c_{im}$$

Here's a Perl program to generate a PNG file.  Over the years I've written this same program in many languages starting with Pascal at school, PostScript at University and Excel VBA and JavaScript...

Here's a Perl program to generate a PNG file.  Over the years I've written this same program in many languages starting with Pascal at school, PostScript at University and [Excel VBA](/downloads/mandelbrot.xlsm) and JavaScript...

    #!/usr/bin/perl -w
    
    use strict;
    use GD;
    
    my $width = 1024;
    my $height = 1024;
    
    GD::Image->trueColor(1);
    my $img = new GD::Image($width, $height);

Focus on an interesting bit. Real should be between -2.5 and 1 and
imaginary between -1 and 1.

    my $MINre = -0.56;
    my $MAXre = -0.55;
    my $MINim = -0.56;
    my $MAXim = -0.55;


Maximum number of iterations before the point is classified as bounded.
I've used 255 because I am using this as the colour component later

    my $max = 255;

Setup the loops to move through all the pixels in the image. The value
of C is calculate from the image size and scale. Note that GD creates
images with the origin in the top left.

    for my $row (1 .. $height) {
        my $Cim = $MINim + ($MAXim - $MINim) * $row / $height;
        for my $col (0 .. $width - 1) {
            my $Cre = $MINre + ($MAXre - $MINre) * $col / $width;

Z starts at the origin

            my $Zre = 0;
            my $Zim = 0;
            my $iteration = 0;

Loop until the modulus of Z \< 2 or the maximum number of iterations
have passed. Note that I've squared both sides to avoid a wasting time
calculating the square root

    while ($Zre * $Zre + $Zim * $Zim <= 4 && $iteration < $max) {

Here's the formula from above to calculate the next value

                my $ZNre = $Zre * $Zre - $Zim * $Zim + $Cre;
                $Zim = 2 * $Zre * $Zim + $Cim;
                $Zre = $ZNre;

Move on to the next iteration

                $iteration++;
            }


Determine why we finished the loop - was it bound or not - and then
colour the pixel appropriately

            if ($iteration < $max) {
                $img->setPixel($col, $height - $row, $iteration * 0x010101);
            } else {
                $img->setPixel($col, $height - $row, 0x00);
            }
        }
    }

Output the PNG file to STDOUT

    binmode STDOUT;
    print $img->png;
