---
layout: post
title:  "Arduino Gas Sensor"
date:   2021-08-29 20:41:29 +0100
categories: arduino
image:
  path: /images/gas-sensor.jpg
  thumbnail: /images/thumbs/gas-sensor.jpg
redirect_from:
  - /arduino-gas-sensor/
---
With the current emphasis on ventilation to reduce the risks associated with inhaled droplets it I have put together a simple gas sensor to record concentrations over time.  The output is a `CSV` file which can be graphed in Excel.

I have used an Arduino Nano for this project which gave some serious memory constraints on the coding particularly as I needed libraries for the real time clock, SD card and OLED display.

The modules used are:
* [Arduino Nano](https://www.amazon.co.uk/dp/B072BMYZ18/ref=cm_sw_em_r_mt_dp_dl_WPWV0XM72DEW1A4HBDGE?_encoding=UTF8&psc=1)
* [DS3231 Real time clock](https://www.amazon.co.uk/dp/B07BRFL7V7/ref=cm_sw_em_r_mt_dp_K5YWV6VZJJRT1D4WF9VJ?_encoding=UTF8&psc=1)
* [SSD1306 OLED display](https://www.amazon.co.uk/dp/B01L9GC470/ref=cm_sw_em_r_mt_dp_QQ8BPJQJP4G62QVRSNS3)
* [SD card reader](https://www.amazon.co.uk/dp/B077MB17JB/ref=cm_sw_em_r_mt_dp_WYZQY0ZZKJRPV83WH8R3)
* [Gas sensor](https://www.amazon.co.uk/dp/B07CYYB82F/ref=cm_sw_em_r_mt_dp_9S4XZ9QD8NBH1V6M7HV5)

## Hardware Connections

I used a veroboard to assemble the circuit as follows
1. Scatter the modules around the board and solder all VCC and GND pins
2. On the Arduino Nano, pins A4 and A5 are used for the Inter-Integrated Circuit (I2C) bus
    * Connect SDA (A4 on Nano) to the display and clock module's SDA pin
    * Connect SCL (A5 on Nano) to the display and clock module's SCL pin

> At this point, the clock and display module can be tested and the time set on the clock.

3. Connect the A0 output from the gas sensor to the A0 pin on the Arduino

> Reading from A0 returns an integer between 0 and 1023 representing a gas concentration between 200 - 10000 ppm

4. The SD card using the Serial Peripheral Interface (SPI) and requires 4 connections
    * Nano D10 to CS on the SD card module
    * Nano D11 to MOSI on the SD card module
    * Nano D12 to MISO on the SD card module
    * Nano D13 to SCK on the SD card module

With the wiring complete load the Arduino sketch from my [GitHub page](https://github.com/mtelvers/Arduino-MQ2/blob/113a2348ce65966b738dc55d9ddace36824ec49f/mq2.ino).

## Software Overview

After the basic library initialization, the code creates two 64 elements arrays to store the samples taken each second and the average of those samples calculated each minute.  These arrays will hold the latest sample in the first position, therefore before a new value is added all the other values will be shifted down by one.  There certainly would be more efficient ways of handing this but with a small number of values this is simple approach is workable.

    #define SAMPLES 64
    uint16_t historySeconds[SAMPLES];
    uint16_t historyMinutes[SAMPLES];

The *main* loop of the program checks remembers the number of seconds on the clock in the variable `lastS` and waits for it to be different thus running the inner code once per second:

    int lastS = -1;

    void loop(void) {
      DateTime dt = RTClib::now();

      if (lastS != dt.second()) {
        lastS = dt.second();

      // Inner code here runs once each second

      }
      delay(250);
    }

The inner code clears the display, 

    u8x8.clear();
    u8x8.setCursor(0, 0);

and then writes the date

    toString(tmp, dt.year() - 2000, dt.month(), dt.day(), '-');
    u8x8.println(tmp);
    
If the time has just rolled over to a new minute (i.e. number of seconds is 0), take an average of the *seconds* samples and store that as the minute average.  Finally, open a file named with the current date.

    if (dt.second() == 0) {
      unsigned long total = 0;
      for (int h = 0; h < SAMPLES; h++)
        total += historySeconds[h];
      memmove(historyMinutes + 1, historyMinutes, (SAMPLES - 1) * sizeof(uint16_t));
      historyMinutes[0] = total / SAMPLES;
      strcat(tmp, ".csv");
      txtFile = SD.open(tmp, FILE_WRITE);
    }
    
Read the next gas value and store it

    uint16_t gasVal = analogRead(0);
    memmove(historySeconds + 1, historySeconds, (SAMPLES - 1) * sizeof(uint16_t));
    historySeconds[0] = gasVal;

Display the current time

    toString(tmp, dt.hour(), dt.minute(), dt.second(), ':');
    u8x8.println(tmp);
    
If there's a file open, write the time to value to the file 

    if (txtFile) {
      strcat(tmp, ",");
      txtFile.print(tmp);
    }

Display the gas value

    itoa(gasVal, tmp, 10);
    u8x8.println(tmp);
    
And similarly, if there is a file open, write the current value to the file and close it

    if (txtFile) {
      txtFile.println(tmp);
      txtFile.close();
    }

Lastly, draw two graphs of the current samples

    drawGraph(8, 3, historySeconds);
    drawGraph(8, 7, historyMinutes);

The graphs were tricky to draw as the slimmed down U8x8 version of the [U8g2](https://github.com/olikraus/u8g2) library doesn't provide any drawing functions.  However you can create and display a custom font glyph.  This mess of nested loops creates thirty-two 8 by 8 pixel glyphs to display a bar graph of 64 values with a maximum *y* value of 32.

    void drawGraph(uint8_t col, uint8_t row, uint16_t *values) {
      uint8_t tmp[8];
      for (uint8_t r = 0; r < 4; r++) {
        for (uint8_t h = 0; h < SAMPLES; h += 8) {
          for (uint8_t i = 0; i < 8; i++) {
            int x = values[SAMPLES - h - 1 - i] / 16;
            x -= 8 * r;
            tmp[i] = 0;
            for (uint8_t b = 0; b < 8 && x > 0; b++, x--) {
              if (x) {
                tmp[i] |= (1 << (7 - b));
              }
            }
          }
          u8x8.drawTile(col + h / 8, row - r, 1, tmp);
        }
      }
    }

The graph below shows the recording during morning ringing and during the quarter peal in the afternoon (plus some messing around blowing directly into the sensor at the end).  Windows open as usual!

![Graph](/images/sample-values-recorded.png)

