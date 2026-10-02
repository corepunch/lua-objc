#pragma mark - Arc and sector geometry

/* The filled annular sector a SectorChart draws, shared by the AppKit and
 * UIKit Arc. SwiftUI's SectorMark separates neighbours by `angularInset`
 * points with parallel sides, not by a wedge that widens outwards, and
 * rounds its corners with `cornerRadius`. Both stay in points whatever the
 * chart's size, so a large chart keeps hairline-calm gaps instead of growing
 * wide wedges. Here every edge moves in by half the inset, so rings are as
 * far apart as neighbours, and each corner is a circle tangent to its edge
 * and its arc (prior art: DaisyDisk's and Swift Charts' sunbursts).
 *
 * Angles are degrees, clockwise from east in a y-down space, as Arc's are.
 * Returns NULL when the inset consumes the sector. */

static CGPoint sector_polar(CGPoint center, CGFloat radius, CGFloat angle) {
	return CGPointMake(center.x + radius * cos(angle), center.y + radius * sin(angle));
}

/* A point `along` the ray at `angle`, moved `offset` across it towards
 * increasing (side 1) or decreasing (side -1) angles. */
static CGPoint sector_edge_point(CGPoint center, CGFloat angle, CGFloat along, CGFloat offset, CGFloat side) {
	return CGPointMake(center.x + along * cos(angle) - side * offset * sin(angle),
		center.y + along * sin(angle) + side * offset * cos(angle));
}

/* The shorter arc of the corner circle at `pivot` from `from` to `to`. */
static void sector_add_corner(CGMutablePathRef path, CGPoint pivot, CGFloat radius, CGPoint from, CGPoint to) {
	CGFloat start = atan2(from.y - pivot.y, from.x - pivot.x);
	CGFloat end = atan2(to.y - pivot.y, to.x - pivot.x);
	CGFloat delta = remainder(end - start, 2 * M_PI);
	CGPathAddArc(path, NULL, pivot.x, pivot.y, radius, start, start + delta, delta < 0);
}

/* The largest corner radius, at most `limit`, whose two corners fit side
 * by side on the arc of `radius` (outer when `outer`) over `sweep`. */
static CGFloat sector_fit_corner(CGFloat radius, CGFloat half, CGFloat sweep, CGFloat limit, BOOL outer) {
	for (CGFloat corner = limit; corner > 0.05; corner *= 0.8) {
		CGFloat pivot = outer ? radius - corner : radius + corner;
		if (pivot <= half + corner) continue;
		if (2 * asin((half + corner) / pivot) < sweep) return corner;
	}
	return 0;
}

