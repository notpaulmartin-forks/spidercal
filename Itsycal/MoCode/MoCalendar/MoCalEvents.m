//
//  MoCalEvents.m
//  Spidercal
//

#import "MoCalEvents.h"
#import "MoCalGrid.h"
#import "MoCalCell.h"
#import "Sizer.h"
#import "Themer.h"

// Details: an event's distance from the cell's edges, its title's
// padding, and the width of the bar before an event at a time.
static const CGFloat kChipInset = 2;
static const CGFloat kTextPadding = 3;
static const CGFloat kTimeBarWidth = 2;
// Lines: the ends of a one-day line and of a multi-day line. A one-day
// line stays inside the today/selected outline.
static const CGFloat kLineInset = 4.5;
static const CGFloat kMultiDayLineInset = 2.5;
// Days outside the month are dimmed, as their dates are.
static const CGFloat kDimmedAlpha = 0.4;
enum { kMaxLanes = 64 };

@implementation MoCalEvent
@end

// An event's place in one week (a row of the calendar).
@interface MoCalLaneItem : NSObject
@property (nonatomic) MoCalEvent *event;
@property (nonatomic) NSInteger startCol, endCol;
@property (nonatomic) NSInteger lane;
// Lanes it takes: 1, or more for a one-day event whose title wraps.
@property (nonatomic) NSInteger lanes;
@property (nonatomic) BOOL multiDay;
// It goes on into the week before / after.
@property (nonatomic) BOOL continuesBefore, continuesAfter;
@end

@implementation MoCalLaneItem
@end

#pragma mark - Text

// Titles are drawn with TextKit, so one can wrap onto a set number of
// lines with its last line clipped, as a one-line title is. Clipping
// shows more of a title than an ellipsis in these narrow cells.
static NSTextStorage *gStorage;
static NSLayoutManager *gLayoutManager;
static NSTextContainer *gContainer;

static void SetText(NSString *text, NSFont *font, NSColor *color, NSTextAlignment alignment, CGFloat width, NSInteger maxLines)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gStorage = [NSTextStorage new];
        gLayoutManager = [NSLayoutManager new];
        gContainer = [[NSTextContainer alloc] initWithSize:NSZeroSize];
        gContainer.lineFragmentPadding = 0;
        [gLayoutManager addTextContainer:gContainer];
        [gStorage addLayoutManager:gLayoutManager];
    });
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = alignment;
    style.lineBreakMode = NSLineBreakByWordWrapping;
    gContainer.size = NSMakeSize(MAX(width, 1), CGFLOAT_MAX);
    gContainer.maximumNumberOfLines = maxLines;
    gContainer.lineBreakMode = NSLineBreakByClipping; // the last line's
    [gStorage setAttributedString:[[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color ?: NSColor.textColor,
        NSParagraphStyleAttributeName: style,
    }]];
}

// The lines text takes when it wraps at width.
static NSInteger LinesForText(NSString *text, NSFont *font, CGFloat width)
{
    SetText(text, font, nil, NSTextAlignmentLeft, width, 0);
    __block NSInteger lines = 0;
    NSRange glyphs = [gLayoutManager glyphRangeForTextContainer:gContainer];
    [gLayoutManager enumerateLineFragmentsForGlyphRange:glyphs usingBlock:^(NSRect rect, NSRect usedRect, NSTextContainer *container, NSRange range, BOOL *stop) {
        lines++;
    }];
    return MAX(lines, 1);
}

// Draw text in rect, centered vertically, on at most maxLines lines.
// The view must be flipped.
static void DrawText(NSString *text, NSRect rect, NSFont *font, NSColor *color, NSTextAlignment alignment, NSInteger maxLines)
{
    SetText(text, font, color, alignment, NSWidth(rect), MAX(maxLines, 1));
    NSRange glyphs = [gLayoutManager glyphRangeForTextContainer:gContainer];
    NSRect used = [gLayoutManager usedRectForTextContainer:gContainer];
    NSPoint origin = NSMakePoint(NSMinX(rect), NSMinY(rect) + round((NSHeight(rect) - NSHeight(used)) / 2));
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(rect);
    [gLayoutManager drawGlyphsForGlyphRange:glyphs atPoint:origin];
    [NSGraphicsContext restoreGraphicsState];
}

#pragma mark - Layout

@interface MoCalEventLayout ()
- (void)drawInView:(NSView *)view grid:(MoCalGrid *)grid;
@end

