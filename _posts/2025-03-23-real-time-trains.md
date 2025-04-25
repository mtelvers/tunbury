---
layout: post
title:  "Real Time Trains API"
date:   2025-03-23 00:00:00 +0000
categories: OCaml
tags: tunbury.org
image:
  path: /images/rtt.png
  thumbnail: /images/rtt.png
---

After the Heathrow substation electrical fire, I found myself in Manchester with a long train ride ahead.  Checking on [Real Time Trains](https://www.realtimetrains.co.uk) for the schedule I noticed that they had an API.  With time to spare, I registered for an account and downloaded the sample code from [ocaml-cohttp](https://github.com/mirage/ocaml-cohttp).

The API account details uses HTTP basic authentication which is added via the HTTP header:

```ocaml
  let headers = Cohttp.Header.init () in
  let headers =
    Cohttp.Header.add_authorization headers (`Basic (user, password))
```

The response from the API can be converted to JSON using [Yojson](https://github.com/ocaml-community/yojson).

```ocaml
let json =
      Eio.Buf_read.(parse_exn take_all) body ~max_size:max_int
      |> Yojson.Safe.from_string
```

The JSON field can be read using the `Util` functions.  For example, `Yojson.Basic.Util.member "services" json` will read the `services` entry.  Elements can be converted to lists with `Yojson.Basic.Util.to_list`.  After a bit of hacking this turned out to be quite tedious to code.

As an alternative, I decided to use `ppx_deriving_yojson.runtime`.  I described the JSON blocks as OCaml types, e.g. `station` as below.

```ocaml
type station = {
  tiploc : string;
  description : string;
  workingTime : string;
  publicTime : string;
}
[@@deriving yojson]
```

The preprocessor automatically generates two functions:`station_of_json` and `station_to_json` which handle the conversion.

The only negative on this approach is that RTT doesn't emit empty JSON fields, so they need to be flagged as possibly missing and a default value provided.  For example, `realtimeArrivalNextDay` is not emitted unless the value is `true`.

```ocaml
  realtimeArrivalNextDay : (bool[@default false]);
```

Now once the JSON has been received we can just convert it to OCaml types very easily:

```ocaml
    match reply_of_yojson json with
    | Ok reply ->
       (* Use reply.services *)
    | Error err -> Printf.printf "Error %s\n" err
```

My work in progress code is available on [GitHub](https://github.com/mtelvers/ocaml-rtt)

```
dune exec --release -- rtt --user USER --pass PASS --station RTR
rtt: [DEBUG] received 3923 bytes of body
rtt: [DEBUG] received 4096 bytes of body
rtt: [DEBUG] received 4096 bytes of body
rtt: [DEBUG] received 4096 bytes of body
rtt: [DEBUG] received 1236 bytes of body
rtt: [DEBUG] end of inbound body
2025-03-23 2132 W16178 1C69 1 Ramsgate St Pancras International
2025-03-23 2132 W25888 9P59 2 Plumstead Rainham (Kent)
2025-03-23 2136 J00119 1U28 2 London Victoria Ramsgate
2025-03-23 2144 W25927 9P86 1 Rainham (Kent) Plumstead
2025-03-23 2157 W16899 1C66 2 St Pancras International Ramsgate
2025-03-23 2202 W25894 9P61 2 Plumstead Rainham (Kent)
2025-03-23 2210 J26398 1U80 1 Ramsgate London Victoria
2025-03-23 2214 W25916 9P70 1 Rainham (Kent) Plumstead
2025-03-23 2232 W16910 1C73 1 Ramsgate St Pancras International
2025-03-23 2232 W25900 9P63 2 Plumstead Rainham (Kent)
2025-03-23 2236 J00121 1U30 2 London Victoria Ramsgate
2025-03-23 2244 W25277 9A92 1 Rainham (Kent) Dartford
2025-03-23 2257 W16450 1F70 2 St Pancras International Faversham
2025-03-23 2302 W25906 9P65 2 Plumstead Rainham (Kent)
2025-03-23 2314 W25283 9A94 1 Rainham (Kent) Dartford
2025-03-23 2318 J00155 1U82 1 Ramsgate London Victoria
2025-03-23 2332 W25912 9P67 2 Plumstead Gillingham (Kent)
2025-03-23 2336 J00123 1U32 2 London Victoria Ramsgate
2025-03-23 2344 W25289 9A96 1 Rainham (Kent) Dartford
2025-03-23 2357 W16475 1F74 2 St Pancras International Faversham
2025-03-23 0002 W25915 9P69 2 Plumstead Gillingham (Kent)
2025-03-23 0041 J26381 1Z34 2 London Victoria Faversham
```
