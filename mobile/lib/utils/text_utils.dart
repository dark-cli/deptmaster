/// Utility functions for handling mixed Arabic/English text
class TextUtils {
  TextUtils._();

  /// Wrap text with Unicode bidirectional control characters to force LTR
  /// This ensures English letters appear in correct position even with Arabic text
  static String forceLtr(String text) {
    if (text.isEmpty) return text;
    
    // Use Left-to-Right Mark (LRM) and Left-to-Right Isolate (LRI) to force LTR
    // \u200E = LRM (Left-to-Right Mark)
    // \u2066 = LRI (Left-to-Right Isolate)
    // \u2069 = PDI (Pop Directional Isolate)
    
    // Check if text contains Arabic characters (Unicode range \u0600-\u06FF)
    final hasArabic = text.contains(RegExp(r'[\u0600-\u06FF]'));
    
    if (hasArabic) {
      // Wrap with LRI and PDI to force LTR rendering
      return '\u2066$text\u2069';
    }
    
    return text;
  }
  
  /// Alternative: Use LRM at start and end
  static String forceLtrSimple(String text) {
    if (text.isEmpty) return text;
    // Left-to-Right Mark (LRM) - invisible character that forces LTR
    return '\u200E$text\u200E';
  }

  /// Returns true if text contains Arabic characters.
  static bool hasArabic(String text) {
    if (text.isEmpty) return false;
    return text.contains(RegExp(r'[\u0600-\u06FF]'));
  }
}
