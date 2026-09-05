#pragma mark - Layout helpers

static BOOL is_flexible(UIView *view) {
	if ([objc_getAssociatedObject(view, &kFlexGrowKey) doubleValue] > 0)
		return YES;
	return [objc_getAssociatedObject(view, &kFlexibleKey) boolValue];
}

static CGFloat view_padding(UIView *view) {
	NSNumber *p = objc_getAssociatedObject(view, &kPaddingKey);
	return p ? p.doubleValue : 0.0;
}

/* A horizontal stack may flex along its own horizontal axis, but it must
 * retain its intrinsic height when it is a child of a vertical stack. */
static BOOL grows_vertically(UIView *view) {
	if (!is_flexible(view)) return NO;
	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	return ![axis isEqualToString:@"hstack"];
}

static CGFloat view_spacing(UIView *view) {
	NSNumber *value = objc_getAssociatedObject(view, &kSpacingKey);
	return value ? value.doubleValue : kStackSpacing;
}

static CGFloat natural_height(UIView *view) {
	if (!view) return 0;
	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	CGFloat pad = view_padding(view);
	if ([axis isEqualToString:@"vstack"]) {
		CGFloat height = 2 * pad;
		NSUInteger index = 0;
		for (UIView *child in view.subviews) {
			if (index++ > 0) height += view_spacing(view);
			height += natural_height(child);
		}
		return height;
	}
	if ([axis isEqualToString:@"hstack"]) {
		CGFloat maximum = 0;
		for (UIView *child in view.subviews)
			maximum = MAX(maximum, natural_height(child));
		return 2 * pad + maximum;
	}
	return view.frame.size.height;
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

static void size_to_fit_if_needed(UIView *view) {
	/* Image views have an explicit display size established by the bridge.
	 * UIImageView's sizeToFit uses the source image's intrinsic dimensions,
	 * which can undo the bridge's max-width scaling and leave a vertically
	 * oversized frame in a VStack. */
	NSValue *imageLayoutSize = objc_getAssociatedObject(view, &kImageLayoutSizeKey);
	if (imageLayoutSize) {
		view.frame = CGRectMake(view.frame.origin.x, view.frame.origin.y,
			imageLayoutSize.CGSizeValue.width, imageLayoutSize.CGSizeValue.height);
		return;
	}
	if (!is_flexible(view)) {
		[view sizeToFit];
	}
}

static void layout_recursive(UIView *view, CGFloat width) {
	if (!view) return;

	NSString *axis = objc_getAssociatedObject(view, &kAxisKey);
	CGFloat availableWidth = view.bounds.size.width > 0
		? view.bounds.size.width : width;
	CGFloat availableHeight = view.bounds.size.height;

	if ([axis isEqualToString:@"vstack"] || [axis isEqualToString:@"hstack"] ||
		[axis isEqualToString:@"hsplit"]) {

		CGFloat pad = view_padding(view);
		CGFloat contentW = availableWidth - 2 * pad;
		CGFloat contentH = availableHeight - 2 * pad;
		NSString *alignment = view_alignment(view);

		if ([axis isEqualToString:@"vstack"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat fixedHeight = 0;
			NSUInteger flexibleCount = 0;
			for (UIView *sv in view.subviews) {
				size_to_fit_if_needed(sv);
				CGFloat fh = view_fixed_height(sv);
				if (grows_vertically(sv)) {
					flexibleCount++;
				} else if (fh > 0) {
					fixedHeight += fh;
				} else {
					fixedHeight += sv.frame.size.height > 0
						? sv.frame.size.height : 22;
				}
			}

			CGFloat stackSpacing = view_spacing(view);
			CGFloat spacing = count > 1 ? (count - 1) * stackSpacing : 0;
			CGFloat flexibleHeight = flexibleCount > 0
				? MAX(0, (contentH - fixedHeight - spacing) / flexibleCount)
				: 0;
			CGFloat y = pad;

			for (UIView *sv in view.subviews) {
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = grows_vertically(sv) ? flexibleHeight
					: (fh > 0 ? fh : MAX(sv.frame.size.height, natural_height(sv)));
				if (childH <= 0) childH = 22;
				CGFloat fw = view_fixed_width(sv);
				BOOL fill = [objc_getAssociatedObject(sv, &kFillWidthKey) boolValue];
				CGFloat childW = (is_flexible(sv) || fill) ? contentW
					: (fw > 0 ? fw : MIN(sv.frame.size.width, contentW));
				CGFloat childX = pad;
				if ([alignment isEqualToString:@"center"]) {
					childX = pad + (contentW - childW) / 2;
				} else if ([alignment isEqualToString:@"trailing"]) {
					childX = pad + contentW - childW;
				}
				sv.frame = CGRectMake(childX, y, childW, childH);
				layout_recursive(sv, childW);
				y += childH + stackSpacing;
			}
		} else if ([axis isEqualToString:@"hstack"]) {
			NSUInteger count = view.subviews.count;
			if (count == 0) return;

			CGFloat fixedWidth = 0;
			NSUInteger flexibleCount = 0;
			for (UIView *sv in view.subviews) {
				size_to_fit_if_needed(sv);
				CGFloat fw = view_fixed_width(sv);
				if (is_flexible(sv)) {
					flexibleCount++;
				} else if (fw > 0) {
					fixedWidth += fw;
				} else {
					fixedWidth += sv.frame.size.width > 0
						? sv.frame.size.width : 40;
				}
			}

			CGFloat stackSpacing = view_spacing(view);
			CGFloat spacing = count > 1 ? (count - 1) * stackSpacing : 0;
			CGFloat flexibleWidth = flexibleCount > 0
				? MAX(0, (contentW - fixedWidth - spacing) / flexibleCount)
				: 0;
			CGFloat x = pad;

			for (UIView *sv in view.subviews) {
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = is_flexible(sv) ? flexibleWidth
					: (fw > 0 ? fw : (sv.frame.size.width > 0 ? sv.frame.size.width : 40));
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = grows_vertically(sv) ? contentH
					: (fh > 0 ? fh : MIN(MAX(sv.frame.size.height,
						natural_height(sv)), contentH));
				CGFloat childY = pad;
				if ([alignment isEqualToString:@"center"]) {
					childY = pad + (contentH - childH) / 2;
				} else if ([alignment isEqualToString:@"bottom"]) {
					childY = pad + contentH - childH;
				}
				sv.frame = CGRectMake(x, childY, childW, childH);
				layout_recursive(sv, childW);
				x += childW + stackSpacing;
			}
		} else if ([axis isEqualToString:@"hsplit"]) {
			CGFloat n = (CGFloat)view.subviews.count;
			if (n == 0) return;
			CGFloat childW = contentW / n;
			CGFloat x = pad;
			for (UIView *sv in view.subviews) {
				sv.frame = CGRectMake(x, pad, childW, contentH);
				layout_recursive(sv, childW);
				x += childW;
			}
		}
	} else {
		for (UIView *sv in view.subviews) {
			if (objc_getAssociatedObject(sv, &kAxisKey)) {
				layout_recursive(sv, width);
			}
		}
	}
}