static CGPathRef sector_path_create(CGPoint center, CGFloat inner, CGFloat outer,
	CGFloat startDegrees, CGFloat sweepDegrees, CGFloat inset, CGFloat cornerRadius) {
	CGFloat half = MAX(0, inset) / 2;
	CGFloat ri = inner > 0 ? inner + half : 0;
	CGFloat ro = outer - half;
	if (ro <= ri) return NULL;
	CGMutablePathRef path = CGPathCreateMutable();
	if (sweepDegrees >= kArcFullCircleDegrees) {
		CGPathAddEllipseInRect(path, NULL, CGRectMake(center.x - ro, center.y - ro, ro * 2, ro * 2));
		if (ri > 0) CGPathAddEllipseInRect(path, NULL, CGRectMake(center.x - ri, center.y - ri, ri * 2, ri * 2));
		return path;
	}
	CGFloat a0 = startDegrees * M_PI / 180.0;
	CGFloat sweep = sweepDegrees * M_PI / 180.0;
	CGFloat a1 = a0 + sweep;
	// The two inset edges meet this far out; nothing nearer the center remains.
	if (half > 0) ri = MAX(ri, sweep < M_PI ? half / sin(sweep / 2) : half);
	if (ro - ri < 0.5) { CGPathRelease(path); return NULL; }
	CGFloat limit = MIN(MAX(0, cornerRadius), (ro - ri) / 2);
	CGFloat co = sector_fit_corner(ro, half, sweep, limit, YES);
	CGFloat ci = ri > half ? sector_fit_corner(ri, half, sweep, limit, NO) : 0;

	// Outer corners: circles of radius co, tangent to each edge and the rim.
	CGFloat pivotOuter = ro - co;
	CGFloat outerTurn = asin(MIN(1, (half + co) / pivotOuter));
	CGFloat outerAlong = sqrt(MAX(0, pivotOuter * pivotOuter - (half + co) * (half + co)));
	CGPoint startOuterEdge = sector_edge_point(center, a0, outerAlong, half, 1);
	CGPoint endOuterEdge = sector_edge_point(center, a1, outerAlong, half, -1);
	// Inner corners, tangent to each edge and the hole.
	CGFloat pivotInner = ri + ci;
	CGFloat innerTurn = pivotInner > 0 ? asin(MIN(1, (half + ci) / pivotInner)) : 0;
	CGFloat innerAlong = sqrt(MAX(0, pivotInner * pivotInner - (half + ci) * (half + ci)));
	CGPoint startInnerEdge = sector_edge_point(center, a0, innerAlong, half, 1);
	CGPoint endInnerEdge = sector_edge_point(center, a1, innerAlong, half, -1);

	CGPathMoveToPoint(path, NULL, startInnerEdge.x, startInnerEdge.y);
	CGPathAddLineToPoint(path, NULL, startOuterEdge.x, startOuterEdge.y);
	if (co > 0) sector_add_corner(path, sector_polar(center, pivotOuter, a0 + outerTurn), co,
		startOuterEdge, sector_polar(center, ro, a0 + outerTurn));
	CGPathAddArc(path, NULL, center.x, center.y, ro, a0 + outerTurn, a1 - outerTurn, false);
	if (co > 0) sector_add_corner(path, sector_polar(center, pivotOuter, a1 - outerTurn), co,
		sector_polar(center, ro, a1 - outerTurn), endOuterEdge);
	CGPathAddLineToPoint(path, NULL, endInnerEdge.x, endInnerEdge.y);
	if (ri > 0) {
		if (ci > 0) sector_add_corner(path, sector_polar(center, pivotInner, a1 - innerTurn), ci,
			endInnerEdge, sector_polar(center, ri, a1 - innerTurn));
		if (a1 - innerTurn > a0 + innerTurn)
			CGPathAddArc(path, NULL, center.x, center.y, ri, a1 - innerTurn, a0 + innerTurn, true);
		if (ci > 0) sector_add_corner(path, sector_polar(center, pivotInner, a0 + innerTurn), ci,
			sector_polar(center, ri, a0 + innerTurn), startInnerEdge);
	}
	CGPathCloseSubpath(path);
	return path;
}

/* Everything an Arc's path is drawn from. A plain arc is its circle's
 * stroke, `lineWidth` wide; with an inset or a corner radius it is the
 * filled sector of that band. `fitDiameter`, when positive, makes the
 * view's shorter side span that many units: the circle (`diameter` units
 * across) and the stroke scale with the view, while the inset and the
 * corner radius stay in points. Without it the circle fills the view. */
typedef struct {
	CGFloat startAngle, endAngle, lineWidth, diameter, fitDiameter, inset, cornerRadius;
	BOOL roundCap;
} ArcShape;

/* The shape `progress` of the way from `a` to `b`, for animation: numbers
 * interpolate, so an arc keeps to its circle while it grows or turns. */
static ArcShape arc_shape_mix(ArcShape a, ArcShape b, CGFloat progress) {
	ArcShape mix = b;
	mix.startAngle = a.startAngle + (b.startAngle - a.startAngle) * progress;
	mix.endAngle = a.endAngle + (b.endAngle - a.endAngle) * progress;
	mix.lineWidth = a.lineWidth + (b.lineWidth - a.lineWidth) * progress;
	mix.diameter = a.diameter + (b.diameter - a.diameter) * progress;
	mix.inset = a.inset + (b.inset - a.inset) * progress;
	mix.cornerRadius = a.cornerRadius + (b.cornerRadius - a.cornerRadius) * progress;
	return mix;
}

/* The filled outline an Arc draws in `bounds` (y down): SwiftUI strokes a
 * shape centered on its path and never clips it to the frame, so a stroke
 * reaches lineWidth/2 past the circle. Equal angles close the circle. */