@implementation MoCalEventLayout
{
    CalendarStyle _style;
    NSInteger _rows;
    NSArray<NSArray<MoCalLaneItem *> *> *_itemsByRow;
    // For each cell (row * 7 + col):
    NSMutableArray *_dotColors;  // NSArray<NSColor *>, or NSNull for none
    NSInteger *_visibleLanes;    // lanes that show events
    NSInteger *_hiddenCount;     // Details: events that don't fit ("+N")
}

- (instancetype)initWithEvents:(NSArray<MoCalEvent *> *)events firstDate:(MoDate)firstDate rows:(NSInteger)rows
{
    self = [super init];
    if (!self) return nil;
    _style = SizePref.calendarStyle;
    _rows = rows;
    _dotColors = [NSMutableArray new];
    _visibleLanes = calloc(rows * 7, sizeof(NSInteger));
    _hiddenCount = calloc(rows * 7, sizeof(NSInteger));

    BOOL details = _style == CalendarStyleDetails;
    NSInteger capacity = SizePref.calendarLaneCount;
    NSFont *font = [NSFont systemFontOfSize:SizePref.calendarEventFontSize];
    // The widths drawDetailsItem gives a title: in a tinted chip, and
    // after the bar of an event at a time.
    CGFloat chipTextWidth = SizePref.dateCellWidth - 2 * kChipInset - 2 * kTextPadding;
    CGFloat timedTextWidth = SizePref.dateCellWidth - 2 * kChipInset - kTimeBarWidth - kTextPadding - 1;

    // Events over several days go first, from the earliest start, and
    // the longest of those starting on the same day.
    NSMutableArray<MoCalEvent *> *multiDay = [NSMutableArray new];
    NSMutableDictionary<NSNumber *, NSMutableArray<MoCalEvent *> *> *oneDay = [NSMutableDictionary new];
    for (MoCalEvent *event in events) {
        if (event.endDate.julian > event.startDate.julian) {
            [multiDay addObject:event];
        }
        else {
            NSNumber *key = @(event.startDate.julian);
            if (!oneDay[key]) oneDay[key] = [NSMutableArray new];
            [oneDay[key] addObject:event];
        }
    }
    [multiDay sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MoCalEvent *a, MoCalEvent *b) {
        if (a.startDate.julian != b.startDate.julian) return a.startDate.julian < b.startDate.julian ? NSOrderedAscending : NSOrderedDescending;
        if (a.endDate.julian != b.endDate.julian) return a.endDate.julian > b.endDate.julian ? NSOrderedAscending : NSOrderedDescending;
        if (a.hasTime != b.hasTime) return a.hasTime ? NSOrderedDescending : NSOrderedAscending;
        return NSOrderedSame;
    }];

    NSMutableArray *itemsByRow = [NSMutableArray new];
    for (NSInteger row = 0; row < rows; row++) {
        MoDate weekStart = AddDaysToDate(row * 7, firstDate);
        NSInteger weekStartJulian = weekStart.julian, weekEndJulian = weekStartJulian + 6;
        BOOL occupied[kMaxLanes][7];
        memset(occupied, 0, sizeof(occupied));
        NSMutableArray<MoCalLaneItem *> *items = [NSMutableArray new];

        // Each event over several days in the lowest lane that's free
        // on all of its days this week.
        for (MoCalEvent *event in multiDay) {
            if (event.endDate.julian < weekStartJulian || event.startDate.julian > weekEndJulian) continue;
            NSInteger c0 = MAX(0, event.startDate.julian - weekStartJulian);
            NSInteger c1 = MIN(6, event.endDate.julian - weekStartJulian);
            NSInteger lane = 0;
            for (; lane < kMaxLanes - 1; lane++) {
                BOOL free = YES;
                for (NSInteger c = c0; c <= c1 && free; c++) free = !occupied[lane][c];
                if (free) break;
            }
            for (NSInteger c = c0; c <= c1; c++) occupied[lane][c] = YES;
            MoCalLaneItem *item = [MoCalLaneItem new];
            item.event = event;
            item.startCol = c0;
            item.endCol = c1;
            item.lane = lane;
            item.lanes = 1;
            item.multiDay = YES;
            item.continuesBefore = event.startDate.julian < weekStartJulian;
            item.continuesAfter = event.endDate.julian > weekEndJulian;
            [items addObject:item];
        }

        // Then each day's own events, in the lanes left.
        for (NSInteger col = 0; col < 7; col++) {
            NSInteger cell = row * 7 + col;
            NSMutableArray<MoCalEvent *> *laned = [NSMutableArray new];
            NSMutableOrderedSet *dots = [NSMutableOrderedSet new];
            BOOL hasDot = NO;
            for (MoCalEvent *event in oneDay[@(weekStartJulian + col)]) {
                // Lines: events at a time are dots.
                if (!details && event.hasTime) {
                    hasDot = YES;
                    if (event.color && dots.count < 3) [dots addObject:event.color];
                }
                else {
                    [laned addObject:event];
                }
            }
            // As in MoCalCell: an empty array is one dot in the theme's color.
            [_dotColors addObject:hasDot ? dots.array : (id)NSNull.null];

            NSMutableArray<NSNumber *> *freeLanes = [NSMutableArray new];
            NSInteger usedLanes = 0;
            for (NSInteger lane = 0; lane < kMaxLanes; lane++) {
                if (occupied[lane][col]) usedLanes = lane + 1;
                else if (freeLanes.count < laned.count + capacity) [freeLanes addObject:@(lane)];
            }
            NSInteger n = MIN(laned.count, freeLanes.count);
            if (n > 0) usedLanes = MAX(usedLanes, freeLanes[n - 1].integerValue + 1);

            // Details: if they don't all fit, the last lane says how
            // many more there are.
            BOOL overflows = details && usedLanes > capacity;
            _visibleLanes[cell] = overflows ? capacity - 1 : capacity;

            NSInteger cursor = 0;
            for (NSInteger i = 0; i < n; i++) {
                MoCalEvent *event = laned[i];
                NSInteger lane = freeLanes[cursor].integerValue;
                // Details: a title that wraps gets the free lanes
                // under it, leaving one for each event after it.
                NSInteger extra = 0;
                if (details && !overflows) {
                    CGFloat width = event.hasTime ? timedTextWidth : chipTextWidth;
                    NSInteger wanted = MIN(LinesForText(event.title, font, width), capacity) - 1;
                    while (extra < wanted) {
                        NSInteger next = cursor + 1 + extra;
                        if (next >= (NSInteger)freeLanes.count) break;
                        NSInteger nextLane = freeLanes[next].integerValue;
                        if (nextLane != lane + 1 + extra || nextLane >= capacity) break;
                        NSInteger lanesLeft = 0;
                        for (NSInteger j = next + 1; j < (NSInteger)freeLanes.count; j++) {
                            if (freeLanes[j].integerValue < capacity) lanesLeft++;
                        }
                        if (lanesLeft < n - i - 1) break;
                        extra++;
                    }
                }
                cursor += 1 + extra;
                MoCalLaneItem *item = [MoCalLaneItem new];
                item.event = event;
                item.startCol = col;
                item.endCol = col;
                item.lane = lane;
                item.lanes = 1 + extra;
                [items addObject:item];
                for (NSInteger l = lane; l < lane + 1 + extra; l++) occupied[l][col] = YES;
            }
            if (overflows) {
                NSInteger hidden = laned.count - n; // (only if there were too many lanes to try)
                for (MoCalLaneItem *item in items) {
                    if (item.startCol <= col && item.endCol >= col && item.lane >= capacity - 1) hidden++;
                }
                _hiddenCount[cell] = hidden;
            }
        }
        [itemsByRow addObject:items];
    }
    _itemsByRow = itemsByRow;
    return self;
}

