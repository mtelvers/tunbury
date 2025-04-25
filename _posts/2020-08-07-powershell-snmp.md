---
layout: post
title:  "PowerShell SNMP"
date:   2020-08-07 13:41:29 +0100
categories: powershell snmp
image:
  path: /images/pssnmp.png
  thumbnail: /images/pssnmp.png
---
Potentially, I’ve got a bit carried away here. There isn’t a native PowerShell module to query SNMP which I found a bit surprising. How hard could it be? I’ve got a SYSLOG server and client in PowerShell so this felt like a simple extension. The SNMP client needs to send a request over UDP to the SNMP server on port 161 and waits for the response back. Sending via .NET’s UDPClient is easy enough

    $UDPCLient = New-Object -TypeName System.Net.Sockets.UdpClient
    $UDPCLient.Connect($Server, $UDPPort)
    $UDPCLient.Send($ByteMessage, $ByteMessage.Length)

Receiving is just a case of waiting on the socket with a timeout in case the host is down!

    $asyncResult = $UDPCLient.BeginReceive($null, $null)
    if ($asyncResult.AsyncWaitHandle.WaitOne($Timeout)) {
        $UDPClient.EndReceive($asyncResult, [ref]$serverEndPoint)
    }
    $UDPCLient.Close()

Using Wireshark I captured the packets to take a look at the protocol in action.  Below is an SNMP Request

![](/images/snmp-request.png)

And this is an SNMP Reply

![](/images/snmp-reply.png)

ASN.1 and X.690
===============

