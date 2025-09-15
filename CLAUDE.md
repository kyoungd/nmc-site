# Claude Coding Rules

## Workflow
1. **Plan**: Read codebase → Write checkable todo list in `tasks/todo.md` → **GET APPROVAL**
2. **Check**: Search for existing code (reuse>create) → Check for side effects → **DISCUSS IF FOUND**
3. **Code**: Work through todos → Mark complete → Keep changes minimal
4. **Update**: High-level summary only (what/why, not how)
5. **Review**: Add summary section to todo.md

## Before ANY Change
- Exists already? → Search & reuse
- Affects other code? → Check & discuss
- Simpler way? → Always simplify
- Updated todo? → Keep current
- Fixing a problem? -> Discover the source of problem first before attemping a fix.
- Fixing a problem? -> If the source of problem is unknown, add logging and inform the user.

## Communication
**YES**: High-level changes, decisions, risks, questions
**NO**: Line-by-line details, obvious info, assumptions

## Core Rule
**Make every change as simple as possible. Impact minimal code.**

---
*When uncertain → Ask, don't assume*

## technology
Next.js
tailwind.css
shadcn/ui
clerk.dev
stripe
stripe - Billing Administration
Prisma
Postgresql
