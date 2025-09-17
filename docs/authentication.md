## Authentication & Authorization (Clerk)
* Clerk for user auth (business owners/employees).
AuthN/Z: Clerk.dev with role claims; Business owns one or more phone numbers; Employees belong to exactly one Business and one calendar; all actions are auditable.

---

## 1. Approach

* Use **Clerk hosted pages** (less work, Clerk manages the UI + flows).
* Your app just redirects users to Clerk for **sign-in / sign-up / forgot password**.
* Clerk returns a session + `clerkUserId` to your app.
* You create a **local User record** in Postgres keyed by `clerkUserId`.

---

## 2. Supported Auth Methods

* **Email + Password** → always available fallback.
* **Google** → covers most tradespeople with Gmail/Workspace.
* **Facebook** → still widely used by local service pros who run business pages.

That’s broad enough for plumbers, electricians, HVAC, etc.
No need for Apple, GitHub, LinkedIn, etc. in this audience.

---

## 3. Core Features (out of the box from Clerk)

* **Sign-In** (email/password or social).
* **New Registration** (email verification included).
* **Forgot Password** (reset via email).
* **Session Management** (Clerk middleware in Next.js).
* **Optional Account Settings UI** (password, MFA, etc. — if you want it).

---

## 4. Where Your DB Comes In

* At **registration**, you only touch the **User** table:

  * Store `clerkUserId`, `email`, `name` (if available).
  * Mark them as `globalRole = USER`.
* **Business** and **Employee** are **not created yet**.

  * Those are only added **after subscription** in your onboarding flow.

---

## 5. User Flow

1. Visitor hits **Sign Up** → sent to Clerk hosted page.
2. Clerk handles registration & verification.
3. Clerk redirects back with a valid session.
4. Your app checks Postgres for `clerkUserId`:

   * If new → create `User` row.
   * If existing → just log them in.
5. User lands in app with **no business info yet**.
6. When they subscribe → create `Business`, `BusinessUser`, and optional `Employee`.

---

✅ Net result: **Clerk handles identity**, you handle **business/employee models** later.
This keeps auth simple and offloads security, while leaving you in control of business logic.


Build this for me.  Baseline (auth + user provisioning + guards + audit stub)
