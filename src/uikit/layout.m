#pragma mark - Layout helpers

static BOOL is_flexible(UIView *view) {
	return [objc_getAssociatedObject(view, &kFlexibleKey) boolValue];
}

static CGFloat view_padding(UIView *view) {
	NSNumber *p = objc_getAssociatedObject(view, &kPaddingKey);
	return p ? p.doubleValue : 12.0;
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
				if (is_flexible(sv)) {
					flexibleCount++;
				} else if (fh > 0) {
					fixedHeight += fh;
				} else {
					fixedHeight += sv.frame.size.height > 0
						? sv.frame.size.height : 22;
				}
			}

			CGFloat spacing = count > 1 ? (count - 1) * kStackSpacing : 0;
			CGFloat flexibleHeight = flexibleCount > 0
				? MAX(0, (contentH - fixedHeight - spacing) / flexibleCount)
				: 0;
			CGFloat top = pad + contentH;

			for (UIView *sv in view.subviews) {
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = is_flexible(sv) ? flexibleHeight
					: (fh > 0 ? fh : (sv.frame.size.height > 0 ? sv.frame.size.height : 22));
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = is_flexible(sv) ? contentW
					: (fw > 0 ? fw : MIN(sv.frame.size.width, contentW));
				top -= childH;
				CGFloat childX = pad;
				if ([alignment isEqualToString:@"center"]) {
					childX = pad + (contentW - childW) / 2;
				} else if ([alignment isEqualToString:@"trailing"]) {
					childX = pad + contentW - childW;
				}
				sv.frame = CGRectMake(childX, top, childW, childH);
				layout_recursive(sv, childW);
				top -= kStackSpacing;
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

			CGFloat spacing = count > 1 ? (count - 1) * kStackSpacing : 0;
			CGFloat flexibleWidth = flexibleCount > 0
				? MAX(0, (contentW - fixedWidth - spacing) / flexibleCount)
				: 0;
			CGFloat x = pad;

			for (UIView *sv in view.subviews) {
				CGFloat fw = view_fixed_width(sv);
				CGFloat childW = is_flexible(sv) ? flexibleWidth
					: (fw > 0 ? fw : (sv.frame.size.width > 0 ? sv.frame.size.width : 40));
				CGFloat fh = view_fixed_height(sv);
				CGFloat childH = is_flexible(sv) ? contentH
					: (fh > 0 ? fh : MIN(sv.frame.size.height, contentH));
				CGFloat childY = pad;
				if ([alignment isEqualToString:@"center"]) {
					childY = pad + (contentH - childH) / 2;
				} else if ([alignment isEqualToString:@"bottom"]) {
					childY = pad + contentH - childH;
				}
				sv.frame = CGRectMake(x, childY, childW, childH);
				layout_recursive(sv, childW);
				x += childW + kStackSpacing;
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

