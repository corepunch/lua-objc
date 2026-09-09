#pragma mark - Layout helpers

static NSNumber *axis_flex_grow(UIView *view, BOOL horizontal) {
	/* Flex weight belongs to the parent's main axis, not the cross axis of
	 * a nested stack. Explicit fillWidth/fillHeight remain axis-specific. */
	NSString *parentAxis = objc_getAssociatedObject(view.superview, &kAxisKey);
	if ([parentAxis isEqualToString:@"hstack"] && !horizontal) return nil;
	if ([parentAxis isEqualToString:@"vstack"] && horizontal) return nil;
	return objc_getAssociatedObject(view, &kFlexGrowKey);
}

static BOOL grows_on_axis(UIView *view, BOOL horizontal) {
	if (objc_getAssociatedObject(view, horizontal ? &kFixedWidthKey : &kFixedHeightKey)) return NO;
	NSNumber *grow = axis_flex_grow(view, horizontal);
	if (grow) return grow.doubleValue > 0;
	if ([objc_getAssociatedObject(view, horizontal ? &kFillWidthKey : &kFillHeightKey) boolValue]) return YES;
	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	if ([axis isEqualToString:@"hstack"] || [axis isEqualToString:@"vstack"] || [axis isEqualToString:@"zstack"]) {
		for (UIView *child in view.subviews) {
			if (child.hidden) continue;
			if (grows_on_axis(child, horizontal)) return YES;
		}
		return NO;
	}
	if (![objc_getAssociatedObject(view, &kFlexibleKey) boolValue]) return NO;
	if (objc_getAssociatedObject(view, &kFlexBasisKey)) {
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

static CGFloat view_padding_vertical(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kPaddingVerticalKey);
	return value ? value.doubleValue : view_padding(view);
}

static CGFloat view_padding_top(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kPaddingTopKey);
	return value ? value.doubleValue : view_padding_vertical(view);
}

static CGFloat view_padding_bottom(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kPaddingBottomKey);
	return value ? value.doubleValue : view_padding_vertical(view);
}

static CGFloat view_fixed_height(UIView *view);

static BOOL grows_vertically(UIView *view) { return grows_on_axis(view, NO); }

static CGFloat view_spacing(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kSpacingKey);
	return value ? value.doubleValue : kStackSpacing;
}

static CGFloat view_fixed_width(UIView *view);

static CGSize measure_size(UIView *view, CGSize proposal);

static CGSize measure_horizontal_children(UIView *view, CGSize proposal, CGSize *sizes) {
	NSArray<UIView *> *children = view.subviews;
	NSMutableArray<NSNumber *> *order = [NSMutableArray array];
	NSMutableArray<NSNumber *> *flexibility = [NSMutableArray array];
	for (NSUInteger i = 0; i < children.count; i++) {
		UIView *child = children[i];
		if (child.hidden) { [flexibility addObject:@0]; continue; }
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
			if (weight > 0) for (NSUInteger next = order.count - left; next < order.count; next++)
				totalWeight += flex_weight(children[order[next].unsignedIntegerValue], YES);
			CGFloat offer = MAX(0, round((weight > 0 ? remaining * weight / totalWeight : remaining / left) * scale) / scale);
			sizes[i] = measure_size(children[i], CGSizeMake(offer, proposal.height));
			if (is_flexible(children[i])) sizes[i].width = offer;
			remaining -= sizes[i].width;
		}
		result.width += sizes[i].width;
		result.height = MAX(result.height, sizes[i].height);
		left--;
	}
	return result;
}

/* Measurement accepts a proposal; it never inherits the previous frame.
 * The same negotiation is used during placement so wrapped text has one size. */
