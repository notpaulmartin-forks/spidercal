//
//  DayPicker.m
//  Spidercal
//

#import "DayPicker.h"
#import "Itsycal.h"
#import "MoUtils.h"
#import "Sizer.h"
#import "Themer.h"

// The box looks like the place suggestions' under the location field.
static const CGFloat kCornerRadius = 6;
// Room around the box for its shadow, which the window doesn't draw.
static const CGFloat kShadowMargin = 6;

#pragma mark -
#pragma mark Helpers

// The sizes of the parts, which follow the size preference. At the
// medium size: rows of 20 points and columns of 25.
typedef struct {
    CGFloat pad, headerHeight, dowHeight, rowHeight, columnWidth;
    CGFloat buttonWidth, buttonImageSize;
} DayPickerMetrics;

static DayPickerMetrics Metrics(void)
{
    CGFloat fontSize = SizePref.fontSize;
    DayPickerMetrics m;
    m.pad = 8;
    m.headerHeight = round(fontSize * 1.55);
    m.dowHeight = round(fontSize * 1.1);
    m.rowHeight = round(fontSize * 1.55);
    m.columnWidth = round(fontSize * 1.9);
    m.buttonWidth = round(fontSize * 1.4);
    m.buttonImageSize = fontSize + 3;
    return m;
}

// image in color. image is a template, like the main calendar's
// buttons.
static NSImage *TintedImage(NSImage *image, NSColor *color)
{
    return [NSImage imageWithSize:image.size flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [image drawInRect:rect];
        [color set];
        NSRectFillUsingOperation(rect, NSCompositingOperationSourceAtop);
        return YES;
    }];
}

static void DrawCentered(NSString *string, NSRect rect, NSDictionary *attributes)
{
    NSSize size = [string sizeWithAttributes:attributes];
    NSPoint point = NSMakePoint(NSMidX(rect) - size.width / 2, NSMidY(rect) - size.height / 2);
    [string drawAtPoint:NSMakePoint(round(point.x * 2) / 2, round(point.y * 2) / 2) withAttributes:attributes];
}

#pragma mark -
#pragma mark DayPickerPanel

// Never becomes key or main, so the window below keeps the focus.
@interface DayPickerPanel : NSPanel
@end

@implementation DayPickerPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

#pragma mark -
#pragma mark DayPickerAXElement

// A day or a button, for VoiceOver.
@interface DayPickerAXElement : NSAccessibilityElement
@property (nonatomic, copy) void (^press)(void);
@end

@implementation DayPickerAXElement
- (BOOL)accessibilityPerformPress
{
    if (self.press) self.press();
    return self.press != nil;
}
@end

#pragma mark -
#pragma mark DayPickerView

typedef NS_ENUM(NSInteger, DayPickerButton) {
    DayPickerButtonNone = -1,
    DayPickerButtonPrevious = 0,
    DayPickerButtonToday,
    DayPickerButtonNext,
};

// What a click is on: a button (DayPickerButton) or a day (kTargetDay
// plus its cell).
static const NSInteger kTargetNone = -1;
static const NSInteger kTargetDay = 100;

// The month's name and year with the main calendar's buttons, the
// days of the week and six weeks of days. The picked day is in a
// circle and today is in the color the main calendar shows it in. It's
// drawn on a card with rounded corners; the window is clear.
@interface DayPickerView : NSView
@property (nonatomic) NSCalendar *calendar;
@property (nonatomic) NSDateFormatter *monthFormatter;
@property (nonatomic) NSDate *date;  // the picked day
@property (nonatomic) NSDate *month; // the first day of the month shown
@property (nonatomic, copy) void (^dayPicked)(NSDate *day);
- (NSSize)size;
@end

@implementation DayPickerView
{
    NSInteger _hoveredCell;
    NSInteger _pressedTarget;
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _hoveredCell = -1;
        _pressedTarget = kTargetNone;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }

#pragma mark Layout

- (CGFloat)gridTop
{
    DayPickerMetrics m = Metrics();
    return m.pad + m.headerHeight + m.dowHeight;
}

