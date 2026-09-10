# Backend AI — CONFIRM: AI chats are private per user

Copy-paste this to Backend AI / engineer. Goal: **prove and enforce** that User A can never read User B’s AI Coach conversations.

iOS already scopes local cache by JWT user (`CoachChatDiskCache` v2). Server must be the source of truth.

---

## ROLE

You are a senior FastAPI security / backend engineer on **TacTech**.

Verify and fix (if needed) that **all `/coach/*` conversation data is strictly owned by the authenticated user**.

---

## RULE (non-negotiable)

| Actor | Can see |
|--------|---------|
| User A (JWT A) | Only conversations where `conversation.userId == A` |
| User B (JWT B) | Only conversations where `conversation.userId == B` |
| User A with B’s `conversationId` | **403 FORBIDDEN** (or 404 — pick one, document it; prefer **403** if id exists but not owned, **404** if id unknown) |

No shared “global” AI chat inbox. No admin leak via list endpoints without admin auth. Trainer role does **not** unlock another user’s `/coach/conversations`.

---

## ENDPOINTS TO AUDIT

For each route, confirm SQL/filter uses **JWT `userId` only** (never trust body/query userId):

1. `GET /coach/conversations` → `WHERE user_id = :jwtUserId` (and not deleted)
2. `POST /coach/conversations` → set `user_id = :jwtUserId`
3. `GET /coach/conversations/{id}/messages` → conversation must belong to jwt user
4. `DELETE /coach/conversations/{id}` → same ownership check
5. `POST /coach/chat` (stream + non-stream) → if `conversationId` provided, must own it; if creating new, attach jwt user
6. `POST /coach/chat/image` → same
7. `POST /coach/voice/turn` → same
8. `POST /coach/rtc/sessions` → session + conversation (if any) owned by jwt user
9. `GET /coach/memory/sync` / memory RAG → embeddings/chunks only for jwt user
10. Signaling WS `/coach/rtc/.../signal?token=` → identity from token; no cross-user session join

---

## ERROR SHAPE

```json
{ "detail": "You can’t access this chat.", "code": "FORBIDDEN" }
```

```json
{ "detail": "Chat not found.", "code": "NOT_FOUND" }
```

---

## TEST PLAN (you must run / script)

Use two real users (trainer or trainee — both OK).

### Setup
- Login as **User A** → create conversation `cA`, send message “secret from A”
- Login as **User B** → create conversation `cB`, send message “secret from B”

### Cases
1. **A list** `GET /coach/conversations` with A token → only `cA` (never `cB`)
2. **B list** with B token → only `cB`
3. **A reads B** `GET /coach/conversations/cB/messages` with A token → **403/404**, empty body not B’s messages
4. **A chats as B** `POST /coach/chat` with A token + `"conversationId": "cB"` → **403/404**, no message appended to `cB`
5. **A deletes B** `DELETE /coach/conversations/cB` with A token → **403/404**, `cB` still exists for B
6. **B still has** `cB` after A’s failed delete
7. **Logout/login** A again → still only A’s threads
8. **Same device** (optional note for QA): iOS cache is per JWT user; still confirm API never returns cross-user data

### Pass criteria
- [ ] Zero cross-user message content in any response above  
- [ ] DB row for `cB` unchanged after A’s forbidden attempts  
- [ ] Automated test or script committed (pytest) covering cases 1–5  

---

## DB CHECK

```sql
-- Conversations must have owner column
-- conversation.user_id  (or userId) NOT NULL, indexed
-- All message queries join/filter through conversation.user_id = :jwt
```

No endpoint may do `SELECT * FROM coach_conversations` without user filter.

---

## DELIVERABLE

Reply with:

1. **Confirmed: yes/no** — cross-user isolation is enforced on production code  
2. File/PR list of any fixes  
3. Test output (pass/fail) for the plan above  
4. Exact status code choice for “exists but not owned” (403 vs 404)

If anything is missing, **implement the filter + tests now** — do not only document.

Production-ready only. No mock auth bypass in prod/staging.
