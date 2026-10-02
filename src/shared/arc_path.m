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

static NSValue *arc_shape_value(ArcShape shape) {
	return [NSValue valueWithBytes:&shape objCType:@encode(ArcShape)];
}

static ArcShape arc_shape_from_value(NSValue *value) {
	ArcShape shape;
	[value getValue:&shape size:sizeof(shape)];
	return shape;
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
