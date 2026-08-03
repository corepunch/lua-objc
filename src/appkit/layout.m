static void position_table_spinner(NSScrollView *sv);

static int bridge_object_add_impl(lua_State *L) {
	id parent = check_objc(L, 1);
	NSView *child = check_view(L, 2);

	NSView *container;
	if ([parent isKindOfClass:[NSWindow class]]) {
		NSWindow *window = (NSWindow *)parent;
		container = window.contentView;
		child.frame = container.bounds;
		child.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

		if (!objc_getAssociatedObject(window, &kKeys[kResizeObserverKey])) {
			__weak NSView *weakChild = child;
			__weak NSWindow *weakWindow = window;
			void (^relayoutRoot)(void) = ^{
				NSView *root = weakChild;
				NSWindow *observedWindow = weakWindow;
				if (!root || !observedWindow) return;
				root.frame = observedWindow.contentView.bounds;
				layout_recursive(root, root.bounds.size.width);
			};
			id windowObserver = [[NSNotificationCenter defaultCenter]
				addObserverForName:NSWindowDidResizeNotification
							object:window
							 queue:nil
						usingBlock:^(NSNotification *note) {
							relayoutRoot();
						}];

			/* Showing or hiding the native NSWindow tab bar changes the
			 * content view's frame without resizing the window. Observe that
			 * frame directly so the root never remains underneath the bar. */
			container.postsFrameChangedNotifications = YES;
			id contentObserver = [[NSNotificationCenter defaultCenter]
				addObserverForName:NSViewFrameDidChangeNotification
							object:container
							 queue:nil
						usingBlock:^(NSNotification *note) {
							relayoutRoot();
						}];
			NSArray *observers = @[windowObserver, contentObserver];
			objc_setAssociatedObject(window, &kKeys[kResizeObserverKey], observers,
				OBJC_ASSOCIATION_RETAIN);
		}
	} else {
		container = (NSView *)parent;
	}

	if ([container isKindOfClass:[NSSplitView class]]) {
		/*
		 * A split pane is a clipping boundary. NSView no longer clips to its
		 * bounds by default on modern macOS, so an intrinsically wide editor
		 * would otherwise draw across the divider into the next pane.
		 */
		/*
		 * NSSplitView adopts each pane's current frame as its initial holding
		 * size. Seed a declared fixed length before insertion so a table's
		 * 400-point construction frame cannot become the preserved width when
		 * the split is mounted into an already-constrained IDE canvas.
		 */
		NSSplitView *split = (NSSplitView *)container;
		NSNumber *fixedLength = objc_getAssociatedObject(
			child,
			split.isVertical
				? &kKeys[kFixedWidthKey]
				: &kKeys[kFixedHeightKey]);
		if (fixedLength.doubleValue > 0) {
			NSRect frame = child.frame;
			if (split.isVertical) {
				frame.size.width = fixedLength.doubleValue;
			} else {
				frame.size.height = fixedLength.doubleValue;
			}
			child.frame = frame;
		}
		child.clipsToBounds = YES;
		[split addArrangedSubview:child];
		if (!objc_getAssociatedObject(
				child, &kKeys[kSplitPaneFrameObserverKey])) {
			child.postsFrameChangedNotifications = YES;
			__weak NSView *weakChild = child;
			id observer = [[NSNotificationCenter defaultCenter]
				addObserverForName:NSViewFrameDidChangeNotification
							object:child
							 queue:nil
						usingBlock:^(NSNotification *note) {
							NSView *pane = weakChild;
							if (!pane) return;
							layout_recursive(pane, pane.bounds.size.width);
						}];
			objc_setAssociatedObject(
				child, &kKeys[kSplitPaneFrameObserverKey], observer,
				OBJC_ASSOCIATION_RETAIN);
		}
		return 0;
	}
	[container addSubview:child];
	return 0;
}

static BOOL is_flexible(NSView *view) {
	return [objc_getAssociatedObject(view, &kKeys[kFlexibleKey]) boolValue];
}

static BOOL is_hidden(NSView *view) {
	return view.isHidden;
}

static CGFloat view_padding_horizontal(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kPaddingHorizontalKey]);
	if (value) return value.doubleValue;
	NSNumber *p = objc_getAssociatedObject(view, &kKeys[kPaddingKey]);
	return p ? p.doubleValue : 0;
}

