String formatCategoryName(String raw) {
  final normalized = raw.trim().toLowerCase();
  if (normalized.isEmpty) return raw.trim();
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}
