/// "+4" / "−7" (true minus sign).
String formatDelta(int delta) => delta >= 0 ? '+$delta' : '−${-delta}';