- (CGFloat)gridWidth
{
    return Metrics().columnWidth * 7;
}

- (NSSize)size
{
    DayPickerMetrics m = Metrics();
    return NSMakeSize([self gridWidth] + m.pad * 2, [self gridTop] + m.rowHeight * 6 + m.pad);
}

- (NSRect)rectForButton:(DayPickerButton)button
{
    DayPickerMetrics m = Metrics();
    CGFloat right = m.pad + [self gridWidth] - 1;
    return NSMakeRect(right - m.buttonWidth * (3 - button), m.pad, m.buttonWidth, m.headerHeight);
}

- (NSRect)rectForCell:(NSInteger)cell
{
    DayPickerMetrics m = Metrics();
    return NSMakeRect(m.pad + (cell % 7) * m.columnWidth, [self gridTop] + (cell / 7) * m.rowHeight, m.columnWidth, m.rowHeight);
}

- (NSInteger)targetAtPoint:(NSPoint)point
{
    for (DayPickerButton button = DayPickerButtonPrevious; button <= DayPickerButtonNext; button++) {
        if (NSPointInRect(point, [self rectForButton:button])) return button;
    }
    NSInteger cell = [self cellAtPoint:point];
    if (cell >= 0) return kTargetDay + cell;
    return kTargetNone;
}

- (NSInteger)cellAtPoint:(NSPoint)point
{
    for (NSInteger cell = 0; cell < 42; cell++) {
        if (NSPointInRect(point, [self rectForCell:cell])) return cell;
    }
    return -1;
}

// The day in the first cell: the start of the week the month starts in.
- (NSDate *)firstShownDay
{
    NSInteger weekday = [_calendar component:NSCalendarUnitWeekday fromDate:_month];
    NSInteger offset = (weekday - _calendar.firstWeekday + 7) % 7;
    return [_calendar dateByAddingUnit:NSCalendarUnitDay value:-offset toDate:_month options:0];
}

- (NSDate *)dayForCell:(NSInteger)cell
{
    return [_calendar dateByAddingUnit:NSCalendarUnitDay value:cell toDate:[self firstShownDay] options:0];
}

#pragma mark Drawing