static CGFloat view_padding_vertical(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kPaddingVerticalKey]);
	if (value) return value.doubleValue;
	NSNumber *p = objc_getAssociatedObject(view, &kKeys[kPaddingKey]);
	return p ? p.doubleValue : 0;
}

static CGFloat view_spacing(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kSpacingKey]);
	return value ? value.doubleValue : kStackSpacing;
}

static NSString *view_alignment(NSView *view) {
	return objc_getAssociatedObject(view, &kKeys[kAlignmentKey]) ?: @"center";
}

static CGFloat view_fixed_width(NSView *view) {
	NSNumber *w = objc_getAssociatedObject(view, &kKeys[kFixedWidthKey]);
	return w ? w.doubleValue : 0;
}

static CGFloat view_fixed_height(NSView *view) {
	NSNumber *h = objc_getAssociatedObject(view, &kKeys[kFixedHeightKey]);
	return h ? h.doubleValue : 0;
}

static CGFloat view_optional_dimension(NSView *view, const void *key, CGFloat fallback) {
	NSNumber *value = objc_getAssociatedObject(view, key);
	return value ? value.doubleValue : fallback;
}

static CGFloat clamp_dimension(CGFloat value, CGFloat minimum, CGFloat maximum) {
	value = MAX(value, minimum);
	if (isfinite(maximum)) value = MIN(value, maximum);
	return MAX(0, value);
}

static BOOL default_grows_on_axis(NSView *view, BOOL horizontal) {
	if (!is_flexible(view)) return NO;
	LayoutAxis axis = layout_axis(view);
	if (!horizontal && axis == LayoutAxisHStack) return NO;
	if (horizontal && axis == LayoutAxisVSplit) return NO;
	return YES;
}

static CGFloat view_flex_grow(NSView *view, BOOL horizontal) {
	if ((horizontal && view_fixed_width(view) > 0) ||
		(!horizontal && view_fixed_height(view) > 0)) {
		return 0;
	}
	NSNumber *grow = objc_getAssociatedObject(view, &kKeys[kFlexGrowKey]);
	if (grow) return MAX(0, grow.doubleValue);
	return default_grows_on_axis(view, horizontal) ? 1 : 0;
}

static CGFloat view_flex_shrink(NSView *view, BOOL horizontal) {
	if ((horizontal && view_fixed_width(view) > 0) ||
		(!horizontal && view_fixed_height(view) > 0)) {
		return 0;
	}
	NSNumber *shrink = objc_getAssociatedObject(view, &kKeys[kFlexShrinkKey]);
	if (shrink) return MAX(0, shrink.doubleValue);
	return is_flexible(view) ? 1 : 0;
}

static BOOL view_fills_cross_axis(NSView *view, BOOL horizontal) {
	const void *key = horizontal ? &kKeys[kFillWidthKey] : &kKeys[kFillHeightKey];
	NSNumber *fill = objc_getAssociatedObject(view, key);
	return fill ? fill.boolValue : view_flex_grow(view, horizontal) > 0;
}

typedef NS_ENUM(NSInteger, LuaMeasureMode) {
	LuaMeasureUndefined,
	LuaMeasureAtMost,
	LuaMeasureExactly,
};

typedef struct {
	CGFloat width;
	CGFloat height;
	LuaMeasureMode widthMode;
	LuaMeasureMode heightMode;
} LuaLayoutConstraint;

static NSSize measure_view(NSView *view, LuaLayoutConstraint constraint);

static CGFloat constrained_result(CGFloat natural, CGFloat proposal,
								  LuaMeasureMode mode) {
	if (mode == LuaMeasureExactly) return MAX(0, proposal);
	if (mode == LuaMeasureAtMost) return MIN(MAX(0, natural), MAX(0, proposal));
	return MAX(0, natural);
}

static NSSize measure_leaf(NSView *view) {
	NSSize size = view.frame.size;
	NSSize intrinsic = view.intrinsicContentSize;
	if (intrinsic.width != NSViewNoIntrinsicMetric && intrinsic.width >= 0) {
		size.width = MAX(size.width, intrinsic.width);
	}
	if (intrinsic.height != NSViewNoIntrinsicMetric && intrinsic.height >= 0) {
		size.height = MAX(size.height, intrinsic.height);
	}

	NSSize fitting = view.fittingSize;
	if (fitting.width > 0) size.width = MAX(size.width, fitting.width);
	if (fitting.height > 0) size.height = MAX(size.height, fitting.height);
	if (size.width <= 0) size.width = kMinLeafWidth;
	if (size.height <= 0) size.height = kMinLeafHeight;
	return size;
}

