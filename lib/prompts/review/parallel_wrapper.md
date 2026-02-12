# PARALLEL REVIEW MODE - ISOLATED OUTPUT

**You are running as ONE of several parallel review specialists.**
Another specialist is reviewing different items at the same time.

## CRITICAL: Isolation Rules

To avoid conflicts with other parallel specialists, you MUST follow these rules:

### 1. Write to ISOLATED files only

- **DO NOT write to `.ralph/review.md`** — write your findings to `.ralph/parallel_reviews/review_SPECIALIST.md` instead (where SPECIALIST is your type, e.g., `review_security.md`)
- **DO NOT modify `.ralph/review_checklist.md`** — write the items you checked to `.ralph/parallel_reviews/checked_SPECIALIST.md` instead

### 2. DO NOT commit or push

- **DO NOT run `git add`, `git commit`, or `git push`** — the orchestrator will handle this after all specialists complete

### 3. Checked items format

In your `checked_SPECIALIST.md` file, list the EXACT text of each checklist item you reviewed (one per line), so the orchestrator can match and mark them complete in the main checklist. Use this format:

```
- [x] [TAG] Exact text of the checklist item as it appears in review_checklist.md
```

### 4. Findings format

Write your findings to `review_SPECIALIST.md` using the same format as your normal review output (the section below describes your specialist focus).

---

# SPECIALIST PROMPT FOLLOWS BELOW