- (void)dealloc
{
    free(_visibleLanes);
    free(_hiddenCount);
}

#pragma mark - Drawing

- (void)drawInView:(NSView *)view grid:(MoCalGrid *)grid
{
    NSArray<MoCalCell *> *cells = grid.cells;
    if (_style == CalendarStyleDots || (NSInteger)cells.count < _rows * 7) return;

    BOOL details = _style == CalendarStyleDetails;
    CGFloat laneTop = SizePref.calendarLaneTop;
    CGFloat laneHeight = SizePref.calendarLaneHeight;
    CGFloat laneGap = SizePref.calendarLaneGap;
    NSFont *font = [NSFont systemFontOfSize:SizePref.calendarEventFontSize];
    CGFloat lineHeight = [gLayoutManager ?: [NSLayoutManager new] defaultLineHeightForFont:font];
    BOOL dark = [[view.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]] isEqualToString:NSAppearanceNameDarkAqua];
    CGFloat fillAlpha = dark ? 0.36 : 0.24;

    for (NSInteger row = 0; row < _rows; row++) {
        NSRect cellRects[7];
        BOOL dimmed[7];
        for (NSInteger col = 0; col < 7; col++) {
            MoCalCell *cell = cells[row * 7 + col];
            cellRects[col] = [view convertRect:cell.frame fromView:grid];
            dimmed[col] = !cell.isInCurrentMonth;
        }
        CGFloat rowTop = NSMinY(cellRects[0]);
        CGFloat (^laneY)(NSInteger) = ^CGFloat(NSInteger lane) {
            return rowTop + laneTop + lane * (laneHeight + laneGap);
        };

        for (MoCalLaneItem *item in _itemsByRow[row]) {
            // The runs of days where it shows: an event over several
            // days is hidden on a day that's out of lanes.
            NSInteger col = item.startCol;
            while (col <= item.endCol) {
                if (item.lane + item.lanes > _visibleLanes[row * 7 + col]) { col++; continue; }
                NSInteger first = col;
                while (col + 1 <= item.endCol && item.lane + item.lanes <= _visibleLanes[row * 7 + col + 1]) col++;
                NSInteger last = col;
                col++;

                // Ends where the event starts or ends are rounded and
                // inset; the others meet the next run or week.
                BOOL roundStart = first == item.startCol && !item.continuesBefore;
                BOOL roundEnd = last == item.endCol && !item.continuesAfter;
                CGFloat inset = details ? kChipInset : (item.multiDay ? kMultiDayLineInset : kLineInset);
                CGFloat x0 = NSMinX(cellRects[first]) + (roundStart ? inset : 0);
                CGFloat x1 = NSMaxX(cellRects[last]) - (roundEnd ? inset : 0);
                CGFloat h = item.lanes * laneHeight + (item.lanes - 1) * laneGap;
                NSRect shape = NSMakeRect(x0, laneY(item.lane), x1 - x0, h);
                CGFloat radius = details ? SizePref.cellRadius : h / 2;
                NSRect drawn = shape;
                if (!roundStart) { drawn.origin.x -= radius; drawn.size.width += radius; }
                if (!roundEnd) drawn.size.width += radius;

                NSColor *color = item.event.color ?: Theme.currentMonthTextColor;
                // Draw each stretch of dimmed or undimmed days on its own.
                NSInteger d = first;
                while (d <= last) {
                    NSInteger dEnd = d;
                    while (dEnd + 1 <= last && dimmed[dEnd + 1] == dimmed[d]) dEnd++;
                    NSRect clip = NSMakeRect(NSMinX(cellRects[d]), NSMinY(shape) - 1, NSMaxX(cellRects[dEnd]) - NSMinX(cellRects[d]), h + 2);
                    [NSGraphicsContext saveGraphicsState];
                    NSRectClip(clip);
                    CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, dimmed[d] ? kDimmedAlpha : 1);
                    if (!details) {
                        [color setFill];
                        [[NSBezierPath bezierPathWithRoundedRect:drawn xRadius:radius yRadius:radius] fill];
                    }
                    else {
                        [self drawDetailsItem:item shape:shape drawn:drawn radius:radius color:color fillAlpha:fillAlpha font:font lineHeight:lineHeight];
                    }
                    [NSGraphicsContext restoreGraphicsState];
                    d = dEnd + 1;
                }
            }
        }

        // Lines: dots for the events at a time, under the day's lines.
        if (!details) {
            CGFloat dotWidth = SizePref.cellDotWidth;
            for (NSInteger col = 0; col < 7; col++) {
                id colors = _dotColors[row * 7 + col];
                if (colors == NSNull.null) continue;
                NSInteger lines = 0;
                for (MoCalLaneItem *item in _itemsByRow[row]) {
                    if (item.startCol <= col && item.endCol >= col && item.lane < _visibleLanes[row * 7 + col]) {
                        lines = MAX(lines, item.lane + 1);
                    }
                }
                NSArray<NSColor *> *dotColors = [colors count] ? colors : @[Theme.currentMonthTextColor];
                NSInteger count = MIN(dotColors.count, 3);
                NSRect r = NSMakeRect(0, laneY(lines) + 1.5, dotWidth, dotWidth);
                [NSGraphicsContext saveGraphicsState];
                CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, dimmed[col] ? kDimmedAlpha : 1);
                for (NSInteger i = 0; i < count; i++) {
                    [dotColors[i] setFill];
                    r.origin.x = NSMidX(cellRects[col]) + (i - (count - 1) / 2.0) * 1.5 * dotWidth - dotWidth / 2;
                    [[NSBezierPath bezierPathWithOvalInRect:r] fill];
                }
                [NSGraphicsContext restoreGraphicsState];
            }
        }

        // Details: "+N" in the last lane of a day with too many events.
        if (details) {
            for (NSInteger col = 0; col < 7; col++) {
                NSInteger hidden = _hiddenCount[row * 7 + col];
                if (hidden <= 0) continue;
                NSRect r = NSMakeRect(NSMinX(cellRects[col]) + kChipInset + kTextPadding, laneY(_visibleLanes[row * 7 + col]),
                                      NSWidth(cellRects[col]) - 2 * (kChipInset + kTextPadding), laneHeight);
                [NSGraphicsContext saveGraphicsState];
                CGContextSetAlpha(NSGraphicsContext.currentContext.CGContext, dimmed[col] ? kDimmedAlpha : 1);
                DrawText([NSString stringWithFormat:@"+%ld", (long)hidden], r, font, Theme.agendaEventDateTextColor, NSTextAlignmentLeft, 1);
                [NSGraphicsContext restoreGraphicsState];
            }
        }
    }
}

