# [Feature Name] - Implementation Checklist

## Overview

This checklist tracks the implementation of the [Feature Name] feature. See `spec.md` for full technical specification.

---

## Phase 1: Backend - Types & Interfaces

### 1.1 Create Core Interfaces
- [ ] Create `libs/[library]/src/domain/ports/[feature].port.ts`
  - [ ] Define `I[Feature]` interface
  - [ ] Define `[Feature]Result` type
  - [ ] Define supporting types:
    - [ ] `[TypeA]`
    - [ ] `[TypeB]`
    - [ ] `[TypeC]`
  - [ ] Define enums (if applicable):
    - [ ] `[EnumName]` ([VALUE_A], [VALUE_B], [VALUE_C])

### 1.2 Export from Domain Index
- [ ] Update `libs/[library]/src/domain/ports/index.ts` to export new types
- [ ] Update `libs/[library]/src/domain/index.ts` if needed

---

## Phase 2: Backend - Constants & Configuration

### 2.1 Add Feature Constants
- [ ] Update `libs/shared/common/src/lib/data/[constants-file].ts`
  - [ ] Add `[ConstantType]` type
  - [ ] Add `[CONSTANT_MAP]` mapping:
    ```typescript
    export const [CONSTANT_MAP]: Record<string, [ConstantType]> = {
      [EXISTING_CONSTANT.VALUE_A]: '[CATEGORY_A]',
      [EXISTING_CONSTANT.VALUE_B]: '[CATEGORY_A]',
      // ... additional mappings
    };
    ```

### 2.2 Add Configuration Constants (if applicable)
- [ ] Add `[FEATURE_CONFIG]` constant:
  ```typescript
  export const [FEATURE_CONFIG] = {
    [KEY_A]: { [property]: [value] },
    [KEY_B]: { [property]: [value] },
  } as const;
  ```

---

## Phase 3: Backend - Repository

### 3.1 Create Feature Repository
- [ ] Create `libs/[library]/src/infrastructure/[feature].repository.ts`
  - [ ] Define `[Feature]Repository` class
  - [ ] Implement `[primaryMethod](params)` method:
    - [ ] Query [TABLE_NAME] table
    - [ ] Apply filters ([filter conditions])
    - [ ] Group by [grouping fields]
    - [ ] Return [result type]
  - [ ] Implement `[secondaryMethod](params)` method:
    - [ ] [Method description]
  - [ ] Export singleton instance

### 3.2 Export from Infrastructure Index
- [ ] Update `libs/[library]/src/infrastructure/index.ts` to export repository

---

## Phase 4: Backend - Module Implementations

### 4.1 Create Module Directory Structure
- [ ] Create directory: `libs/[library]/src/application/[feature]/`
- [ ] Create directory: `libs/[library]/src/application/[feature]/[sub-modules]/` (if applicable)

### 4.2 Implement [Module A]
- [ ] Create `libs/[library]/src/application/[feature]/[sub-modules]/[module-a].ts`
  - [ ] Implement `I[Feature]` interface
  - [ ] `[methodA]()` returns '[VALUE_A]'
  - [ ] `[methodB]()` returns [list of related IDs]
  - [ ] `[methodC]()` returns '[Label A]'
  - [ ] `[processMethod](data)` implementation:
    - [ ] [Processing step 1]
    - [ ] [Processing step 2]
    - [ ] [Processing step 3]
    - [ ] Return `[ResultTypeA]`

### 4.3 Implement [Module B]
- [ ] Create `libs/[library]/src/application/[feature]/[sub-modules]/[module-b].ts`
  - [ ] Implement `I[Feature]` interface
  - [ ] `[methodA]()` returns '[VALUE_B]'
  - [ ] `[methodB]()` returns [list of related IDs]
  - [ ] `[methodC]()` returns '[Label B]'
  - [ ] `[processMethod](data)` implementation:
    - [ ] [Processing step 1]
    - [ ] [Processing step 2]
    - [ ] Return `[ResultTypeB]`

### 4.4 Implement [Module C]
- [ ] Create `libs/[library]/src/application/[feature]/[sub-modules]/[module-c].ts`
  - [ ] Implement `I[Feature]` interface
  - [ ] `[methodA]()` returns '[VALUE_C]'
  - [ ] `[methodB]()` returns [list of related IDs]
  - [ ] `[methodC]()` returns '[Label C]'
  - [ ] `[processMethod](data)` implementation:
    - [ ] [Processing step 1]
    - [ ] [Processing step 2]
    - [ ] Return `[ResultTypeC]`