- (void)drawRect:(NSRect)dirtyRect
{
    if (_calendar == nil || _month == nil) return;
    DayPickerMetrics m = Metrics();
    CGFloat fontSize = SizePref.fontSize;

    // The box, with a hairline around it, as the place suggestions have.
    NSBezierPath *card = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:kCornerRadius yRadius:kCornerRadius];
    [Theme.tooltipBackgroundColor setFill];
    [card fill];
    [Theme.agendaDividerColor setStroke];
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:kCornerRadius - 0.5 yRadius:kCornerRadius - 0.5];
    outline.lineWidth = 1;
    [outline stroke];

    // The month and year, and the buttons.
    NSDictionary *monthAttributes = @{NSFontAttributeName: [NSFont systemFontOfSize:fontSize - 1 weight:NSFontWeightSemibold],
                                      NSForegroundColorAttributeName: Theme.monthTextColor};
    NSString *title = [_monthFormatter stringFromDate:_month];
    NSSize titleSize = [title sizeWithAttributes:monthAttributes];
    [title drawAtPoint:NSMakePoint(m.pad + 3, m.pad + round((m.headerHeight - titleSize.height) / 2)) withAttributes:monthAttributes];
    NSArray<NSString *> *imageNames = @[@"btnPrev", @"btnToday", @"btnNext"];
    for (DayPickerButton button = DayPickerButtonPrevious; button <= DayPickerButtonNext; button++) {
        NSString *name = imageNames[button];
        if (button == _pressedTarget) name = [name stringByAppendingString:@"Alt"];
        NSImage *image = TintedImage([NSImage imageNamed:name], Theme.buttonTintColor);
        NSRect rect = [self rectForButton:button];
        CGFloat size = m.buttonImageSize;
        NSRect imageRect = NSMakeRect(round(NSMidX(rect) - size / 2), round(NSMidY(rect) - size / 2), size, size);
        [image drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
    }

    // The days of the week.
    NSMutableParagraphStyle *centered = [NSMutableParagraphStyle new];
    centered.alignment = NSTextAlignmentCenter;
    NSDictionary *dowAttributes = @{NSFontAttributeName: [NSFont systemFontOfSize:fontSize - 3 weight:NSFontWeightSemibold],
                                    NSForegroundColorAttributeName: NSColor.secondaryLabelColor};
    NSArray<NSString *> *symbols = _monthFormatter.veryShortStandaloneWeekdaySymbols;
    for (NSInteger column = 0; column < 7; column++) {
        NSString *symbol = symbols[(_calendar.firstWeekday - 1 + column) % 7];
        DrawCentered(symbol, NSMakeRect(m.pad + column * m.columnWidth, m.pad + m.headerHeight, m.columnWidth, m.dowHeight), dowAttributes);
    }

    // The days.
    CGFloat diameter = MIN(m.rowHeight, m.columnWidth);
    for (NSInteger cell = 0; cell < 42; cell++) {
        NSDate *day = [self dayForCell:cell];
        NSRect rect = [self rectForCell:cell];
        NSRect circle = NSMakeRect(NSMidX(rect) - diameter / 2, NSMidY(rect) - diameter / 2, diameter, diameter);
        BOOL inMonth = [_calendar isDate:day equalToDate:_month toUnitGranularity:NSCalendarUnitMonth];
        BOOL picked = _date && [_calendar isDate:day inSameDayAsDate:_date];
        NSColor *color = inMonth ? Theme.currentMonthTextColor : Theme.noncurrentMonthTextColor;
        NSFontWeight weight = NSFontWeightRegular;
        if (picked) {
            [Theme.todayCellColor setFill];
            [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
            color = NSColor.whiteColor;
            weight = NSFontWeightSemibold;
        }
        else {
            BOOL pressed = _pressedTarget == kTargetDay + cell;
            if (pressed || cell == _hoveredCell) {
                [[NSColor.labelColor colorWithAlphaComponent:pressed ? 0.16 : 0.08] setFill];
                [[NSBezierPath bezierPathWithOvalInRect:circle] fill];
            }
            if ([_calendar isDateInToday:day]) {
                color = Theme.todayCellColor;
                weight = NSFontWeightSemibold;
            }
        }
        NSString *number = [NSString stringWithFormat:@"%ld", (long)[_calendar component:NSCalendarUnitDay fromDate:day]];
        DrawCentered(number, rect, @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:fontSize - 2 weight:weight],
                                     NSForegroundColorAttributeName: color});
    }
}

#pragma mark Mouse

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)setHoveredCell:(NSInteger)cell
{
    if (cell == _hoveredCell) return;
    _hoveredCell = cell;
    self.needsDisplay = YES;
}

- (void)mouseMoved:(NSEvent *)event
{
    [self setHoveredCell:[self cellAtPoint:[self convertPoint:event.locationInWindow fromView:nil]]];
}

- (void)mouseExited:(NSEvent *)event
{
    [self setHoveredCell:-1];
}

// A day or a button is clicked when the mouse goes up on it.
- (void)mouseDown:(NSEvent *)event
{
    NSInteger target = [self targetAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (target == kTargetNone) return;
    BOOL inside = YES;
    while (YES) {
        _pressedTarget = inside ? target : kTargetNone;
        [self display];
        NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        inside = [self targetAtPoint:[self convertPoint:next.locationInWindow fromView:nil]] == target;
        if (next.type == NSEventTypeLeftMouseUp) break;
    }
    _pressedTarget = kTargetNone;
    self.needsDisplay = YES;
    if (!inside) return;
    if (target >= kTargetDay) {
        [self pickDay:[self dayForCell:target - kTargetDay]];
    }
    else {
        [self clickButton:target];
    }
}

- (void)clickButton:(DayPickerButton)button
{
    if (button == DayPickerButtonToday) {
        self.month = [self firstDayOfMonthOf:[NSDate date]];
    }
    else {
        self.month = [_calendar dateByAddingUnit:NSCalendarUnitMonth value:button == DayPickerButtonNext ? 1 : -1 toDate:_month options:0];
    }
    self.needsDisplay = YES;
    NSAccessibilityPostNotification(self, NSAccessibilityLayoutChangedNotification);
}

- (void)pickDay:(NSDate *)day
{
    if (self.dayPicked) self.dayPicked([_calendar startOfDayForDate:day]);
}

- (NSDate *)firstDayOfMonthOf:(NSDate *)date
{
    NSDate *month = nil;
    [_calendar rangeOfUnit:NSCalendarUnitMonth startDate:&month interval:NULL forDate:date];
    return month ?: date;
}

#pragma mark Accessibility

- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityGroupRole; }

