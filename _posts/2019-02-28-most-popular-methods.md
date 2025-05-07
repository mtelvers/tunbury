---
layout: post
title:  "Most Popular Methods"
date:   2019-02-28 13:41:29 +0100
categories: bells bash
image:
  path: /images/bellboard.png
  thumbnail: /images/bellboard.png
---
There are ~72,000 Surprise Major performances on Bell Board. Bell Board displays results in pages of 200 performances. Thus we will need to download all the pages and concatenate them into a single file:

    for i in {1..366}; do wget "https://bb.ringingworld.co.uk/search.php?title=surprise+major&page=$i" -O - >> surprise-major.txt; done

Quick analysis with awk/sed/sort and uniq:

    awk '/class="title"/ { print $3, $4, $5, $6, $7, $8, $9}' surprise-major.txt | sed 's/<\/td>//' | sort | uniq -c | sort -gr | less

As expect the Standard 8 are right there:-

    10732 Yorkshire Surprise Major
     7633 Cambridge Surprise Major
     6908 Bristol Surprise Major
     3629 Superlative Surprise Major
     3425 Lincolnshire Surprise Major
     3048 Rutland Surprise Major
     2716 London Surprise Major
     1556 Pudsey Surprise Major
      957 Glasgow Surprise Major
      931 Lessness Surprise Major
      666 Belfast Surprise Major
      645 Uxbridge Surprise Major
      568 Cornwall Surprise Major

Repeating for the ~3,800 Delight Major performances

    for i in {1..30}; do wget "https://bb.ringingworld.co.uk/search.php?title=delight+major&page=$i" -O - >> delight-major.txt; done
    awk '/class="title"/ { print $3, $4, $5, $6, $7, $8, $9}' delight-major.txt | sed 's/<\/td>//' | sort | uniq -c | sort -gr | less

Gives us these

    141 Cooktown Orchid Delight Major
     36 Christmas Delight Major
     30 Wedding Delight Major
     28 Coniston Bluebird Delight Major
     27 Diamond Delight Major
     26 Ruby Delight Major
     22 Birthday Delight Major
     19 Anniversary Delight Major
     18 Dordrecht Delight Major
     16 Yelling Delight Major
     16 Lye Delight Major
     16 Burnopfield Delight Major
     15 Winchester Delight Major
     15 Hunsdon Delight Major
     13 Uttlesford Delight Major
     13 Magna Carta Delight Major
     12 Sussex Delight Major
     12 Sunderland Delight Major
     12 Sleaford Delight Major
     12 Heptonstall Delight Major
     11 Windy Gyle Delight Major
     11 Spitfire Delight Major
     11 Ketteringham Delight Major
     11 Keele University Delight Major
     11 Ian's Delight Major
     11 Eardisland Delight Major
     11 Dingley Delight Major
     10 West Bridgford Delight Major
     10 Paisley Delight Major
     10 Morville Delight Major
     10 Longstanton Delight Major
     10 Knotty Ash Delight Major

And once again for the 2,200 Delight Minor performances

    for i in {1..12}; do wget "https://bb.ringingworld.co.uk/search.php?title=delight+minor&page=$i" -O - >> delight-minor.txt; done
    awk '/class="title"/ { print $3, $4, $5, $6, $7, $8, $9}' delight-minor.txt | sed 's/<\/td>//' | sort | uniq -c | sort -gr | less

Gives

     85 Woodbine Delight Minor
     78 Old Oxford Delight Minor
     46 Oswald Delight Minor
     41 Elston Delight Minor
     30 College Bob IV Delight Minor
     25 Morning Exercise Delight Minor
     23 Kirkstall Delight Minor
     22 Francis Genius Delight Minor
     20 St Albans Delight Minor
     20 Julie McDonnell Delight Minor
     19 Southwark Delight Minor
     18 Burslem Delight Minor
     18 Barham Delight Minor
     17 Kentish Delight Minor
     17 Darton Exercise Delight Minor
     17 Burnaby Delight Minor
     16 Edinburgh Delight Minor
     15 Disley Delight Minor
     14 Neasden Delight Minor
     14 London Delight Minor
     14 Glastonbury Delight Minor
     14 Bedford Delight Minor
     13 Croome d'Abitot Delight Minor
     13 Christmas Pudding Delight Minor
     13 Charlwood Delight Minor
     12 Wragby Delight Minor
     11 Willesden Delight Minor
     11 Newdigate Delight Minor
     10 Combermere Delight Minor
     10 Cambridge Delight Minor