### 4.5 Create Module Index
- [ ] Create `libs/[library]/src/application/[feature]/[sub-modules]/index.ts`
  - [ ] Export all modules

---

## Phase 5: Backend - Registry & Service

### 5.1 Create Registry (if applicable)
- [ ] Create `libs/[library]/src/application/[feature]/[feature].registry.ts`
  - [ ] Singleton pattern (matching existing registries)
  - [ ] `register(item)` method
  - [ ] `getAll()` method
  - [ ] `getBy[Key](key)` method
  - [ ] `initialize()` method that registers all items
  - [ ] Export singleton instance

### 5.2 Create Feature Service
- [ ] Create `libs/[library]/src/application/[feature]/[feature].service.ts`
  - [ ] Inject repository and registry
  - [ ] Inject Redis service (if caching)
  - [ ] Implement `[primaryMethod](params)`:
    - [ ] Check Redis cache first (if applicable)
    - [ ] If cache miss:
      - [ ] [Computation step 1]
      - [ ] [Computation step 2]
      - [ ] [Computation step 3]
      - [ ] Cache result with TTL
    - [ ] Return [ResponseType]
  - [ ] Implement `[secondaryMethod](params)`:
    - [ ] [Method logic]
  - [ ] Export singleton instance

### 5.3 Create Module Index
- [ ] Create `libs/[library]/src/application/[feature]/index.ts`
  - [ ] Export service
  - [ ] Export registry
  - [ ] Export sub-modules

### 5.4 Update Application Index
- [ ] Update `libs/[library]/src/application/index.ts`
  - [ ] Add export for [feature] module

---

## Phase 6: Backend - API Endpoint

### 6.1 Add Route Handler
- [ ] Update `apps/api/src/routes/[resource].ts`
  - [ ] Import `[feature]Service` from [library]
  - [ ] Add [HTTP_METHOD] `/api/[resource]/[endpoint]` endpoint:
    - [ ] Validate input parameters
    - [ ] Check resource exists
    - [ ] Apply feature guard (require[Permission] for [FEATURE])
    - [ ] Call `[feature]Service.[method](params)`
    - [ ] Return JSON response
    - [ ] Handle errors gracefully

### 6.2 Add OpenAPI Documentation
- [ ] Add Swagger JSDoc comments for the endpoint:
  - [ ] Summary and description
  - [ ] Parameter documentation
  - [ ] Response schema documentation
  - [ ] Error responses (400, 404, 500)

---

## Phase 7: Backend - Integration Points

### 7.1 [Integration Point A]
- [ ] Update [related component/service]:
  - [ ] [Integration step 1]
  - [ ] [Integration step 2]

### 7.2 [Integration Point B] (if applicable)
- [ ] Update [related component/service]:
  - [ ] [Integration step 1]

---

## Phase 8: Frontend - Display Component

### 8.1 Add Types
- [ ] Create/update types file for [feature] response
  - [ ] Match the API response schema from spec

### 8.2 Add API Hook
- [ ] Create hook or add to existing hooks file:
  - [ ] `use[Feature](params)` hook
  - [ ] Fetch from `/api/[resource]/[endpoint]`
  - [ ] Handle loading, error, data states

### 8.3 Update [Component]
- [ ] Update `apps/ui/src/components/[area]/[Component].tsx`
  - [ ] Import [feature] hook
  - [ ] Add state for [feature] data
  - [ ] Fetch when [trigger condition]
  - [ ] Add "[Feature]" section:
    - [ ] Section header
    - [ ] Layout for content (grid, list, etc.)
    - [ ] For each item:
      - [ ] [Display element 1]
      - [ ] [Display element 2]
      - [ ] [Display element 3]
  - [ ] Handle loading state (skeleton)
  - [ ] Handle error state ("[Feature] unavailable")
  - [ ] Handle empty state (no data)

### 8.4 Styling
- [ ] Use existing Tailwind classes and component patterns
- [ ] Match visual style of existing components
- [ ] Ensure responsive layout (mobile-friendly)

---

## Phase 9: Testing

### 9.1 Unit Tests

#### Repository Tests
- [ ] Create `libs/[library]/src/infrastructure/[feature].repository.spec.ts`
  - [ ] Test `[primaryMethod]` with various filters
  - [ ] Test `[secondaryMethod]` accuracy
  - [ ] Test empty results handling

#### Module Tests
- [ ] Create `libs/[library]/src/application/[feature]/[sub-modules]/[module-a].spec.ts`
  - [ ] Test normal processing
  - [ ] Test edge case handling
  - [ ] Test empty input
  - [ ] Test null values handling

