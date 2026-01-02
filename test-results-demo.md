# FGABattle Test Results - Demo Session

## Test Environment
- **Date**: 2026-01-02
- **OpenFGA Version**: v1.11.1
- **Store ID**: 01KDYC1WTMXYRGSKMZ311X3HPJ
- **Authorization Model ID**: 01KDYC3MWZHYGT0NPQR0CPQ41H

## Authorization Model
**Model**: Document-based permissions (models/document-simple.fga)

Permission hierarchy:
```
owner → editor → viewer
  │       │        │
  │       │        └─→ can_read
  │       └─→ can_write
  └─→ can_delete
```

## Test Data
Created relationships for two documents:

### planning-doc
- **alice**: owner
- **bob**: editor
- **charlie**: viewer

### budget-2026
- **alice**: owner
- **david**: viewer

## Authorization Check Results

### Test 1: Permission Hierarchy
| User | Relation | Object | Expected | Result | Status |
|------|----------|--------|----------|--------|--------|
| alice | can_delete | planning-doc | ✓ | allowed: true | ✅ PASS |
| bob | can_write | planning-doc | ✓ | allowed: true | ✅ PASS |
| bob | can_delete | planning-doc | ✗ | allowed: false | ✅ PASS |
| charlie | can_read | planning-doc | ✓ | allowed: true | ✅ PASS |
| charlie | can_write | planning-doc | ✗ | allowed: false | ✅ PASS |

### Test 2: Permission Inheritance
| User | Relation | Object | Expected | Result | Status |
|------|----------|--------|----------|--------|--------|
| alice | can_read | planning-doc | ✓ (inherited from owner) | allowed: true | ✅ PASS |

### Test 3: List Objects
| User | Relation | Expected Objects | Result | Status |
|------|----------|------------------|--------|--------|
| alice | can_read | [planning-doc, budget-2026] | [document:budget-2026, document:planning-doc] | ✅ PASS |
| bob | can_write | [planning-doc] | [document:planning-doc] | ✅ PASS |

## Summary
- **Total Tests**: 8
- **Passed**: 8
- **Failed**: 0
- **Success Rate**: 100%

## Key Findings
1. ✅ Permission hierarchy works correctly (owner → editor → viewer)
2. ✅ Permission inheritance functions as expected
3. ✅ Authorization checks properly deny unauthorized actions
4. ✅ List-objects API correctly returns accessible resources
5. ✅ Multiple documents with different permission sets are isolated correctly

## Next Steps
- Create more complex authorization models (organizations, teams, nested hierarchies)
- Add K6 load tests for performance benchmarking
- Test conditional relationships and contextual permissions
- Compare with other OpenFGA-compatible implementations