static CGSize measure_size(UIView *view, CGSize proposal) {
	if (!view || view.hidden) return CGSizeZero;
	NSNumber *fixedW = objc_getAssociatedObject(view, &kFixedWidthKey);
	NSNumber *fixedH = objc_getAssociatedObject(view, &kFixedHeightKey);
	if (fixedW) proposal.width = MAX(0, fixedW.doubleValue);
	if (fixedH) proposal.height = MAX(0, fixedH.doubleValue);
	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	CGSize size = CGSizeZero;
	if (axis) {
		CGFloat padX = 2 * view_padding_horizontal(view);
		CGFloat padY = view_padding_top(view) + view_padding_bottom(view);
		CGSize inner = CGSizeMake(MAX(0, proposal.width - padX), MAX(0, proposal.height - padY));
		NSUInteger count = 0;
		if ([axis isEqualToString:@"hstack"]) {
			CGSize *sizes = calloc(MAX(view.subviews.count, 1), sizeof(CGSize));
			size = measure_horizontal_children(view, inner, sizes);
			free(sizes);
		} else {
			for (UIView *child in view.subviews) {
				if (child.hidden) continue;
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
	}
	if (fixedW) size.width = MAX(0, fixedW.doubleValue);
	if (fixedH) size.height = MAX(0, fixedH.doubleValue);
	NSNumber *maxW = objc_getAssociatedObject(view, &kMaxWidthKey);
	NSNumber *maxH = objc_getAssociatedObject(view, &kMaxHeightKey);
	size.width = MAX([objc_getAssociatedObject(view, &kMinWidthKey) doubleValue], maxW ? MIN(size.width, maxW.doubleValue) : size.width);
	size.height = MAX([objc_getAssociatedObject(view, &kMinHeightKey) doubleValue], maxH ? MIN(size.height, maxH.doubleValue) : size.height);
	return size;
}

static BOOL fills_axis(UIView *view, BOOL horizontal) {
	if (objc_getAssociatedObject(view, horizontal ? &kFixedWidthKey : &kFixedHeightKey)) return NO;
	NSNumber *fill = objc_getAssociatedObject(view, horizontal ? &kFillWidthKey : &kFillHeightKey);
	if (fill) return fill.boolValue;
	return horizontal ? is_flexible(view) : grows_vertically(view);
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

static void layout_recursive(UIView *view, CGFloat width) {
	if (!view) return;

	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	CGFloat availableWidth = view.bounds.size.width > 0
		? view.bounds.size.width : width;
	CGFloat availableHeight = view.bounds.size.height;

	if ([axis isEqualToString:@"vstack"] || [axis isEqualToString:@"hstack"] ||
		[axis isEqualToString:@"zstack"] ||
		[axis isEqualToString:@"hsplit"]) {

	NSMutableArray<UIView *> *children = [NSMutableArray array];
	for (UIView *child in view.subviews) if (!child.hidden) [children addObject:child];
	CGFloat padX = view_padding_horizontal(view);
	CGFloat padTop = view_padding_top(view);
	CGFloat padBottom = view_padding_bottom(view);
	CGFloat contentW = MAX(0, availableWidth - 2 * padX);
	CGFloat contentH = MAX(0, availableHeight - padTop - padBottom);
		NSString *alignment = view_alignment(view);

		if ([axis isEqualToString:@"zstack"]) {
			for (UIView *sv in children) {
				if (sv.hidden) continue;
				CGSize natural = measure_size(sv, CGSizeMake(contentW, contentH));
				CGFloat childW = fills_axis(sv, YES) ? contentW : natural.width;
				CGFloat childH = fills_axis(sv, NO) ? contentH : natural.height;
				CGFloat childX = padX + (contentW - childW) / 2;
				CGFloat childY = padTop + (contentH - childH) / 2;
				if ([alignment isEqualToString:@"leading"]) childX = padX;
				if ([alignment isEqualToString:@"trailing"]) childX = padX + contentW - childW;
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
				CGFloat childH = grows_vertically(sv) ? flexibleHeight * flex_weight(sv, NO)
					: (fh > 0 ? fh : sv.frame.size.height);

				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = fills_axis(sv, YES) ? contentW
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
				CGFloat childH = fills_axis(sv, NO) ? contentH : measured.height;
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
