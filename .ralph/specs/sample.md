# [Feature Name]

## Overview

[1-2 sentence description of what this feature does and the value it provides to users.]

## Problem Statement

Currently, users experience [describe the current limitation or pain point]:
- [Specific problem 1]
- [Specific problem 2]
- [Specific problem 3]

This creates friction because [explain why this matters and the impact on users].

## Requirements

### Functional Requirements

1. **[Requirement Category 1]**: [Description of what the system must do]

2. **[Requirement Category 2]**: [Description of what the system must do]
   - [Sub-requirement a]
   - [Sub-requirement b]
   - [Sub-requirement c]

3. **[Requirement Category 3]**:
   - [Format/behavior specification]
   - Examples:
     - [Example 1]
     - [Example 2]
     - [Example 3]

4. **[Requirement Category 4]**: [Description with any special cases]

### Non-Functional Requirements

1. **Performance**: [Specify performance targets, e.g., response time, throughput]
2. **Caching**: [Specify caching strategy if applicable]
3. **Scalability**: [Specify scale requirements]

---

## Architecture

### High-Level Design

```
┌─────────────────────────────────────┐
│  [Entry Point / API Endpoint]       │
└──────────────────┬──────────────────┘
                   │
                   v
┌──────────────────┴──────────────────┐
│      [Service Layer]                │
│      (Orchestrator)                 │
│  - [Responsibility 1]               │
│  - [Responsibility 2]               │
│  - [Responsibility 3]               │
└──────────────────┬──────────────────┘
                   │
     ┌─────────────┼─────────────┐
     v             v             v
┌────┴────┐  ┌────┴────┐  ┌────┴────┐
│[Module1]│  │[Module2]│  │[Module3]│
└────┬────┘  └────┬────┘  └────┬────┘
     │             │             │
     └─────────────┼─────────────┘
                   v
┌──────────────────┴──────────────────┐
│     [Data Access Layer]             │
│     ([Table/Data Source])           │
└─────────────────────────────────────┘
```

### Design Pattern