static NSSize measure_view(NSView *view, LuaLayoutConstraint constraint) {
	if (!view) return NSZeroSize;

	CGFloat padX = view_padding_horizontal(view);
	CGFloat padY = view_padding_vertical(view);
	CGFloat innerWidth = constraint.widthMode == LuaMeasureUndefined
		? 0 : MAX(0, constraint.width - 2 * padX);
	CGFloat innerHeight = constraint.heightMode == LuaMeasureUndefined
		? 0 : MAX(0, constraint.height - 2 * padY);
	NSSize natural = NSZeroSize;

	switch (layout_axis(view)) {
	case LayoutAxisVStack: {
		NSInteger visibleCount = 0;
		for (NSView *child in view.subviews) {
			if (is_hidden(child)) continue;
			visibleCount++;
			LuaLayoutConstraint childConstraint = {
				.width = innerWidth,
				.height = 0,
				.widthMode = constraint.widthMode == LuaMeasureUndefined
					? LuaMeasureUndefined : LuaMeasureAtMost,
				.heightMode = LuaMeasureUndefined,
			};
			NSSize childSize = measure_view(child, childConstraint);
			natural.width = MAX(natural.width, childSize.width);
			natural.height += childSize.height;
		}
		if (visibleCount > 1) natural.height += (visibleCount - 1) * view_spacing(view);
		natural.width += 2 * padX;
		natural.height += 2 * padY;
	} break;
	case LayoutAxisHStack: {
		NSInteger visibleCount = 0;
		for (NSView *child in view.subviews) {
			if (is_hidden(child)) continue;
			visibleCount++;
			LuaLayoutConstraint childConstraint = {
				.width = 0,
				.height = innerHeight,
				.widthMode = LuaMeasureUndefined,
				.heightMode = constraint.heightMode == LuaMeasureUndefined
					? LuaMeasureUndefined : LuaMeasureAtMost,
			};
			NSSize childSize = measure_view(child, childConstraint);
			natural.width += childSize.width;
			natural.height = MAX(natural.height, childSize.height);
		}
		if (visibleCount > 1) natural.width += (visibleCount - 1) * view_spacing(view);
		natural.width += 2 * padX;
		natural.height += 2 * padY;
	} break;
	case LayoutAxisHSplit: {
		NSInteger visibleCount = 0;
		for (NSView *child in view.subviews) {
			if (is_hidden(child)) continue;
			visibleCount++;
			CGFloat fw = view_fixed_width(child);
			NSSize childSize;
			if (fw > 0) {
				childSize = NSMakeSize(fw, 0);
			} else {
				childSize = measure_view(child, (LuaLayoutConstraint){
					.width = 0,
					.height = innerHeight,
					.widthMode = LuaMeasureUndefined,
					.heightMode = constraint.heightMode == LuaMeasureUndefined
						? LuaMeasureUndefined : LuaMeasureAtMost,
				});
			}
			natural.width += childSize.width;
			natural.height = MAX(natural.height, childSize.height);
		}
		CGFloat dividers = visibleCount > 1
			? (visibleCount - 1) * [(NSSplitView *)view dividerThickness] : 0;
		natural.width += dividers + 2 * padX;
		natural.height += 2 * padY;
	} break;
	case LayoutAxisVSplit: {
		NSInteger visibleCount = 0;
		for (NSView *child in view.subviews) {
			if (is_hidden(child)) continue;
			visibleCount++;
			CGFloat fh = view_fixed_height(child);
			NSSize childSize;
			if (fh > 0) {
				childSize = NSMakeSize(0, fh);
			} else {
				childSize = measure_view(child, (LuaLayoutConstraint){
					.width = innerWidth,
					.height = 0,
					.widthMode = constraint.widthMode == LuaMeasureUndefined
						? LuaMeasureUndefined : LuaMeasureAtMost,
					.heightMode = LuaMeasureUndefined,
				});
			}
			natural.width = MAX(natural.width, childSize.width);
			natural.height += childSize.height;
		}
		CGFloat dividers = visibleCount > 1
			? (visibleCount - 1) * [(NSSplitView *)view dividerThickness] : 0;
		natural.width += 2 * padX;
		natural.height += dividers + 2 * padY;
	} break;
	default: break;
	}

	NSValue *imageLayoutSize =
		objc_getAssociatedObject(view, &kKeys[kImageLayoutSizeKey]);
	if (imageLayoutSize) {
		natural = imageLayoutSize.sizeValue;
		CGFloat scale = 1;
		if (constraint.widthMode != LuaMeasureUndefined
			&& natural.width > constraint.width && natural.width > 0) {
			scale = MIN(scale, constraint.width / natural.width);
		}
		if (constraint.heightMode != LuaMeasureUndefined
			&& natural.height > constraint.height && natural.height > 0) {
			scale = MIN(scale, constraint.height / natural.height);
		}
		natural.width *= MAX(0, scale);
		natural.height *= MAX(0, scale);
	} else if (layout_axis(view) == LayoutAxisNone) {
		natural = measure_leaf(view);
	}

	CGFloat fixedWidth = view_fixed_width(view);
	CGFloat fixedHeight = view_fixed_height(view);
	if (fixedWidth > 0) natural.width = fixedWidth;
	if (fixedHeight > 0) natural.height = fixedHeight;

	natural.width = clamp_dimension(
		natural.width,
		view_optional_dimension(view, &kKeys[kMinWidthKey], 0),
		view_optional_dimension(view, &kKeys[kMaxWidthKey], INFINITY));
	natural.height = clamp_dimension(
		natural.height,
		view_optional_dimension(view, &kKeys[kMinHeightKey], 0),
		view_optional_dimension(view, &kKeys[kMaxHeightKey], INFINITY));

	if (fixedWidth <= 0) {
		natural.width = constrained_result(
			natural.width, constraint.width, constraint.widthMode);
	}
	if (fixedHeight <= 0) {
		natural.height = constrained_result(
			natural.height, constraint.height, constraint.heightMode);
	}
	return natural;
}

