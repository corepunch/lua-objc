static void layout_recursive(NSView *view, CGFloat width);
static void position_table_spinner(NSScrollView *sv);

static int bridge_object_add_impl(lua_State *L) {
@autoreleasepool {
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
	invalidate_layout(container);
	return 0;
}
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

static CGFloat view_padding_edge(NSView *view, BOOL left) {
	BOOL rtl = view.userInterfaceLayoutDirection == NSUserInterfaceLayoutDirectionRightToLeft;
	NSNumber *value = objc_getAssociatedObject(view, left != rtl ? &kKeys[kPaddingLeadingKey] : &kKeys[kPaddingTrailingKey]);
	return value ? value.doubleValue : view_padding_horizontal(view);
}

static CGFloat view_padding_vertical(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kPaddingVerticalKey]);
	if (value) return value.doubleValue;
	NSNumber *p = objc_getAssociatedObject(view, &kKeys[kPaddingKey]);
	return p ? p.doubleValue : 0;
}

static CGFloat view_padding_top(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kPaddingTopKey]);
	return value ? value.doubleValue : view_padding_vertical(view);
}

static CGFloat view_padding_bottom(NSView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kKeys[kPaddingBottomKey]);
	return value ? value.doubleValue : view_padding_vertical(view);
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

static CGFloat view_flex_grow(NSView *view, BOOL horizontal);

static BOOL default_grows_on_axis(NSView *view, BOOL horizontal) {
	NSView *label = objc_getAssociatedObject(view, &kKeys[kButtonContentKey]);
	if (label) return view_flex_grow(label, horizontal) > 0;
	if ([view isKindOfClass:NSGlassEffectView.class])
		return view_flex_grow(((NSGlassEffectView *)view).contentView, horizontal) > 0;
	if ([view isKindOfClass:NSGlassEffectContainerView.class])
		return view_flex_grow(((NSGlassEffectContainerView *)view).contentView, horizontal) > 0;
	// A list that does not scroll takes its rows' height, never the proposal.
	if ([view isKindOfClass:NSScrollView.class] && ((NSScrollView *)view).scrollDisabled)
		return horizontal;
	if (objc_getAssociatedObject(view, &kKeys[kScrollContentKey])) {
		NSScrollView *scroll = (NSScrollView *)view;
		// A horizontal strip gets its height from its content, including when
		// nested in a vertical scroll view with no proposed height.
		if (scroll.hasHorizontalScroller && !scroll.hasVerticalScroller) return horizontal;
	}
	LayoutAxis axis = layout_axis(view);
	if (axis == LayoutAxisHStack || axis == LayoutAxisVStack || axis == LayoutAxisZStack) {
		for (NSView *child in view.subviews) {
			if (is_hidden(child)) continue;
			if (view_flex_grow(child, horizontal) > 0) return YES;
		}
		return NO;
	}
	if (!is_flexible(view)) return NO;
	if (objc_getAssociatedObject(view, &kKeys[kFlexBasisKey])) {
		LayoutAxis parentAxis = layout_axis(view.superview);
		if (parentAxis == LayoutAxisHStack) return horizontal;
		if (parentAxis == LayoutAxisVStack) return !horizontal;
	}
	if (horizontal && axis == LayoutAxisVSplit) return NO;
	return YES;
}

static CGFloat view_flex_grow(NSView *view, BOOL horizontal) {
	if (objc_getAssociatedObject(view, horizontal ? &kKeys[kFixedWidthKey] : &kKeys[kFixedHeightKey])) {
		return 0;
	}
	NSNumber *grow = objc_getAssociatedObject(view, &kKeys[kFlexGrowKey]);
	/* Flex weight belongs to the parent's main axis. Letting it leak into
	 * the cross axis stretches nested text stacks and their enclosing rows. */
	LayoutAxis parentAxis = layout_axis(view.superview);
	BOOL mainAxis = parentAxis == LayoutAxisHStack ? horizontal
		: parentAxis == LayoutAxisVStack ? !horizontal : YES;
	if (grow && mainAxis) return MAX(0, grow.doubleValue);
	if ([objc_getAssociatedObject(view, horizontal ? &kKeys[kFillWidthKey] : &kKeys[kFillHeightKey]) boolValue]) return 1;
	return default_grows_on_axis(view, horizontal) ? 1 : 0;
}

