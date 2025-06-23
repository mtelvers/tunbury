---
layout: post
title:  "Import Text File of events into Apple Calendar using AppleScript"
date:   2020-02-06 13:41:29 +0100
categories: applescript
permalink: /import-text-file-of-events-into-apple-calendar-using-applescript/
---
The Church of England has a very useful [calendar](https://www.churchofengland.org/prayer-and-worship/worship-texts-and-resources/common-worship/prayer-and-worship/worship-texts-and-resources/common-worship/churchs-year/calendar) page, but I’d really like it in my iPhone calendar so I can have reminders for Saints’ days particularly red letter days when the flag goes up.

I’ve never used AppleScript before but with a little searching online it seemed relatively easy to create a script to import a text file copy of the web page into my Mac calendar which is synchronised with my phone.

    set OldDelimiters to AppleScript's text item delimiters
    set LF to ASCII character 10
    set tab to ASCII character 9
    set theFile to choose file with prompt "Select TAB delimited file calendar file"
    set theLines to read theFile
    set AppleScript's text item delimiters to {LF}
    set theLines to paragraphs of theLines
    set AppleScript's text item delimiters to {tab}
    repeat with ThisLine in theLines
    if (count of ThisLine) > 0 then
    set theStartDate to current date
    set hours of theStartDate to 0
    set minutes of theStartDate to 0
    set seconds of theStartDate to 0
    
    if text item 1 of ThisLine is not "0" then
    set year of theStartDate to text item 1 of ThisLine as number
    end if
    
    if text item 2 of ThisLine is equal to "January" then
    set month of theStartDate to 1
    else if text item 2 of ThisLine is equal to "February" then
    set month of theStartDate to 2
    else if text item 2 of ThisLine is equal to "March" then
    set month of theStartDate to 3
    else if text item 2 of ThisLine is equal to "April" then
    set month of theStartDate to 4
    else if text item 2 of ThisLine is equal to "May" then
    set month of theStartDate to 5
    else if text item 2 of ThisLine is equal to "June" then
    set month of theStartDate to 6
    else if text item 2 of ThisLine is equal to "July" then
    set month of theStartDate to 7
    else if text item 2 of ThisLine is equal to "August" then
    set month of theStartDate to 8
    else if text item 2 of ThisLine is equal to "September" then
    set month of theStartDate to 9
    else if text item 2 of ThisLine is equal to "October" then
    set month of theStartDate to 10
    else if text item 2 of ThisLine is equal to "November" then
    set month of theStartDate to 11
    else if text item 2 of ThisLine is equal to "December" then
    set month of theStartDate to 12
    else
    log text item 2 of ThisLine
    end if
    
    set day of theStartDate to text item 3 of ThisLine
    
    set theEndDate to theStartDate + (23 * hours)
    
    log theStartDate
    
    tell application "Calendar"
    if text item 5 of ThisLine is "RED" then
    tell calendar "CofE RED"
    if text item 1 of ThisLine is not "0" then
    set newEvent to make new event with properties {summary:text item 4 of ThisLine, start date:theStartDate, end date:theEndDate, allday event:true}
    else
    set newEvent to make new event with properties {summary:text item 4 of ThisLine, start date:theStartDate, end date:theEndDate, allday event:true, recurrence:"freq=Yearly"}
    end if
    end tell
    else
    tell calendar "CofE"
    if text item 1 of ThisLine is not "0" then
    set newEvent to make new event with properties {summary:text item 4 of ThisLine, start date:theStartDate, end date:theEndDate, allday event:true}
    else
    set newEvent to make new event with properties {summary:text item 4 of ThisLine, start date:theStartDate, end date:theEndDate, allday event:true, recurrence:"freq=Yearly"}
    end if
    end tell
    end if
    end tell
    
    end if
    
    end repeat
 
    set AppleScript's text item delimiters to OldDelimiters

[cofe-calendar](/downloads/cofe-calendar.txt)
