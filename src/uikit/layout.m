static BOOL uikit_is_hidden(UIView *view) {
	return view.hidden;
}

#pragma mark - Layout helpers

static void layout_recursive(UIView *view, CGFloat width);

static NSNumber *axis_flex_grow(UIView *view, BOOL horizontal) {
	/* Flex weight belongs to the parent's main axis, not the cross axis of
	 * a nested stack. Explicit fillWidth/fillHeight remain axis-specific. */
	NSString *parentAxis = objc_getAssociatedObject(view.superview, &kAxisKey);
	if ([parentAxis isEqualToString:@"hstack"] && !horizontal) return nil;
	if ([parentAxis isEqualToString:@"vstack"] && horizontal) return nil;
	return objc_getAssociatedObject(view, &kFlexGrowKey);
}

/* SwiftUI `.fixedSize(horizontal:vertical:)`; see the AppKit layout. */
static BOOL fixed_on_axis(UIView *view, BOOL horizontal) {
	NSString *fixed = objc_getAssociatedObject(view, &kFixedSizeKey);
	if (!fixed) return NO;
	return [fixed isEqualToString:@"both"] || [fixed isEqualToString:horizontal ? @"horizontal" : @"vertical"];
}

static BOOL grows_on_axis(UIView *view, BOOL horizontal) {
	if (objc_getAssociatedObject(view, horizontal ? &kFixedWidthKey : &kFixedHeightKey)) return NO;
	if (fixed_on_axis(view, horizontal)) return NO;
	NSNumber *grow = axis_flex_grow(view, horizontal);
	if (grow) return grow.doubleValue > 0;
	if ([objc_getAssociatedObject(view, horizontal ? &kFillWidthKey : &kFillHeightKey) boolValue]) return YES;
	UIView *label = objc_getAssociatedObject(view, &kButtonContentKey);
	if (label) return grows_on_axis(label, horizontal);
	UIView *effectContent = objc_getAssociatedObject(view, &kVisualEffectContentKey);
	if (effectContent) return grows_on_axis(effectContent, horizontal);
	if (objc_getAssociatedObject(view, &kScrollContentKey)) {
		UIScrollView *scroll = (UIScrollView *)view;
		if (scroll.alwaysBounceHorizontal && !scroll.alwaysBounceVertical) return horizontal;
	}
	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	if ([axis isEqualToString:@"hstack"] || [axis isEqualToString:@"vstack"] || [axis isEqualToString:@"zstack"]) {
		for (UIView *child in view.subviews) {
			if (uikit_is_hidden(child)) continue;
			if (grows_on_axis(child, horizontal)) return YES;
		}
		return NO;
	}
	if (![objc_getAssociatedObject(view, &kFlexibleKey) boolValue]) return NO;
	// A basis names the main axis of a flex item; a scroll view stays flexible
	// on both axes, as in SwiftUI.
	if (objc_getAssociatedObject(view, &kFlexBasisKey) && ![view isKindOfClass:UIScrollView.class]) {
		NSString *parentAxis = objc_getAssociatedObject(view.superview, &kAxisKey);
		if ([parentAxis isEqualToString:@"hstack"]) return horizontal;
		if ([parentAxis isEqualToString:@"vstack"]) return !horizontal;
	}
	return YES;
}

static CGFloat flex_weight(UIView *view, BOOL horizontal) {
	if (!grows_on_axis(view, horizontal)) return 0;
	NSNumber *grow = axis_flex_grow(view, horizontal);
	return grow ? grow.doubleValue : 1;
}

static BOOL is_flexible(UIView *view) { return grows_on_axis(view, YES); }

static CGFloat view_padding(UIView *view) {
	NSNumber *p = objc_getAssociatedObject(view, &kPaddingKey);
	return p ? p.doubleValue : 0.0;
}

static CGFloat view_padding_horizontal(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kPaddingHorizontalKey);
	return value ? value.doubleValue : view_padding(view);
}

static CGFloat view_padding_edge(UIView *view, BOOL left) {
	BOOL rtl = view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
	NSNumber *value = objc_getAssociatedObject(view, left != rtl ? &kPaddingLeadingKey : &kPaddingTrailingKey);
	return value ? value.doubleValue : view_padding_horizontal(view);
}

