# Backend AI — implement AI chat DELETE (copy-paste prompt)

You are a senior FastAPI backend engineer on **TacTech**.

iOS already ships delete in the AI Coach drawer (swipe / trash / confirm). Wire the API so delete is **real on the server**, not local-only.

---

## Endpoint (exact)

```
DELETE /coach/conversations/{id}
Authorization: Bearer <accessJWT>
```

### Success
- **204 No Content** (preferred), empty body  
- OR **200**:
```json
{ "id": "c1", "deleted": true }
```

### Errors (always this shape)
```json
{ "detail": "Human-readable message", "code": "NOT_FOUND" }
```

| Case | HTTP | code |
|------|------|------|
| Not logged in | 401 | `UNAUTHORIZED` |
| Chat belongs to another user | 403 | `FORBIDDEN` |
| Unknown / already deleted | 404 | `NOT_FOUND` |
| Unexpected | 500 | `INTERNAL` |

---

## Behavior

1. Resolve `userId` from JWT only — never trust body.
2. Load conversation by `{id}`; if missing → 404.
3. If `conversation.userId != jwt.userId` → 403.
4. Delete **all messages** for that conversation (cascade).
5. Delete or GC conversation-scoped media (image/audio URLs) if stored on your CDN.
6. If an RTC session is open for this `conversationId`, end it (signaling `hangup`).
7. Commit transaction; return 204.
8. CamelCase JSON everywhere else; this route may have empty body.

Do **not** touch:
- `/chat/*` (trainer↔trainee human chat)
- `/support/*` (help center)

---

## DB / migration notes

- Prefer FK `ON DELETE CASCADE` from messages → conversations  
- Index `(user_id, updated_at desc)` for list after delete  
- Soft-delete OK if you filter `deleted_at IS NULL` on `GET /coach/conversations` — iOS must never see deleted threads again after refresh

---

## Acceptance

- [ ] Trainer deletes chat in iOS drawer → `GET /coach/conversations` no longer returns it  
- [ ] Trainee same  
- [ ] Other user’s id → 403  
- [ ] Random id → 404  
- [ ] Messages for that id are gone (or soft-hidden)  
- [ ] Existing SSE chat / create / list still green  

---

## OpenAPI snippet

```
DELETE /coach/conversations/{id}
  security: bearer
  responses:
    204: empty
    401/403/404: { detail, code }
```

Implement production-ready code only. No mock delete. Match TacTech multi-tenant JWT rules.