static void distribute_main_axis(NSArray<NSView *> *children, CGFloat *sizes,
								 CGFloat available, BOOL horizontal) {
	NSUInteger count = children.count;
	if (count == 0) return;

	CGFloat used = 0;
	for (NSUInteger i = 0; i < count; i++) {
		if (!is_hidden(children[i])) used += sizes[i];
	}
	CGFloat freeSpace = available - used;
	if (fabs(freeSpace) < kFlexEpsilon) return;

	BOOL growing = freeSpace > 0;
	BOOL *frozen = calloc(count, sizeof(BOOL));
	for (NSUInteger pass = 0; pass < count && fabs(freeSpace) >= kFlexEpsilon; pass++) {
		CGFloat totalWeight = 0;
		for (NSUInteger i = 0; i < count; i++) {
			if (frozen[i] || is_hidden(children[i])) continue;
			NSView *child = children[i];
			CGFloat weight = growing
				? view_flex_grow(child, horizontal)
				: view_flex_shrink(child, horizontal) * MAX(kMinLeafWidth, sizes[i]);
			totalWeight += weight;
		}
		if (totalWeight <= 0) break;

		CGFloat distributed = 0;
		BOOL hitBound = NO;
		for (NSUInteger i = 0; i < count; i++) {
			if (frozen[i] || is_hidden(children[i])) continue;
			NSView *child = children[i];
			CGFloat weight = growing
				? view_flex_grow(child, horizontal)
				: view_flex_shrink(child, horizontal) * MAX(kMinLeafWidth, sizes[i]);
			if (weight <= 0) continue;

			CGFloat delta = freeSpace * weight / totalWeight;
			CGFloat minimum = view_optional_dimension(child,
				horizontal ? &kKeys[kMinWidthKey] : &kKeys[kMinHeightKey], 0);
			CGFloat maximum = view_optional_dimension(child,
				horizontal ? &kKeys[kMaxWidthKey] : &kKeys[kMaxHeightKey], INFINITY);
			CGFloat proposed = sizes[i] + delta;
			CGFloat clamped = clamp_dimension(proposed, minimum, maximum);
			distributed += clamped - sizes[i];
			sizes[i] = clamped;
			if (fabs(clamped - proposed) >= kFlexEpsilon) {
				frozen[i] = YES;
				hitBound = YES;
			}
		}
		freeSpace -= distributed;
		if (!hitBound) break;
	}
	free(frozen);
}