Reading [RFC1157](https://tools.ietf.org/pdf/rfc1157.pdf) the SNMP protocol is defined using Abstract Syntax Notation One (ASN.1) notation and is encoded Basic Encoding Rules (BER) as defined in [X.690](https://en.wikipedia.org/wiki/X.69).

.NET Methods
============

.NET has methods for `BerConverter.Encode()` and `BerConverter.Decode()` which on face value look pretty promising. Taking the data above, it can decode a chunk of it:

    [System.Reflection.Assembly]::LoadWithPartialName("System.DirectoryServices.Protocols")
    [System.DirectoryServices.Protocols.BerConverter]::Decode("{ia[iii]}", @(0x30, 0x17, 0x2, 0x1, 0x0, 0x4, 0x6, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0xa0, 0xa, 0x2, 0x2, 0x65, 0x2e, 0x2, 0x1, 0x0, 0x2, 0x1, 0x0))
    0
    public
    25902
    0
    0

And it can encode although:

* it unnecessarily uses the long form encoding for length, for example: `84-00-00-00-1B` could easily be just `1B` thereby saving 4 bytes; and
* the *choice* section is encoded as a *set*.

While these limitation make these functions unsuitable they do a good job given the input specification is just a text string and a byte array.

    $data = [System.DirectoryServices.Protocols.BerConverter]::Encode("{is[iii]}", @(0, "public", 25902, 0, 0))
    [System.BitConverter]::ToString($data)
    30-84-00-00-00-1B-02-01-00-04-06-70-75-62-6C-69-63-31-84-00-00-00-0A-02-02-65-2E-02-01-00-02-01-00

Packet Structure
================

You can’t really get around the nested nature of the packets particularly when it comes encoding as the length of each block incorporates the length of all the nested blocks.

![](/images/get-request.svg)

BER Parser in PowerShell
========================

To match the nested nature of the packet I’m going to create a tree of PowerShell Objects (PSObject).  Leaf nodes will be actual data aka *Primitives* (P) from X.690 while the other nodes will be have child nodes, *Constructed* (C) in X.690.

Node Structure
==============

Each PSObject will have the following properties

* Class [enumerated type]
* Constructed/Primitive [boolean]
* Tag [enumerated type]
* content [byte[]]
* inner [PSObject[]]

A recursive function such as this produces the required structure:

    Function DecodeBER {
        Param (
            [Parameter(mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [byte[]] 
            $berInput
        )

        $ret = [PSObject[]]@()
        $length = 0

        for ($i = 0; $i -lt $berInput.length; $i += $length) {
            $tag = [asn1tag]($berInput[$i] -band 0x1f)
            $constructed = [boolean]($berInput[$i] -band 0x20)
            $class = [asn1class](($berInput[$i] -band 0xc0) -shr 6)

            $i++

            if ($tag -eq 31) {
                $tag = 0
                do {
                    $tag = ($tag -shl 7) -bor ($berInput[$i] -band 0x7f)
                } while ($berInput[$i++] -band 0x80)
            }

            $length = $berInput[$i] -band 0x7f
            if ($berInput[$i++] -band 0x80) {
                $end = $i + $length
                $length = 0
                for (; $i -lt $end; $i++) {
                    $length = ($length -shl 8) -bor $berInput[$i]
                }
            }

            $content = $berInput[$i..($i + $length - 1)]

            if ($constructed) {
                $ret += New-Object PSObject -Property @{class=$class; constructed=$true; tag=$tag; content=$null; inner=(DecodeBER $content)}
            } else {
                $ret += New-Object PSObject -Property @{class=$class; constructed=$false; tag=$tag; content=$content}
            }
        }
        return ,$ret
    }

Taking the payload from the Wireshark capture from above

    $data = [Byte[]]@(0x30, 0x30, 0x02, 0x01, 0x00, 0x04,
        0x06, 0x70, 0x75, 0x62, 0x6c, 0x69, 0x63, 0xa2,  0x23, 0x02, 0x02, 0x65, 0x2e, 0x02, 0x01, 0x00,
        0x02, 0x01, 0x00, 0x30, 0x17, 0x30, 0x15, 0x06,  0x08, 0x2b, 0x06, 0x01, 0x02, 0x01, 0x01, 0x05,
        0x00, 0x04, 0x09, 0x4e, 0x50, 0x49, 0x46, 0x30,  0x30, 0x46, 0x45, 0x34)

And passing that through the BER decoder and visualising it as JSON for the purpose this post (and I’ve manually merged some lines in a text editor)

    DecodeBER $data | ConvertTo-Json -Depth 10
    {
    "value":  [
            {
                "content":  null,
                "tag":  16,
                "constructed":  true,
                "class":  0,
                "inner":  [
                    {
                        "content":  [ 0 ],
                        "tag":  2,
                        "constructed":  false,
                        "class":  0
                    },
                    {
                        "content":  [ 112, 117, 98, 108, 105, 99 ],
                        "tag":  4,
                        "constructed":  false,
                        "class":  0
                    },
                    {
                        "content":  null,
                        "tag":  2,
                        "constructed":  true,
                        "class":  2,
                        "inner":  [
                                {
                                "content":  [ 101, 46 ],
                                "tag":  2,
                                "constructed":  false,
                                "class":  0
                                },
                                {
                                "content":  [ 0 ],
                                "tag":  2,
                                "constructed":  false,
                                "class":  0
                                },
                                {
                                "content":  [ 0 ],
                                "tag":  2,
                                "constructed":  false,
                                "class":  0
                                },
                                {
                                "content":  null,
                                "tag":  16,
                                "constructed":  true,
                                "class":  0,
                                "inner":  [
                                        {
                                        "content":  null,
                                        "tag":  16,
                                        "constructed":  true,
                                        "class":  0,
                                        "inner":  [
                                                {
                                                    "content":  [ 43, 6, 1, 2, 1, 1, 5, 0 ],
                                                    "tag":  6,
                                                    "constructed":  false,
                                                    "class":  0
                                                },
                                                {
                                                    "content":  [ 78, 80, 73, 70, 48, 48, 70, 69, 52 ],
                                                    "tag":  4,
                                                    "constructed":  false,
                                                    "class":  0
                                                }
                                                ]
                                        }
                                    ]
                                }
                            ]
                    }
                    ]
            }
            ],
    "Count":  1
    }

To convert it back the other way we need an EncodeBER function

    Function EncodeBER {
        Param (
            [Parameter(mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [PSObject[]] 
            $berObj
        )

        $bytes = [byte[]]@()
        foreach ($b in $berObj) {
            $bits = (($b.class.value__ -band 0x3) -shl 6)
            if ($b.constructed) {
                $bits = $bits -bor 0x20
            }
            if ($b.tag -lt 31) {
                $bytes += $bits -bor $b.tag.value__
            } else {
                $bytes += $bits -bor 0x1f
                $num = $b.tag
                $tmp = @()
                do {
                    $bits = [byte]($num -band 0x7f)
                    if ($tmp.length -gt 0) {
                        $bits = $bits -bor 0x80
                    }
                    $tmp += $bits
                    $num = $num -shr 7
                } while ($num -gt 0)
                $bytes += $ret[-1..-($ret.length)]
            }

            if ($b.constructed) {
                $content = EncodeBER $b.inner
            } else {
                $content = $b.content
            }

            if ($content.length -lt 127) {
                $bytes += $content.length
            } else {
                $num = $content.length
                $len = [byte[]]@()
                do {
                    $len += [byte]($num -band 0xff)
                    $num = $num -shr 8
                } while ($num -gt 0)
                $bytes += $len.length -bor 0x80
                $bytes += $len[-1..-($len.length)]
            }

            if ($content.length -gt 0) {
                $bytes += $content
            }
        }
        return ,$bytes
    }

Thus a superficial check of encoding and decoding:

    [System.BitConverter]::ToString($data)
    30-30-02-01-00-04-06-70-75-62-6C-69-63-A2-23-02-02-65-2E-02-01-00-02-01-00-30-17-30-15-06-08-2B-06-01-02-01-01-05-00-04-09-4E-50-49-46-30-30-46-45-34
    $obj = DecodeBER $data
    [System.BitConverter]::ToString(EncodeBER $obj)
    30-30-02-01-00-04-06-70-75-62-6C-69-63-A2-23-02-02-65-2E-02-01-00-02-01-00-30-17-30-15-06-08-2B-06-01-02-01-01-05-00-04-09-4E-50-49-46-30-30-46-45-34

The next steps here are to convert the `PSObject[]` tree into some sort of representation of an SNMP request and also create the reverse function to create an SNMP request the tree structure. I’m not going to both pasting those here as the code is available on [GitHub](https://github.com/mtelvers/PS-SNMP). They need some work to do better error checking etc but they work To use the function run `$x = Get-SNMP -Server 172.29.0.89 -OIDs @('1.3.6.1.2.1.1.5.0', '1.3.6.1.2.1.1.3.0', '1.3.6.1.2.1.25.3.2.1.3.1', '1.3.6.1.2.1.43.5.1.1.17.1')` and then check `$x.varbind`

    Name                           Value
    ----                           -----
    1.3.6.1.2.1.1.3.0              70328978
    1.3.6.1.2.1.43.5.1.1.17.1      JPBVK7C09V
    1.3.6.1.2.1.1.5.0              NPI27362C
    1.3.6.1.2.1.25.3.2.1.3.1       HP Color LaserJet M553
