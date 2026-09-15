# Backend AI — Plans assign / unassign / edit / delete (copy-paste prompt)

**Copy-paste this entire document to the Backend AI.**

---

You are a senior FastAPI engineer on **TacTech** (trainer/trainee gym app).

## Mission

Ship the plan-management APIs the **TacTech Trainer iOS** app now calls for:

1. **Assign** a plan to a trainee  
2. **Unassign** a plan from a trainee  
3. **Update (PATCH)** an existing workout plan  
4. **Delete** a workout plan  

Do **not** break existing create/list/assign flows iOS already uses in production.

**iOS app:** TacTech Trainer iOS  
**Auth:** `Authorization: Bearer <accessToken>` (trainer role required for all routes below)  
**JSON:** camelCase  
**Dates:** ISO-8601  

---

## 0. Already live (do not break)

| Method | Path | Notes |
|--------|------|--------|
| GET | `/trainer/plans` | List trainer’s plans |
| POST | `/trainer/plans` | Create plan (`PlanBody`) |
| POST | `/trainer/assignments` | Assign `{ planId, traineeId }` |
| GET | `/trainee/assigned-plan` | Trainee’s current plan |

---

## 1. Implement now (iOS is wired)

### 1.1 Update plan

```http
PATCH /trainer/plans/{planId}
```

**Auth:** trainer who owns the plan only.  
**Body:** same shape as create (`PlanBody`) — treat as full replace of editable fields (or documented partial; iOS sends full body):

```json
{
  "title": "4-day strength block",
  "focus": "Hypertrophy",
  "durationMinutes": 55,
  "level": "Intermediate",
  "daysPerWeek": 4,
  "notes": "optional",
  "exercises": [ /* PlanExerciseBody[] — flat list OK */ ],
  "days": [ /* PlanDayBody[] — preferred when weekly schedule exists */ ]
}
```

**Response:** `200` updated `WorkoutPlan` (include `id`, `trainerId`, `days`, `exercises`, …).  
**Errors:** `401`, `403` (not owner), `404`.

**Rules:**
- Preserve `id` and `trainerId`.
- If `days` is non-empty, that is the schedule source of truth; keep `exercises` as aggregate or mirror `days.flatMap`.
- Assignments to this plan **stay** unless you soft-delete (see delete).
- After PATCH, `GET /trainee/assigned-plan` for assigned trainees must return the **updated** plan.

---

### 1.2 Delete plan

```http
DELETE /trainer/plans/{planId}
```

**Auth:** owning trainer.  
**Response:** `204` (or `200` `{ "deleted": true }`).  
**Errors:** `401`, `403`, `404`.

**Rules (pick one and document; iOS expects this behavior):**
1. **Preferred:** soft-delete plan + **clear active assignments** for that `planId`.  
2. Historical `WorkoutLog` rows that reference `planId` **must remain** (do not cascade-delete logs).  
3. After delete, plan must not appear in `GET /trainer/plans`.  
4. Trainees who had it assigned: `GET /trainee/assigned-plan` → `null` / 404 empty.

---

### 1.3 Unassign

iOS calls:

```http
DELETE /trainer/assignments?planId={planId}&traineeId={traineeId}
```

**Also accept (optional alias):**

```http
DELETE /trainer/assignments/{assignmentId}
```

**Auth:** trainer must own the plan **and** the trainee must be on their roster.  
**Response:** `204`.  
**Errors:** `401`, `403`, `404` if no matching active assignment.

**Rules:**
- Remove (or deactivate) the active assignment linking that trainee to that plan.
- If trainee had this as current plan, `GET /trainee/assigned-plan` must no longer return it.
- Idempotent: second DELETE with same query → `204` or `404` (document; iOS tolerates both).
- Do **not** delete workout logs.

---

### 1.4 Assign (already exists — confirm semantics)

```http
POST /trainer/assignments
{ "planId": "...", "traineeId": "..." }
```

**Confirm:**
- One **active** plan per trainee (replace previous assignment).
- Trainee must be on trainer’s roster.
- Response `201`/`200` with assignment or void is fine; iOS currently ignores body.

---

## 2. Ownership & multi-tenant checks

Every route must enforce:

- JWT role = `trainer`
- `plan.trainerId` == current trainer profile id  
- `trainee.trainerId` == current trainer (roster) for assign/unassign  

Never allow trainer A to mutate trainer B’s plans or assignments.

---

## 3. OpenAPI / contract tests

Add/update paths:

| Method | Path |
|--------|------|
| PATCH | `/trainer/plans/{planId}` |
| DELETE | `/trainer/plans/{planId}` |
| DELETE | `/trainer/assignments?planId=&traineeId=` |
| DELETE | `/trainer/assignments/{assignmentId}` (optional) |

Contract tests:

1. Trainer creates plan → PATCH title → GET list shows new title.  
2. Assign trainee → `assigned-plan` returns plan → DELETE unassign → `assigned-plan` empty.  
3. Assign → DELETE plan → plan gone from list + trainee unassigned; logs for that planId still queryable if you expose them.  
4. Other trainer’s token → PATCH/DELETE/unassign → `403`/`404`.

---

## 4. Done when

- [ ] `PATCH /trainer/plans/{id}` updates plan; iOS Edit Plan saves successfully  
- [ ] `DELETE /trainer/plans/{id}` removes plan + clears assignments; iOS Delete works  
- [ ] `DELETE /trainer/assignments?planId=&traineeId=` unassigns; iOS Unassign works  
- [ ] `POST /trainer/assignments` still works; one active plan per trainee  
- [ ] `GET /trainee/assigned-plan` reflects assign / unassign / edit / delete immediately  
- [ ] Logs are not cascade-deleted  
- [ ] camelCase JSON; Bearer auth; OpenAPI updated  

---

## 5. Out of scope

- Changing chat, coach, or auth token TTL  
- Meal/log CRUD  
- Push notifications  

---

## 6. Reply format

1. Routes implemented (exact paths)  
2. Soft-delete vs hard-delete choice for plans  
3. Assignment uniqueness rule (one active plan per trainee)  
4. Sample request/response for PATCH plan + DELETE unassign  
5. Test checklist results  
