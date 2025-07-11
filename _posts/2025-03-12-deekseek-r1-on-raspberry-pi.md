---
layout: post
title:  "Deepseek R1 on a Raspberry Pi"
date:   2025-03-12 21:15:00 +0100
categories: raspberry-pi
tags: tunbury.org
image:
  path: /images/pi5.jpg
  thumbnail: /images/thumbs/pi5.jpg
redirect_from:
  - /deekseek-r1-on-raspberry-pi/
---

I've heard a lot about Deepseek and wanted to try it for myself.

Using a Raspberry Pi 5 with 8GB of RAM and an NVMe, I installed Ollama:

```shell
curl -fsSL https://ollama.com/install.sh | sh
```

Next, I downloaded the smallest Deepseek model

```shell
ollama pull deepseek-r1:1.5b
```

And ran it using:

```shell
ollama run deepseek-r1:1.5b
```

Things went downhill after that, as I couldn't get a complete response.
The Pi would lock up with no output on the display:

```
$ ollama run deepseek-r1:1.5b
>>> what is the capital of england?
<think>
Okay, so I need to figure out whatclient_loop: send disconnect: Broken pipe
```

Switching from the Apple iPad charger I was using to an official Pi
power supply resolved this problem.

```
$ ollama run deepseek-r1:1.5b
>>> what is the capital of england?
<think>

</think>

The capital of England is London.

>>>
```

However, it's not so good with a more niche question:

```
$ ollama run deepseek-r1:1.5b
>>> what is OCaml?
<think>

</think>

OCaml is a high-level, multi-paradigm programming language that combines
features from several other languages and frameworks. It was created by
Martin Abadi, the founding father of Google, and has gained popularity
in both academic research and industrial applications.

...
```

How about an easier question?

```
$ ollama run deepseek-r1:1.5b
>>> Who invented the C programming language?
<think>
Okay, so I need to figure out who invented the C programming
language. Hmm, I remember that C is a high-level programming language
used for system programming and embedded systems because it's efficient
and portable. But I'm not sure about its origin.

First, I'll think about other languages that are often mentioned
before C. For example, C was developed by Dennis Ritchie in the late
1960s. He wrote the header files, which made the language more readable
and maintainable. He probably worked for Bell Labs since that's where
Dennis is associated.

I wonder if there were any other contributors. Maybe someone else helped
develop parts of the language before Ritchie did everything. But I don't
recall any major alternatives to C being widely used before it became
dominant in certain areas like operating systems and embedded devices.

So, putting it all together, Dennis Ritchie is credited with inventing
C. He created a lot of header files that made the language structured
and easier to use, which helped it become very popular for its efficiency
and portability.
</think>

The C programming language was invented by Dennis Ritchie, who worked at
Bell Labs in the late 1960s. His work led to the creation of significant
header files that enhanced readability and maintainability. Ritchie's
contributions made C a widely used language in areas like operating
systems and embedded systems.

**Answer:**

Dennis Ritchie invented the C programming language. He worked at Bell Labs
(now part of Tufts University) in the late 1960s, contributing to its
development by creating essential header files that made the language
more readable and maintainable. His work led to a widely popularized
language used for system programming and embedded systems.

**Step-by-Step Explanation:**

1. **Identify the Problem:** The question is about the origin of C,
an early high-level programming language.
2. **Recall Other Languages Before C:** Mention languages like Pascal,
Ada, and Modula-2 that were around before C.
3. **Consider Developers Known for C:** Dennis Ritchie stands out as a
key figure in C's development.
4. **Details about Ritchie’s Contributions:** He worked at Bell Labs
(now Tufts University) in the 1960s, creating header files to improve
C's structure and readability.
5. **Link to C Language Development:** This led to C becoming prominent
for system programming due to its efficiency and portability.

**Conclusion:**
Dennis Ritchie is credited with inventing C by developing header files
that enhanced the language’s usability and structure.
```