static CGFloat view_padding_vertical(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kPaddingVerticalKey);
	return value ? value.doubleValue : view_padding(view);
}

static CGFloat view_padding_top(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kPaddingTopKey);
	CGFloat declared = value ? value.doubleValue : view_padding_vertical(view);
	return declared + [objc_getAssociatedObject(view, &kHostSafeAreaTopKey) doubleValue];
}

static CGFloat view_padding_bottom(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kPaddingBottomKey);
	CGFloat declared = value ? value.doubleValue : view_padding_vertical(view);
	return declared + [objc_getAssociatedObject(view, &kHostSafeAreaBottomKey) doubleValue];
}

/* The part of a vertical scroll view that the tab bar, its bottom accessory,
 * or the home indicator covers. UIKit folds all three into the owning view
 * controller's safe area, as SwiftUI's ScrollView inset does, and recomputes
 * it as the accessory appears, hides, or moves inline beside a minimized bar.
 * The scroll view keeps its full frame so content stays visible through the
 * glass; this distance becomes a content inset so the last row can scroll
 * clear of the bars. An ancestor that already pads above the safe area leaves
 * nothing to cover, so the inset is zero and never counted twice. */
static CGFloat uikit_scroll_bottom_inset(UIScrollView *scroll) {
	NSString *ignored = scroll.ignoresSafeArea;
	if ([ignored isEqualToString:@"bottom"] || [ignored isEqualToString:@"all"]
		|| [ignored isEqualToString:@"edges"]) return 0;
	return MAX(0, scroll.safeAreaInsets.bottom);
}

static CGFloat view_fixed_height(UIView *view);

static BOOL grows_vertically(UIView *view) { return grows_on_axis(view, NO); }

static CGFloat view_spacing(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kSpacingKey);
	return value ? value.doubleValue : kStackSpacing;
}

static CGFloat view_fixed_width(UIView *view);

/* SwiftUI containerRelativeFrame(.horizontal): a view inside a horizontal
 * scroll view takes a fraction of the scroll view's visible width, less the
 * content's own horizontal padding, so one card fills a phone and several
 * share an iPad. Resolved per proposal, never cached. */
static void apply_container_relative_widths(UIView *view, CGFloat available) {
	for (UIView *child in view.subviews) {
		NSNumber *fraction = objc_getAssociatedObject(child, &kContainerRelativeWidthKey);
		if (fraction.doubleValue > 0)
			objc_setAssociatedObject(child, &kFixedWidthKey,
				@(floor(MAX(0, available) * fraction.doubleValue)), OBJC_ASSOCIATION_RETAIN);
		if (![child isKindOfClass:UIScrollView.class]) apply_container_relative_widths(child, available);
	}
}

static void apply_scroll_container_widths(UIView *content, CGFloat viewportWidth) {
	if (!content || viewportWidth <= 0 || viewportWidth >= CGFLOAT_MAX / 2) return;
	apply_container_relative_widths(content,
		viewportWidth - view_padding_edge(content, YES) - view_padding_edge(content, NO));
}

static CGSize measure_size(UIView *view, CGSize proposal);

/* Use native trailing content width, with the same decision in measurement
 * and placement, so an existing header adapts to each width proposal. */
static NSString *proposed_stack_axis(UIView *view, CGFloat innerWidth) {
	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	CGFloat fraction = [objc_getAssociatedObject(view, &kTrailingMaxWidthFractionKey) doubleValue];
	if (![axis isEqualToString:@"hstack"] || fraction <= 0 || !isfinite(innerWidth) || innerWidth >= CGFLOAT_MAX / 2) return axis;
	UIView *trailing = nil;
	NSUInteger count = 0;
	for (UIView *child in view.subviews) {
		if (uikit_is_hidden(child)) continue;
		trailing = child;
		count++;
	}
	if (count != 2) return axis;
	CGSize size = measure_size(trailing, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX));
	return size.width > MAX(0, innerWidth) * fraction ? @"vstack" : axis;
}

