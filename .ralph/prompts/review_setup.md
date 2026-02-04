# REVIEW SETUP - Initialize Review Checklist with Specialist Tags

This is a single-shot prompt that runs BEFORE the review loop begins.

---

## Your Task

Create a `review_checklist.md` file that transforms the implementation plan into a reviewable checklist, **tagged by specialist type**.

## Setup

1. Read `.ralph/specs/active.md` to understand the feature requirements
2. Read `.ralph/implementation_plan.md` to see what was planned
3. Read `.ralph/AGENTS.md` for project conventions

---

## Specialist Tags

Each review item must be tagged with ONE of these specialist types:

| Tag | Specialist | When to Use |
|-----|------------|-------------|
| `[UX]` | UX/Frontend Expert | React/Vue/Angular components, CSS/styling, UI interactions, accessibility, responsive design |
| `[DB]` | Database Specialist | SQL queries, migrations, data models, ORM code, database connections, caching |
| `[QA]` | QA Engineer | Business logic, API endpoints, services, utilities, error handling, testing, everything else |

### File Path Patterns for Tagging

Use these patterns to determine the specialist:

**[UX] - Frontend/UI files:**
- `*.tsx`, `*.jsx` (React components)
- `*.vue` (Vue components)
- `*.svelte` (Svelte components)
- `*.css`, `*.scss`, `*.less`, `*.styled.ts`
- `components/`, `pages/`, `views/`, `layouts/`
- `hooks/`, `composables/` (if UI-related)
- Files with "button", "form", "modal", "dialog", "input" in name

**[DB] - Database files:**
- `*.sql` (SQL scripts)
- `migrations/`, `seeds/`, `schema/`
- `models/`, `entities/` (ORM models)
- `repositories/`, `dao/`
- Files with "query", "database", "db", "migration" in name
- `prisma/`, `drizzle/`, `typeorm/`, `sequelize/`

**[QA] - Everything else (default):**
- `services/`, `controllers/`, `handlers/`
- `utils/`, `helpers/`, `lib/`
- `api/`, `routes/`, `endpoints/`
- `*.spec.ts`, `*.test.ts` (test files)
- Business logic, integrations, etc.

---

## Create Review Checklist

Generate `.ralph/review_checklist.md` with this structure:

```markdown
# [Feature Name] - Review Checklist

## Overview
Brief description of the review scope and what has been implemented.

---

## Review Items

### UX Reviews (Frontend/UI)
- [ ] `[UX]` **[Component Name]** - [Brief description of what to review]
  - Files: `path/to/component.tsx`, `path/to/styles.css`
  - Spec reference: [Section in spec]
- [ ] `[UX]` **[Another Component]** - [Brief description]
  - Files: `path/to/file`
  - Spec reference: [Section in spec]

### Database Reviews
- [ ] `[DB]` **[Migration/Query Name]** - [Brief description]
  - Files: `path/to/migration.sql`, `path/to/model.ts`
  - Spec reference: [Section in spec]
- [ ] `[DB]` **[Data Model]** - [Brief description]
  - Files: `path/to/entity.ts`
  - Spec reference: [Section in spec]

### QA Reviews (Logic/Services/API)
- [ ] `[QA]` **[Service/Feature Name]** - [Brief description]
  - Files: `path/to/service.ts`, `path/to/handler.ts`
  - Spec reference: [Section in spec]
- [ ] `[QA]` **[API Endpoint]** - [Brief description]
  - Files: `path/to/controller.ts`
  - Spec reference: [Section in spec]

---

## Cross-Cutting Concerns
- [ ] `[QA]` **Error Handling** - Review error handling patterns across all implementations
- [ ] `[QA]` **Code Quality** - Check for consistent patterns, clear naming, maintainability
- [ ] `[DB]` **Performance** - Identify potential database performance issues
- [ ] `[QA]` **Security** - Check for security vulnerabilities and data handling
- [ ] `[QA]` **Testing** - Verify test coverage and quality
- [ ] `[UX]` **Accessibility** - Check accessibility across all UI components

---

## Review Progress
- Total items: [count]
- UX items: [count]
- DB items: [count]
- QA items: [count]
- Reviewed: 0
- Issues found: 0

## Issues Log
_Issues will be added here during review_
```

### Guidelines for Creating the Checklist

1. **Tag every item** - Each item MUST have a `[UX]`, `[DB]`, or `[QA]` tag
2. **Group by specialist** - Organize items under UX, Database, and QA sections
3. **Include file paths** - List the specific files that need to be reviewed for each item
4. **Reference the spec** - Link each item back to the relevant spec section
5. **Only include completed items** - Only add items from the implementation plan that are marked `[x]` (completed)
6. **Use file patterns** - Use the file path patterns above to determine the correct tag
7. **When in doubt, use [QA]** - QA specialist handles general quality review

---

## Commit and Push

After creating the checklist:

```bash
git add .ralph/review_checklist.md
git commit -m "Initialize review checklist for [feature] with specialist tags"
git push
```

Then STOP. The review loop will begin next.
