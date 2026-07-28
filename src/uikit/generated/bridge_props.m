/* AUTO-GENERATED — do not edit by hand.
 * Regenerate with:  python3 tools/gen_bridge.py --xml tools/UIKit.xml
 * Source:           tools/UIKit.xml
 */

/* --- nsview_index property lookups --- */
/* #include this block inside nsview_index, after the key check. */
#if defined(GEN_PROPS_INDEX)
if ([obj isKindOfClass:[UIView class]]) {
	INDEX_NUMBER("padding", &kPaddingKey, 12.0);
	INDEX_STRING("alignment", &kAlignmentKey, "center");
	INDEX_NUMBER("fixedWidth", &kFixedWidthKey, 0);
	INDEX_NUMBER("fixedHeight", &kFixedHeightKey, 0);
}
#endif /* GEN_PROPS_INDEX */

/* --- nsview_newindex property setters --- */
/* #include this block inside nsview_newindex, after the key check. */
#if defined(GEN_PROPS_NEWINDEX)
if ([obj isKindOfClass:[UIView class]]) {
	NEWINDEX_NUMBER("padding", &kPaddingKey);
	NEWINDEX_STRING("alignment", &kAlignmentKey);
	NEWINDEX_NUMBER("fixedWidth", &kFixedWidthKey);
	NEWINDEX_NUMBER("fixedHeight", &kFixedHeightKey);
}
#endif /* GEN_PROPS_NEWINDEX */