static CGPathRef arc_path_create(CGRect bounds, ArcShape shape) {
	CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
	CGFloat side = MIN(bounds.size.width, bounds.size.height);
	CGFloat scale = shape.fitDiameter > 0 ? side / shape.fitDiameter : 1;
	CGFloat radius = shape.fitDiameter > 0 ? shape.diameter * scale / 2.0 : side / 2.0;
	CGFloat width = shape.lineWidth * scale;
	if (radius <= 0 || width <= 0) return NULL;
	CGFloat sweep = shape.endAngle - shape.startAngle;
	sweep = fmod(fmod(sweep, 360.0) + 360.0, 360.0);
	if (sweep == 0) sweep = 360.0;
	if (shape.inset > 0 || shape.cornerRadius > 0)
		return sector_path_create(center, MAX(0, radius - width / 2), radius + width / 2,
			shape.startAngle, sweep, shape.inset, shape.cornerRadius);
	CGMutablePathRef line = CGPathCreateMutable();
	CGFloat start = shape.startAngle * M_PI / 180.0;
	if (sweep >= kArcFullCircleDegrees)
		CGPathAddEllipseInRect(line, NULL, CGRectMake(center.x - radius, center.y - radius, radius * 2, radius * 2));
	else
		CGPathAddArc(line, NULL, center.x, center.y, radius, start, start + sweep * M_PI / 180.0, false);
	CGPathRef outline = CGPathCreateCopyByStrokingPath(line, NULL, width,
		shape.roundCap ? kCGLineCapRound : kCGLineCapButt, kCGLineJoinMiter, 10);
	CGPathRelease(line);
	return outline;
}


/* ----- The arc's own animation ----- */

static BOOL arc_shape_equal(ArcShape a, ArcShape b) {
	return a.startAngle == b.startAngle && a.endAngle == b.endAngle && a.lineWidth == b.lineWidth
		&& a.diameter == b.diameter && a.fitDiameter == b.fitDiameter && a.inset == b.inset
		&& a.cornerRadius == b.cornerRadius && a.roundCap == b.roundCap;
}

static CGFloat arc_ease(CGFloat t) { return t * t * (3 - 2 * t); }

/*
 * An `animated` Arc turns, grows and changes rings along its circle when its
 * numbers change, instead of the layer morphing point by point. The motion
 * belongs to the arc alone: nothing else in the view tree is snapshotted,
 * diffed or animated. The layer's path is always the final one; the
 * animation only decorates how it is reached, so skipping or interrupting it
 * never leaves a stale shape. Several property writes in one run-loop turn
 * (angles, then radius) make one animation from where the arc was.
 */
@interface ArcAnimator : NSObject
@property(nonatomic) BOOL animated;
- (void)layer:(CAShapeLayer *)layer shows:(ArcShape)shape inWindow:(BOOL)inWindow
	pathFor:(CGPathRef (^)(ArcShape))pathFor;
@end

@implementation ArcAnimator {
	ArcShape _shown, _from, _to, _batchFrom;
	BOOL _hasShown, _animating, _batching;
	CFTimeInterval _start;
}

/* What is on screen now, partway through a running animation. */
- (ArcShape)displayed {
	if (!_animating) return _shown;
	CGFloat t = (CGFloat)((CACurrentMediaTime() - _start) / kArcAnimationDuration);
	return t >= 1 ? _shown : arc_shape_mix(_from, _to, arc_ease(MAX(0, t)));
}

- (void)layer:(CAShapeLayer *)layer shows:(ArcShape)shape inWindow:(BOOL)inWindow
	pathFor:(CGPathRef (^)(ArcShape))pathFor {
	if (_hasShown && arc_shape_equal(shape, _shown)) return;
	BOOL animate = self.animated && _hasShown && inWindow && !reduce_motion_enabled();
	if (animate) {
		if (!_batching) {
			_batching = YES;
			_batchFrom = [self displayed];
			dispatch_async(dispatch_get_main_queue(), ^{ self->_batching = NO; });
		}
		NSInteger frames = (NSInteger)ceil(kArcAnimationDuration * kArcShapeFrameRate) + 1;
		NSMutableArray *paths = [NSMutableArray arrayWithCapacity:(NSUInteger)frames];
		NSMutableArray<NSNumber *> *times = [NSMutableArray arrayWithCapacity:(NSUInteger)frames];
		for (NSInteger frame = 0; frame < frames; frame++) {
			CGFloat t = (CGFloat)frame / (CGFloat)(frames - 1);
			CGPathRef path = pathFor(frame == frames - 1 ? shape : arc_shape_mix(_batchFrom, shape, arc_ease(t)));
			[paths addObject:path ? (__bridge_transfer id)path : (__bridge_transfer id)CGPathCreateMutable()];
			[times addObject:@(t)];
		}
		CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"path"];
		animation.values = paths;
		animation.keyTimes = times;
		animation.calculationMode = kCAAnimationLinear;
		animation.duration = kArcAnimationDuration;
		[layer addAnimation:animation forKey:@"arc.shape"];
		_from = _batchFrom;
		_to = shape;
		_start = CACurrentMediaTime();
		_animating = YES;
	} else {
		[layer removeAnimationForKey:@"arc.shape"];
		_animating = NO;
	}
	_shown = shape;
	_hasShown = YES;
}
@end
