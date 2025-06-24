---
layout: post
title:  "Which Funds Have Exposure to NetFlix?"
date:   2018-08-27 13:41:29 +0100
categories: powershell
image:
  path: /images/hl_hi_res.gif
  thumbnail: /images/thumbs/hl_hi_res.gif
redirect_from:
  - /which-funds-have-exposure-to-netflix/
---
Dabbling in the markets by way of investment funds is amusing. I use [Hargreaves Lansdown](www.hl.co.uk) to do this. HL have a fund research section which lets you look at a given fund and view the top 10 holdings so you can base your decision to invest in your belief in the underlying stock.

How do you tackle it from the other direction? Suppose you want to invest in NetFlix but which fund(s) has expose to their stock? The search tool on HL’s website doesn’t let you search the fund’s holdings.

Firstly, we can get a list of funds starting with `a` by visiting the link https://www.hl.co.uk/funds/fund-discounts,-prices–and–factsheets/search-results/a. There are 25 more to go plus 0 for anything starting with a number. These pages are HTML unordered lists `ul`, of hyperlinks `href`. We can get the alphabet as an array in a tidy loop such as this `foreach ($l in [char[]]([char]'a'..[char]'z') + '0') { }` (assuming ASCII)

We can download the HTML using PowerShell's `Invoke-WebRequest` and then extra tags using `getElementsByTagName` however it can be desperately slow in some circumstances so I prefer to just get the HTML as a string using `$_.RawContent` then processing it with `IndexOf()`.

The code, and basically the methodology for the rest of this script, is show as below:

    $baseURL = "https://www.hl.co.uk/funds/fund-discounts,-prices--and--factsheets/search-results"
    $html = $(Invoke-WebRequest -uri "$baseURL/a").RawContent
    $x1 = $html.IndexOf('<ul class="list-unstyled list-indent"')
    $x1 = $html.IndexOf('>', $x1) + 1
    $x2 = $html.IndexOf('</ul', $x1)
    $tbl = $html.substring($x1, $x2 - $x1).trim()

Search the HTML for the start of the `ul` tag and save it in `$x1`. As tags can be of variable length we move `$x1` to the end of the tag by searching for the close tag marker `>` and adding 1. Now, just search for the end of the list by looking for the `</ul` tag and store that in `$x2`. The table can now be extracted as the sub string between `$x1` and `$x2`.

Each list item `li`, contains a hyperlink tag `<a href=` including the URL of the page with the fund details and the the fund name. We can use a `for` loop to move through the string and build up an array of fund URLs. Back tick is the escape character in PowerShell.

    $funds = @()
    for ($x1 = $tbl.IndexOf("href="); $x1 -ge 0; $x1 = $tbl.IndexOf("href=", $x2)) {
        $x1 = $tbl.IndexOf('"', $x1) + 1   # x1 is the start of the string
        $x2 = $tbl.IndexOf('"', $x1)       # x2 is the end of the string
        $funds += $tbl.Substring($x1, $x2 - $x1)
    }

At this point we can examine our funds in `$funds`, or perhaps write then to a CSV: `$funds | Export-Csv funds.csv`.