static CGFloat view_flex_shrink(NSView *view, BOOL horizontal) {
	if (objc_getAssociatedObject(view, horizontal ? &kKeys[kFixedWidthKey] : &kKeys[kFixedHeightKey])) {
		return 0;
	}
	NSNumber *shrink = objc_getAssociatedObject(view, &kKeys[kFlexShrinkKey]);
	if (shrink) return MAX(0, shrink.doubleValue);
	/* A stack that fills its parent must be able to give space back when the
	 * window shrinks, even when the stack itself has no flexible native leaf. */
	return (is_flexible(view) || view_flex_grow(view, horizontal) > 0) ? 1 : 0;
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
	NSSize fitting = view.fittingSize;
	/* A previous layout frame is an output, never a new intrinsic minimum.
	 * NSTextField also distinguishes intrinsic text size from sizeToFit's
	 * editing-cell frame. Use Cocoa's intrinsic measurement when available. */
	if (intrinsic.width != NSViewNoIntrinsicMetric && intrinsic.width >= 0) {
		size.width = intrinsic.width;
	} else if (fitting.width > 0) {
		size.width = fitting.width;
	} else if (size.width <= 0) {
		size.width = kMinLeafWidth;
	}
	// NSTextField's glyph advance omits its native text-cell inset. Retain the
	// fitting width for labels so the final glyph is not clipped (e.g. Diskmap).
	if ([view isKindOfClass:LuaLabel.class]) size.width = MAX(size.width, fitting.width);
	if (intrinsic.height != NSViewNoIntrinsicMetric && intrinsic.height >= 0) {
		size.height = intrinsic.height;
	} else if (fitting.height > 0) {
		size.height = fitting.height;
	} else if (size.height <= 0) {
		size.height = kMinLeafHeight;
	}
	return size;
}

/* Offer scarce horizontal space to the least flexible children first. Each
 * child answers the proposal; unused width is available to later siblings.
 * Reuse this negotiation for measurement and placement so wrapping agrees. */
static NSSize measure_horizontal_children(NSView *view, LuaLayoutConstraint constraint, NSSize *sizes) {
	NSArray<NSView *> *children = view.subviews;
	NSMutableArray<NSNumber *> *order = [NSMutableArray array];
	NSMutableArray<NSNumber *> *flexibility = [NSMutableArray array];
	for (NSUInteger i = 0; i < children.count; i++) {
		NSView *child = children[i];
		if (child.hidden) { [flexibility addObject:@0]; continue; }
		sizes[i] = measure_view(child, (LuaLayoutConstraint){
			.height = constraint.height, .heightMode = constraint.heightMode,
			.widthMode = LuaMeasureUndefined });
		[flexibility addObject:@(view_flex_grow(child, YES) > 0 ? INFINITY : sizes[i].width)];
		[order addObject:@(i)];
	}
	[order sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
		NSComparisonResult result = [flexibility[a.unsignedIntegerValue] compare:flexibility[b.unsignedIntegerValue]];
		return result == NSOrderedSame ? [a compare:b] : result;
	}];
	CGFloat spacing = order.count > 1 ? (order.count - 1) * view_spacing(view) : 0;
	CGFloat remaining = MAX(0, constraint.width - spacing);
	NSUInteger left = order.count;
	NSSize result = NSMakeSize(spacing, 0);
	for (NSNumber *index in order) {
		NSUInteger i = index.unsignedIntegerValue;
		if (constraint.widthMode != LuaMeasureUndefined) {
			CGFloat scale = view.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor ?: 1;
			CGFloat weight = view_flex_grow(children[i], YES);
			CGFloat totalWeight = 0;
			if (weight > 0) for (NSUInteger next = order.count - left; next < order.count; next++)
				totalWeight += view_flex_grow(children[order[next].unsignedIntegerValue], YES);
			/* Fixed children keep the width of their title. Only flexible
			 * siblings share what remains, so a button is not truncated while
			 * a spacer still has room. */
			CGFloat offer = weight > 0
				? MAX(0, round((remaining * weight / totalWeight) * scale) / scale)
				: remaining;
			sizes[i] = measure_view(children[i], (LuaLayoutConstraint){
				.width = offer, .widthMode = LuaMeasureAtMost,
				.height = constraint.height, .heightMode = constraint.heightMode });
			if (weight > 0) sizes[i].width = offer;
			remaining -= sizes[i].width;
		}
		result.width += sizes[i].width;
		result.height = MAX(result.height, sizes[i].height);
		left--;
	}
	return result;
}

