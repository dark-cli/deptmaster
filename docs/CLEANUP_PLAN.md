# Repository Cleanup Plan

## Overview
This document outlines the cleanup tasks for the repository to remove outdated files, consolidate scripts, and improve maintainability.

## Statistics
- **Markdown files**: 142 total (74 in root directory)
- **Shell scripts**: 28 total (13 in root directory)
- **Build artifacts**: ~6.2GB (mobile/build: 1.9GB, backend/rust-api/target: 4.3GB)
- **Backup files**: Multiple .zip files and temp_backup/ directory

---

## Task 1: Remove Outdated Status/Update README Files (Priority: HIGH)

### Root Directory (74 files to review)
**Keep:**
- `README.md` - Main project documentation

**Remove (outdated status/update files):**
- ALL_ERRORS_FIXED.md
- ALL_FIXED_FINAL.md
- ALL_FIXED.md
- ALL_FONTS_DEFAULT.md
- ALL_WORKING.md
- APP_READY.md
- APP_RUNNING.md
- BALANCE_FIXED.md
- BALANCE_SYSTEM.md
- CHECK_CONSOLE.md
- CHECK_SERVER.md
- CLIENT_STATUS.md
- CONSOLE_CLEANED.md
- CONTACT_TRANSACTIONS_ADDED.md
- CREATE_ENDPOINTS_IMPLEMENTED.md
- CREATE_WORKING.md
- DATA_IMPORTED.md
- DEBUG_TRANSACTIONS.md
- DEFAULT_FONTS_FIXED.md
- DESKTOP_FIX.md
- DESKTOP_TRANSACTIONS_FIXED.md
- DESKTOP_WORKS_BY_DEFAULT.md
- FINAL_STATUS.md
- FIXED_ERRORS.md
- FIXED_TRANSACTION_ERROR.md
- FIXES_APPLIED.md
- FLUTTER_APP_RUNNING.md
- FLUTTER_READY.md
- FLUTTER_WEB_STATUS.md
- HOT_RELOAD_ANSWER.md
- HOW_TO_STOP_SERVER.md
- ICONS_FIXED.md
- IMPLEMENTATION_COMPLETE.md
- IMPORT_DEBITUM.md
- INSTALL_FLUTTER.md
- INSTALL_INSTRUCTIONS.md
- INSTALL_LINUX_TOOLS.md
- INSTALL_STEPS.md
- ITEMS_REMOVED_COMPLETE.md
- ITEMS_REMOVED.md
- LINUX_DESKTOP_SETUP.md
- MANUAL_REFRESH_ACTIVE.md
- MANUAL_REFRESH_FINAL.md
- MANUAL_REFRESH_ONLY.md
- NAME_SORTING_COMPLETE.md
- NEW_UI_IMPLEMENTED.md
- NO_AUTO_REFRESH.md
- NO_AUTO_START.md
- QUICK_LINUX_START.md
- QUICK_START.md
- README_RUNNING.md
- READY.md
- READY_NOW.md
- READY_TO_TEST.md
- READY_TO_USE.md
- REBUILD_APP.md
- REFRESH_COMPLETE.md
- RUN_LINUX_APP.md
- SERVER_STATUS.md
- SETUP_COMPLETE.md
- SORT_BY_NAME_ADDED.md
- SORTING_ADDED.md
- SORTING_COMPLETE.md
- SOURCE_MAP_FIXED.md
- STATUS.md
- SUCCESS_ALL_WORKING.md
- SUCCESS.md
- TRANSACTION_FIX.md
- TRANSACTION_STATUS.md
- TRANSACTIONS_FIX.md
- TRANSLATION.md
- UI_COMPLETE.md
- USER_CONTROLS_SERVER.md
- WEB_FIX_SUMMARY.md

**Review/Consolidate:**
- Move installation instructions to main README.md or docs/INSTALLATION.md

---

## Task 2: Consolidate Shell Scripts (Priority: HIGH)

### Current Root Scripts (13 files)
**Keep:**
- `manage.sh` - Main unified management script