What we really want is the list of holdings for each funds. So using the techniques above, download the HTML for each fund detail page, extract the fund size where it appears on the page. Then locate the Top 10 holdings table and build a PowerShell object based upon the table headings and populate the values:

    $holdings = @()
    for ($f = 0; $f -lt $funds.count; $f++) {
        $html = $(Invoke-WebRequest -uri $funds[$f]).RawContent
        if ($html.IndexOf("Factsheet unavailable") -ge 0 -or
            $html.IndexOf("Market data not available") -ge 0 -or
            $html.IndexOf("holdings currently unavailable") -ge 0) {
            Write-Host -ForegroundColor Red $f $funds[$f].substring($baseURL.length) "- unavailable"
            continue
        }

        $x1 = $html.IndexOf('Fund size')
        $x1 = $html.IndexOf('<td', $x1)
        $x1 = $html.IndexOf(">", $x1) + 1
        $x2 = $html.IndexOf('</td', $x1)
        $fundSize = $html.Substring($x1, $x2 - $x1).trim()
        $fundSize = $fundSize -replace "&pound;", "GBP "
        $fundSize = $fundSize -replace "&euro;", "EUR "
        $fundSize = $fundSize -replace "\$", "USD "

        $x1 = $html.IndexOf('<table class="factsheet-table" summary="Top 10 holdings"')
        $x1 = $html.IndexOf('>', $x1) + 1
        $x2 = $html.IndexOf('</table>', $x1)
        $tbl = $html.substring($x1, $x2 - $x1).trim()

        $headings = @()
        for ($x1 = $tbl.IndexOf('<th', 1); $x1 -gt 0; $x1 = $tbl.IndexOf('<th', $x2)) {
            $x1 = $tbl.IndexOf(">", $x1) + 1
            $x2 = $tbl.IndexOf("</th>", $x1)
            $headings += $tbl.Substring($x1, $x2 - $x1)
        }

        if ($headings.count -eq 0) {
            Write-Host -ForegroundColor Red $f $funds[$f].substring($baseURL.length) "- no table"
            continue
        }

        $i = 0
        for ($x1 = $tbl.IndexOf('<td'); $x1 -gt 0; $x1 = $tbl.IndexOf('<td', $x2)) {
            if ($i % $headings.count -eq 0) {
                $h = New-Object -TypeName PSObject -Property @{Fund=$funds[$f].substring($baseURL.length);Size=$fundSize}
            }
            $x1 = $tbl.IndexOf(">", $x1) + 1
            $x2 = $tbl.IndexOf("</td", $x1)
            $cell = $tbl.Substring($x1, $x2 - $x1).trim()
            if ($cell.Substring(0, 1) -eq '<') {
                $x1 = $tbl.IndexOf(">", $x1) + 1
                $x2 = $tbl.IndexOf("</a", $x1)
                $cell = $tbl.Substring($x1, $x2 - $x1).trim()
            }
            Add-Member -InputObject $h -MemberType NoteProperty -Name $headings[$i % $headings.count] -Value $cell
            $i++
            if ($i % $headings.count -eq 0) {
                $holdings += $h
            }
        }
        Write-Host $f $funds[$f].substring($baseURL.length) $fundSize ($i / 2) "holdings"
    }

As I mentioned, most of the code is as explained before but the PowerShell object bit deserves a mention. I use an iterator `$i` to count the cells in the table (note this assumes that the table has equal number of cells per row which isn’t necessarily true in HTML). We have two column headings, so `$i % $headings.count -eq 0` is true for 0, 2, 4 etc and this happens at the start of the loop so we use it to create the object.

Once we have the cells content, we can use `Add-Member` to add the property to the object. The property name is given by `$headings[$i % $headings.count]`: either zero or one in this case.

At the end of the loop we increment `$i` and test whether it we are now on the next row `$i % $headings.count -eq 0` and if so add the current object to the output array (as it will be overwritten at the start of the next iteration of the loop).

After all that work lets save the results as a CSV: `$holdings | Export-Csv holdings.csv`

We now know the percentages of each holding and the total fund value so we can calculate a new column with the monetary value invested in a fund as follows:

    $holdings |% {
        [decimal]$w = $_.weight -replace '[^\d.]'
        [decimal]$s = $_.size -replace '[^\d.]'
        Add-Member -InputObject $_ -MemberType NoteProperty -Name Value -Value ($w * $s / 100) -Force
    }

Perhaps save it again? `$holdings | Export-Csv -Force holdings.csv`

    import-csv .\holdings.csv |? Security -match "Netflix" | sort -Property Value

The full code can be downloaded from [GitHub](https://github.com/mtelvers/Hargreaves-Lansdown/blob/master/fund-holdings.ps1) or probably more usefully you can get [holdings.csv](https://raw.githubusercontent.com/mtelvers/Hargreaves-Lansdown/master/holdings.csv)

Addendum
========

To make the analysis easier it would help to standardise the currencies. Most are in GBP by some margin so let’s convert to that:-

    $ExchangeRates = @{GBP = 1; YEN = 0.00698098; EUR = 0.905805; USD = 0.776454; AUSD = 0.567308}

    $holdings |% {
        [decimal]$s = $_.size -replace '[^\d.]'
        [decimal]$w = $_.weight -replace '[^\d.]'
        if ($s -gt 0) {
            $currency = $_.size.substring(0, $_.size.IndexOf(" "))
            $sGBP = $s * $ExchangeRates[$currency]
        } else {
            $sGBP = 0
        }
        Add-Member -InputObject $_ -MemberType NoteProperty -Name SizeGBP -Value $sGBP -Force
        Add-Member -InputObject $_ -MemberType NoteProperty -Name ValueGBP -Value ($w * $sGBP / 100) -Force
    }