- (NSString *)accessibilityLabel
{
    return _month ? [_monthFormatter stringFromDate:_month] : nil;
}

- (NSArray *)accessibilityChildren
{
    if (_calendar == nil || _month == nil) return @[];
    __weak DayPickerView *weakSelf = self;
    NSMutableArray *children = [NSMutableArray new];
    NSArray<NSString *> *buttonLabels = @[NSLocalizedString(@"Previous Month", @""),
                                          NSLocalizedString(@"Today", @""),
                                          NSLocalizedString(@"Next Month", @"")];
    for (DayPickerButton button = DayPickerButtonPrevious; button <= DayPickerButtonNext; button++) {
        DayPickerAXElement *element = [DayPickerAXElement new];
        element.accessibilityRole = NSAccessibilityButtonRole;
        element.accessibilityLabel = buttonLabels[button];
        element.accessibilityParent = self;
        element.accessibilityFrameInParentSpace = [self rectForButton:button];
        element.press = ^{ [weakSelf clickButton:button]; };
        [children addObject:element];
    }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = _monthFormatter.locale;
    formatter.dateStyle = NSDateFormatterFullStyle;
    for (NSInteger cell = 0; cell < 42; cell++) {
        NSDate *day = [self dayForCell:cell];
        DayPickerAXElement *element = [DayPickerAXElement new];
        element.accessibilityRole = NSAccessibilityButtonRole;
        element.accessibilityLabel = [formatter stringFromDate:day];
        element.accessibilitySelected = _date && [_calendar isDate:day inSameDayAsDate:_date];
        element.accessibilityParent = self;
        element.accessibilityFrameInParentSpace = [self rectForCell:cell];
        element.press = ^{ [weakSelf pickDay:day]; };
        [children addObject:element];
    }
    return children;
}

@end

#pragma mark -
#pragma mark DayPicker

@implementation DayPicker
{
    DayPickerPanel *_panel;
    DayPickerView *_view;
    __weak NSView *_anchor;
    __weak NSWindow *_observedWindow;
}

- (void)makePanel
{
    _view = [[DayPickerView alloc] initWithFrame:NSZeroRect];
    __weak DayPicker *weakSelf = self;
    _view.dayPicked = ^(NSDate *day) {
        DayPicker *strongSelf = weakSelf;
        if (strongSelf.dayPicked) strongSelf.dayPicked(day);
    };

    // The same faint shadow as the place suggestions, not a window's.
    // The box sits in a clear view with room around it for the shadow.
    _view.wantsLayer = YES;
    NSShadow *shadow = [NSShadow new];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.08];
    shadow.shadowBlurRadius = 3;
    shadow.shadowOffset = NSMakeSize(0, -1);
    _view.shadow = shadow;
    NSView *container = [NSView new];
    container.wantsLayer = YES;
    [container addSubview:_view];

    _panel = [[DayPickerPanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:YES];
    _panel.contentView = container;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = NO;
    _panel.releasedWhenClosed = NO;
    _panel.becomesKeyOnlyIfNeeded = YES;
    _panel.hidesOnDeactivate = YES;
    _panel.animationBehavior = NSWindowAnimationBehaviorNone;
}

- (void)dealloc
{
    [self close];
}