// Details: all-day and multi-day events are tinted with their color;
// events at a time have a bar of it before the title.
- (void)drawDetailsItem:(MoCalLaneItem *)item shape:(NSRect)shape drawn:(NSRect)drawn radius:(CGFloat)radius color:(NSColor *)color fillAlpha:(CGFloat)fillAlpha font:(NSFont *)font lineHeight:(CGFloat)lineHeight
{
    MoCalEvent *event = item.event;
    BOOL tinted = item.multiDay || !event.hasTime;
    NSRect textRect;
    if (tinted) {
        [[color colorWithAlphaComponent:fillAlpha] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:drawn xRadius:radius yRadius:radius] fill];
        textRect = NSInsetRect(shape, kTextPadding, 0);
    }
    else {
        [color setFill];
        NSRect bar = NSMakeRect(NSMinX(shape), NSMinY(shape) + 1, kTimeBarWidth, NSHeight(shape) - 2);
        [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:kTimeBarWidth / 2 yRadius:kTimeBarWidth / 2] fill];
        textRect = shape;
        textRect.origin.x += kTimeBarWidth + kTextPadding;
        textRect.size.width -= kTimeBarWidth + kTextPadding + 1;
    }
    NSInteger maxLines = MAX(1, (NSInteger)floor((NSHeight(shape) - 1) / lineHeight));
    if (item.lanes == 1) maxLines = 1;
    // A multi-day event's title is centered over its days, if it fits.
    NSTextAlignment alignment = NSTextAlignmentLeft;
    if (item.multiDay) {
        CGFloat width = [event.title ?: @"" sizeWithAttributes:@{NSFontAttributeName: font}].width;
        if (width <= NSWidth(textRect)) alignment = NSTextAlignmentCenter;
    }
    DrawText(event.title, textRect, font, Theme.agendaEventTextColor, alignment, maxLines);
}