**Remove/Consolidate into manage.sh:**
- CHECK_AND_INSTALL.sh → Add `check` and `install` commands
- INSTALL_LINUX_DEPS.sh → Add `install-deps` command
- INSTALL_NOW.sh → Add `install` command
- RESET_DATABASE.sh → Already exists as `reset-db`
- RESTART_SERVER.sh → Already exists as `restart-server`
- RUN_APP.sh → Add `run-app` command
- START_AFTER_SELINUX.sh → Add `start-after-selinux` command
- START_SERVER.sh → Already exists as `start-server`
- START_WITH_YOUR_DATA.sh → Add `start-with-data` command
- STOP_SERVER.sh → Already exists as `stop-server`
- TEST_APP.sh → Add `test-app` command
- test_server.sh → Add `test-server` command
- run_integration_test.sh → Add `test-integration` command

### Mobile Scripts (Review)
- Keep essential scripts, remove redundant ones
- Consolidate run scripts into manage.sh

---

## Task 3: Clean Up Mobile Directory (Priority: MEDIUM)

### Mobile Markdown Files
**Keep:**
- mobile/README.md - Main mobile documentation
- mobile/ARCHITECTURE_V2.md - Architecture documentation

**Review/Consolidate:**
- Move setup/installation docs to main docs/
- Remove outdated status files

**Remove:**
- mobile/CHANGES_SUMMARY.md (outdated)
- mobile/CODE_FIXED.md (outdated)
- mobile/DEBUG_WEB.md (outdated)
- mobile/PHASE1_COMPLETE.md (outdated)
- mobile/README_FILTER_LOGS.md (outdated)
- mobile/README_START.md (outdated)

---

## Task 4: Remove Backup Files (Priority: MEDIUM)

**Remove:**
- `temp_backup/` directory
- `debitum-backup-2026-01-18T05_51_03.zip` (old backup)
- Any other `*.zip` backup files in root

**Note:** Backup scripts in `scripts/` should remain for future use.

---

## Task 5: Update .gitignore (Priority: HIGH)

**Add/Verify:**
- `mobile/build/` - Build artifacts (~1.9GB)
- `backend/rust-api/target/` - Rust build artifacts (~4.3GB)
- `*.log` - Log files
- `__pycache__/` - Python cache
- `*.pyc` - Python compiled files
- `.DS_Store` - macOS files
- `*.backup` - Backup files
- `temp_backup/` - Temporary backup directory

---

## Task 6: Remove Log Files (Priority: LOW)

**Remove:**
- `mobile/flutter_01.log`
- `mobile/build/**/*.log` (build logs)
- Any other `*.log` files

---

## Task 7: Review and Consolidate Docs Directory (Priority: LOW)

**Review:**
- Check for duplicate/outdated documentation
- Consolidate similar docs
- Update main README.md with links to relevant docs

---

## Task 8: Remove Python Cache (Priority: LOW)

**Remove:**
- `scripts/__pycache__/` directory
- Any `*.pyc` files

---

## Task 9: Enhance manage.sh (Priority: HIGH)

**Add missing commands:**
- `run-app` - Run Flutter mobile app
- `run-web` - Run Flutter web app
- `test-app` - Run Flutter tests
- `test-server` - Test server endpoints
- `test-integration` - Run integration tests
- `install-deps` - Install system dependencies
- `check` - Check system requirements
- `start-with-data` - Start server with data import

---

## Execution Order

1. ✅ Create cleanup plan (this document)
2. ⏳ Remove outdated README files from root
3. ⏳ Update .gitignore
4. ⏳ Enhance manage.sh with missing commands
5. ⏳ Remove redundant shell scripts
6. ⏳ Remove backup files
7. ⏳ Clean mobile directory
8. ⏳ Remove log files and cache
9. ⏳ Review docs directory

---

## Notes

- All changes are on `cleanup-repo` branch
- Test manage.sh commands after consolidation
- Update main README.md with new script usage
- Consider creating CHANGELOG.md for future updates
