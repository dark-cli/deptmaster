# Build Warnings Explanation

## Date: 2026-01-24

### 1. "Try `flutter pub outdated`" Message

**What it means:**
- Some packages have newer versions available
- Those versions may be incompatible with current dependency constraints
- Your current versions are working fine

**Action Required:** None - this is just informational

**To check (optional):**
```bash
flutter pub outdated
```

This will show which packages have updates available and why they're not being used.

---

### 2. json.hpp Deprecation Warnings

**Warning Messages:**
```
/home/max/dev/debitum/mobile/linux/flutter/ephemeral/.plugin_symlinks/flutter_secure_storage_linux/linux/include/json.hpp:24392:35: warning: identifier '_json' preceded by whitespace in a literal operator declaration is deprecated [-Wdeprecated-literal-operator]
```

**What they mean:**
- These are C++ compiler warnings from the `flutter_secure_storage_linux` plugin
- The plugin uses a C++ library (nlohmann/json) that has deprecated syntax
- The warnings are from the plugin's dependencies, **not your code**

**Why they appear:**
- `flutter_secure_storage_linux` includes C++ code that compiles on Linux
- The json.hpp header file uses deprecated C++ syntax
- The compiler warns about it, but it still compiles successfully

**Can you fix it?**
- ❌ **No** - This is in a third-party plugin
- ❌ You can't modify plugin source code
- ✅ Wait for plugin maintainers to update their dependencies

**Options:**
1. **Ignore them** (recommended) - They're harmless warnings
2. **Suppress warnings** - Add compiler flags (not recommended)
3. **Wait for plugin update** - Plugin maintainers will fix it eventually

**Impact:**
- ✅ **No functional impact** - Everything works fine
- ✅ **No security issues** - Just deprecation warnings
- ⚠️ **Cosmetic only** - Makes build output look noisy

---

### Summary

Both messages are **informational/harmless**:
- ✅ Your code is fine
- ✅ Everything compiles and works
- ✅ No action required
- ⚠️ These are from third-party dependencies

**Recommendation:** Ignore them for now. They'll be resolved when:
1. Plugin maintainers update their dependencies
2. You update to newer plugin versions (when compatible)