@end

#pragma mark - View

@implementation MoCalEventsView

- (BOOL)isFlipped
{
    return YES; // for TextKit
}

- (NSView *)hitTest:(NSPoint)point
{
    return nil; // clicks are the calendar's
}

- (void)setLayout:(MoCalEventLayout *)layout
{
    _layout = layout;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (!self.grid) return;
    if (SizePref.calendarStyle == CalendarStyleDetails) [self drawWeekLines];
    [self.layout drawInView:self grid:self.grid];
}

// Details: faint lines between the weeks, under the events, so it's
// clear which dates an event is under.
- (void)drawWeekLines
{
    NSArray<MoCalCell *> *cells = self.grid.cells;
    NSInteger rows = self.grid.rows;
    if ((NSInteger)cells.count < rows * 7) return;
    [Theme.agendaDividerColor setFill];
    for (NSInteger row = 1; row < rows; row++) {
        NSRect first = [self convertRect:cells[row * 7].frame fromView:self.grid];
        NSRect last = [self convertRect:cells[row * 7 + 6].frame fromView:self.grid];
        NSRectFillUsingOperation(NSMakeRect(NSMinX(first), NSMinY(first) - 0.5, NSMaxX(last) - NSMinX(first), 1), NSCompositingOperationSourceOver);
    }
}

@end
