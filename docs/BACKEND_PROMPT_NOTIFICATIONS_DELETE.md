# Backend AI — Notifications delete / clear all (copy-paste prompt)

**Copy-paste this entire document to the Backend AI.**

---

You are a senior FastAPI engineer on **TacTech**.

## Mission

Ship the **notification delete** APIs the **TacTech iOS** app already calls. Without these routes, iOS gets **HTTP 404 `Not Found`**, so deletes never persist (inbox reloads from the server and rows come back).

Do **not** break existing list / read / unread-count flows.

**iOS app:** TacTech (trainer + trainee share the same inbox client)  
**Auth:** `Authorization: Bearer <accessToken>`  
**JSON:** camelCase  
**Errors:** `{ "detail": "…", "code": "…" }`

---

## 0. Already live (do not break)

| Method | Path | Notes |
|--------|------|--------|
| GET | `/me/notifications?limit=&cursor=` | Inbox page |
| GET | `/me/notifications/unread-count` | `{ "unreadCount": N }` |
| POST | `/me/notifications/read` | One id, or null/omit = mark all |
| GET/PUT | `/me/preferences/notifications` | Pref toggles |

---

## 1. Missing route iOS calls today (this is the bug)

```http
POST /me/notifications/delete
Authorization: Bearer <accessToken>
Content-Type: application/json
```

### Single delete
```json
{ "notificationId": "n1" }
```

### Clear entire inbox
```json
{ "notificationId": null }
```
…or omit `notificationId` entirely (`{}`).

### Success **200**
```json
{ "unreadCount": 0 }
```
(`unreadCount` = remaining unread for **this** user after the delete.)

### Rules
1. Scope deletes to the **JWT user only** — never delete another user’s rows.
2. Single id: soft- or hard-delete that notification; return updated `unreadCount`.
3. Null / omitted id: delete **all** notifications for the current user; `unreadCount` **must** be `0`.
4. **Idempotent:** unknown / already-deleted id → still **200** with current `unreadCount` (do **not** 404).
5. After clear-all, `GET /me/notifications` returns empty `items`.
6. Trainer and trainee both use the same `/me/notifications*` surface.

### Failure codes
| HTTP | When |
|------|------|
| 401 | Missing / invalid JWT |
| 400 | Malformed body |
| 404 | **Only** if the route itself is not registered (should not happen after this ships). Never 404 a missing notification id. |

---

## 2. FastAPI sketch (match your project style)

```python
class NotificationDeleteIn(BaseModel):
    notificationId: str | None = None  # camelCase alias if you use alias_generator

@router.post("/me/notifications/delete")
async def delete_notifications(
    body: NotificationDeleteIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> dict:
    if body.notificationId:
        # delete one row where id == body.notificationId AND user_id == user.id
        ...
    else:
        # delete all rows for user.id
        ...
    unread = count_unread(db, user.id)
    return {"unreadCount": unread}
```

Register the router on the same API prefix iOS already hits for `GET /me/notifications`.

---

## 3. Acceptance tests

- [ ] `POST /me/notifications/delete` with a real `notificationId` → **200** `{ "unreadCount": N }`; row gone from `GET /me/notifications`.
- [ ] Same id again → **200** (idempotent), not 404.
- [ ] `POST` with `{ "notificationId": null }` or `{}` → inbox empty, `unreadCount: 0`.
- [ ] User A cannot delete User B’s notification id (no-op or 200 for A’s own unread only — never leak B’s data).
- [ ] iOS Clear all + single trash no longer show “Couldn't sync delete / Not Found”.

---

## 4. Out of scope

- Push token registration  
- Preference toggles  
- Socket `notification.created` payload changes  

Ship **only** the delete/clear route above.
