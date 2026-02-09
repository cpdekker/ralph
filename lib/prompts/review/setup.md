# REVIEW SETUP - Initialize Review Checklist with Specialist Tags

This is a single-shot prompt that runs BEFORE the review loop begins.

---

## Your Task

Create a `review_checklist.md` file that transforms the implementation plan into a reviewable checklist, **tagged by specialist type and severity**.

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
| `[SEC]` | Security Specialist | Authentication, authorization, input validation, secrets, encryption |
| `[PERF]` | Performance Specialist | Algorithm complexity, caching, lazy loading, bundle optimization |
| `[API]` | API Specialist | REST endpoints, GraphQL resolvers, API contracts, request/response handling |
| `[ANTAG]` | Antagonist Reviewer | AI code smell detection, over-engineering, cargo-culted patterns, hallucinated APIs |

---

## Smart Tagging Rules

### Content-Based Tagging (Priority)

Analyze the **file contents** to determine the best specialist:

**[SEC] - Security-related code (high priority detection):**
- Contains: `bcrypt`, `jwt`, `auth`, `password`, `token`, `session`, `encrypt`, `decrypt`
- Contains: `sanitize`, `escape`, `validate`, `permission`, `role`, `access`
- Handles: user credentials, API keys, secrets, OAuth flows

**[API] - API layer code:**
- Contains: `fetch()`, `axios`, `http`, `request`, `response`
- Contains: route handlers, controllers, middleware
- Defines: REST endpoints, GraphQL resolvers

**[DB] - Database code:**
- Contains: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `JOIN`
- Contains: Prisma, TypeORM, Sequelize, Drizzle decorators/methods
- Contains: `migration`, `schema`, `entity`, `repository`
- Handles: connection pools, transactions

**[PERF] - Performance-critical code:**
- Contains: loops over large datasets
- Contains: `cache`, `memoize`, `lazy`, `defer`
- Contains: image processing, file handling, streaming

**[UX] - Frontend/UI code:**
- Contains: JSX/TSX, CSS imports, `className`, `style`
- Contains: hooks like `useState`, `useEffect`, `useRef`
- Contains: accessibility attributes (`aria-*`, `role=`)

**[ANTAG] - AI code smell review (applied broadly):**
- Contains: excessive comments explaining obvious code, over-documented simple functions
- Contains: unused parameters, dead code paths, premature abstractions
- Contains: generic catch-all error handling, defensive null checks on guaranteed values
- Contains: factory/strategy patterns with only one implementation
- Exhibits: suspiciously uniform file structure, no codebase-specific conventions followed

**[QA] - Default for everything else:**
- Business logic, utilities, services
- Test files (reviewers verify test quality)
- Configuration files

### File Path Patterns (Fallback)

Use these patterns when content analysis isn't definitive:

**[UX] - Frontend/UI files:**
- `*.tsx`, `*.jsx` (React components)
- `*.vue` (Vue components)
- `*.svelte` (Svelte components)
- `*.css`, `*.scss`, `*.less`, `*.styled.ts`
- `components/`, `pages/`, `views/`, `layouts/`

**[DB] - Database files:**
- `*.sql` (SQL scripts)
- `migrations/`, `seeds/`, `schema/`
- `models/`, `entities/`, `repositories/`, `dao/`
- `prisma/`, `drizzle/`, `typeorm/`, `sequelize/`

**[API] - API files:**
- `routes/`, `controllers/`, `handlers/`
- `api/`, `endpoints/`, `resolvers/`
- `middleware/`

**[SEC] - Security files:**
- `auth/`, `security/`, `crypto/`
- Files with `auth`, `guard`, `policy` in name

**[PERF] - Performance files:**
- `cache/`, `optimization/`
- Files with `worker`, `queue`, `batch` in name

**[QA] - Everything else (default):**
- `services/`, `utils/`, `helpers/`, `lib/`
- `*.spec.ts`, `*.test.ts` (test files)

---

## Severity Indicators

Add severity to help prioritize reviews:

| Severity | Tag | When to Use |
|----------|-----|-------------|
| Critical | `-CRITICAL` | Security vulnerabilities, data integrity, blocking bugs |
| High | (default) | Core functionality, important features |
| Low | `-MINOR` | Nice-to-haves, style issues, minor improvements |

**Examples:**
- `[SEC-CRITICAL]` - Authentication bypass vulnerability
- `[DB-CRITICAL]` - Potential data loss scenario
- `[UX]` - Standard frontend review (default high priority)
- `[QA-MINOR]` - Code style suggestion
- `[ANTAG]` - AI code smell check on new implementation

---

## Create Review Checklist

Generate `.ralph/review_checklist.md` with this structure:

```markdown
# [Feature Name] - Review Checklist

## Overview
Brief description of the review scope and what has been implemented.

---

## Review Items

### 🔒 Security Reviews (Priority 1)
- [ ] `[SEC-CRITICAL]` **[Authentication Flow]** - Verify auth tokens are validated
  - Files: `path/to/auth.ts`, `path/to/middleware.ts`
  - Spec reference: [Section in spec]
- [ ] `[SEC]` **[Input Validation]** - Check for injection vulnerabilities
  - Files: `path/to/handler.ts`
  - Spec reference: [Section in spec]

### 🗄️ Database Reviews (Priority 2)
- [ ] `[DB-CRITICAL]` **[Migration Safety]** - Verify no data loss
  - Files: `path/to/migration.sql`, `path/to/model.ts`
  - Spec reference: [Section in spec]
- [ ] `[DB]` **[Query Performance]** - Check for N+1 and missing indexes
  - Files: `path/to/repository.ts`
  - Spec reference: [Section in spec]

### 🔌 API Reviews (Priority 3)
- [ ] `[API]` **[Endpoint Contracts]** - Verify request/response schemas
  - Files: `path/to/controller.ts`
  - Spec reference: [Section in spec]
- [ ] `[API]` **[Error Responses]** - Check error handling consistency
  - Files: `path/to/handler.ts`
  - Spec reference: [Section in spec]

### ⚡ Performance Reviews (Priority 4)
- [ ] `[PERF]` **[Data Loading]** - Check for efficient data fetching
  - Files: `path/to/service.ts`
  - Spec reference: [Section in spec]

### 🎨 UX/Frontend Reviews (Priority 5)
- [ ] `[UX]` **[Component Name]** - Review UI implementation
  - Files: `path/to/component.tsx`, `path/to/styles.css`
  - Spec reference: [Section in spec]
- [ ] `[UX-MINOR]` **[Accessibility]** - Check ARIA labels
  - Files: `path/to/component.tsx`
  - Spec reference: [Section in spec]

### 🤖 Antagonist Reviews (Priority 6)
- [ ] `[ANTAG]` **[Core Implementation]** - Check for AI code smells and over-engineering
  - Files: `path/to/main-implementation-files`
  - Spec reference: [Section in spec]
- [ ] `[ANTAG]` **[Error Handling Patterns]** - Verify error handling is specific, not generic
  - Files: `path/to/files-with-error-handling`
  - Spec reference: [Section in spec]

### 🔍 QA/General Reviews (Priority 7)
- [ ] `[QA]` **[Business Logic]** - Verify core functionality
  - Files: `path/to/service.ts`
  - Spec reference: [Section in spec]
- [ ] `[QA]` **[Test Coverage]** - Review test quality
  - Files: `path/to/service.spec.ts`
  - Spec reference: [Section in spec]

---

## Cross-Cutting Concerns
- [ ] `[SEC]` **Authentication/Authorization** - Review access control across all implementations
- [ ] `[QA]` **Error Handling** - Review error handling patterns
- [ ] `[QA]` **Code Quality** - Check for consistent patterns, clear naming
- [ ] `[DB]` **Data Integrity** - Check for constraint enforcement
- [ ] `[PERF]` **Caching** - Identify caching opportunities
- [ ] `[UX]` **Accessibility** - Check accessibility across all UI components

---

## Review Progress
- Total items: [count]
- By specialist:
  - SEC: [count] (critical: [count])
  - DB: [count] (critical: [count])
  - API: [count]
  - PERF: [count]
  - UX: [count]
  - ANTAG: [count]
  - QA: [count]
- Reviewed: 0
- Issues found: 0

## Issues Log
_Issues will be added here during review_
```

### Guidelines for Creating the Checklist

1. **Tag every item** - Each item MUST have a specialist tag (e.g., `[UX]`, `[DB]`, `[QA]`, `[SEC]`, `[PERF]`, `[API]`, `[ANTAG]`)
2. **Add severity when needed** - Append `-CRITICAL` or `-MINOR` for non-standard priority
3. **Prioritize security** - Security items should be reviewed first
4. **Group by specialist** - Organize items under specialist sections
5. **Include file paths** - List the specific files that need to be reviewed for each item
6. **Reference the spec** - Link each item back to the relevant spec section
7. **Only include completed items** - Only add items from the implementation plan that are marked `[x]` (completed)
8. **Use smart tagging** - Analyze file contents, not just paths, to determine the best specialist
9. **When in doubt, use [QA]** - QA specialist handles general quality review

---

## Commit and Push

After creating the checklist:

```bash
git add .ralph/review_checklist.md
git commit -m "Initialize review checklist for [feature] with specialist tags"
git push
```

Then STOP. The review loop will begin next.
