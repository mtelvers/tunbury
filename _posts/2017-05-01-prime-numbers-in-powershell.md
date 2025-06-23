---
layout: post
title:  "Prime Numbers in PowerShell"
date:   2017-05-01 13:41:29 +0100
categories: powershell
image:
    path: /images/prime-numbers.jpg
    thumbnail: /images/thumbs/prime-numbers.jpg
permalink: /prime-numbers-in-powershell/
---
Dylan was using a number square to calculate prime numbers so it amused me to code up a couple of algorithms to show just how quick the sieve method actually is. I’ve done these in PowerShell because … reasons.

So as a baseline, here’s a basic way to calculate a prime. Start with a number and try to divide it by every number starting from 2 up to the square root of the number. I’ve used `throw` in a `try`/`catch` block to move to the next iteration of the outer loop without executing the `Write-Host` line.

    for ($n = 3; $n -lt 100000; $n++) {
        try {
            for ($d = 2; $d -le [Math]::Sqrt($n); $d++) {
                if ($n % $d -eq 0) {
                    throw
                }
            }
            Write-Host -NoNewLine "$n "
        }
        catch { }
    }

Interestingly, all those exceptions add quite an overhead because this same algorithm using a local variable ran three times quicker on my machine (27 seconds for the first and 9 seconds for this)

    for ($n = 3; $n -lt 100000; $n++) {
        $prime = $true
        for ($d = 2; $d -le [Math]::Sqrt($n); $d++) {
            if ($n % $d -eq 0) {
                $prime = $false
                break;
            }
        }
        if ($prime) {
            Write-Host -NoNewLine "$n "
        }
    }

Obviously we should optimise this by removing even numbers as below and this, as you’d expect, halves the run time.

    for ($n = 3; $n -lt 100000; $n += 2) {
        $prime = $true
        for ($d = 3; $d -le [Math]::Sqrt($n); $d += 2) {
            if ($n % $d -eq 0) {
                $prime = $false
                break;
            }
        }
        if ($prime) {
        }
    }

Anyway, the sieve is all done in 0.75 seconds:

    $ints = 0..100000
    for ($i = 2; $i -lt [Math]::Sqrt($ints.length); $i++) {
        if ($ints[$i] -eq 0) {
            continue
        }
        for ($j = $i * $i; $j -lt $ints.length; $j += $i) {
            $ints[$j] = 0
        }
    }
    $ints | foreach { if ($_) { Write-Host -NoNewLine "$_ " } }

As the maximum number increases the differences become even more stark. At 1,000,000 the sieve completed in 11 seconds but the simple method took 129 seconds

For my timings, I used `measure-command` and removed the `Write-Host` lines.
