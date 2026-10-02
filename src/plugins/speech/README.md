# Speech native Lua plugin

`Speech` is dictation without the software keyboard: `SFSpeechRecognizer`
transcribing the microphone through `AVAudioEngine`. It uses public Speech
and AVFoundation APIs only and is iOS-only (it configures `AVAudioSession`).
iOS cannot load plugin dylibs, so the iOS hosts (`make ios-host`,
`scripts/ipad/build.mk`, `ios/AdventureArena`) link it and add it to
`package.preload`. Where it is not linked, `require("Speech")` fails, so an
app treats it as optional. Adventure Arena (`apps/adventure-arena`) is the
client.

```lua
local ok, Speech = pcall(require, "Speech")
local recognizer = Speech.recognizer(function(state, text, message) end, "en-US")  -- locale optional
recognizer:start()   -- asks for speech and microphone access, then listens
recognizer:stop()    -- finishes: "processing", then "finished" with the text
recognizer:cancel()  -- discards: "idle"
```

The callback runs on the main thread with `(state, text, message)`:
`starting`, `listening`, `partial` (text so far), `processing`, `finished`
(final text), `idle`, or `error` (message). Recognition runs on the device
when the locale supports it.

Closing the Lua state finalizes every recognizer, which cancels it and
forgets the state, so no event can reach a closed state (the iOS host closes
its state on reload). Errors raised by the callback are logged.

The host app's `Info.plist` must describe microphone and speech recognition
use (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`).