static CGSize measure_horizontal_children(UIView *view, CGSize proposal, CGSize *sizes) {
	NSArray<UIView *> *children = view.subviews;
	NSMutableArray<NSNumber *> *order = [NSMutableArray array];
	NSMutableArray<NSNumber *> *flexibility = [NSMutableArray array];
	for (NSUInteger i = 0; i < children.count; i++) {
		UIView *child = children[i];
		if (uikit_is_hidden(child)) { [flexibility addObject:@0]; continue; }
		sizes[i] = measure_size(child, CGSizeMake(CGFLOAT_MAX, proposal.height));
		[flexibility addObject:@(is_flexible(child) ? INFINITY : sizes[i].width)];
		[order addObject:@(i)];
	}
	[order sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
		NSComparisonResult result = [flexibility[a.unsignedIntegerValue] compare:flexibility[b.unsignedIntegerValue]];
		return result == NSOrderedSame ? [a compare:b] : result;
	}];
	CGFloat spacing = order.count > 1 ? (order.count - 1) * view_spacing(view) : 0;
	CGFloat remaining = MAX(0, proposal.width - spacing);
	NSUInteger left = order.count;
	CGSize result = CGSizeMake(spacing, 0);
	for (NSNumber *index in order) {
		NSUInteger i = index.unsignedIntegerValue;
		if (proposal.width < CGFLOAT_MAX) {
			CGFloat scale = view.traitCollection.displayScale ?: 1;
			CGFloat weight = flex_weight(children[i], YES);
			CGFloat totalWeight = 0;
			CGFloat reserved = 0;
			for (NSUInteger next = order.count - left + 1; next < order.count; next++)
				reserved += children[order[next].unsignedIntegerValue].minWidth;
			if (weight > 0) for (NSUInteger next = order.count - left; next < order.count; next++)
				totalWeight += flex_weight(children[order[next].unsignedIntegerValue], YES);
			CGFloat offer = MAX(0, round((weight > 0 ? remaining * weight / totalWeight : remaining - reserved) * scale) / scale);
			sizes[i] = measure_size(children[i], CGSizeMake(offer, proposal.height));
			/* Flex is a proposal; explicit minimum dimensions remain layout constraints. */
			if (is_flexible(children[i])) sizes[i].width = MAX(offer, children[i].minWidth);
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
static CGSize layout_flow_children(UIView *view, CGFloat width, BOOL place) {
	NSMutableArray<UIView *> *children = [NSMutableArray array];
	for (UIView *child in view.subviews) if ((!child.hidden || objc_getAssociatedObject(child, &kFlowOverflowKey))) [children addObject:child];
	CGSize *sizes = calloc(MAX(1, children.count), sizeof(CGSize));
	CGRect *frames = place ? calloc(MAX(1, children.count), sizeof(CGRect)) : NULL;
	for (NSUInteger i = 0; i < children.count; i++) {
		UIView *child = children[i];
		sizes[i] = measure_size(child, CGSizeMake(width, CGFLOAT_MAX));
	}
	CGSize result = flow_layout(sizes, frames, children.count, width, view_spacing(view), view.maxRows);
	if (place) {
		BOOL rtl = view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
		for (NSUInteger i = 0; i < children.count; i++) {
			CGRect frame = frames[i];
			if (CGRectIsNull(frame)) {
				children[i].hidden = YES;
				objc_setAssociatedObject(children[i], &kFlowOverflowKey, @YES, OBJC_ASSOCIATION_RETAIN);
				continue;
			}
			children[i].hidden = NO;
			objc_setAssociatedObject(children[i], &kFlowOverflowKey, nil, OBJC_ASSOCIATION_RETAIN);
			frame.origin.x = view_padding_edge(view, YES) + (rtl ? width - CGRectGetMaxX(frame) : frame.origin.x);
			CGFloat top = view_padding_top(view) + frame.origin.y;
			frame.origin.y = top;
			children[i].frame = frame;
			layout_recursive(children[i], frame.size.width);
		}
	}
	free(sizes); free(frames);
	return result;
}

/* Measurement accepts a proposal; it never inherits the previous frame.
 * The same negotiation is used during placement so wrapped text has one size. */
static BOOL fills_axis(UIView *view, BOOL horizontal);

/* A ZStack with `fitDiameter` lays the children that do not fill it out in
 * units, as its arcs draw: the stack's shorter side spans that many units. */
static BOOL fills_stack(UIView *view) {
	return fills_axis(view, YES) || fills_axis(view, NO);
}

/* A label in units draws its declared size times the scale. The pair kept
 * with the label is its declared font and the scaled one last applied, so a
 * font set since then becomes the new declared font. */
static void scale_labels(UIView *view, CGFloat scale) {
	if ([view isKindOfClass:UILabel.class]) {
		UILabel *label = (UILabel *)view;
		NSArray<UIFont *> *fonts = objc_getAssociatedObject(label, &kUnitFontKey);
		UIFont *declared = fonts && [label.font isEqual:fonts[1]] ? fonts[0] : label.font;
		UIFont *scaled = [declared fontWithSize:declared.pointSize * scale];
		objc_setAssociatedObject(label, &kUnitFontKey, @[declared, scaled], OBJC_ASSOCIATION_RETAIN);
		if (![label.font isEqual:scaled]) label.font = scaled;
	}
	for (UIView *child in view.subviews) scale_labels(child, scale);
}

/* Points per unit for a child laid out in its ZStack's units; 1 elsewhere. */
static CGFloat view_unit_scale(UIView *view) {
	NSNumber *scale = objc_getAssociatedObject(view, &kUnitScaleKey);
	return scale ? scale.doubleValue : 1;
}

static void set_unit_scale(UIView *view, CGFloat scale) {
	objc_setAssociatedObject(view, &kUnitScaleKey, @(scale), OBJC_ASSOCIATION_RETAIN);
	scale_labels(view, scale);
}

static CGSize measure_size(UIView *view, CGSize proposal) {
	if (!view || view.hidden) return CGSizeZero;
	NSNumber *fixedW = objc_getAssociatedObject(view, &kFixedWidthKey);
	NSNumber *fixedH = objc_getAssociatedObject(view, &kFixedHeightKey);
	if (fixedW) proposal.width = MAX(0, fixedW.doubleValue);
	if (fixedH) proposal.height = MAX(0, fixedH.doubleValue);
	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	CGSize size = CGSizeZero;
	if (axis) {
		CGFloat padX = view_padding_edge(view, YES) + view_padding_edge(view, NO);
		CGFloat padY = view_padding_top(view) + view_padding_bottom(view);
		CGSize inner = CGSizeMake(MAX(0, proposal.width - padX), MAX(0, proposal.height - padY));
		axis = proposed_stack_axis(view, inner.width);
		NSUInteger count = 0;
		if ([axis isEqualToString:@"flow"]) {
			size = layout_flow_children(view, inner.width, NO);
		} else if ([axis isEqualToString:@"hstack"]) {
			CGSize *sizes = calloc(MAX(view.subviews.count, 1), sizeof(CGSize));
			size = measure_horizontal_children(view, inner, sizes);
			free(sizes);
		} else {
			/* Content in units takes its size from the stack, not the reverse. */
			BOOL units = [axis isEqualToString:@"zstack"] && view.fitDiameter > 0;
			if (units) {
				CGFloat side = MIN(view.fitDiameter, MIN(inner.width, inner.height));
				size = CGSizeMake(side, side);
			}
			for (UIView *child in view.subviews) {
				if (uikit_is_hidden(child) || units) continue;
				CGSize childSize = measure_size(child, CGSizeMake(inner.width,
					[axis isEqualToString:@"vstack"] ? CGFLOAT_MAX : inner.height));
				size.width = MAX(size.width, childSize.width);
				if ([axis isEqualToString:@"vstack"]) size.height += childSize.height;
				else size.height = MAX(size.height, childSize.height);
				count++;
			}
			if (count > 1 && [axis isEqualToString:@"vstack"])
				size.height += (count - 1) * view_spacing(view);
		}
		size.width += padX;
		size.height += padY;
	} else {
		NSValue *imageSize = objc_getAssociatedObject(view, &kImageLayoutSizeKey);
		size = imageSize ? imageSize.CGSizeValue : [view sizeThatFits:proposal];
		if (![view isKindOfClass:UILabel.class]) {
			CGSize intrinsic = view.intrinsicContentSize;
			if (intrinsic.width >= 0) size.width = intrinsic.width;
			if (intrinsic.height >= 0) size.height = intrinsic.height;
		}
		UIView *scrollContent = objc_getAssociatedObject(view, &kScrollContentKey);
		UIView *buttonContent = objc_getAssociatedObject(view, &kButtonContentKey);
		if (buttonContent) size = measure_size(buttonContent, proposal);
		UIView *effectContent = objc_getAssociatedObject(view, &kVisualEffectContentKey);
		if (effectContent) size = measure_size(effectContent, proposal);
		if (scrollContent) {
			UIScrollView *scroll = (UIScrollView *)view;
			if (scroll.alwaysBounceHorizontal && !scroll.alwaysBounceVertical) {
				apply_scroll_container_widths(scrollContent, proposal.width);
				size.height = measure_size(scrollContent, CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)).height;
			}
		}
		// A list that does not scroll is as tall as all its rows.
		if ([view isKindOfClass:UITableView.class] && !((UITableView *)view).scrollEnabled) {
			UITableView *table = (UITableView *)view;
			[table layoutIfNeeded];
			size.height = table.contentSize.height;
		}
	}
	if (fixedW) size.width = MAX(0, fixedW.doubleValue);
	if (fixedH) size.height = MAX(0, fixedH.doubleValue);
	NSNumber *maxW = objc_getAssociatedObject(view, &kMaxWidthKey);
	NSNumber *maxH = objc_getAssociatedObject(view, &kMaxHeightKey);
	size.width = MAX([objc_getAssociatedObject(view, &kMinWidthKey) doubleValue], maxW ? MIN(size.width, maxW.doubleValue * view_unit_scale(view)) : size.width);
	size.height = MAX([objc_getAssociatedObject(view, &kMinHeightKey) doubleValue], maxH ? MIN(size.height, maxH.doubleValue) : size.height);
	return size;
}

static BOOL fills_axis(UIView *view, BOOL horizontal) {
	if (objc_getAssociatedObject(view, horizontal ? &kFixedWidthKey : &kFixedHeightKey)) return NO;
	if (fixed_on_axis(view, horizontal)) return NO;
	NSNumber *fill = objc_getAssociatedObject(view, horizontal ? &kFillWidthKey : &kFillHeightKey);
	if (fill) return fill.boolValue;
	return horizontal ? is_flexible(view) : grows_vertically(view);
}

/* A filling child takes the offered cross-axis space up to its own maximum,
 * like SwiftUI's frame(maxWidth:), and never less than its minimum. The
 * parent's alignment then places the capped child, as AppKit layout does. */
static CGFloat clamp_fill(UIView *view, CGFloat offered, BOOL horizontal) {
	NSNumber *maximum = objc_getAssociatedObject(view, horizontal ? &kMaxWidthKey : &kMaxHeightKey);
	NSNumber *minimum = objc_getAssociatedObject(view, horizontal ? &kMinWidthKey : &kMinHeightKey);
	CGFloat value = maximum ? MIN(offered, maximum.doubleValue) : offered;
	return MAX(value, minimum.doubleValue);
}

static NSString *view_alignment(UIView *view) {
	return objc_getAssociatedObject(view, &kAlignmentKey) ?: @"center";
}

static CGFloat view_fixed_width(UIView *view) {
	NSNumber *w = objc_getAssociatedObject(view, &kFixedWidthKey);
	return w ? w.doubleValue : 0;
}

static CGFloat view_fixed_height(UIView *view) {
	NSNumber *h = objc_getAssociatedObject(view, &kFixedHeightKey);
	return h ? h.doubleValue : 0;
}

static void layout_recursive_impl(UIView *view, CGFloat width) {
	if (!view) return;

	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	CGFloat availableWidth = view.bounds.size.width > 0
		? view.bounds.size.width : width;
	CGFloat availableHeight = view.bounds.size.height;
	axis = proposed_stack_axis(view, MAX(0, availableWidth - view_padding_edge(view, YES) - view_padding_edge(view, NO)));

	if ([axis isEqualToString:@"flow"]) {
		layout_flow_children(view, MAX(0, availableWidth - view_padding_edge(view, YES) - view_padding_edge(view, NO)), YES);
		return;
	}

	if ([axis isEqualToString:@"vstack"] || [axis isEqualToString:@"hstack"] ||
		[axis isEqualToString:@"zstack"] ||
		[axis isEqualToString:@"hsplit"]) {

	NSMutableArray<UIView *> *children = [NSMutableArray array];
	for (UIView *child in view.subviews) if (!uikit_is_hidden(child)) [children addObject:child];
	CGFloat padX = view_padding_edge(view, YES);
	CGFloat padRight = view_padding_edge(view, NO);
	CGFloat padTop = view_padding_top(view);
	CGFloat padBottom = view_padding_bottom(view);
	CGFloat contentW = MAX(0, availableWidth - (padX + padRight));
	CGFloat contentH = MAX(0, availableHeight - padTop - padBottom);
		NSString *alignment = view_alignment(view);

		if ([axis isEqualToString:@"zstack"]) {
			CGFloat units = view.fitDiameter;
			CGFloat shorter = MIN(contentW, contentH);
			for (UIView *sv in children) {
				if (uikit_is_hidden(sv)) continue;
				if (units > 0 && shorter > 0 && !fills_stack(sv)) set_unit_scale(sv, shorter / units);
				CGSize natural = measure_size(sv, CGSizeMake(contentW, contentH));
				CGFloat childW = fills_axis(sv, YES) ? clamp_fill(sv, contentW, YES) : natural.width;
				CGFloat childH = fills_axis(sv, NO) ? clamp_fill(sv, contentH, NO) : natural.height;
				CGFloat childX = padX + (contentW - childW) / 2;
				CGFloat childY = padTop + (contentH - childH) / 2;
				NSString *position = alignment.lowercaseString;
				if ([position containsString:@"leading"]) childX = padX;
				if ([position containsString:@"trailing"]) childX = padX + contentW - childW;
				if ([position containsString:@"top"]) childY = padTop;
				if ([position containsString:@"bottom"]) childY = padTop + contentH - childH;
				/* SwiftUI `.ignoresSafeArea(edges: .top)` on a layer of the
				 * root ZStack: a background that fills the stack also runs
				 * under the status bar, while its siblings stay below it. */
				CGFloat hostTop = [objc_getAssociatedObject(view, &kHostSafeAreaTopKey) doubleValue];
				NSString *ignored = sv.ignoresSafeArea;
				if (hostTop > 0 && fills_axis(sv, NO) && ([ignored isEqualToString:@"top"]
					|| [ignored isEqualToString:@"all"] || [ignored isEqualToString:@"edges"])) {
					childY -= hostTop;
					childH += hostTop;
				}
				sv.frame = CGRectMake(childX, childY, childW, childH);
				layout_recursive(sv, childW);
			}
		} else if ([axis isEqualToString:@"vstack"]) {
			NSUInteger count = children.count;
			if (count == 0) return;

			CGFloat fixedHeight = 0;
			CGFloat flexibleWeight = 0;
			for (UIView *sv in children) {
				CGSize measured = measure_size(sv, CGSizeMake(contentW, CGFLOAT_MAX));
				sv.frame = (CGRect){sv.frame.origin, measured};
				CGFloat fh = view_fixed_height(sv);
				if (grows_vertically(sv)) {
					flexibleWeight += flex_weight(sv, NO);
				} else if (fh > 0) {
					fixedHeight += fh;
				} else {
					fixedHeight += sv.frame.size.height;
				}
			}

			CGFloat stackSpacing = view_spacing(view);
			CGFloat spacing = count > 1 ? (count - 1) * stackSpacing : 0;
			CGFloat flexibleHeight = flexibleWeight > 0
				? MAX(0, (contentH - fixedHeight - spacing) / flexibleWeight)
				: 0;
			CGFloat y = padTop;

			for (UIView *sv in children) {
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = grows_vertically(sv) ? MAX(flexibleHeight * flex_weight(sv, NO), sv.minHeight)
					: (fh > 0 ? fh : sv.frame.size.height);

				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = fills_axis(sv, YES) ? clamp_fill(sv, contentW, YES)
					: (fw > 0 ? fw : MIN(sv.frame.size.width, contentW));
				CGFloat childX = padX;
				if ([alignment isEqualToString:@"center"]) {
					childX = padX + (contentW - childW) / 2;
				} else if ([alignment isEqualToString:@"trailing"]) {
					childX = padX + contentW - childW;
				}
				sv.frame = CGRectMake(childX, y, childW, childH);
				layout_recursive(sv, childW);
				y += childH + stackSpacing;
			}
		} else if ([axis isEqualToString:@"hstack"]) {
			NSUInteger count = children.count;
			if (count == 0) return;

			CGSize *sizes = calloc(MAX(view.subviews.count, 1), sizeof(CGSize));
			measure_horizontal_children(view, CGSizeMake(contentW, contentH), sizes);
			CGFloat stackSpacing = view_spacing(view);
			CGFloat x = padX;

			for (UIView *sv in children) {
				CGSize measured = sizes[[view.subviews indexOfObjectIdenticalTo:sv]];
				CGFloat childW = measured.width;
				CGFloat childH = fills_axis(sv, NO) ? clamp_fill(sv, contentH, NO) : measured.height;
				CGFloat childY = padTop;
				if ([alignment isEqualToString:@"center"]) {
					childY = padTop + (contentH - childH) / 2;
				} else if ([alignment isEqualToString:@"bottom"]) {
					childY = padTop + contentH - childH;
				}
				sv.frame = CGRectMake(x, childY, childW, childH);
				layout_recursive(sv, childW);
				x += childW + stackSpacing;
			}
			free(sizes);
		} else if ([axis isEqualToString:@"hsplit"]) {
			CGFloat n = (CGFloat)children.count;
			if (n == 0) return;
			CGFloat childW = contentW / n;
			CGFloat x = padX;
			for (UIView *sv in children) {
				sv.frame = CGRectMake(x, padTop, childW, contentH);
				layout_recursive(sv, childW);
				x += childW;
			}
		}
	} else {
		UIView *effectContent = objc_getAssociatedObject(view, &kVisualEffectContentKey);
		if (effectContent) {
			UIVisualEffectView *effectView = (UIVisualEffectView *)view;
			effectContent.frame = effectView.contentView.bounds;
			layout_recursive(effectContent, effectContent.bounds.size.width);
			return;
		}
		UIView *buttonContent = objc_getAssociatedObject(view, &kButtonContentKey);
		if (buttonContent) {
			buttonContent.frame = view.bounds;
			layout_recursive(buttonContent, buttonContent.bounds.size.width);
			return;
		}
		if ([view isKindOfClass:UIScrollView.class]) {
			[view setNeedsLayout];
			[view layoutIfNeeded];
			return;
		}
		for (UIView *sv in view.subviews) {
			if (objc_getAssociatedObject(sv, &kAxisKey)) {
				layout_recursive(sv, width);
			}
		}
	}
}

/* Lua writes that change measured size mark the view and every ancestor.
 * UIKit coalesces them into its next layout pass, where the hosting
 * controller's viewDidLayoutSubviews lays the Lua root out at its real width. */
static void uikit_invalidate_layout(UIView *view) {
	for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview)
		[ancestor setNeedsLayout];
}

/* Geometry reads observe pending layout, like AppKit's flush. */
static void uikit_layout_if_needed(UIView *view) {
	UIView *root = view;
	while (root.superview) root = root.superview;
	if (root.window) [root layoutIfNeeded];
}

static void layout_recursive(UIView *view, CGFloat width) {
	LUA_OBJC_PERF_BEGIN("uikit.layout", signpost);
	layout_recursive_impl(view, width);
	LUA_OBJC_PERF_END("uikit.layout", signpost);
}

/* Whether the layout engine arranges this view's children (a stack) rather
 * than measuring it as a leaf. The XML renderer pads leaves by wrapping them,
 * as SwiftUI's .padding wraps any view. */
static int bridge_has_layout_axis(lua_State *L) {
	UIView *view = check_view(L, 1);
	lua_pushboolean(L, objc_getAssociatedObject(view, &kAxisKey) != nil);
	return 1;
}
