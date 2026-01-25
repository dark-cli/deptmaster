import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/settings_service.dart';

// Provider for flip colors that can be watched and updated
final flipColorsProvider = StateNotifierProvider<FlipColorsNotifier, bool>((ref) {
  return FlipColorsNotifier();
});

class FlipColorsNotifier extends StateNotifier<bool> {
  FlipColorsNotifier() : super(false) {
    // Load initial value asynchronously
    _loadFlipColors();
  }

  Future<void> _loadFlipColors() async {
    try {
      final flipColors = await SettingsService.getFlipColors();
      if (state != flipColors) {
        state = flipColors;
      }
    } catch (e) {
      // If loading fails, keep default value (false)
      print('Error loading flip colors: $e');
    }
  }

  Future<void> setFlipColors(bool value) async {
    await SettingsService.setFlipColors(value);
    state = value;
  }

  Future<void> refresh() async {
    await _loadFlipColors();
  }
}

// Provider for due date enabled that can be watched and updated
final dueDateEnabledProvider = StateNotifierProvider<DueDateEnabledNotifier, bool>((ref) {
  return DueDateEnabledNotifier();
});

class DueDateEnabledNotifier extends StateNotifier<bool> {
  DueDateEnabledNotifier() : super(true) { // Default ON
    // Load initial value asynchronously
    _loadDueDateEnabled();
  }

  Future<void> _loadDueDateEnabled() async {
    try {
      final enabled = await SettingsService.getDueDateEnabled();
      if (state != enabled) {
        state = enabled;
      }
    } catch (e) {
      // If loading fails, keep default value (false)
      print('Error loading due date enabled: $e');
    }
  }

  Future<void> setDueDateEnabled(bool value) async {
    await SettingsService.setDueDateEnabled(value);
    state = value;
  }

  Future<void> refresh() async {
    await _loadDueDateEnabled();
  }
}

// Provider for show dashboard chart
final showDashboardChartProvider = StateNotifierProvider<ShowDashboardChartNotifier, bool>((ref) {
  return ShowDashboardChartNotifier();
});

class ShowDashboardChartNotifier extends StateNotifier<bool> {
  ShowDashboardChartNotifier() : super(true) {
    _loadShowDashboardChart();
  }

  Future<void> _loadShowDashboardChart() async {
    try {
      final enabled = await SettingsService.getShowDashboardChart();
      if (state != enabled) {
        state = enabled;
      }
    } catch (e) {
      print('Error loading show dashboard chart: $e');
    }
  }

  Future<void> setShowDashboardChart(bool value) async {
    await SettingsService.setShowDashboardChart(value);
    state = value;
  }

  Future<void> refresh() async {
    await _loadShowDashboardChart();
  }
}

// Provider for invert Y-axis
final invertYAxisProvider = StateNotifierProvider<InvertYAxisNotifier, bool>((ref) {
  return InvertYAxisNotifier();
});

class InvertYAxisNotifier extends StateNotifier<bool> {
  InvertYAxisNotifier() : super(false) {
    _loadInvertYAxis();
  }

  Future<void> _loadInvertYAxis() async {
    try {
      final invert = await SettingsService.getInvertYAxis();
      if (state != invert) {
        state = invert;
      }
    } catch (e) {
      print('Error loading invert Y-axis: $e');
    }
  }

  Future<void> setInvertYAxis(bool value) async {
    await SettingsService.setInvertYAxis(value);
    state = value;
  }

  Future<void> refresh() async {
    await _loadInvertYAxis();
  }
}

// Provider for dashboard default period
final dashboardDefaultPeriodProvider = StateNotifierProvider<DashboardDefaultPeriodNotifier, String>((ref) {
  return DashboardDefaultPeriodNotifier();
});

class DashboardDefaultPeriodNotifier extends StateNotifier<String> {
  DashboardDefaultPeriodNotifier() : super('month') {
    _loadDashboardDefaultPeriod();
  }

  Future<void> _loadDashboardDefaultPeriod() async {
    try {
      final period = await SettingsService.getDashboardDefaultPeriod();
      if (state != period) {
        state = period;
      }
    } catch (e) {
      print('Error loading dashboard default period: $e');
    }
  }

  Future<void> setDashboardDefaultPeriod(String period) async {
    await SettingsService.setDashboardDefaultPeriod(period);
    state = period;
  }

  Future<void> refresh() async {
    await _loadDashboardDefaultPeriod();
  }
}
