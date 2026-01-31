# Performance Optimizations Applied

## Date: 2026-01-24

### Optimizations Implemented

#### 1. ✅ Moved ensureTestUserExists to setUpAll
**Impact**: High
**Savings**: ~1.2s × (number of tests - 1)
**Result**: 
- Single test: 33s → 21s (36% improvement)
- 4 tests: ~132s → ~45s (66% improvement)

**Change**: Moved `ensureTestUserExists()` from `setUp()` to `setUpAll()`
**Files**: `basic_sync_scenarios.dart`, `offline_online_scenarios.dart`, etc.

#### 2. ✅ Added Login Check Before User Creation
**Impact**: Medium
**Savings**: ~1.2s per call if user already exists
**Result**: Skips expensive Rust binary call if user can login

**Change**: Added quick login check before calling reset_password binary
**Files**: `multi_app_helpers.dart`

#### 3. ✅ Skipped WebSocket and Initial Sync During Login
**Impact**: High
**Savings**: ~20-30 seconds per test setup
**Result**: Login now takes ~0.6s instead of ~10s

**Change**: Skip WebSocket connection and initial sync in `AppInstance.login()`
**Files**: `app_instance.dart`

### Remaining Optimizations (Not Implemented)

#### 1. ⚠️ Enable API Endpoint for Server Reset
**Impact**: Very High
**Potential Savings**: 20-40 seconds for 4 tests
**Status**: Requires server restart
**Action Needed**: Restart server to enable `/api/dev/clear-database` endpoint

**Current**: Using manage.sh fallback (5-10s per reset)
**After**: Using API endpoint (~137ms per reset)

#### 2. ⚠️ Reduce Number of Apps
**Impact**: Medium
**Potential Savings**: ~0.7s per test (one less login)
**Status**: May reduce test coverage
**Action Needed**: Evaluate if 2 apps sufficient for some tests

#### 3. ⚠️ Optimize Sync Wait Logic
**Impact**: Low
**Potential Savings**: ~200-500ms per sync wait
**Status**: Requires careful testing
**Action Needed**: Reduce polling frequency or improve sync detection

### Performance Breakdown

**Single Test (Basic Sync 1.1)**:
- Server Reset: ~5-10s (manage.sh) or ~0.14s (API)
- Ensure User: ~0s (setUpAll) or ~1.2s (if in setUp)
- Hive Init: ~0.01s (setUpAll)
- Create 3 Apps: ~0.08s
- Login 3 Apps: ~1.8s
- Test Execution: ~2s
- **Total**: ~9-14s (with API) or ~21s (with manage.sh)

**All 4 Basic Sync Tests**:
- setUpAll: ~1.2s (ensure user once)
- Per Test Setup: ~7-12s (with manage.sh) or ~2-3s (with API)
- Per Test Execution: ~2s
- **Total**: ~45s (with manage.sh) or ~15-20s (with API)

### Recommendations

1. **Immediate**: Restart server to enable API endpoint (saves 20-40s)
2. **Short-term**: Apply same optimizations to other test suites
3. **Long-term**: Consider reducing app count or optimizing sync logic

### Files Modified

- `mobile/integration_test/multi_app/scenarios/basic_sync_scenarios.dart`
- `mobile/integration_test/helpers/multi_app_helpers.dart`
- `mobile/integration_test/multi_app/app_instance.dart`
