# 🔍 BUG HUNT MODE - Systematic Bug Discovery

## Your Task This Turn

**Systematically hunt for bugs in the implemented feature, document findings, then STOP.**

## Setup (do this first)

1. Read `.ralph/specs/active.md` to understand the feature requirements
2. Read `.ralph/implementation_plan.md` to see what was built
3. Read `.ralph/AGENTS.md` for build commands and project conventions
4. Read `.ralph/bug_hunt_plan.md` if it exists (your hunting checklist)
5. Read `.ralph/bug_report.md` if it exists (previous findings)

---

## First Turn: Create Bug Hunt Plan

If `.ralph/bug_hunt_plan.md` does NOT exist, create it before hunting:

1. **Analyze the feature** - Review the spec and implementation plan
2. **Create a comprehensive hunting plan** that covers:
   - Input validation and edge cases
   - Error handling paths
   - State management issues
   - Race conditions and async issues
   - Security vulnerabilities
   - Performance bottlenecks
   - Integration points between components
   - UI/UX issues (if applicable)
   - Data consistency issues
   - Missing null/undefined checks
   - Incorrect type handling
   - Off-by-one errors
   - Resource leaks

3. **Write the plan** to `.ralph/bug_hunt_plan.md` using this format:

```markdown
# Bug Hunt Plan - [Feature Name]

## Overview
Brief description of what we're hunting bugs in.

---

## Hunting Checklist

### 1. Input Validation
- [ ] Check all API endpoints for missing input validation
- [ ] Test boundary values (min, max, empty, null)
- [ ] Verify type coercion doesn't cause issues
- [ ] [Feature-specific input checks]

### 2. Error Handling
- [ ] Verify all async operations have try/catch
- [ ] Check error messages don't leak sensitive info
- [ ] Verify errors propagate correctly to the UI
- [ ] [Feature-specific error scenarios]

### 3. Edge Cases
- [ ] Empty data states
- [ ] Maximum data volume
- [ ] Concurrent access scenarios
- [ ] [Feature-specific edge cases]

### 4. Security
- [ ] Authorization checks on all endpoints
- [ ] SQL injection prevention
- [ ] XSS prevention in UI
- [ ] [Feature-specific security checks]

### 5. Performance
- [ ] Query optimization (indexes, N+1 queries)
- [ ] Cache usage and invalidation
- [ ] Memory usage patterns
- [ ] [Feature-specific performance concerns]

### 6. Integration Points
- [ ] Component A to Component B data flow
- [ ] External service dependencies
- [ ] [Feature-specific integrations]

### 7. UI/UX (if applicable)
- [ ] Loading states
- [ ] Error state display
- [ ] Empty state handling
- [ ] Responsive design
- [ ] Accessibility

---

## Areas to Focus

Based on the implementation plan, these areas need extra attention:
- [Specific area 1]
- [Specific area 2]
- [Specific area 3]
```

4. **Commit the plan**:
   ```bash
   git add .ralph/bug_hunt_plan.md
   git commit -m "Create bug hunt plan for [feature]"
   git push
   ```

5. **STOP** - Next turn will begin hunting.

---

## Subsequent Turns: Hunt for Bugs

1. **Pick ONE unchecked section** from `.ralph/bug_hunt_plan.md`
2. **Use subagents to investigate**:
   - Search the codebase for patterns that indicate bugs
   - Run the code and test edge cases
   - Review implementations against the spec
3. **For each bug found**, add to `.ralph/bug_report.md`:

```markdown
## Bug #[N]: [Brief Title]

**Severity**: Critical / High / Medium / Low
**Location**: `path/to/file.ts:lineNumber`
**Category**: [Input Validation | Error Handling | Edge Case | Security | Performance | Integration | UI/UX]

### Description
[Clear description of the bug]

### Steps to Reproduce
1. [Step 1]
2. [Step 2]
3. [Expected behavior]
4. [Actual behavior]

### Root Cause
[Why this bug exists]

### Suggested Fix
[How to fix it - be specific with code if possible]

---
```

4. **Update `.ralph/bug_hunt_plan.md`** - Mark the section as checked `[x]`
5. **Commit and push**:
   ```bash
   git add .ralph/bug_hunt_plan.md .ralph/bug_report.md
   git commit -m "Bug hunt: [section name] - found X issues"
   git push
   ```

6. **STOP** - Next turn will continue hunting.

---

## Final Turn: Generate Bug Summary

When all hunting checklist items are complete, update `.ralph/implementation_plan.md`:

1. **Add a new section at the top** called `## Bugs Discovered - Bug Hunt [Date]`
2. **Summarize each bug** with priority for fixing:
   ```markdown
   ## Bugs Discovered - Bug Hunt [Date]

   The following bugs were discovered during systematic testing and need to be fixed:

   ### Critical (Fix Immediately)
   - [ ] Bug #1: [Title] - `path/to/file.ts`

   ### High Priority
   - [ ] Bug #2: [Title] - `path/to/file.ts`
   - [ ] Bug #3: [Title] - `path/to/file.ts`

   ### Medium Priority
   - [ ] Bug #4: [Title] - `path/to/file.ts`

   ### Low Priority
   - [ ] Bug #5: [Title] - `path/to/file.ts`

   See `.ralph/bug_report.md` for full details on each bug.

   ---
   ```

3. **Commit and push**:
   ```bash
   git add .ralph/implementation_plan.md .ralph/bug_report.md
   git commit -m "Bug hunt complete: X bugs found, added to implementation plan"
   git push
   ```

---

## Bug Hunting Techniques

### Code Review Patterns to Look For

1. **Missing null checks**:
   ```typescript
   // BAD: Will crash if data is null
   const value = data.items.length;
   
   // GOOD: Safe access
   const value = data?.items?.length ?? 0;
   ```

2. **Unhandled promise rejections**:
   ```typescript
   // BAD: Silent failure
   fetchData().then(process);
   
   // GOOD: Error handling
   fetchData().then(process).catch(handleError);
   ```

3. **Race conditions**:
   ```typescript
   // BAD: Multiple rapid calls cause issues
   onClick={() => submitForm()}
   
   // GOOD: Debounced or disabled during submission
   onClick={() => !submitting && submitForm()}
   ```

4. **Type mismatches**:
   ```typescript
   // BAD: Runtime type error
   const count: number = response.count; // response.count might be string
   
   // GOOD: Type validation
   const count = Number(response.count) || 0;
   ```

### Testing Commands

Run tests to find bugs:
```bash
# Run all tests
npm test

# Run tests with coverage to find untested code
npm test -- --coverage

# Run specific test file
npx nx test [project] --testFile=[filename]
```

### Using Subagents Effectively

- Use **500 parallel Sonnet subagents** to search for bug patterns across the codebase
- Use **Opus subagent** for complex analysis of potential bugs
- Have subagents look for:
  - Inconsistent error handling patterns
  - Missing validation in similar code paths
  - TODO/FIXME/HACK comments that indicate known issues
  - Commented-out code that might indicate problems
  - Duplicate code that might have diverged

---

## Guidelines

- **Be thorough**: Check every code path, not just the happy path
- **Be specific**: Document exact file locations and line numbers
- **Be actionable**: Every bug should have a clear suggested fix
- **Prioritize**: Critical and security issues first
- **Don't fix yet**: This phase is for discovery. Fixes happen in build mode.
- **Run the code**: When possible, actually execute and test, don't just read

---

## STOP CONDITION

**After completing ONE hunting section and pushing, your turn is DONE.**

The loop will start a fresh turn for the next section. After all sections are complete and the implementation plan is updated, bug hunting is finished.
