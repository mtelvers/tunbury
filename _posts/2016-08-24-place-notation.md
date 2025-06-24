---
layout: post
title:  "Place Notation"
date:   2016-08-24 13:41:29 +0100
categories: perl bells
redirect_from:
  - /place-notation/
---
Thomas Barlow has taught me place notation using [Strike Back Surprise Major](/downloads/Strike-Back-Surprise-Major.pdf) as the example. The notation for that is `x38x14x58x16x12x38x14.12.78 l.e. 12`. There are plenty of guides online on how to interpret it, such as this one on the [CCCBR website](http://www.cccbr.org.uk/education/thelearningcurve/pdfs/200404.pdf).

Briefly an x in the notation causes all bells to swap places. A group of numbers indicates that the bells in these places remain fixed while all others swap places. In this example, giving a starting order of rounds: 12345678 the first x would yield 21436587. The subsequent 38 indicates that the 3rd placed and 8th placed bells are fixed, so bells in position 1 and 2 swap as do 4 and 5 and 6 and 7 resulting in 12463857 and so on. As many methods are symmetrical, typically only half is written out. The second half is the reverse of the first with the given lead end appended.

My attempt to write out [Ajax Surprise Major](/downloads/Ajax-Surprise-Major.pdf) `x58x14x56x16x14x1258x12x58,12` by hand went wrong in the early stages so I turned to Perl to do the job for me.

The first part of the script parses the place notation into an array, unwraps the symmetry and tags on the lead end. I don’t much like parsers as they tend to be messy as they have to deal with the real world, so moving swiftly on to the core of the script with the assumption that the place notation of the method is held in the array `@method`.

    x 58 x 14 x 56 x 16 x 14 x 1258 x 12 x 58 x 12 x 1258 x 14 x 16 x 56 x 14 x 58 x 12

Define `@rounds` to be rounds and then set the current bell arrangement to be rounds!

    my @rounds = (1..$stage);
    my @bells = @rounds;
    do {

Loop through each of the elements in the method (`@method`)

        foreach my $m (@method) {

`$stage` is the number of bells involved in the method. Our examples have all been *major* methods so `$stage` is 8. Perl arrays are inconveniently numbered from zero so we actually want number 0 through 7 so I’ve used pop to remove the last one

            my @changes = (0..$stage);
            pop @changes;

If the current step contains bell places (noting that 0 = 10, E = 11, T = 12) we split up the string into an array which we process in *reverse* order (to preserve the position numbering) and we remove these numbers from the array of changes.  The function numeric returns the integer value from the character (T=12 etc).

            if ($m =~ /[0-9ET]*/) {
                my @fixed = split //, $m;
                while (@fixed) {
                    splice @changes, numeric(pop @fixed) - 1, 1;
                }
            }

For example, taking `$m` to be `1258` then `@changes` and `@fixed` will iterate as shown. Note the annoying -1 to align the bell position to the array index

| Iteration | `@changes`      | `@fixed` |
| --------- | --------------- | -------- |
|           | 0 1 2 3 4 5 6 7 | 1 2 5 8  |
| 1         | 0 1 2 3 4 5 6   | 1 2	5    |
| 2         | 0 1 2 3 5 6     | 1 2      |
| 3         | 0 2 3 5 6       | 1        |
| 4         | 2 3 5 6         |          |
					
The resulting array `@changes` contains the pairs of bell place indices which need to be swapped. Changes need to be made in order working up to the back as place notation can omit implied changes. For example 18 could be shortened to just 1 as by the time 2nd and 3rd, 4th and 5th, 6th and 7th have all swapped, 8th place must be fixed.

            while (@changes) {
                my ($swap1, $swap2) = splice @changes, 0, 2;
                @bells[$swap1, $swap2] = @bells[$swap2, $swap1];
                last if (scalar @changes < 2);
            }

Now we need to output the current arrangement which at this point will just be a print statement.

            print "@bells\n";
        }

Keep going until we are back in rounds.

    } while (not @bells ~~ @rounds);

Now that that is working the natural desire is to produce beautiful output. Since I was coding in Perl and ultimately I’d like a webpage out of this I experimented using Perl’s GD::Graph library to draw a line graph of the place of each bell. GD::Graph can display the point value on the graph which was used to show the bell number. The output was functional although far from high resolution. The font of the point values cannot be controlled.  See Bob Doubles output below

![](/images/bob-doubles.png)

Since the GD::Graph output wasn’t great, I’ve coded a version which creates the output using SVG.  Have a go:

{% include place-notation.html %} 
