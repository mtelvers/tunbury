---
layout: post
title:  "Narcissistic Numbers"
date:   2014-01-02 13:41:29 +0100
categories: perl
usemathjax: true
redirect_from:
  - /narcissistic-numbers/
---

I heard about these on [BBC Radio 4 More or
Less](http://www.bbc.co.uk/programmes/b006qshd) and they just intrigued
me, perhaps in part because they have no known application! In the past
similar obsessions have appeared with the calculation of PI and right
back to my childhood calculating powers of 2 on a BBC Micro.

The full definition, as for everything, is on
[Wikipedia](https://en.wikipedia.org/wiki/Narcissistic_number) but in
short a narcissistic number is one where the sum of the digits raised to
the power of the number of digits equals the number itself. For example

$$153 = 1^3 + 5^3 + 3^3$$

Here’s some quick and dirty Perl code to calculate them:

    use strict;
    use warnings;
    
    for (my $i = 10; $i < 10000; $i++) {
        my $pwr = length($i);
        my $total = 0;
        for (my $j = 0; $j < $pwr; $j++) {
            $total += int(substr $i, $j, 1) ** $pwr;
        }
        if ($total == $i) {
            print $i . " is narcissistic\n";
        }
    }

This yields this output

    153 is narcissistic
    370 is narcissistic
    371 is narcissistic
    407 is narcissistic
    1634 is narcissistic
    8208 is narcissistic
    9474 is narcissistic

However, due to the typical limitation in the implementation of integers
this doesn’t get you very far. Perl’s `Math::BigInt` gets you further if
you are very patient

    use strict;
    use warnings;
    use Math::BigInt;
    
    my $i = Math::BigInt->bone();
    
    while ((my $pwr = $i->length()) < 10) {
        my $total = Math::BigInt->bzero;
        for (my $j = 0; $j < $pwr; $j++) {
            my $t = Math::BigInt->new($i->digit($j));
            $total->badd($t->bpow($pwr));
        }
        if ($total == $i) {
            print $i . " is narcissistic\n";
        }
        $i->binc();
    }