static void apply_initial_split_proportions(NSSplitView *split) {
	NSArray<NSView *> *panes = split.arrangedSubviews;
	NSUInteger count = panes.count;
	CGFloat totalLength = split.vertical
		? split.bounds.size.width : split.bounds.size.height;
	if (count < 2 || totalLength <= 0) return;

	BOOL horizontalFlex = split.vertical;
	CGFloat divider = split.dividerThickness;
	CGFloat usableLength = MAX(0, totalLength - (count - 1) * divider);

	NSArray<NSNumber *> *configured =
		objc_getAssociatedObject(split, &kKeys[kSplitProportionsKey]);
	BOOL useConfigured = configured.count == count;

	/*
	 * Explicit proportions are applied once and then left to NSSplitView's
	 * native resizing (the user can freely drag dividers afterward).
	 */
	if (useConfigured) {
		if ([objc_getAssociatedObject(
				split, &kKeys[kSplitProportionsAppliedKey]) boolValue]) return;

		CGFloat totalWeight = 0;
		for (NSNumber *weight in configured) totalWeight += weight.doubleValue;
		if (totalWeight <= 0) return;

		CGFloat consumedWeight = 0;
		for (NSUInteger i = 0; i + 1 < count; i++) {
			consumedWeight += configured[i].doubleValue;
			CGFloat leadingLength = usableLength * consumedWeight / totalWeight;
			CGFloat position = split.vertical
				? leadingLength + i * divider
				: totalLength - leadingLength - i * divider;
			[split setPosition:position ofDividerAtIndex:(NSInteger)i];
		}
		objc_setAssociatedObject(
			split, &kKeys[kSplitProportionsAppliedKey], @YES,
			OBJC_ASSOCIATION_RETAIN);
		return;
	}

	/*
	 * No explicit proportions: derive initial (and on-resize) pane widths
	 * from child flex characteristics. Panes with flexGrow == 0 (including
	 * those with fixedWidth) retain their natural width; flexible panes split
	 * the remaining space proportionally by flexGrow.
	 *
	 * Holding priorities are set so that NSSplitView's native resize path
	 * also respects the same fixed-vs-flexible intent.
	 */
	for (NSUInteger i = 0; i < count; i++) {
		CGFloat fg = view_flex_grow(panes[i], horizontalFlex);
		[split setHoldingPriority:(fg > 0
			? NSLayoutPriorityDefaultLow
			: NSLayoutPriorityDefaultHigh) forSubviewAtIndex:i];
	}

	CGFloat fixedWidths[count];
	CGFloat flexWeights[count];
	CGFloat flexSum = 0;
	CGFloat fixedSum = 0;
	BOOL hasFlexible = NO;

	for (NSUInteger i = 0; i < count; i++) {
		NSView *child = panes[i];
		CGFloat fw = view_fixed_width(child);
		CGFloat fg = view_flex_grow(child, horizontalFlex);

		if (fg <= 0) {
			fixedWidths[i] = fw > 0
				? fw : MAX(kMinLeafWidth, child.frame.size.width);
			flexWeights[i] = 0;
			fixedSum += fixedWidths[i];
		} else {
			flexWeights[i] = fg;
			fixedWidths[i] = 0;
			flexSum += fg;
			hasFlexible = YES;
		}
	}

	CGFloat consumed = 0;
	if (hasFlexible && flexSum > 0) {
		CGFloat remaining = MAX(0, usableLength - fixedSum);
		for (NSUInteger i = 0; i + 1 < count; i++) {
			consumed += fixedWidths[i];
			if (flexWeights[i] > 0) {
				consumed += remaining * flexWeights[i] / flexSum;
			}
			CGFloat position = split.vertical
				? consumed + i * divider
				: totalLength - consumed - i * divider;
			[split setPosition:position ofDividerAtIndex:(NSInteger)i];
		}
	} else {
		for (NSUInteger i = 0; i + 1 < count; i++) {
			consumed += usableLength / count;
			CGFloat position = split.vertical
				? consumed + i * divider
				: totalLength - consumed - i * divider;
			[split setPosition:position ofDividerAtIndex:(NSInteger)i];
		}
	}
}