// Flow children retain their native intrinsic widths. Row breaks are computed
// from the current proposal, never from a previous layout or an item count.
static NSSize layout_flow_children(NSView *view, CGFloat width, BOOL place) {
	NSMutableArray<NSView *> *children = [NSMutableArray array];
	for (NSView *child in view.subviews) if (!child.hidden || objc_getAssociatedObject(child, &kKeys[kFlowOverflowKey])) [children addObject:child];
	CGSize *sizes = calloc(MAX(1, children.count), sizeof(CGSize));
	CGRect *frames = place ? calloc(MAX(1, children.count), sizeof(CGRect)) : NULL;
	for (NSUInteger i = 0; i < children.count; i++) {
		NSView *child = children[i];
		sizes[i] = measure_view(child, (LuaLayoutConstraint){.width = width,
			.widthMode = width < CGFLOAT_MAX ? LuaMeasureAtMost : LuaMeasureUndefined,
			.heightMode = LuaMeasureUndefined});
	}
	NSUInteger maxRows = [objc_getAssociatedObject(view, &kKeys[kFlowMaxRowsKey]) unsignedIntegerValue];
	CGSize result = flow_layout(sizes, frames, children.count, width, view_spacing(view), maxRows);
	if (place) {
		BOOL rtl = view.userInterfaceLayoutDirection == NSUserInterfaceLayoutDirectionRightToLeft;
		for (NSUInteger i = 0; i < children.count; i++) {
			CGRect frame = frames[i];
			if (CGRectIsNull(frame)) {
				children[i].hidden = YES;
				objc_setAssociatedObject(children[i], &kKeys[kFlowOverflowKey], @YES, OBJC_ASSOCIATION_RETAIN);
				continue;
			}
			children[i].hidden = NO;
			objc_setAssociatedObject(children[i], &kKeys[kFlowOverflowKey], nil, OBJC_ASSOCIATION_RETAIN);
			frame.origin.x = view_padding_edge(view, YES) + (rtl ? width - CGRectGetMaxX(frame) : frame.origin.x);
			CGFloat top = view_padding_top(view) + frame.origin.y;
			frame.origin.y = view.isFlipped ? top : view.bounds.size.height - top - frame.size.height;
			children[i].frame = frame;
			layout_recursive(children[i], frame.size.width);
		}
	}
	free(sizes); free(frames);
	return result;
}

