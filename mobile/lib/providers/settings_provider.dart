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
