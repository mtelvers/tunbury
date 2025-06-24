---
layout: post
title:  "Arduino PWM Train Controller"
date:   2025-01-18 16:15:00 +0100
categories: 3d-printing
tags: tunbury.org
image:
  path: /images/train-controller-photo.png
  thumbnail: /images/thumbs/train-controller-photo.png
redirect_from:
  - /arduino-pwm-train-controller/
---

# Circuit

![](/images/train-controller-diagram.png)

# Case

3D printable STL files are available for download: [STL files](/images/train-controller.stl)

![](/images/train-controller-fusion-360.png)

# Arduino Code

```
/*
 * Arduino Nano PWM Dual Train Controller
 * This sketch reads values from two potentiometers connected to A0 and A1
 * and uses these values to control the speed and direction of a motor via
 * an L298N motor driver. The motor speed is controlled using PWM signals
 * on pins D5 and D10, and the direction is controlled using digital signals
 * on pins D6, D7, D8, and D9.
 */

// Pin definitions
const int potLeftPin = A0;
const int potRightPin = A1;
const int enaPin = 10;
const int in1Pin = 9;
const int in2Pin = 8;
const int in3Pin = 7;
const int in4Pin = 6;
const int enbPin = 5;

void setup() {
  // Initialize serial communication
  Serial.begin(9600);

  // Set motor control pins as outputs
  pinMode(enbPin, OUTPUT);
  pinMode(enaPin, OUTPUT);
  pinMode(in1Pin, OUTPUT);
  pinMode(in2Pin, OUTPUT);
  pinMode(in3Pin, OUTPUT);
  pinMode(in4Pin, OUTPUT);
}

void loop() {
  // Read potentiometer values
  int potLeft = analogRead(potLeftPin);
  int potRight = analogRead(potRightPin);

  // Map potentiometer values to PWM range
  int pwmLeft = pow(potLeft - 512, 2) / 1024;
  int pwmRight = pow(potRight - 512, 2) / 1024;

  // Control motor speed and direction
  analogWrite(enaPin, pwmLeft);
  analogWrite(enbPin, pwmRight);

  // Set motor direction based on potentiometer values
  if (potLeft < 512) {
    digitalWrite(in1Pin, LOW);
    digitalWrite(in2Pin, HIGH);
  } else {
    digitalWrite(in1Pin, HIGH);
    digitalWrite(in2Pin, LOW);
  }

  if (potRight < 512) {
    digitalWrite(in3Pin, LOW);
    digitalWrite(in4Pin, HIGH);
  } else {
    digitalWrite(in3Pin, HIGH);
    digitalWrite(in4Pin, LOW);
  }

  // Print values to serial monitor for debugging
  Serial.print("potLeft: ");
  Serial.print(potLeft);
  Serial.print(" PWMLeft: ");
  Serial.print(pwmLeft);
  Serial.print(" potRight: ");
  Serial.print(potRight);
  Serial.print(" PWMRight: ");
  Serial.println(pwmRight);

  // Small delay to stabilize readings
  delay(100);
}
```