- (void)setDate:(NSDate *)date
{
    _date = date;
    if (_view == nil || date == nil) return;
    _view.date = date;
    _view.month = [_view firstDayOfMonthOf:date];
    _view.needsDisplay = YES;
}

- (BOOL)isShown
{
    return _panel.isVisible;
}

- (void)showBelowView:(NSView *)view
{
    NSWindow *parent = view.window;
    if (parent == nil) return;
    if (_panel == nil) [self makePanel];
    _anchor = view;

    // As in the main calendar: the week starts on the day Settings
    // says, and the names are in the user's language.
    NSCalendar *calendar = [NSCalendar.currentCalendar copy];
    calendar.firstWeekday = [NSUserDefaults.standardUserDefaults integerForKey:kWeekStartDOW] + 1;
    NSDateFormatter *monthFormatter = [NSDateFormatter new];
    monthFormatter.locale = DateIntervalFormatterLocale();
    monthFormatter.calendar = calendar;
    [monthFormatter setLocalizedDateFormatFromTemplate:@"MMMMy"];
    _view.calendar = calendar;
    _view.monthFormatter = monthFormatter;
    if (!self.isShown) self.date = _date ?: [NSDate date];
    _panel.appearance = view.effectiveAppearance;

    [self place];
    _view.needsDisplay = YES;
    if (_panel.parentWindow != parent) {
        [_panel.parentWindow removeChildWindow:_panel];
        [parent addChildWindow:_panel ordered:NSWindowAbove];
    }
    [self observeWindow:parent];
    [_panel orderFront:nil];
    [_panel display];
}

// Below the anchor, with the month's name lined up with its text, or
// above it if there's no room below. If neither has room, on the side
// with more, kept on the screen.
- (void)place
{
    NSView *view = _anchor;
    NSWindow *parent = view.window;
    if (parent == nil) return;
    NSSize size = [_view size];
    NSRect anchor = [parent convertRectToScreen:[view convertRect:view.bounds toView:nil]];
    NSRect visible = (parent.screen ?: NSScreen.mainScreen).visibleFrame;
    CGFloat below = NSMinY(anchor) - 6 - size.height;
    CGFloat above = NSMaxY(anchor) + 6;
    CGFloat y = below;
    if (below < NSMinY(visible)) {
        if (above + size.height <= NSMaxY(visible) || NSMaxY(visible) - NSMaxY(anchor) > NSMinY(anchor) - NSMinY(visible)) {
            y = above;
        }
        y = MAX(NSMinY(visible), MIN(y, NSMaxY(visible) - size.height));
    }
    CGFloat x = MAX(NSMinX(visible), MIN(NSMinX(anchor) - 4, NSMaxX(visible) - size.width));
    _view.frame = NSMakeRect(kShadowMargin, kShadowMargin, size.width, size.height);
    NSRect frame = NSInsetRect(NSMakeRect(x, y, size.width, size.height), -kShadowMargin, -kShadowMargin);
    if (!NSEqualRects(frame, _panel.frame)) [_panel setFrame:frame display:YES];
}

// The popover moves with its event when the agenda scrolls, and the
// panel moves with the popover. Each time, it's placed again, so it
// goes above the date when the screen ends below it, and back when
// there's room again.
- (void)observeWindow:(NSWindow *)window
{
    if (_observedWindow == window) return;
    [self stopObservingWindow];
    _observedWindow = window;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(windowMoved:) name:NSWindowDidMoveNotification object:window];
    [center addObserver:self selector:@selector(windowMoved:) name:NSWindowDidResizeNotification object:window];
}

- (void)stopObservingWindow
{
    if (_observedWindow == nil) return;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:self name:NSWindowDidMoveNotification object:_observedWindow];
    [center removeObserver:self name:NSWindowDidResizeNotification object:_observedWindow];
    _observedWindow = nil;
}

- (void)windowMoved:(NSNotification *)notification
{
    if (self.isShown && _anchor) [self place];
}

- (void)close
{
    _anchor = nil;
    [self stopObservingWindow];
    if (_panel == nil) return;
    [_panel.parentWindow removeChildWindow:_panel];
    [_panel orderOut:nil];
}

@end
