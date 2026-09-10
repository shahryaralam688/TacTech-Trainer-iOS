# Backend AI — Incoming video call ring (copy-paste prompt)

You are a senior FastAPI engineer on **TacTech**.

iOS now shows a **full-screen incoming call UI with ringtone** for trainer↔trainee video calls. That only works if the callee receives realtime + push when the caller creates an RTC session.

## Required behavior (must work even if callee is NOT inside the chat screen)

When caller does:
```
POST /chat/rtc/sessions
{ "threadId": "t1" }
```

Server must:

1. Create session + return `{ id, threadId, signalingPath, iceServers }` to caller.  
2. **Immediately** emit Socket.IO event on namespace `/chat` to the **other participant**:

```json
Event: "chat.call.incoming"
Payload: {
  "threadId": "t1",
  "sessionId": "rtc_h1",
  "fromUserId": "<caller User.id>",
  "fromName": "<caller display name>",
  "signalingPath": "wss://…/chat/rtc/sessions/rtc_h1/signal"
}
```

`signalingPath` is **required** (absolute wss URL preferred). iOS falls back to `/chat/rtc/sessions/{sessionId}/signal` if missing.

3. If peer is **not** connected to Socket.IO `/chat`, send a **high-priority push**:

```json
{
  "title": "<caller name>",
  "body": "Incoming video call",
  "data": {
    "type": "chat_call",
    "threadId": "t1",
    "sessionId": "rtc_h1",
    "fromUserId": "…",
    "fromName": "…"
  }
}
```

## On hangup / decline

When either side sends signaling `{ "type":"hangup", "reason":"ended"|"declined"|"timeout" }` **or** session times out:

Emit to both participants:
```json
Event: "chat.call.ended"
Payload: { "threadId": "t1", "sessionId": "rtc_h1", "reason": "declined" }
```

Prefer also inserting a `call_event` message into the thread so both inboxes show the call.

## Signaling WS (already specified)

`GET {signalingPath}?token=<accessJWT>`

Relay at least:
- `joined` when a participant connects (so caller can stop “Calling…” and enter in-call)
- `hangup`
- (later) `offer` / `answer` / `ice-candidate` for real WebRTC media

**Critical for ring UX:** when callee Accepts and connects signaling, server must send `joined` to the **caller** so iOS stops ringback.

## Acceptance checklist

- [ ] Trainer calls while trainee is on Home tab (chat closed) → trainee gets incoming UI + ringtone within ~1s  
- [ ] Trainee Accept → caller leaves “Calling…” and both see in-call  
- [ ] Trainee Decline → caller call ends; both get `chat.call.ended`  
- [ ] Push fires when trainee app is backgrounded / Socket disconnected  
- [ ] Payload includes `fromName` + `signalingPath`

## Out of scope

- Full WebRTC media (iOS shell already rings / accept / decline / camera preview)
- CallKit / VoIP push certs (nice later; standard high-priority push is enough for v1)

---

**Reply with:** confirm `chat.call.incoming` is emitted on session create, sample payload, and whether push is wired for `type=chat_call`.
