# Backend AI — Human chat WhatsApp fidelity (copy-paste prompt)

You are a senior FastAPI backend engineer on **TacTech**.

iOS **already shipped** a WhatsApp-style human chat UX on trainer↔trainee threads (`/chat/*` + Socket.IO `/chat`). Delivery ticks, reply quotes, reactions, and voice “played” are **partially local-only**. Extend the **existing** human-chat contract so those features round-trip. Do **not** invent a parallel chat API. Do **not** touch `/coach/*`.

---

## Context (read carefully)

| Already working on iOS + expected BE | Status |
|--------------------------------------|--------|
| `POST/GET /chat/threads`, messages, media, call events | Keep |
| Socket `chat.join` / `chat.leave` / `chat.message` / `chat.thread` | Keep |
| `chat.typing` bidirectional | Keep / verify |
| `POST .../read` + Socket `chat.read` → blue double-check | Keep / verify |
| Optimistic send with `clientId` → server id replace | Keep / verify |
| Cursor pagination `GET .../messages?cursor=&limit=` | Keep |

| Gap (iOS UI ready / degrading) | Needs BE |
|--------------------------------|----------|
| Reply quote on bubble + composer | `replyTo*` on send + DTO |
| Reaction pills on bubbles | react REST/Socket + DTO field |
| Grey **double** check (Delivered) | `deliveredAt` / `chat.delivered` |
| Blue mic / played state for voice | `playedAt` / `chat.played` |
| Delete for everyone | soft-delete + Socket |
| Edit within 15 min (outgoing text) | optional edit endpoint |

Auth, errors, camelCase JSON, ISO-8601 UTC, absolute media URLs — same as existing `/chat/*` prompt.

Error body always:
```json
{ "detail": "Human-readable message for toast", "code": "FORBIDDEN" }
```

---

## 1) Extend `ChatMessage` DTO (additive — never break clients)

Every message in REST list/send responses and Socket `chat.message` payloads must remain backward compatible. **Add optional fields** (omit or `null` if unused):

```json
{
  "id": "m1",
  "threadId": "t1",
  "senderUserId": "u1",
  "senderRole": "trainer",
  "kind": "text",
  "text": "Hello",
  "attachmentUrl": null,
  "attachmentType": null,
  "durationSeconds": null,
  "callOutcome": null,
  "clientId": "uuid-from-client",
  "createdAt": "2026-09-11T12:00:00.000Z",
  "deliveredAt": "2026-09-11T12:00:01.000Z",
  "readAt": "2026-09-11T12:00:05.000Z",
  "playedAt": null,
  "replyToMessageId": "m0",
  "replyToText": "Original snippet…",
  "replyToSenderName": "Alex",
  "reactions": [
    { "emoji": "❤️", "userId": "u2", "createdAt": "2026-09-11T12:01:00.000Z" }
  ],
  "editedAt": null,
  "deletedForEveryoneAt": null
}
```

### Tick mapping (1:1 threads)

| State | Condition | iOS tick |
|-------|-----------|----------|
| Pending | client-only (`local-*`) | clock |
| Sent | persisted, no `deliveredAt`/`readAt` | single grey ✓ |
| Delivered | `deliveredAt` set, `readAt` null | double grey ✓✓ |
| Read | `readAt` set | double blue ✓✓ |
| Played (voice only) | `playedAt` set | blue play/mic cue |
| Failed | client timeout/reject | red retry (client) |

For 1:1, “all members” = the single peer.

---

## 2) Reply-to (quoted context)

### Send text — extend body (optional fields)

`POST /chat/threads/{threadId}/messages`

```json
{
  "text": "Sure, 6pm works",
  "clientId": "uuid",
  "replyToMessageId": "m0"
}
```

### Send media multipart

Add form field `replyToMessageId` (optional) alongside existing `clientId`, caption, etc.

### Server behavior

1. Validate `replyToMessageId` belongs to same `threadId` (else 400 `VALIDATION`).
2. Snapshot at send time:
   - `replyToText` = truncated preview of original (`text` / “📷 Photo” / “🎤 Voice” …, max ~120 chars)
   - `replyToSenderName` = display name of original sender
3. Persist on the new message; echo on REST + Socket `chat.message`.
4. If original was deleted-for-everyone, still allow reply but snapshot may be `"Original message"`.

Do **not** require iOS to send `replyToText` / `replyToSenderName` — server is source of truth for the snapshot.

---

## 3) Delivery ACK (`chat.delivered`)

When peer’s device **receives** a message (Socket delivery or successful poll merge), mark delivery.

### Preferred Socket (client → server)

```json
{
  "event": "chat.delivered",
  "data": {
    "threadId": "t1",
    "upToMessageId": "m9"
  }
}
```

### Optional REST

```
POST /chat/threads/{threadId}/delivered
{ "upToMessageId": "m9" }
```

### Server

1. Caller must be thread participant.
2. For all messages in thread where `senderUserId != caller` and `id` ≤ `upToMessageId` (by createdAt/order) and `deliveredAt` is null → set `deliveredAt = now`.
3. Emit to thread / sender room:

```json
{
  "event": "chat.delivered",
  "data": {
    "threadId": "t1",
    "upToMessageId": "m9",
    "deliveredByUserId": "u2",
    "deliveredAt": "2026-09-11T12:00:01.000Z"
  }
}
```

4. Idempotent. Never clear `deliveredAt`. If already `readAt`, leave both set.

---

## 4) Read (already exists — verify)

Keep:

```
POST /chat/threads/{threadId}/read
{ "upToMessageId": "m9" }
```

Socket out:

```json
{
  "event": "chat.read",
  "data": {
    "threadId": "t1",
    "upToMessageId": "m9",
    "readerUserId": "u2"
  }
}
```

Also set `readAt` on covered **incoming** messages for the reader’s peer view, and ensure message DTOs include `readAt` so ticks survive cold load.

Rule: `readAt` implies delivered — if `deliveredAt` null when reading, set both.

---

## 5) Voice played (`chat.played`)

Only for `attachmentType: "voice"` (or kind voice).

### Client → server (Socket preferred)

```json
{
  "event": "chat.played",
  "data": {
    "threadId": "t1",
    "messageId": "m5"
  }
}
```

### Optional REST

```
POST /chat/threads/{threadId}/messages/{messageId}/played
```

### Server

1. Message must be voice; caller ≠ sender; same thread.
2. Set `playedAt` once (idempotent).
3. Emit:

```json
{
  "event": "chat.played",
  "data": {
    "threadId": "t1",
    "messageId": "m5",
    "playedByUserId": "u2",
    "playedAt": "2026-09-11T12:02:00.000Z"
  }
}
```

---

## 6) Reactions

### Upsert reaction

```
POST /chat/threads/{threadId}/messages/{messageId}/reactions
{ "emoji": "❤️" }
```

Or Socket:

```json
{
  "event": "chat.react",
  "data": {
    "threadId": "t1",
    "messageId": "m1",
    "emoji": "❤️"
  }
}
```

### Remove reaction

```
DELETE /chat/threads/{threadId}/messages/{messageId}/reactions/{emoji}
```

Or Socket `chat.unreact` with same ids.

### Rules

- One reaction per `(messageId, userId)` **or** allow multiple distinct emojis per user — pick **one emoji per user** (WhatsApp-like): new emoji replaces previous.
- Allowed set can be open UTF-8 emoji; iOS quick bar uses `👍 ❤️ 😂 😮 😢 🙏`.
- Persist `reactions[]` on message; broadcast:

```json
{
  "event": "chat.reaction",
  "data": {
    "threadId": "t1",
    "messageId": "m1",
    "reactions": [
      { "emoji": "❤️", "userId": "u2", "createdAt": "..." }
    ]
  }
}
```

---

## 7) Delete for everyone / edit (optional but UI-ready)

### Delete for everyone

```
DELETE /chat/threads/{threadId}/messages/{messageId}?scope=everyone
```

- Only sender; within **~1 hour** of `createdAt` (configurable) OR always allow for sender — document choice.
- Soft-delete: set `deletedForEveryoneAt`, clear `text`/media URLs (or replace with tombstone).
- Emit `chat.message.deleted` with `{ threadId, messageId, scope: "everyone" }`.

### Delete for me

Client-local is OK; if you support server-side hide:

```
DELETE /chat/threads/{threadId}/messages/{messageId}?scope=me
```

Do not remove for the other participant.

### Edit (outgoing text, ≤15 minutes)

```
PATCH /chat/threads/{threadId}/messages/{messageId}
{ "text": "Updated copy" }
```

- Sender only; `kind == text`; `now - createdAt ≤ 15m`.
- Set `editedAt`; emit updated `chat.message`.

---

## 8) Typing (verify)

Existing:

```json
// client → server
{ "event": "chat.typing", "data": { "threadId": "t1", "isTyping": true } }

// server → peer
{ "event": "chat.typing", "data": { "threadId": "t1", "userId": "u1", "isTyping": true } }
```

iOS: start on keystroke, stop after ~2.5s idle, auto-clear UI after 25s if no stop. Server should forward only to thread peers (not echo to sender).

---

## 9) Idempotency & offline replay

- `clientId` unique per sender (or per thread+sender). Re-POST same `clientId` → return **same** message (200), no duplicate row.
- This lets iOS retry failed sends without list jitter.

---

## 10) What not to change

- Do not break existing fields iOS already decodes (`ChatMessageDTO` without the new keys must still decode).
- Do not move human chat onto `/coach/*`.
- Do not require new mandatory request fields — all extensions optional.
- Call / WebRTC (`/chat/rtc/*`) — out of scope for this prompt unless a delete-for-everyone must hang up (no).

---

## Acceptance checklist

- [ ] Message JSON may include `deliveredAt`, `readAt`, `playedAt`, `replyTo*`, `reactions`, `editedAt`, `deletedForEveryoneAt` without breaking old clients.
- [ ] Send with `replyToMessageId` stores server-side snapshot; appears on list + Socket.
- [ ] `chat.delivered` / REST sets `deliveredAt` and notifies sender.
- [ ] Existing `chat.read` still sets `readAt` and implies delivered.
- [ ] Voice `chat.played` sets `playedAt` once and notifies sender.
- [ ] React / unreact updates `reactions` and broadcasts `chat.reaction`.
- [ ] Duplicate `clientId` send is idempotent.
- [ ] `chat.typing` still works peer-to-peer.
- [ ] CamelCase, JWT auth, standard `{ detail, code }` errors.

---

## Suggested implementation order

1. Additive DTO columns + echo on existing send/list/Socket  
2. `replyToMessageId` on send  
3. `chat.delivered` (+ auto-set on read)  
4. `chat.played`  
5. Reactions  
6. Delete-for-everyone / edit  

After deploy, iOS will wire decoding + Socket handlers in a follow-up; until then UI keeps local fallbacks.