- [ ] Create `libs/[library]/src/application/[feature]/[sub-modules]/[module-b].spec.ts`
  - [ ] Test [specific scenario 1]
  - [ ] Test [specific scenario 2]
  - [ ] Test empty input

- [ ] Create `libs/[library]/src/application/[feature]/[sub-modules]/[module-c].spec.ts`
  - [ ] Test [specific scenario 1]
  - [ ] Test [specific scenario 2]
  - [ ] Test empty input

#### Service Tests
- [ ] Create `libs/[library]/src/application/[feature]/[feature].service.spec.ts`
  - [ ] Test cache hit scenario
  - [ ] Test cache miss and computation
  - [ ] Test cache invalidation (if applicable)
  - [ ] Test error handling
  - [ ] Test empty data scenario

#### Registry Tests (if applicable)
- [ ] Create `libs/[library]/src/application/[feature]/[feature].registry.spec.ts`
  - [ ] Test registration
  - [ ] Test getAll
  - [ ] Test getBy[Key]

### 9.2 Integration Tests
- [ ] Add integration test in `apps/api/tests/integration/`
  - [ ] Test full API endpoint
  - [ ] Test with real data
  - [ ] Test performance with large datasets

### 9.3 Frontend Tests
- [ ] Test [feature] component renders correctly
- [ ] Test loading state
- [ ] Test error state
- [ ] Test empty state
- [ ] Test [special state/mode]

---

## Phase 10: Documentation & Cleanup

### 10.1 Code Documentation
- [ ] Add JSDoc comments to all public methods
- [ ] Add inline comments for complex logic

### 10.2 Update AGENTS.md (if needed)
- [ ] Document the [feature] architecture
- [ ] Add to relevant section if applicable

### 10.3 Final Review
- [ ] Run linter: `npm run lint:all`
- [ ] Run tests: `npm run test:all`
- [ ] Run build: `npm run build:all`
- [ ] Manual testing with real data

---

## Verification Checklist

### Functional Verification
- [ ] [Functional requirement 1] works correctly
- [ ] [Functional requirement 2] works correctly
- [ ] [Functional requirement 3] works correctly
- [ ] [Edge case 1] handled properly
- [ ] [Edge case 2] handled properly
- [ ] Empty data shows appropriate state

### Performance Verification
- [ ] Response time <[target]ms for [scale] records
- [ ] Cache hit returns <[target]ms
- [ ] No memory issues with large datasets

### Integration Verification
- [ ] [Integration point 1] works correctly
- [ ] Feature guard properly applied
- [ ] UI matches existing design patterns

---

## File Checklist

### New Files
- [ ] `libs/[library]/src/domain/ports/[feature].port.ts`
- [ ] `libs/[library]/src/infrastructure/[feature].repository.ts`
- [ ] `libs/[library]/src/application/[feature]/index.ts`
- [ ] `libs/[library]/src/application/[feature]/[feature].service.ts`
- [ ] `libs/[library]/src/application/[feature]/[feature].registry.ts` (if applicable)
- [ ] `libs/[library]/src/application/[feature]/[sub-modules]/index.ts`
- [ ] `libs/[library]/src/application/[feature]/[sub-modules]/[module-a].ts`
- [ ] `libs/[library]/src/application/[feature]/[sub-modules]/[module-b].ts`
- [ ] `libs/[library]/src/application/[feature]/[sub-modules]/[module-c].ts`

### Modified Files
- [ ] `libs/shared/common/src/lib/data/[constants-file].ts`
- [ ] `libs/[library]/src/domain/ports/index.ts`
- [ ] `libs/[library]/src/infrastructure/index.ts`
- [ ] `libs/[library]/src/application/index.ts`
- [ ] `apps/api/src/routes/[resource].ts`
- [ ] `apps/ui/src/components/[area]/[Component].tsx`

### Test Files
- [ ] `libs/[library]/src/infrastructure/[feature].repository.spec.ts`
- [ ] `libs/[library]/src/application/[feature]/[feature].service.spec.ts`
- [ ] `libs/[library]/src/application/[feature]/[feature].registry.spec.ts`
- [ ] `libs/[library]/src/application/[feature]/[sub-modules]/[module-a].spec.ts`
- [ ] `libs/[library]/src/application/[feature]/[sub-modules]/[module-b].spec.ts`
- [ ] `libs/[library]/src/application/[feature]/[sub-modules]/[module-c].spec.ts`

---

## Notes

- [Important implementation note 1]
- [Important implementation note 2]
- [Important implementation note 3]
- [Important implementation note 4]
