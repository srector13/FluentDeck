# FluentDeck wire protocol (v1)

One WebSocket per client at `ws://<host>:47610/ws`. Every frame is a UTF-8 JSON object with a `type` field.
Binary assets (album art, app icons) are fetched over HTTP: `GET /assets/<key>` with
`Authorization: Bearer <token>`.

## Handshake

```
host → client  {"type":"server","protocol":1,"hostId":"…","name":"SURFACE","version":"0.1.0"}

client → host  {"type":"hello","token":"…","client":{"name":"Stephen's iPad","version":"1.0"}}
           or  {"type":"pair","code":"482913","client":{…}}

host → client  {"type":"paired","token":"…"}                     (pair only — store it in the Keychain)
host → client  {"type":"welcome","panels":[PanelDescriptor…]}
           or  {"type":"authError","reason":"…","needsPairing":true}   (socket stays open for a pair attempt)
```

Pairing codes come from the host: tray icon → **Pair new device…** (6 digits, valid 3 minutes,
5 attempts). A paired token never expires until it is revoked from the tray menu.

`PanelDescriptor`: `{"id":"media","title":"Media","icon":"music.note","version":1,"actions":["playPause",…]}`

## After welcome

```
client → host  {"type":"subscribe","topics":["media","audio","deck","system","theme"]}
host → client  {"type":"state","topic":"media","data":{…}}      (snapshot immediately, then on every change)

client → host  {"type":"invoke","id":"c1","panel":"media","action":"seek","args":{"seconds":42.5}}
host → client  {"type":"result","id":"c1","ok":true,"data":null}
           or  {"type":"result","id":"c1","ok":false,"error":"No media session"}

client → host  {"type":"ping"}   host → client {"type":"pong"}
```

`id` is optional — omit it for fire-and-forget (slider drags). State for a topic is always the
**whole** state object (never a patch); the host de-duplicates identical states and coalesces
bursts to ~30 per second per topic.

## Built-in topics

| topic    | state shape (abridged) | actions |
|----------|------------------------|---------|
| `media`  | `hasSession, source{appId,name}, title, artist, album, artwork, status, position, duration, positionAt, canPlay/canPause/canNext/canPrevious/canSeek/canShuffle/canRepeat, shuffle, repeat, sessions[]` | `playPause play pause next previous seek{seconds} shuffle{on} repeat{mode} selectSession{appId}` |
| `audio`  | `output{id,name,volume,muted}, input{…}, devices[{id,name,isDefault}], sessions[{id,name,icon,volume,muted,active}]` | `setVolume{volume} toggleMute setMicVolume{volume} toggleMicMute setSessionVolume{id,volume} toggleSessionMute{id} setDefaultDevice{id}` |
| `deck`   | `pages[{id,title,columns,buttons[{id,label,symbol,icon,state{topic,path,equals},symbolOn,style}]}]` | `press{buttonId}` |
| `system` | `hostName, cpu, memory, memoryUsedGb, memoryTotalGb, battery{percent,charging}?, uptimeSeconds` | `lock sleep displayOff` |
| `theme`  | `isDark, accent, accentLight1..3, accentDark1..3` (hex `#RRGGBB`) | — |

`position` is seconds at `positionAt` (unix ms). Clients interpolate while `status == "playing"`.
Asset fields (`artwork`, `icon`) are paths like `/assets/3f9a…`; null when absent.
