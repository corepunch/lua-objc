/* AUTO-GENERATED — do not edit by hand.
 * Regenerate with:  python3 tools/gen_bridge.py --xml tools/bridge.xml
 * Source:           tools/bridge.xml
 */

/* --- nsview_index property lookups --- */
/* #include this block inside nsview_index, after the key check. */
#if defined(GEN_PROPS_INDEX)
INDEX_NUMBER("padding", kPaddingKey, 0);
INDEX_NUMBER("paddingHorizontal", kPaddingHorizontalKey, 0);
INDEX_NUMBER("paddingVertical", kPaddingVerticalKey, 0);
INDEX_NUMBER("spacing", kSpacingKey, kStackSpacing);
INDEX_STRING("alignment", kAlignmentKey, "center");
INDEX_NUMBER("fixedWidth", kFixedWidthKey, 0);
INDEX_NUMBER("fixedHeight", kFixedHeightKey, 0);
INDEX_NUMBER("minWidth", kMinWidthKey, 0);
INDEX_NUMBER("minHeight", kMinHeightKey, 0);
INDEX_NUMBER_OR_NIL("maxWidth", kMaxWidthKey);
INDEX_NUMBER_OR_NIL("maxHeight", kMaxHeightKey);
INDEX_NUMBER("flexGrow", kFlexGrowKey, 0);
INDEX_NUMBER("flexShrink", kFlexShrinkKey, 1);
INDEX_NUMBER_OR_NIL("flexBasis", kFlexBasisKey);
INDEX_BOOL("fillWidth", kFillWidthKey);
INDEX_BOOL("fillHeight", kFillHeightKey);
#endif /* GEN_PROPS_INDEX */

/* --- nsview_newindex property setters --- */
/* #include this block inside nsview_newindex, after the key check. */
#if defined(GEN_PROPS_NEWINDEX)
NEWINDEX_NUMBER("padding", kPaddingKey);
NEWINDEX_NUMBER("paddingHorizontal", kPaddingHorizontalKey);
NEWINDEX_NUMBER("paddingVertical", kPaddingVerticalKey);
NEWINDEX_NUMBER_CLAMP("spacing", kSpacingKey, MAX(0, val));
NEWINDEX_STRING("alignment", kAlignmentKey);
NEWINDEX_NUMBER("fixedWidth", kFixedWidthKey);
NEWINDEX_NUMBER("fixedHeight", kFixedHeightKey);
NEWINDEX_NUMBER("minWidth", kMinWidthKey);
NEWINDEX_NUMBER("minHeight", kMinHeightKey);
NEWINDEX_NILABLE_NUMBER("maxWidth", kMaxWidthKey);
NEWINDEX_NILABLE_NUMBER("maxHeight", kMaxHeightKey);
NEWINDEX_NUMBER_CLAMP("flexGrow", kFlexGrowKey, MAX(0, val));
NEWINDEX_NUMBER_CLAMP("flexShrink", kFlexShrinkKey, MAX(0, val));
NEWINDEX_NILABLE_NUMBER_CLAMP("flexBasis", kFlexBasisKey, MAX(0, val));
NEWINDEX_BOOL("fillWidth", kFillWidthKey);
NEWINDEX_BOOL("fillHeight", kFillHeightKey);
#endif /* GEN_PROPS_NEWINDEX */