static void layout_recursive(NSView *view, CGFloat width) {
	if (!view) return;

	LayoutAxis axis = layout_axis(view);
	CGFloat availableWidth = view.bounds.size.width > 0
		? view.bounds.size.width : width;
	CGFloat availableHeight = view.bounds.size.height;

	if (axis != LayoutAxisNone) {

		CGFloat padX = view_padding_horizontal(view);
		CGFloat padY = view_padding_vertical(view);
		CGFloat stackSpacing = view_spacing(view);
		CGFloat contentW = availableWidth - 2 * padX;
		CGFloat contentH = availableHeight - 2 * padY;
		NSString *alignment = view_alignment(view);

		switch (axis) {
		case LayoutAxisVStack: {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat spacing = count > 1 ? (count - 1) * stackSpacing : 0;
			CGFloat *heights = calloc(count, sizeof(CGFloat));
			NSMutableArray<NSValue *> *measured = [NSMutableArray arrayWithCapacity:count];
			for (NSUInteger i = 0; i < count; i++) {
				NSView *child = view.subviews[i];
				if (is_hidden(child)) {
					heights[i] = 0;
					[measured addObject:[NSValue valueWithSize:NSZeroSize]];
					continue;
				}
				NSSize size = measure_view(child, (LuaLayoutConstraint){
					.width = contentW,
					.height = 0,
					.widthMode = LuaMeasureAtMost,
					.heightMode = LuaMeasureUndefined,
				});
				NSNumber *basis = objc_getAssociatedObject(child, &kKeys[kFlexBasisKey]);
				CGFloat fixed = view_fixed_height(child);
				heights[i] = clamp_dimension(
					fixed > 0 ? fixed : (basis ? basis.doubleValue : size.height),
					view_optional_dimension(child, &kKeys[kMinHeightKey], 0),
					view_optional_dimension(child, &kKeys[kMaxHeightKey], INFINITY));
				[measured addObject:[NSValue valueWithSize:size]];
			}
			distribute_main_axis(view.subviews, heights,
				MAX(0, contentH - spacing), NO);
			CGFloat top = padY + contentH;

			for (NSUInteger i = 0; i < count; i++) {
				NSView *sv = view.subviews[i];
				if (is_hidden(sv)) continue;
				CGFloat childH = heights[i];
				NSSize natural = measured[i].sizeValue;
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = fw > 0 ? fw
					: (view_fills_cross_axis(sv, YES) ? contentW
						: MIN(natural.width, contentW));
				childW = clamp_dimension(
					childW,
					view_optional_dimension(sv, &kKeys[kMinWidthKey], 0),
					view_optional_dimension(sv, &kKeys[kMaxWidthKey], INFINITY));
				top -= childH;
				CGFloat childX = padX;
				if ([alignment isEqualToString:@"center"]) {
					childX = padX + (contentW - childW) / 2;
				} else if ([alignment isEqualToString:@"trailing"]) {
					childX = padX + contentW - childW;
				}
				sv.frame = NSMakeRect(childX, top, childW, childH);
				layout_recursive(sv, childW);
				top -= stackSpacing;
			}
			free(heights);
	} break;
	case LayoutAxisHStack: {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat spacing = count > 1 ? (count - 1) * stackSpacing : 0;
			CGFloat *widths = calloc(count, sizeof(CGFloat));
			NSMutableArray<NSValue *> *measured = [NSMutableArray arrayWithCapacity:count];
			for (NSUInteger i = 0; i < count; i++) {
				NSView *child = view.subviews[i];
				if (is_hidden(child)) {
					widths[i] = 0;
					[measured addObject:[NSValue valueWithSize:NSZeroSize]];
					continue;
				}
				NSSize size = measure_view(child, (LuaLayoutConstraint){
					.width = 0,
					.height = contentH,
					.widthMode = LuaMeasureUndefined,
					.heightMode = LuaMeasureAtMost,
				});
				NSNumber *basis = objc_getAssociatedObject(child, &kKeys[kFlexBasisKey]);
				CGFloat fixed = view_fixed_width(child);
				widths[i] = clamp_dimension(
					fixed > 0 ? fixed : (basis ? basis.doubleValue : size.width),
					view_optional_dimension(child, &kKeys[kMinWidthKey], 0),
					view_optional_dimension(child, &kKeys[kMaxWidthKey], INFINITY));
				[measured addObject:[NSValue valueWithSize:size]];
			}
			distribute_main_axis(view.subviews, widths,
				MAX(0, contentW - spacing), YES);
			CGFloat x = padX;

			for (NSUInteger i = 0; i < count; i++) {
				NSView *sv = view.subviews[i];
				if (is_hidden(sv)) continue;
				CGFloat childW = widths[i];
				NSSize natural = measured[i].sizeValue;
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = fh > 0 ? fh
					: (view_fills_cross_axis(sv, NO) ? contentH
						: MIN(natural.height, contentH));
				childH = clamp_dimension(
					childH,
					view_optional_dimension(sv, &kKeys[kMinHeightKey], 0),
					view_optional_dimension(sv, &kKeys[kMaxHeightKey], INFINITY));
				CGFloat childY = padY;
				if ([alignment isEqualToString:@"center"]) {
					childY = padY + (contentH - childH) / 2;
				} else if ([alignment isEqualToString:@"top"]) {
					childY = padY + contentH - childH;
				}
				sv.frame = NSMakeRect(x, childY, childW, childH);
				layout_recursive(sv, childW);
				x += childW + stackSpacing;
			}
			free(widths);
	} break;
	case LayoutAxisHSplit: {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			NSSplitView *split = (NSSplitView *)view;
			[split layoutSubtreeIfNeeded];
			apply_initial_split_proportions(split);
			for (NSView *pane in split.arrangedSubviews) {
				if (is_hidden(pane)) continue;
				layout_recursive(pane, pane.bounds.size.width);
			}
	} break;
	case LayoutAxisVSplit: {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			NSSplitView *split = (NSSplitView *)view;
			[split layoutSubtreeIfNeeded];
			apply_initial_split_proportions(split);
			for (NSView *pane in split.arrangedSubviews) {
				if (is_hidden(pane)) continue;
				layout_recursive(pane, pane.bounds.size.width);
			}
	} break;
	default: break;
	}
	} else {
		if ([view isKindOfClass:[NSScrollView class]]) {
			[(NSScrollView *)view tile];
			LuaTableViewSource *source =
				objc_getAssociatedObject(view, &kKeys[kTableSourceKey]);
			[source updateTableFrame];
			position_table_spinner((NSScrollView *)view);
		}
		for (NSView *sv in view.subviews) {
			if (objc_getAssociatedObject(sv, &kKeys[kAxisKey])) {
				layout_recursive(sv, width);
			}
		}
	}
}

