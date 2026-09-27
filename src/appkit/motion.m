#pragma mark - Motion (AppKit glue for shared/motion.m)

/* The region a layout write can move: the view's layout owner, the subtree
 * the flex engine relays out for it. */
static NSView *motion_layout_owner(NSView *view) {
	return layout_owner(view);
}

/* Commit applies pending layout synchronously so frames are final before
 * they are compared with the snapshot. */
static void motion_flush_layout(NSArray<NSView *> *owners) {
	(void)owners;
	flush_pending_layout();
}