static NSSize measure_view(NSView *view, LuaLayoutConstraint constraint) {
	if (!view) return NSZeroSize;

	CGFloat padX = view_padding_edge(view, YES);
	CGFloat padRight = view_padding_edge(view, NO);
	CGFloat padTop = view_padding_top(view);
	CGFloat padBottom = view_padding_bottom(view);
	CGFloat padY = padTop + padBottom;
	CGFloat innerWidth = constraint.widthMode == LuaMeasureUndefined
		? 0 : MAX(0, constraint.width - (padX + padRight));
	CGFloat innerHeight = constraint.heightMode == LuaMeasureUndefined
		? 0 : MAX(0, constraint.height - padY);
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
		natural.width += (padX + padRight);
		natural.height += padY;
	} break;
	case LayoutAxisFlow:
		natural = layout_flow_children(view, constraint.widthMode == LuaMeasureUndefined ? CGFLOAT_MAX : innerWidth, NO);
		natural.width += padX + padRight;
		natural.height += padY;
		break;
	case LayoutAxisHStack: {
		NSSize *sizes = calloc(MAX(1, view.subviews.count), sizeof(NSSize));
		natural = measure_horizontal_children(view, (LuaLayoutConstraint){
			.width = innerWidth, .widthMode = constraint.widthMode,
			.height = innerHeight, .heightMode = constraint.heightMode }, sizes);
		free(sizes);
		natural.width += (padX + padRight);
		natural.height += padY;
	} break;
	case LayoutAxisZStack: {
		for (NSView *child in view.subviews) {
			if (is_hidden(child)) continue;
			NSSize childSize = measure_view(child, (LuaLayoutConstraint){
				.width = innerWidth,
				.height = innerHeight,
				.widthMode = constraint.widthMode == LuaMeasureUndefined
					? LuaMeasureUndefined : LuaMeasureAtMost,
				.heightMode = constraint.heightMode == LuaMeasureUndefined
					? LuaMeasureUndefined : LuaMeasureAtMost,
			});
			natural.width = MAX(natural.width, childSize.width);
			natural.height = MAX(natural.height, childSize.height);
		}
		natural.width += (padX + padRight);
		natural.height += padY;
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
		natural.width += dividers + (padX + padRight);
		natural.height += padY;
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
		natural.width += (padX + padRight);
		natural.height += dividers + padY;
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
		NSView *buttonContent = objc_getAssociatedObject(view, &kKeys[kButtonContentKey]);
		if (buttonContent) natural = measure_view(buttonContent, constraint);
		NSView *scrollContent = objc_getAssociatedObject(view, &kKeys[kScrollContentKey]);
		if (scrollContent) {
			NSScrollView *scroll = (NSScrollView *)view;
			if (scroll.hasHorizontalScroller && !scroll.hasVerticalScroller) {
				NSSize content = measure_view(scrollContent, (LuaLayoutConstraint){
					.widthMode = LuaMeasureUndefined, .heightMode = LuaMeasureUndefined });
				natural.height = [NSScrollView frameSizeForContentSize:content
					horizontalScrollerClass:scroll.horizontalScroller.class
					verticalScrollerClass:Nil borderType:scroll.borderType
					controlSize:scroll.horizontalScroller.controlSize
					scrollerStyle:scroll.scrollerStyle].height;
			}
		}
		if ([view isKindOfClass:NSScrollView.class] && ((NSScrollView *)view).scrollDisabled
			&& [((NSScrollView *)view).documentView isKindOfClass:NSTableView.class]) {
			NSScrollView *scroll = (NSScrollView *)view;
			NSTableView *table = (NSTableView *)scroll.documentView;
			// Size to the final row count: an animated insert has not reached the
			// table yet, so extend by uniform rows past those it has laid out.
			NSInteger laidOut = table.numberOfRows;
			NSInteger rows = [table.dataSource respondsToSelector:@selector(numberOfRowsInTableView:)]
				? [table.dataSource numberOfRowsInTableView:table] : laidOut;
			CGFloat height = laidOut > 0 ? NSMaxY([table rectOfRow:laidOut - 1]) : 0;
			if (rows > laidOut)
				height += (rows - laidOut) * (table.rowHeight + table.intercellSpacing.height);
			if (table.headerView) height += table.headerView.frame.size.height;
			natural.height = [NSScrollView frameSizeForContentSize:NSMakeSize(natural.width, height)
				horizontalScrollerClass:Nil verticalScrollerClass:Nil
				borderType:scroll.borderType controlSize:NSControlSizeRegular
				scrollerStyle:scroll.scrollerStyle].height;
		}
		if ([view isKindOfClass:NSBox.class] && ((NSBox *)view).boxType == NSBoxPrimary) {
			NSBox *box = (NSBox *)view;
			NSSize margins = box.contentViewMargins;
			NSSize content = measure_view(box.contentView, (LuaLayoutConstraint){
				MAX(0, constraint.width - margins.width * 2), 0, constraint.widthMode, LuaMeasureUndefined});
			natural = NSMakeSize(content.width + margins.width * 2, content.height + margins.height * 2);
		}
		if ([view isKindOfClass:NSGlassEffectView.class]) {
			natural = measure_view(((NSGlassEffectView *)view).contentView,
				constraint);
		}
		if ([view isKindOfClass:NSGlassEffectContainerView.class]) {
			natural = measure_view(((NSGlassEffectContainerView *)view).contentView,
				constraint);
		}
		if ([view isKindOfClass:LuaLabel.class]) {
			NSTextField *label = (NSTextField *)view;
			/* Match the native drawing mode to the negotiated line count. A
			 * multiline editing cell otherwise wraps an intrinsic-width label
			 * at its internal field margins and drops the final word. */
			((NSTextFieldCell *)label.cell).usesSingleLineMode = label.maximumNumberOfLines == 1
				|| constraint.widthMode == LuaMeasureUndefined || natural.width <= constraint.width;
		}
		if ([view isKindOfClass:NSTextField.class] && !((NSTextField *)view).isEditable
			&& constraint.widthMode != LuaMeasureUndefined && natural.width > constraint.width) {
			NSTextField *field = (NSTextField *)view;
			if (field.maximumNumberOfLines != 1 && constraint.width > 0) {
				// Measure in the same text-cell width AppKit draws into. Its
				// fitting width includes field insets absent from glyph advances.
				CGFloat textInsets = MAX(0, field.fittingSize.width - field.intrinsicContentSize.width);
				NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:field.attributedStringValue];
				NSLayoutManager *manager = [[NSLayoutManager alloc] init];
				NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(MAX(0, constraint.width - textInsets),
					constraint.heightMode == LuaMeasureUndefined ? CGFLOAT_MAX : constraint.height)];
				container.lineFragmentPadding = 0;
				NSParagraphStyle *paragraph = field.attributedStringValue.length
					? [field.attributedStringValue attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL] : nil;
				container.lineBreakMode = paragraph ? paragraph.lineBreakMode : field.lineBreakMode;
				container.maximumNumberOfLines = field.maximumNumberOfLines;
				[storage addLayoutManager:manager];
				[manager addTextContainer:container];
				[manager ensureLayoutForTextContainer:container];
				NSRect text = [manager usedRectForTextContainer:container];
				CGFloat scale = view.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor ?: 1;
				natural = NSMakeSize(ceil((text.size.width + textInsets) * scale) / scale, ceil(text.size.height * scale) / scale);

				if (field.maximumNumberOfLines > 0) {
					CGFloat lineHeight = ceil((field.font.ascender - field.font.descender + field.font.leading) * scale) / scale;
					natural.height = MIN(natural.height, lineHeight * field.maximumNumberOfLines);
				}
			}
		}
	}

	CGFloat fixedWidth = view_fixed_width(view);
	CGFloat fixedHeight = view_fixed_height(view);
	if (objc_getAssociatedObject(view, &kKeys[kFixedWidthKey])) natural.width = fixedWidth;
	if (objc_getAssociatedObject(view, &kKeys[kFixedHeightKey])) natural.height = fixedHeight;

	natural.width = clamp_dimension(
		natural.width,
		view_optional_dimension(view, &kKeys[kMinWidthKey], 0),
		view_optional_dimension(view, &kKeys[kMaxWidthKey], INFINITY));
	natural.height = clamp_dimension(
		natural.height,
		view_optional_dimension(view, &kKeys[kMinHeightKey], 0),
		view_optional_dimension(view, &kKeys[kMaxHeightKey], INFINITY));

	if (!objc_getAssociatedObject(view, &kKeys[kFixedWidthKey])) {
		natural.width = constrained_result(
			natural.width, constraint.width, constraint.widthMode);
	}
	if (!objc_getAssociatedObject(view, &kKeys[kFixedHeightKey])) {
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

static void layout_recursive_impl(NSView *view, CGFloat width) {
	if (!view) return;

	LayoutAxis axis = layout_axis(view);
	CGFloat availableWidth = view.bounds.size.width > 0
		? view.bounds.size.width : width;
	CGFloat availableHeight = view.bounds.size.height;

	if (axis != LayoutAxisNone) {

		CGFloat padX = view_padding_edge(view, YES);
		CGFloat padRight = view_padding_edge(view, NO);
		CGFloat padTop = view_padding_top(view);
		CGFloat padBottom = view_padding_bottom(view);
		CGFloat stackSpacing = view_spacing(view);
		NSUInteger visibleCount = 0;
		for (NSView *child in view.subviews) if (!is_hidden(child)) visibleCount++;
		CGFloat contentW = availableWidth - (padX + padRight);
		CGFloat contentH = availableHeight - padTop - padBottom;
		NSString *alignment = view_alignment(view);

		switch (axis) {
		case LayoutAxisFlow:
			layout_flow_children(view, MAX(0, contentW), YES);
			break;
		case LayoutAxisVStack: {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat spacing = visibleCount > 1 ? (visibleCount - 1) * stackSpacing : 0;
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
			CGFloat top = padBottom + contentH;

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

			CGFloat spacing = visibleCount > 1 ? (visibleCount - 1) * stackSpacing : 0;
			CGFloat *widths = calloc(count, sizeof(CGFloat));
			NSSize *proposed = calloc(count, sizeof(NSSize));
			measure_horizontal_children(view, (LuaLayoutConstraint){
				.width = contentW, .widthMode = LuaMeasureAtMost,
				.height = contentH, .heightMode = LuaMeasureAtMost }, proposed);
			NSMutableArray<NSValue *> *measured = [NSMutableArray arrayWithCapacity:count];
			for (NSUInteger i = 0; i < count; i++) {
				NSView *child = view.subviews[i];
				if (is_hidden(child)) {
					widths[i] = 0;
					[measured addObject:[NSValue valueWithSize:NSZeroSize]];
					continue;
				}
				NSSize size = proposed[i];
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
					CGFloat childY = padBottom;
					if ([alignment isEqualToString:@"center"]) {
						childY = padBottom + (contentH - childH) / 2;
					} else if ([alignment isEqualToString:@"top"]) {
						childY = padBottom + contentH - childH;
				}
				sv.frame = NSMakeRect(x, childY, childW, childH);
				layout_recursive(sv, childW);
				x += childW + stackSpacing;
			}
			free(widths);
			free(proposed);
	} break;
		case LayoutAxisZStack: {
			for (NSView *sv in view.subviews) {
				if (is_hidden(sv)) continue;
				NSSize natural = measure_view(sv, (LuaLayoutConstraint){
					.width = contentW,
					.height = contentH,
					.widthMode = LuaMeasureAtMost,
					.heightMode = LuaMeasureAtMost,
				});
				CGFloat childW = view_fills_cross_axis(sv, YES)
					? contentW : MIN(natural.width, contentW);
				CGFloat childH = view_fills_cross_axis(sv, NO)
					? contentH : MIN(natural.height, contentH);
				if (view_fixed_width(sv) > 0) childW = view_fixed_width(sv);
				if (view_fixed_height(sv) > 0) childH = view_fixed_height(sv);
				CGFloat childX = padX + (contentW - childW) / 2;
				CGFloat childY = padBottom + (contentH - childH) / 2;
				NSString *position = alignment.lowercaseString;
				if ([position containsString:@"leading"]) childX = padX;
				if ([position containsString:@"trailing"]) childX = padX + contentW - childW;
				if ([position containsString:@"bottom"]) childY = padBottom;
				if ([position containsString:@"top"]) childY = padBottom + contentH - childH;
				sv.frame = NSMakeRect(childX, childY, childW, childH);
				layout_recursive(sv, childW);
			}
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
		if ([view isKindOfClass:LuaLabel.class]) {
			NSTextField *label = (NSTextField *)view;
			// Measurement visits several proposals; drawing must use the final one.
			BOOL singleLine = label.maximumNumberOfLines == 1
				|| measure_leaf(label).width <= view.bounds.size.width;
			((NSTextFieldCell *)label.cell).usesSingleLineMode = singleLine;
			((NSTextFieldCell *)label.cell).wraps = !singleLine;
			// usesSingleLineMode changes the cell's break mode to clipping.
			// Restore the declared paragraph mode when the label wraps again.
			if (!singleLine && label.attributedStringValue.length) {
				NSParagraphStyle *paragraph = [label.attributedStringValue
					attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
				if (paragraph) label.cell.lineBreakMode = paragraph.lineBreakMode;
			}
		}
		if (objc_getAssociatedObject(view, &kKeys[kNavigationControllerKey])) {
			view.needsLayout = YES;
			[view layoutSubtreeIfNeeded];
			return;
		}
		NSView *buttonContent = objc_getAssociatedObject(view, &kKeys[kButtonContentKey]);
		if (buttonContent) {
			buttonContent.frame = view.bounds;
			layout_recursive(buttonContent, buttonContent.bounds.size.width);
			return;
		}
		if ([view isKindOfClass:[NSTabView class]]) {
			/* AppKit owns the tab content rectangle. Once it has placed the
			 * selected view, lay out that view's declarative descendants. */
			[view layoutSubtreeIfNeeded];
			NSView *selected = ((NSTabView *)view).selectedTabViewItem.view;
			if (selected) layout_recursive(selected, selected.bounds.size.width);
			return;
		}
		if ([view isKindOfClass:NSBox.class] && ((NSBox *)view).boxType == NSBoxPrimary) {
			[view layoutSubtreeIfNeeded];
			NSView *content = ((NSBox *)view).contentView;
			layout_recursive(content, content.bounds.size.width);
			return;
		}
		if ([view isKindOfClass:NSGlassEffectView.class]) {
			NSGlassEffectView *glass = (NSGlassEffectView *)view;
			NSView *content = glass.contentView;
			content.frame = glass.bounds;
			layout_recursive(content, content.bounds.size.width);
			return;
		}
		if ([view isKindOfClass:NSGlassEffectContainerView.class]) {
			NSGlassEffectContainerView *container = (NSGlassEffectContainerView *)view;
			NSView *content = container.contentView;
			content.frame = container.bounds;
			layout_recursive(content, content.bounds.size.width);
			return;
		}
		if ([view isKindOfClass:[NSScrollView class]]) {
			NSScrollView *scroll = (NSScrollView *)view;
			[scroll tile];
			LuaTableViewSource *source =
				objc_getAssociatedObject(view, &kKeys[kTableSourceKey]);
			[source updateTableFrame];
			position_table_spinner((NSScrollView *)view);
			NSView *document = scroll.documentView;
			if (!source && document && layout_axis(document) != LayoutAxisNone) {
				NSSize viewport = scroll.contentSize;
				NSRect previous = document.frame;
				NSValue *previousViewport = objc_getAssociatedObject(scroll, &kKeys[kScrollViewportSizeKey]);
				// AppKit has already adjusted the clip origin when tiling a resized
				// viewport. Pair that origin with the current height, not the old
				// height, or a resize is mistaken for a user scroll.
				CGFloat distanceFromTop = previousViewport ? MAX(0, previous.size.height
					- scroll.contentView.bounds.origin.y - viewport.height) : 0;
				NSSize content = measure_view(document, (LuaLayoutConstraint){
					.width = viewport.width, .height = viewport.height,
					.widthMode = scroll.hasHorizontalScroller ? LuaMeasureUndefined : LuaMeasureAtMost,
					.heightMode = scroll.hasVerticalScroller ? LuaMeasureUndefined : LuaMeasureAtMost,
				});
				content.width = scroll.hasHorizontalScroller ? MAX(viewport.width, content.width) : viewport.width;
				content.height = scroll.hasVerticalScroller ? MAX(viewport.height, content.height) : viewport.height;
				document.frame = NSMakeRect(0, 0, content.width, content.height);
				layout_recursive(document, content.width);
				NSPoint origin = scroll.contentView.bounds.origin;
				if (!document.isFlipped) origin.y = MAX(0, content.height - viewport.height - distanceFromTop);
				NSString *anchor = objc_getAssociatedObject(scroll, &kKeys[kScrollAnchorKey]);
				if (anchor && content.height > 0 && viewport.height > 0) {
					CGFloat limit = MAX(0, content.height - viewport.height);
					if ([anchor isEqualToString:@"bottom"])
						origin.y = document.isFlipped ? limit : 0;
					else if ([anchor isEqualToString:@"top"])
						origin.y = document.isFlipped ? 0 : limit;
					objc_setAssociatedObject(scroll, &kKeys[kScrollAnchorKey], nil,
						OBJC_ASSOCIATION_RETAIN);
				}
				[scroll.contentView scrollToPoint:origin];
				objc_setAssociatedObject(scroll, &kKeys[kScrollViewportSizeKey],
					[NSValue valueWithSize:viewport], OBJC_ASSOCIATION_RETAIN);
				/* Revealing a non-overlay scroller changes the native viewport.
				 * Resolve that change before accepting document geometry. */
				[scroll tile];
				NSSize tiledViewport = scroll.contentSize;
				if (!NSEqualSizes(viewport, tiledViewport)) {
					layout_recursive(scroll, width);
					return;
				}
				[scroll reflectScrolledClipView:scroll.contentView];
				return;
			}
		}
		for (NSView *sv in view.subviews) {
			if (objc_getAssociatedObject(sv, &kKeys[kAxisKey])) {
				layout_recursive(sv, width);
			}
		}
	}
}

static void layout_recursive(NSView *view, CGFloat width) {
	LUA_OBJC_PERF_BEGIN("appkit.layout", signpost);
	layout_recursive_impl(view, width);
	LUA_OBJC_PERF_END("appkit.layout", signpost);
}

static NSView *view_with_identifier(NSView *view, NSString *identifier) {
	if (identifier.length == 0) return nil;
	if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
	for (NSView *child in view.subviews) {
		NSView *found = view_with_identifier(child, identifier);
		if (found) return found;
	}
	return nil;
}

static CGFloat clamp_scroll_offset(CGFloat value, CGFloat limit) {
	if (value < 0) return 0;
	if (value > limit) return limit;
	return value;
}

static void scroll_view_apply_target(NSScrollView *scroll, NSString *target, BOOL animated) {
	NSView *document = scroll.documentView;
	if (!document || target.length == 0) return;
	[scroll tile];
	CGFloat viewport = scroll.contentSize.height;
	CGFloat limit = MAX(0, document.frame.size.height - viewport);
	NSPoint origin = scroll.contentView.bounds.origin;
	if ([target isEqualToString:@"bottom"]) origin.y = document.isFlipped ? limit : 0;
	else if ([target isEqualToString:@"top"]) origin.y = document.isFlipped ? 0 : limit;
	else {
		NSView *match = view_with_identifier(document, target);
		if (!match) return;
		NSRect rect = [document convertRect:match.bounds fromView:match];
		CGFloat y = document.isFlipped ? NSMaxY(rect) - viewport : NSMinY(rect);
		origin.y = clamp_scroll_offset(y, limit);
	}
	origin.x = 0;
	if (animated && scroll.window) {
		[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
			context.duration = kScrollToAnimationDuration;
			[[scroll.contentView animator] setBoundsOrigin:origin];
		} completionHandler:nil];
	} else {
		[scroll.contentView scrollToPoint:origin];
		[scroll reflectScrolledClipView:scroll.contentView];
	}
}

static int bridge_NSScrollView_scrollTo(lua_State *L) {
	NSScrollView *scroll = lua_objc_check_object(L, 1, [NSScrollView class], "ScrollView");
	NSString *target = [NSString stringWithUTF8String:luaL_checkstring(L, 2)];
	BOOL animated = lua_toboolean(L, 3);
	if ([target isEqualToString:@"bottom"] || [target isEqualToString:@"top"]) {
		objc_setAssociatedObject(scroll, &kKeys[kScrollAnchorKey], target,
			OBJC_ASSOCIATION_RETAIN);
	}
	scroll_view_apply_target(scroll, target, animated);
	return 0;
}

static void toolbar_size_content(NSView *view) {
	NSSize size = measure_view(view, (LuaLayoutConstraint){
		.widthMode = LuaMeasureUndefined, .heightMode = LuaMeasureUndefined });
	[view invalidateIntrinsicContentSize];
	[view setFrameSize:size];
	layout_recursive(view, size.width);
}

// A nested stack's changed intrinsic size affects its siblings. Its layout
// owner is the nearest ancestor that is not a stack, scroll or group box,
// stopping at the pane geometry owned by NSSplitView.
static NSView *layout_owner(NSView *view) {
	while (view.superview && ![view.superview isKindOfClass:NSSplitView.class]) {
		NSView *parent = view.superview;
		if (layout_axis(parent) == LayoutAxisNone && ![parent isKindOfClass:NSClipView.class]
			&& ![parent isKindOfClass:NSScrollView.class] && ![parent isKindOfClass:NSBox.class]) break;
		view = parent;
	}
	return view;
}

static void relayout_view(NSView *view, CGFloat width) {
	// A toolbar owns its item's placement, but content determines its size.
	// Recompute after title/subtitle mutations instead of retaining the old frame.
	for (NSToolbarItem *item in view.window.toolbar.items) {
		if (item.view != view) continue;
		NSSize size = measure_view(view, (LuaLayoutConstraint){
			.widthMode = LuaMeasureUndefined, .heightMode = LuaMeasureUndefined });
		[view invalidateIntrinsicContentSize];
		[view setFrameSize:size];
		width = size.width;
		break;
	}
	layout_recursive(view, width);
}

#pragma mark - Automatic invalidation

/* SwiftUI never asks an app to lay out. A Lua write that changes a view's
 * measured size marks it dirty; one pass per run-loop turn, just before the
 * loop sleeps (where Core Animation commits), relayouts each dirty view's
 * owner. Lua geometry reads flush first, so code and tests observe the
 * layout their writes imply without calling layout(). */
static NSHashTable<NSView *> *pendingLayout;
static BOOL flushingLayout;

static void flush_pending_layout(void) {
	if (flushingLayout || pendingLayout.count == 0) return;
	flushingLayout = YES;
	NSArray<NSView *> *dirty = pendingLayout.allObjects;
	[pendingLayout removeAllObjects];
	NSMutableOrderedSet<NSView *> *owners = [NSMutableOrderedSet orderedSet];
	for (NSView *view in dirty) [owners addObject:layout_owner(view)];
	for (NSView *owner in owners) {
		// An owner inside another dirty owner is laid out by that pass.
		BOOL nested = NO;
		for (NSView *other in owners) {
			if (other != owner && [owner isDescendantOf:other]) { nested = YES; break; }
		}
		if (!nested) relayout_view(owner, owner.bounds.size.width);
	}
	flushingLayout = NO;
}

static void invalidate_layout(NSView *view) {
	if (!view || flushingLayout) return;
	if (!pendingLayout) {
		pendingLayout = [NSHashTable weakObjectsHashTable];
		CFRunLoopObserverRef observer = CFRunLoopObserverCreateWithHandler(NULL,
			kCFRunLoopBeforeWaiting, true, 0, ^(CFRunLoopObserverRef o, CFRunLoopActivity a) {
				flush_pending_layout();
			});
		CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
		CFRelease(observer);
	}
	[pendingLayout addObject:view];
}

static int bridge_flush_layout(lua_State *L) {
	(void)L;
	flush_pending_layout();
	return 0;
}

// Test hook: the number of views awaiting the next layout pass.
static int bridge_pending_layout_count(lua_State *L) {
	lua_pushinteger(L, (lua_Integer)pendingLayout.count);
	return 1;
}

// A layout pass satisfies every pending invalidation inside its root.
static void satisfy_pending_layout(NSView *root) {
	for (NSView *dirty in pendingLayout.allObjects) {
		if (dirty == root || [dirty isDescendantOf:root]) [pendingLayout removeObject:dirty];
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
			satisfy_pending_layout(view);
			return 0;
		}
	} else {
		view = (NSView *)obj;
		if (lua_isnoneornil(L, 2)) {
			view = layout_owner(view);
			width = view.bounds.size.width;
		}
	}
	relayout_view(view, width);
	satisfy_pending_layout(view);
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