static int bridge_object_layout_impl(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_optnumber(L, 2, kLayoutDefaultWidth);

	NSView *view;
	if ([obj isKindOfClass:[NSWindow class]]) {
		NSWindow *window = (NSWindow *)obj;
		view = window.contentView;

		/* Workspace windows use NSSplitViewController.  layout_recursive
		 * does not cascade into split-view panes, so re-layout each pane
		 * individually at its current NSSplitView-assigned width. */
		if ([window.contentViewController
				isKindOfClass:[NSSplitViewController class]]) {
			NSSplitViewController *svc =
				(NSSplitViewController *)window.contentViewController;
			for (NSSplitViewItem *item in svc.splitViewItems) {
				NSView *pane = item.viewController.view;
				layout_recursive(pane, pane.bounds.size.width);
			}
			return 0;
		}
	} else {
		view = (NSView *)obj;
	}

	layout_recursive(view, width);
	return 0;
}

static int bridge_object_set_content_size_impl(lua_State *L) {
	id obj = check_objc(L, 1);
	CGFloat width = luaL_checknumber(L, 2);
	CGFloat height = luaL_checknumber(L, 3);
	const char *anchor = luaL_optstring(L, 4, "");

	if ([obj isKindOfClass:[NSWindow class]]) {
		NSWindow *w = (NSWindow *)obj;
		NSRect frame = w.frame;
		CGFloat top = NSMaxY(frame);
		NSRect contentRect = [w contentRectForFrameRect:frame];
		contentRect.size = NSMakeSize(width, height);
		NSRect newFrame = [w frameRectForContentRect:contentRect];
		if (strcmp(anchor, "top") == 0) {
			newFrame.origin.y = top - newFrame.size.height;
		}
		[w setFrame:newFrame display:YES animate:NO];
	} else {
		NSView *v = (NSView *)obj;
		v.frame = NSMakeRect(v.frame.origin.x, v.frame.origin.y, width, height);
	}
	return 0;
}

#pragma mark - Button, toggle, separator
