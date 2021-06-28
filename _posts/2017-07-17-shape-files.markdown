---
layout: post
title:  "Shape Files"
date:   2015-01-19 13:41:29 +0100
categories: perl
usemathjax: true
image:
  path: /images/roadnode.png
  thumbnail: /images/roadnode.png
---
Below is a perl script to create a PNG from a Shape file.

[Shape file specification](/downloads/shapefile.pdf)

[UK Road network as a shape file ](/downloads/ROADNODE.zip)

    use strict;
    use warnings;

    use GD;
    GD::Image->trueColor(1);

    my $width = 8 * 1024;
    my $height = 8 * 1024;

    my $shpfile = $ARGV[0];
    open(FH, "<$shpfile") or die("No input file\n");
    binmode(FH); 

    my $csvfile = $shpfile;
    $csvfile =~ s/.shp$/.csv/g;
    open(POLYOUT, ">$csvfile");

    my $buffer;
    my $num_bytes = read(FH, $buffer, 100);
    my ($code, $u1, $u2, $u3, $u4, $u5, $filelength, $version, $type, $BBminX, $BBminY, $BBmaxX, $BBmaxY, $BBminZ, $BBmaxZ, $BBminM, $BBmaxM) = unpack("N N N N N N N V V F F F F F F F F", $buffer);
    print "code = $code\n";
    print "filelength = $filelength\n";
    print "version = $version\n";
    print "minX = $BBminX\n";
    print "minY = $BBminY\n";
    print "maxX = $BBmaxX\n";
    print "maxY = $BBmaxY\n";
    print "minZ = $BBminZ\n";
    print "maxZ = $BBmaxZ\n";
    print "minM = $BBminM\n";
    print "maxM = $BBmaxM\n";

    sub mapx {
        my $x = shift;
        return ($x - $BBminX) / ($BBmaxX - $BBminX) * $width;
    }

    sub mapy {
        my $y = shift;
        return $height - ($y - $BBminY) / ($BBmaxY - $BBminY) * $height;
    }

    my $polyCount = 0;

    my $img = new GD::Image($width, $height);

    while (read(FH, $buffer, 12)) {
        my ($recordnumber, $recordlength, $shapetype) = unpack("N N V", $buffer);
        if ($shapetype == 5) {
            # Polygon
            read(FH, $buffer, 4 * 8 + 2 * 4);
            my ($minX, $minY, $maxX, $maxY, $NumParts, $NumPoints) = unpack("F F F F V V", $buffer);
            my @parts;
            foreach my $part (1 .. $NumParts) {
                read(FH, $buffer, 4);
                my ($part) = unpack("V", $buffer);
                push @parts, $part;
                #syswrite(SHPOUT, pack("V", $part), 4);
            }
            push @parts, $NumPoints;
            @parts = reverse @parts;
            while (@parts) {
                my $firstpoint = pop @parts;
                my $lastpoint = pop @parts;
                my $poly = new GD::Polygon;
                $polyCount++;
                foreach ($firstpoint .. $lastpoint - 1) {
                    read(FH, $buffer, 16);
                    my ($x, $y) = unpack("F F", $buffer);
                    print POLYOUT "$x,$y,$polyCount\n";
                    $poly->addPt(mapx($x), mapy($y));
                }
                $img->openPolygon($poly, 0xff0000);
                push @parts, $lastpoint if (@parts);
            }
        } elsif ($shapetype == 3) {
            # PolyLine
            read(FH, $buffer, 4 * 8 + 2 * 4);
            my ($minX, $minY, $maxX, $maxY, $NumParts, $NumPoints) = unpack("F F F F V V", $buffer);
            my @parts;
            foreach my $part (1 .. $NumParts) {
                read(FH, $buffer, 4);
                my ($part) = unpack("V", $buffer);
                push @parts, $part;
            }
            push @parts, $NumPoints;
            @parts = reverse @parts;
            while (@parts) {
                my $firstpoint = pop @parts;
                my $lastpoint = pop @parts;
                read(FH, $buffer, 16);
                my ($x1, $y1) = unpack("F F", $buffer);
                print POLYOUT "$x1,$y1\n";
                foreach ($firstpoint .. $lastpoint - 2) {
                    read(FH, $buffer, 16);
                    my ($x2, $y2) = unpack("F F", $buffer);
                    print POLYOUT "$x2,$y2\n";
                    $img->line(mapx($x1), mapy($y1), mapx($x2), mapy($y2), 0xff0000);
                    $x1 = $x2;
                    $y1 = $y2;
                }
                push @parts, $lastpoint if (@parts);
            }

        } elsif ($shapetype == 1) {
            read(FH, $buffer, 2 * 8);
            my ($x, $y) = unpack("F F", $buffer);
            $img->setPixel(mapx($x), mapy($y), 0xff0000);
            print POLYOUT "$x,$y\n";
        } else {
            print "unhandled type shapetype = $shapetype\n";
            read(FH, $buffer, $recordlength * 2 - 4);
        }
    }

    close(POLYOUT);

    my $pngfile = $shpfile;
    $pngfile =~ s/.shp$/.png/g;
    open(PNGOUT, ">$pngfile");
    binmode(PNGOUT);
    print PNGOUT $img->png;
    close(PNGOUT);