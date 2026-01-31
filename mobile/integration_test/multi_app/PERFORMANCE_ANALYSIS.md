# Performance Analysis

## Date: 2026-01-24

### Single App Performance Test Results

**Total Time**: 3.5 seconds for single app setup + one contact creation + sync

**Breakdown**:
1. **Sync**: 1,502ms (42.5%) - Network operation, expected
2. **Ensure Test User**: 1,207ms (34.2%) - **BOTTLENECK** - Calls Rust binary
3. **Login**: 627ms (17.7%) - HTTP call, expected
4. **Server Reset**: 137ms (3.9%) - Fast with API endpoint
5. **Initialize Instance**: 27ms (0.8%) - Fast
6. **Create Contact**: 16ms (0.5%) - Fast
7. **Hive Init**: 14ms (0.4%) - Fast
8. **Other**: <1ms each

### Why Basic Sync Scenarios Takes 33 Seconds

**Setup (per test)**:
- Server Reset: ~137ms (with API) or ~5-10s (with manage.sh fallback)
- Ensure Test User: ~1,207ms × 1 = 1.2s (only once, but called in setUp)
- Hive Init: ~14ms
- Create 3 App Instances: ~27ms × 3 = 81ms
- Login 3 Apps: ~627ms × 3 = 1.9s
- **Setup Total**: ~3.3s (with API) or ~8-13s (with manage.sh)

**Per Test Execution**:
- Create contact: ~16ms
- Sync wait: ~1.5s (network operation)
- Validations: ~500ms
- **Per Test**: ~2s

**For 4 Tests**:
- Setup: ~3.3s × 4 = 13.2s (if API works) or ~32-52s (if manage.sh)
- Test Execution: ~2s × 4 = 8s
- **Total**: ~21s (with API) or ~40-60s (with manage.sh)

**Actual**: 33 seconds suggests manage.sh is being used (API returns 404)

### Bottlenecks Identified

#### 1. Ensure Test User (1.2s per call) - **MAJOR BOTTLENECK**
**Problem**: Calls Rust binary `reset_password` which:
- Compiles Rust code (if not cached)
- Connects to database
- Generates bcrypt hash
- Updates database

**Solution**: 
- Move to `setUpAll` (runs once for all tests)
- Cache user creation
- Use SQL directly instead of Rust binary

#### 2. Server Reset (5-10s with manage.sh) - **MAJOR BOTTLENECK**
**Problem**: API endpoint returns 404, falls back to manage.sh which:
- Stops server
- Drops/recreates database
- Runs migrations
- Takes 5-10 seconds

**Solution**:
- Restart server to enable `/api/dev/clear-database` endpoint
- API endpoint takes only ~137ms

#### 3. Sync Operations (1.5s each) - **EXPECTED**
**Problem**: Network operations are inherently slow
**Solution**: 
- This is expected for network sync
- Can't optimize much without affecting functionality
- Multiple syncs in tests add up

#### 4. Multiple App Instances (3x setup time)
**Problem**: Each test creates 3 app instances
**Solution**:
- Use 2 apps instead of 3 for some tests
- Reuse instances across tests (if possible)

### Optimization Recommendations

#### High Impact (Easy to Implement)

1. **Move Ensure Test User to setUpAll**
   - Currently called in `setUp` (runs before each test)
   - Should be in `setUpAll` (runs once for all tests)
   - **Savings**: ~1.2s × (number of tests - 1) = ~3.6s for 4 tests

2. **Enable API Endpoint for Server Reset**
   - Restart server to enable `/api/dev/clear-database`
   - **Savings**: ~5-10s per test = ~20-40s for 4 tests

3. **Cache User Creation**
   - Check if user exists before creating
   - **Savings**: ~1.2s per test if user already exists

#### Medium Impact

4. **Reduce Number of Apps**
   - Use 2 apps instead of 3 for some tests
   - **Savings**: ~0.7s per test (one less login)

5. **Optimize Sync Wait Logic**
   - Reduce sync timeout checks
   - **Savings**: ~200-500ms per sync wait

#### Low Impact

6. **Parallel Operations**
   - Initialize apps in parallel (may cause conflicts)
   - **Savings**: ~0.1-0.2s per test

### Performance Results

**Before Optimizations**: 33 seconds for single test
**After Optimization 1 (setUpAll)**: ~21 seconds for single test (36% improvement)
**After Optimization 1 + 2 (Login check)**: ~21 seconds for single test
**All 4 Basic Sync Tests**: ~45 seconds total (down from ~132s if each took 33s)

### Remaining Bottlenecks

1. **Server Reset**: 5-10 seconds per test (using manage.sh fallback)
   - API endpoint returns 404 (server needs restart)
   - **Potential Savings**: 20-40 seconds for 4 tests

2. **Sync Operations**: 1.5 seconds each (network operations - expected)
   - Multiple syncs per test add up
   - **Cannot optimize** without affecting functionality

3. **Login**: 0.6 seconds per app × 3 apps = 1.8 seconds
   - HTTP calls are expected
   - **Minor optimization possible**: Reduce to 2 apps for some tests

### Implementation Priority

1. ✅ **Move ensureTestUserExists to setUpAll** - Easy, high impact
2. ⚠️ **Restart server to enable API endpoint** - Requires server restart
3. ✅ **Add user existence check** - Easy, medium impact
4. ⚠️ **Reduce app count** - May reduce test coverage