[Explain the chosen design pattern (Strategy, Factory, Repository, etc.) and why it's appropriate]:
1. [How components interact]
2. [Key benefits of this approach]
3. [How it enables extensibility]

---

## Data Model

### Entity Mapping

| Category | Types/Values |
|----------|--------------|
| [Category 1] | [Type A], [Type B], [Type C] |
| [Category 2] | [Type D], [Type E], [Type F] |
| [Category 3] | [Type G], [Type H], [Type I] |

### Source Table: [TABLE_NAME]

The feature uses the existing `[TABLE_NAME]` table which contains:

```sql
-- Key columns for this feature
COLUMN_1        VARCHAR(36)   -- [Description]
COLUMN_2        VARCHAR(36)   -- [Description]
COLUMN_3        VARCHAR(50)   -- [Description]
COLUMN_4        VARIANT       -- [Description]
COLUMN_5        BOOLEAN       -- [Description]
```

### API Response Schema

```typescript
interface [FeatureName]Response {
  id: string;
  [field1]: [type];
  [field2]: [type];
  items: [ItemType][];
}

interface [ItemType] {
  category: '[CATEGORY_A]' | '[CATEGORY_B]' | '[CATEGORY_C]';
  label: string;
  count: number;
  details: [DetailsType];
}

// Category-specific details
interface [DetailsTypeA] {
  [field]: [type];
}

interface [DetailsTypeB] {
  [field]: [type];
}
```

---

## Data Transformations

[If applicable, describe any data transformations or normalizations:]

| Source | Format | Transformation |
|--------|--------|----------------|
| [Source 1] | [Format description] | [Transformation logic] |
| [Source 2] | [Format description] | [Transformation logic] |
| [Source 3] | [Format description] | [Transformation logic] |

**Implementation**: [Brief description of where/how transformations are handled]

---

## Caching Strategy

### Redis Cache

- **Key Pattern**: `[feature-name]:${identifier}`
- **TTL**: [Duration] ([seconds] seconds)
- **Invalidation**: [When/how cache is invalidated]

### Cache Flow

```
1. Request arrives at [endpoint]
2. Check Redis for cached data
3. If cache hit → return cached data
4. If cache miss:
   a. [Query/compute step 1]
   b. [Query/compute step 2]
   c. Store in Redis with TTL
   d. Return computed result
5. On [invalidation event]: DELETE [cache-key-pattern]
```

---

## File Structure

```
libs/[library-name]/src/
├── domain/ports/
│   └── [feature].port.ts              # Interface definitions
├── application/[feature]/
│   ├── index.ts                       # Module exports
│   ├── [feature].service.ts           # Orchestrator service
│   ├── [feature].registry.ts          # Registry (if applicable)
│   └── [sub-modules]/
│       ├── index.ts
│       ├── [module-a].ts
│       ├── [module-b].ts
│       └── [module-c].ts
└── infrastructure/
    └── [feature].repository.ts        # Data access

libs/shared/common/src/lib/
└── [relevant-constants].ts            # Shared constants

apps/api/src/routes/
└── [resource].ts                      # API endpoint

apps/ui/src/components/[area]/
└── [Component].tsx                    # UI component
```

---

## UI Design

### Placement

[Describe where in the UI this feature appears and how it integrates with existing components.]

### Visual Design

```
┌─────────────────────────────────────────────────────────────────┐
│ [Section Header]                                     [Actions]  │
├─────────────────────────────────────────────────────────────────┤
│  [Column 1]   [Column 2]    [Column 3]    [Column 4]           │
│  [Value 1]    [Value 2]     [Value 3]     [Value 4]            │
├─────────────────────────────────────────────────────────────────┤
│ [Feature Section]                                               │
│                                                                 │
│ [Icon] [Category 1]      [Icon] [Category 2]      [Icon] [Cat3]│
│ [Count/Value]            [Count/Value]            [Count/Value]│
│ [Detail line 1]          [Detail line 1]          [Detail 1]   │
│ [Detail line 2]          [Detail line 2]          [Detail 2]   │
└─────────────────────────────────────────────────────────────────┘
```

### State Variations

[Describe any visual variations based on state, e.g., loading, empty, error, or mode-specific styling.]

---

## Error Handling

### Graceful Degradation

If [feature] computation fails:
1. Log error with full context
2. [Fallback behavior]
3. UI shows [user-friendly message]
4. [Core functionality] still works

### Edge Cases

| Scenario | Handling |
|----------|----------|
| [Edge case 1] | [How it's handled] |
| [Edge case 2] | [How it's handled] |
| [Edge case 3] | [How it's handled] |
| [Edge case 4] | [How it's handled] |

---

## Testing Strategy

### Unit Tests

1. **[Component A] Tests**: [What scenarios to test]
   - [Scenario 1]
   - [Scenario 2]
   - [Scenario 3]

2. **[Component B] Tests**: [What scenarios to test]

3. **[Component C] Tests**:
   - [Scenario 1]
   - [Scenario 2]

### Integration Tests

1. **API Endpoint Test**: Full request/response cycle
2. **[End-to-end scenario]**: [Description]

### Manual Testing Checklist

- [ ] [Test case 1]
- [ ] [Test case 2]
- [ ] [Test case 3]
- [ ] [Test case 4]
- [ ] [Performance test case]
- [ ] [Edge case test]

---

## Security Considerations

1. **Authorization**: [How access is controlled]
2. **Input Validation**: [What validation is performed]
3. **SQL Injection**: [How it's prevented]
4. **Data Access**: [Access control rules]

---

## Future Enhancements

1. **[Enhancement 1]**: [Brief description]
2. **[Enhancement 2]**: [Brief description]
3. **[Enhancement 3]**: [Brief description]
4. **[Enhancement 4]**: [Brief description]
5. **[Enhancement 5]**: [Brief description]

---

## Dependencies

### Existing

- [Existing dependency 1]
- [Existing dependency 2]
- [Existing dependency 3]
- [Existing dependency 4]

### New

- [New component 1]
- [New component 2]
- [New component 3]
- [New component 4]

---

## Glossary

| Term | Definition |
|------|------------|
| [Term 1] | [Definition] |
| [Term 2] | [Definition] |
| [Term 3] | [Definition] |
| [Term 4] | [Definition] |
