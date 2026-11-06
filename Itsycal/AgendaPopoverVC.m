//
//  Created by Sanjay Madan on 10/28/26.
//  Copyright © 2026 mowglii.com. All rights reserved.
//

#import "AgendaPopoverVC.h"
#import "EventCenter.h"
#import "MoPopover.h"
#import "MoThemeView.h"
#import "MoUtils.h"
#import "MoVFLHelper.h"
#import "NLEventParser.h"
#import "Sizer.h"
#import "Themer.h"

// The width of the popover's text.
static const CGFloat kTextWidth = 280;

// Rows for many attendees take long to lay out: about 40 ms for 50,
// seconds for 500. Show at most this many lines: all the attendees if
// they fit, or one fewer and a line saying how many more.
static const NSUInteger kMaxAttendeeLines = 50;

// Space between the popover's edge and its content.
static const CGFloat kInset = 14;

// The popover is at most this tall, about as tall as Calendar's event
// popover can be, and the body scrolls. (NSPopover keeps it on screen.)
static const CGFloat kMaxPopoverHeight = 800;

// The space between a time picker's edges and its text.
static const CGFloat kTimePickerLeadingInset = 2.5;
static const CGFloat kTimePickerTrailingInset = 3;

// The changes made in the details, kept until -saveChanges, by part.
// NSNull for a part that was removed.
static NSString * const kChangeTitle = @"title";
static NSString * const kChangeLocation = @"location";
static NSString * const kChangeNotes = @"notes";       // plain text
static NSString * const kChangeURL = @"URL";
static NSString * const kChangeStart = @"start";
static NSString * const kChangeEnd = @"end";
static NSString * const kChangeAllDay = @"allDay";
static NSString * const kChangeAlarms = @"alarms";     // see AlarmValues()
static NSString * const kChangeRule = @"rule";         // EKRecurrenceRule
static NSString * const kChangeCalendar = @"calendar";

// YES if any of views isn't hidden.
static BOOL AnyViewShows(NSArray<NSView *> *views)
{
    for (NSView *view in views) {
        if (!view.hidden) return YES;
    }
    return NO;
}

// A dot in a calendar's color, the size of the agenda's. Gray if the
// calendar has no color.
static NSImage *CalendarDotImage(NSColor *color)
{
    CGFloat side = SizePref.agendaDotWidth;
    return [NSImage imageWithSize:NSMakeSize(side, side) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [(color ?: NSColor.secondaryLabelColor) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:rect] fill];
        return YES;
    }];
}

// string without surrounding whitespace, or nil if that leaves nothing.
static NSString *Trimmed(NSString *string)
{
    NSString *trimmed = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 ? trimmed : nil;
}

static NSString *BackspaceKeyEquivalent(void)
{
    unichar backspaceKey = NSBackspaceCharacter;
    return [NSString stringWithCharacters:&backspaceKey length:1];
}

#pragma mark -
#pragma mark Dates

// A day as the details show it, e.g. "6 Nov 2026".
static NSString *DayString(NSDate *date)
{
    static NSDateFormatter *formatter = nil;
    if (formatter == nil) {
        formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterNoStyle;
    }
    formatter.locale = DateIntervalFormatterLocale();
    formatter.timeZone = NSTimeZone.localTimeZone;
    return [formatter stringFromDate:date];
}

// The last second of date's day, where an all-day event ends.
static NSDate *EndOfDay(NSCalendar *calendar, NSDate *date)
{
    NSDate *startOfDay = [calendar startOfDayForDate:date];
    return [[calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:startOfDay options:0] dateByAddingTimeInterval:-1];
}

// day at the time of day of time.
static NSDate *DayAtTimeOf(NSCalendar *calendar, NSDate *day, NSDate *time)
{
    NSDateComponents *t = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:time];
    return [calendar dateBySettingHour:t.hour minute:t.minute second:t.second ofDate:day options:0] ?: day;
}

// When an event is, as the details showed it before they could be
// changed. A timed event's start and end are on separate lines if
// they're on different days.
static NSString *DurationText(NSDate *start, NSDate *end, BOOL allDay)
{
    NSString *duration = DateRangeString(start, end, allDay);
    // The – is U+2013 (en-dash) and the space is U+2009 (thin space)
    if (!allDay) {
        NSDateComponents *s = [NSCalendar.currentCalendar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:start];
        NSDateComponents *e = [NSCalendar.currentCalendar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:end];
        if (s.day != e.day || s.month != e.month) {
            duration = [duration stringByReplacingOccurrencesOfString:@"– " withString:@"–\n"];
        }
    }
    return duration;
}

#pragma mark -
#pragma mark Alerts

// An event's alarms as values: NSNumber for an offset from the start
// (EKAlarm's relativeOffset), NSDate for an alarm at a date.
static NSArray *AlarmValues(NSArray<EKAlarm *> *alarms)
{
    NSMutableArray *values = [NSMutableArray new];
    for (EKAlarm *alarm in alarms) {
        [values addObject:alarm.absoluteDate ?: @(alarm.relativeOffset)];
    }
    return values;
}

// The alerts offered, as in the new event form.
static NSArray<NSNumber *> *AlertOffsets(BOOL allDay)
{
    if (allDay) return @[@(32400), @(-54000), @(-140400), @(-572400)];
    return @[@(0), @(-300), @(-600), @(-900), @(-1800), @(-3600), @(-7200), @(-86400), @(-172800)];
}

// An alarm value (see AlarmValues()) as words, e.g. "1 hour before".
static NSString *AlertTitle(id alarm, BOOL allDay)
{
    if ([alarm isKindOfClass:[NSDate class]]) {
        return [NSDateFormatter localizedStringFromDate:alarm dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle];
    }
    NSInteger offset = [alarm integerValue];
    if (allDay) {
        switch (offset) {
            case 32400:   return NSLocalizedString(@"On day of event (9 AM)", @"");
            case -54000:  return NSLocalizedString(@"1 day before (9 AM)", @"");
            case -140400: return NSLocalizedString(@"2 days before (9 AM)", @"");
            case -572400: return NSLocalizedString(@"1 week before", @"");
        }
    }
    else {
        switch (offset) {
            case -300:    return NSLocalizedString(@"5 minutes before", @"");
            case -600:    return NSLocalizedString(@"10 minutes before", @"");
            case -900:    return NSLocalizedString(@"15 minutes before", @"");
            case -1800:   return NSLocalizedString(@"30 minutes before", @"");
            case -3600:   return NSLocalizedString(@"1 hour before", @"");
            case -7200:   return NSLocalizedString(@"2 hours before", @"");
            case -86400:  return NSLocalizedString(@"1 day before", @"");
            case -172800: return NSLocalizedString(@"2 days before", @"");
        }
    }
    if (offset == 0) return NSLocalizedString(@"At time of event", @"");
    static NSDateComponentsFormatter *formatter = nil;
    if (formatter == nil) {
        formatter = [NSDateComponentsFormatter new];
        formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleFull;
        formatter.allowedUnits = NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute;
        formatter.maximumUnitCount = 2;
    }
    NSString *amount = [formatter stringFromTimeInterval:labs(offset)] ?: @"";
    return offset < 0
        ? [NSString stringWithFormat:NSLocalizedString(@"%@ before", @"An event's alert, e.g. 3 hours before"), amount]
        : [NSString stringWithFormat:NSLocalizedString(@"%@ after", @"An event's alert, e.g. 3 hours after"), amount];
}

#pragma mark -
#pragma mark Repeat

typedef struct {
    EKRecurrenceFrequency frequency;
    NSInteger interval;
} RepeatPreset;

// The repeats offered, as in the new event form.
static const RepeatPreset kRepeatPresets[] = {
    {EKRecurrenceFrequencyDaily, 1},
    {EKRecurrenceFrequencyWeekly, 1},
    {EKRecurrenceFrequencyWeekly, 2},
    {EKRecurrenceFrequencyMonthly, 1},
    {EKRecurrenceFrequencyYearly, 1},
};
static const NSInteger kRepeatPresetCount = sizeof(kRepeatPresets) / sizeof(kRepeatPresets[0]);

// The rule repeats every so many days, weeks, months or years, with
// no particular days, like the presets.
static BOOL RuleIsSimple(EKRecurrenceRule *rule)
{
    return rule.daysOfTheWeek.count == 0 && rule.daysOfTheMonth.count == 0 &&
           rule.monthsOfTheYear.count == 0 && rule.weeksOfTheYear.count == 0 &&
           rule.daysOfTheYear.count == 0 && rule.setPositions.count == 0;
}

static NSString *FrequencyText(EKRecurrenceFrequency frequency, NSInteger interval)
{
    switch (frequency) {
        case EKRecurrenceFrequencyDaily:
            return interval == 1
                ? NSLocalizedString(@"Every Day", nil)
                : [NSString stringWithFormat:NSLocalizedString(@"Every %zd Days", nil), interval];
        case EKRecurrenceFrequencyWeekly:
            return interval == 1
                ? NSLocalizedString(@"Every Week", nil)
                : [NSString stringWithFormat:NSLocalizedString(@"Every %zd Weeks", nil), interval];
        case EKRecurrenceFrequencyMonthly:
            return interval == 1
                ? NSLocalizedString(@"Every Month", nil)
                : [NSString stringWithFormat:NSLocalizedString(@"Every %zd Months", nil), interval];
        case EKRecurrenceFrequencyYearly:
            return interval == 1
                ? NSLocalizedString(@"Every Year", nil)
                : [NSString stringWithFormat:NSLocalizedString(@"Every %zd Years", nil), interval];
    }
    return @"✓";
}

// How the event repeats, e.g. "Every Week on Mon, Thu", and on a
// second line when it stops.
static NSString *RepeatText(EKRecurrenceRule *rule)
{
    NSString *text = FrequencyText(rule.frequency, rule.interval);
    if (rule.frequency == EKRecurrenceFrequencyWeekly && rule.daysOfTheWeek.count > 0 && rule.setPositions.count == 0) {
        // The days in the order of the user's week.
        NSCalendar *calendar = NSCalendar.currentCalendar;
        NSInteger first = calendar.firstWeekday;
        NSArray<EKRecurrenceDayOfWeek *> *days = [rule.daysOfTheWeek sortedArrayUsingComparator:^NSComparisonResult(EKRecurrenceDayOfWeek *d1, EKRecurrenceDayOfWeek *d2) {
            NSInteger i1 = (d1.dayOfTheWeek - first + 7) % 7, i2 = (d2.dayOfTheWeek - first + 7) % 7;
            return i1 < i2 ? NSOrderedAscending : i1 > i2 ? NSOrderedDescending : NSOrderedSame;
        }];
        NSMutableArray<NSString *> *names = [NSMutableArray new];
        for (EKRecurrenceDayOfWeek *day in days) {
            NSInteger index = day.dayOfTheWeek - 1;
            if (index >= 0 && index < (NSInteger)calendar.shortWeekdaySymbols.count) {
                [names addObject:calendar.shortWeekdaySymbols[index]];
            }
        }
        if (names.count > 0) {
            text = [NSString stringWithFormat:NSLocalizedString(@"%@ on %@", @"How an event repeats, e.g. Every Week on Mon, Thu"), text, [names componentsJoinedByString:@", "]];
        }
    }
    if (rule.recurrenceEnd.endDate) {
        NSDate *repeatEnd = rule.recurrenceEnd.endDate;
        text = [text stringByAppendingFormat:@"\n%@ %@", NSLocalizedString(@"End Repeat:", nil), DateRangeString(repeatEnd, repeatEnd, YES)];
    }
    else if (rule.recurrenceEnd.occurrenceCount) {
        text = [text stringByAppendingFormat:@"\n%@ ×%zd", NSLocalizedString(@"End Repeat:", nil), rule.recurrenceEnd.occurrenceCount];
    }
    return text;
}

#pragma mark -
#pragma mark Saving

// Make the changes (see kChangeTitle etc.) to event.
static void ApplyChanges(EKEvent *event, NSDictionary<NSString *, id> *changes)
{
    id (^value)(NSString *) = ^id(NSString *key) {
        id v = changes[key];
        return v == NSNull.null ? nil : v;
    };
    if (changes[kChangeTitle]) event.title = value(kChangeTitle);
    if (changes[kChangeLocation]) event.location = value(kChangeLocation);
    if (changes[kChangeNotes]) event.notes = value(kChangeNotes);
    if (changes[kChangeURL]) event.URL = value(kChangeURL);
    if (changes[kChangeCalendar]) event.calendar = value(kChangeCalendar);
    if (changes[kChangeAllDay] || changes[kChangeStart] || changes[kChangeEnd]) {
        BOOL wasAllDay = event.allDay;
        if (changes[kChangeAllDay]) event.allDay = [value(kChangeAllDay) boolValue];
        if (changes[kChangeStart]) event.startDate = value(kChangeStart);
        if (changes[kChangeEnd]) event.endDate = value(kChangeEnd);
        // All-day events have no time zone. Set it after allDay.
        if (event.allDay) event.timeZone = nil;
        else if (wasAllDay) event.timeZone = NSTimeZone.localTimeZone;
    }
    if (changes[kChangeAlarms]) {
        NSMutableArray<EKAlarm *> *alarms = [NSMutableArray new];
        for (id alarm in value(kChangeAlarms)) {
            [alarms addObject:[alarm isKindOfClass:[NSDate class]]
                ? [EKAlarm alarmWithAbsoluteDate:alarm]
                : [EKAlarm alarmWithRelativeOffset:[alarm doubleValue]]];
        }
        event.alarms = alarms;
    }
    if (changes[kChangeRule]) {
        EKRecurrenceRule *rule = value(kChangeRule);
        event.recurrenceRules = rule ? @[rule] : nil;
    }
}

#pragma mark -
#pragma mark AgendaPopoverSeparator

// =========================================================================
// AgendaPopoverSeparator
// =========================================================================

// A line between sections, drawn like the agenda's dividers.
@interface AgendaPopoverSeparator : NSView
@end

@implementation AgendaPopoverSeparator

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(NSViewNoIntrinsicMetric, 1);
}

- (void)drawRect:(NSRect)dirtyRect
{
    [Theme.agendaDividerColor set];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
}

@end

#pragma mark -
#pragma mark AgendaPopoverSection

// =========================================================================
// AgendaPopoverSection
// =========================================================================

// A section of the popover: rows, below a separator unless it's the
// title. -updateHidden hides it, separator and all, when all its rows
// are hidden.
@interface AgendaPopoverSection : NSStackView
- (instancetype)initWithRows:(NSArray<NSView *> *)rows separator:(BOOL)separator;
- (void)updateHidden;
// Set the width of the section's rows. kTextWidth to start.
- (void)setRowWidth:(CGFloat)rowWidth;
@end

@implementation AgendaPopoverSection
{
    NSArray<NSView *> *_rows;
    NSArray<NSLayoutConstraint *> *_rowWidths;
}

- (instancetype)initWithRows:(NSArray<NSView *> *)rows separator:(BOOL)separator
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _rows = rows;
        self.orientation = NSUserInterfaceLayoutOrientationVertical;
        self.alignment = NSLayoutAttributeLeading;
        NSMutableArray<NSView *> *views = [rows mutableCopy];
        if (separator) {
            [views insertObject:[AgendaPopoverSeparator new] atIndex:0];
        }
        NSMutableArray *rowWidths = [NSMutableArray new];
        for (NSView *view in views) {
            [self addArrangedSubview:view];
            NSLayoutConstraint *rowWidth = [view.widthAnchor constraintEqualToConstant:kTextWidth];
            rowWidth.active = YES;
            [rowWidths addObject:rowWidth];
        }
        _rowWidths = rowWidths;
    }
    return self;
}

- (void)updateHidden
{
    self.hidden = !AnyViewShows(_rows);
}

- (void)setRowWidth:(CGFloat)rowWidth
{
    for (NSLayoutConstraint *constraint in _rowWidths) {
        constraint.constant = rowWidth;
    }
}

@end

#pragma mark -
#pragma mark AgendaPopoverTextView

// =========================================================================
// AgendaPopoverTextView
// =========================================================================

// Selectable text with links, as tall as its text. It uses TextKit 1
// from the start. (A plain NSTextView starts with TextKit 2 and
// switches to TextKit 1 the first time its layoutManager is used.)
// If canEdit, clicking it (but not a link in it) edits it as plain
// text until it loses focus.
@interface AgendaPopoverTextView : NSTextView
@property (nonatomic) BOOL canEdit;
// Return finishes editing.
@property (nonatomic) BOOL singleLine;
// Shown while there's no text.
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, copy) void (^beganEditing)(void);
// The text as edited and as it was before. Esc puts it back.
@property (nonatomic, copy) void (^endedEditing)(NSString *text, NSString *before);
@property (nonatomic, copy) void (^textChanged)(void);
// Set the width the text wraps to. kTextWidth to start.
- (void)setWrapWidth:(CGFloat)width;
- (void)setAttributedText:(NSAttributedString *)text;
// Edit it, with the insertion point at index.
- (void)beginEditingAtIndex:(NSUInteger)index;
@end

@implementation AgendaPopoverTextView
{
    NSString *_textBeforeEditing;
}

- (instancetype)init
{
    self = [super initUsingTextLayoutManager:NO];
    if (self) {
        self.editable = NO;
        self.selectable = YES;
        self.drawsBackground = NO;
        self.importsGraphics = NO;
        self.focusRingType = NSFocusRingTypeExterior;
        // Auto Layout sizes the view, from -intrinsicContentSize.
        self.verticallyResizable = NO;
        self.horizontallyResizable = NO;
        self.textContainer.widthTracksTextView = NO;
        self.textContainer.lineFragmentPadding = 0;
        [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        [self setWrapWidth:kTextWidth];
    }
    return self;
}

- (void)setWrapWidth:(CGFloat)width
{
    self.textContainer.size = NSMakeSize(width, CGFLOAT_MAX);
    [self invalidateIntrinsicContentSize];
}

- (void)setAttributedText:(NSAttributedString *)text
{
    [self.textStorage setAttributedString:text];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}

- (NSFont *)plainFont
{
    return [NSFont systemFontOfSize:SizePref.fontSize];
}

- (NSSize)intrinsicContentSize
{
    [self.layoutManager ensureLayoutForTextContainer:self.textContainer];
    CGFloat height = NSHeight([self.layoutManager usedRectForTextContainer:self.textContainer]);
    // At least a line while it's being edited, even with no text.
    if (self.editable || self.string.length == 0) {
        height = MAX(height, [self.layoutManager defaultLineHeightForFont:[self plainFont]]);
    }
    return NSMakeSize(NSViewNoIntrinsicMetric, height);
}

// YES if there's a link at point, in the view's coordinates.
- (BOOL)hasLinkAtPoint:(NSPoint)point
{
    NSLayoutManager *layoutManager = self.layoutManager;
    NSPoint origin = self.textContainerOrigin;
    NSPoint p = NSMakePoint(point.x - origin.x, point.y - origin.y);
    CGFloat fraction;
    NSUInteger glyph = [layoutManager glyphIndexForPoint:p inTextContainer:self.textContainer fractionOfDistanceThroughGlyph:&fraction];
    if (glyph >= layoutManager.numberOfGlyphs) return NO;
    NSRect glyphRect = [layoutManager boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:self.textContainer];
    if (!NSPointInRect(p, glyphRect)) return NO;
    NSUInteger index = [layoutManager characterIndexForGlyphAtIndex:glyph];
    return [self.textStorage attribute:NSLinkAttributeName atIndex:index effectiveRange:NULL] != nil;
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!self.canEdit || self.editable || [self hasLinkAtPoint:point]) {
        [super mouseDown:event];
        return;
    }
    [self beginEditingAtIndex:[self characterIndexForInsertionAtPoint:point]];
}

- (void)beginEditingAtIndex:(NSUInteger)index
{
    if (!self.canEdit || self.editable) return;
    // Edit the text as it shows, as plain text without links.
    _textBeforeEditing = [self.string copy];
    NSDictionary *attributes = @{NSFontAttributeName: [self plainFont],
                                 NSForegroundColorAttributeName: Theme.agendaEventTextColor};
    [self.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:_textBeforeEditing attributes:attributes]];
    self.typingAttributes = attributes;
    self.richText = NO;
    self.editable = YES;
    [self invalidateIntrinsicContentSize];
    if (![self.window makeFirstResponder:self]) {
        self.editable = NO;
        self.richText = YES;
        return;
    }
    self.selectedRange = NSMakeRange(MIN(index, self.string.length), 0);
    [self noteFocusRingMaskChanged];
    [self setNeedsDisplay:YES];
    if (self.beganEditing) self.beganEditing();
}

- (BOOL)resignFirstResponder
{
    BOOL resigned = [super resignFirstResponder];
    if (resigned && self.editable) {
        self.editable = NO;
        self.richText = YES;
        self.selectedRange = NSMakeRange(0, 0);
        [self noteFocusRingMaskChanged];
        [self invalidateIntrinsicContentSize];
        NSString *before = _textBeforeEditing ?: @"";
        _textBeforeEditing = nil;
        if (self.endedEditing) self.endedEditing([self.string copy], before);
    }
    return resigned;
}

// Finish editing, keeping the text.
- (void)finishEditing
{
    [self.window makeFirstResponder:nil];
}

- (void)cancelOperation:(id)sender
{
    if (!self.editable) {
        [super cancelOperation:sender];
        return;
    }
    // Esc puts the text back as it was.
    [self.textStorage replaceCharactersInRange:NSMakeRange(0, self.textStorage.length) withString:_textBeforeEditing ?: @""];
    [self finishEditing];
}

- (void)doCommandBySelector:(SEL)selector
{
    if (self.editable) {
        if ((selector == @selector(insertNewline:) && self.singleLine) ||
            selector == @selector(insertTab:) || selector == @selector(insertBacktab:)) {
            [self finishEditing];
            return;
        }
        if (selector == @selector(cancelOperation:) || selector == @selector(complete:)) {
            [self cancelOperation:nil];
            return;
        }
    }
    [super doCommandBySelector:selector];
}

- (void)didChangeText
{
    [super didChangeText];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
    if (self.textChanged) self.textChanged();
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if (self.string.length == 0 && self.placeholder.length > 0) {
        [self.placeholder drawAtPoint:self.textContainerOrigin withAttributes:@{
            NSFontAttributeName: [self plainFont],
            NSForegroundColorAttributeName: NSColor.placeholderTextColor}];
    }
}

// While it's being edited, a focus ring around the text, a little
// outside it, like the fields' rings.
- (NSRect)focusRingMaskBounds
{
    return self.editable ? NSInsetRect(self.bounds, -3, -1) : NSZeroRect;
}

- (void)drawFocusRingMask
{
    if (!self.editable) return;
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, -3, -1) xRadius:4 yRadius:4] fill];
}

@end

#pragma mark -
#pragma mark AgendaPopoverField

// =========================================================================
// AgendaPopoverField
// =========================================================================

// A text field that looks like a label until it's clicked. Says when
// it starts being edited; its delegate learns when that ends.
@interface AgendaPopoverField : NSTextField
@property (nonatomic, copy) void (^beganEditing)(void);
// As wide as its text, and at least minEditingWidth while it's being
// edited. For the date fields.
@property (nonatomic) BOOL hugsText;
@property (nonatomic) CGFloat minEditingWidth;
@end

@implementation AgendaPopoverField

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.bezeled = NO;
        self.bordered = NO;
        self.drawsBackground = NO;
        self.editable = NO;
        self.selectable = YES;
    }
    return self;
}

- (BOOL)becomeFirstResponder
{
    BOOL became = [super becomeFirstResponder];
    if (became && self.editable) {
        if (self.hugsText) [self invalidateIntrinsicContentSize];
        // The field editor is set up after this returns.
        void (^began)(void) = self.beganEditing;
        if (began) dispatch_async(dispatch_get_main_queue(), began);
    }
    return became;
}

- (NSSize)intrinsicContentSize
{
    NSSize size = [super intrinsicContentSize];
    NSText *editor = self.currentEditor;
    NSString *text = editor ? editor.string : self.stringValue;
    if (self.cell.wraps && self.preferredMaxLayoutWidth > 0) {
        // An editable field is one line tall. Make it as tall as its
        // text, as it's typed, up to maximumNumberOfLines. (The cell's
        // frame is 2 points wider on each side than its alignment rect.)
        NSTextFieldCell *cell = [self.cell copy];
        cell.stringValue = text;
        CGFloat height = [cell cellSizeForBounds:NSMakeRect(0, 0, self.preferredMaxLayoutWidth + 4, CGFLOAT_MAX)].height;
        if (self.maximumNumberOfLines > 0) {
            CGFloat lineHeight = [[NSLayoutManager new] defaultLineHeightForFont:self.font ?: [NSFont systemFontOfSize:0]];
            height = MIN(height, ceil(lineHeight * self.maximumNumberOfLines));
        }
        return NSMakeSize(NSViewNoIntrinsicMetric, ceil(height));
    }
    if (!self.hugsText) return size;
    // The width of its alignment rect, which leaves out the cell's
    // padding: the text's, and room for the insertion point.
    CGFloat width = ceil([text sizeWithAttributes:@{NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:0]}].width);
    if (editor) width = MAX(width + 2, self.minEditingWidth);
    size.width = width;
    return size;
}

- (void)textDidChange:(NSNotification *)notification
{
    // Before the delegate hears of the change and resizes the popover.
    [self invalidateIntrinsicContentSize];
    [super textDidChange:notification];
}

- (void)textDidEndEditing:(NSNotification *)notification
{
    [super textDidEndEditing:notification];
    [self invalidateIntrinsicContentSize];
}

@end

#pragma mark -
#pragma mark AgendaPopoverTimePicker

// =========================================================================
// AgendaPopoverTimePicker
// =========================================================================

// A time of day that looks like text until it's clicked. Return
// finishes changing it and Esc puts it back.
@interface AgendaPopoverTimePicker : NSDatePicker
@property (nonatomic, copy) void (^beganEditing)(void);
@property (nonatomic, copy) void (^endedEditing)(void);
// Esc was pressed. Called before endedEditing.
@property (nonatomic, copy) void (^cancelled)(void);
@end

@implementation AgendaPopoverTimePicker
{
    BOOL _editing;
}

- (instancetype)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.datePickerStyle = NSDatePickerStyleTextField;
        self.datePickerElements = NSDatePickerElementFlagHourMinute;
        self.bezeled = NO;
        self.bordered = NO;
        self.drawsBackground = NO;
        [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    return self;
}

- (BOOL)becomeFirstResponder
{
    BOOL became = [super becomeFirstResponder];
    if (became && !_editing) {
        _editing = YES;
        if (self.beganEditing) self.beganEditing();
    }
    return became;
}

- (BOOL)resignFirstResponder
{
    BOOL resigned = [super resignFirstResponder];
    if (resigned && _editing) {
        _editing = NO;
        if (self.endedEditing) self.endedEditing();
    }
    return resigned;
}

- (void)keyDown:(NSEvent *)event
{
    switch (event.keyCode) {
        case 36: // Return
        case 76: // Enter
            [self.window makeFirstResponder:nil];
            return;
        case 53: // Esc
            if (self.cancelled) self.cancelled();
            [self.window makeFirstResponder:nil];
            return;
    }
    [super keyDown:event];
}

@end

#pragma mark -
#pragma mark AgendaPopoverMenuRow

// =========================================================================
// AgendaPopoverMenuRow
// =========================================================================

// An icon and text, e.g. how the event repeats. If canEdit, clicking
// it shows a menu below it to change it.
@interface AgendaPopoverMenuRow : NSView
@property (nonatomic, readonly) NSImageView *icon;
@property (nonatomic, readonly) NSTextField *label;
@property (nonatomic) BOOL canEdit;
@property (nonatomic, copy) NSMenu *(^menuProvider)(void);
// spacing: between the icon and the text.
- (instancetype)initWithSpacing:(CGFloat)spacing;
- (void)setTextFont:(NSFont *)font iconSize:(CGFloat)iconSize;
@end

@implementation AgendaPopoverMenuRow
{
    NSView *_highlight;
    NSLayoutConstraint *_iconCenter;
}

- (instancetype)initWithSpacing:(CGFloat)spacing
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        // While the menu shows, the row is highlighted, a little
        // beyond its edges.
        _highlight = [NSView new];
        _highlight.translatesAutoresizingMaskIntoConstraints = NO;
        _highlight.wantsLayer = YES;
        _highlight.layer.cornerRadius = 5;
        _highlight.hidden = YES;
        _icon = [NSImageView new];
        _icon.translatesAutoresizingMaskIntoConstraints = NO;
        _icon.accessibilityElement = NO;
        [_icon setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [_icon setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        _label = [NSTextField wrappingLabelWithString:@""];
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        _label.drawsBackground = NO;
        _label.selectable = NO;
        _label.accessibilityElement = NO;
        [_label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self addSubview:_highlight];
        [self addSubview:_icon];
        [self addSubview:_label];
        _iconCenter = [_icon.centerYAnchor constraintEqualToAnchor:_label.topAnchor constant:8];
        [NSLayoutConstraint activateConstraints:@[
            [_highlight.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:-6],
            [_highlight.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:6],
            [_highlight.topAnchor constraintEqualToAnchor:self.topAnchor constant:-2],
            [_highlight.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:2],
            [_icon.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_label.leadingAnchor constraintEqualToAnchor:_icon.trailingAnchor constant:spacing],
            [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_label.topAnchor constraintEqualToAnchor:self.topAnchor],
            [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            _iconCenter,
        ]];
    }
    return self;
}

- (void)setTextFont:(NSFont *)font iconSize:(CGFloat)iconSize
{
    _label.font = font;
    _icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:iconSize weight:NSFontWeightRegular];
    // Center the icon on the first line of text.
    _iconCenter.constant = round((font.ascender - font.descender + font.leading) / 2);
}

- (void)mouseDown:(NSEvent *)event
{
    if (!self.canEdit || !self.menuProvider) {
        [super mouseDown:event];
        return;
    }
    [self showMenu];
}

- (void)showMenu
{
    NSMenu *menu = self.menuProvider();
    if (menu.numberOfItems == 0) return;
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
        self->_highlight.layer.backgroundColor = [NSColor.labelColor colorWithAlphaComponent:0.08].CGColor;
    }];
    _highlight.hidden = NO;
    [self displayIfNeeded];
    // Below the row, lined up with its text.
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(_label.frame) - 14, -4) inView:self];
    _highlight.hidden = YES;
}

- (BOOL)isAccessibilityElement
{
    return YES;
}

- (NSAccessibilityRole)accessibilityRole
{
    return self.canEdit ? NSAccessibilityPopUpButtonRole : NSAccessibilityStaticTextRole;
}

- (NSString *)accessibilityLabel
{
    return _label.stringValue;
}

- (BOOL)accessibilityPerformPress
{
    if (!self.canEdit || !self.menuProvider) return NO;
    [self showMenu];
    return YES;
}

@end

#pragma mark -
#pragma mark AgendaPopoverVC

// =========================================================================
// AgendaPopoverVC
// =========================================================================

@interface AgendaPopoverVC () <NSTextFieldDelegate>
@end

@implementation AgendaPopoverVC
{
    NSStackView *_header; // pinned at the top
    NSStackView *_body;   // scrolls below the header
    NSArray<AgendaPopoverSection *> *_sections;
    AgendaPopoverField *_title;
    NSButton *_btnDelete;
    // When: a label for events that can't be changed and reminders...
    NSTextField *_duration;
    // ...and for events that can, the days and times to click. A
    // timed event on more than one day has its end on a second line.
    NSStackView *_dateRow;
    NSStackView *_dateLine1, *_dateLine2;
    AgendaPopoverField *_startDateField, *_endDateField;
    AgendaPopoverTimePicker *_startTimePicker, *_endTimePicker;
    NSTextField *_dateComma1, *_dateComma2, *_dateDash;
    NSInteger _dateLayout;
    // "+ Add › End Date" shows the end date of an event on one day
    // until it's been changed.
    BOOL _showsEndDate;
    AgendaPopoverMenuRow *_repeatRow;
    NSStackView *_alertRows;
    NSMutableArray<AgendaPopoverMenuRow *> *_alertRowPool;
    AgendaPopoverMenuRow *_addAlertRow; // "+ Add Alert", below the alerts
    NSLayoutConstraint *_addAlertIconWidth;
    AgendaPopoverTextView *_location;
    AgendaPopoverTextView *_note;
    AgendaPopoverTextView *_URL;
    NSStackView *_attendees;
    AgendaPopoverMenuRow *_lockRow; // meetings can't be changed here
    NSStackView *_meetingRow;  // video icon, host and Join button
    NSImageView *_meetingIcon;
    NSTextField *_meetingHost;
    NSURL *_meetingURL;
    AgendaPopoverMenuRow *_calendarRow; // the calendar's dot and name
    AgendaPopoverMenuRow *_addRow;      // "+ Add"
    NSScrollView *_scrollView;
    NSDataDetector *_linkDetector;
    NSRegularExpression *_hiddenLinksRegex;
    NSRegularExpression *_messageLinksRegex;
    NSRegularExpression *_htmlTagRegex;

    EventInfo *_info;
    EKEvent *_event;  // nil for a reminder
    BOOL _editable;   // the details can be changed
    NSMutableDictionary<NSString *, id> *_changes; // see kChangeTitle
    NSView *_editingView; // the part being changed, or nil
    id _clickMonitor;     // see -viewDidAppear
    // Before the title, a date or a time was changed, for Esc.
    NSString *_titleBeforeEditing;
    NSDate *_startBeforeEditing, *_endBeforeEditing;
    BOOL _allDayBeforeEditing;
    // The text of the date field being edited, for the day it's set to.
    NSString *_dateFieldText;
    // The calendar below a date field being edited.
    MoPopover *_calendarPopover;
    NSDatePicker *_calendarPicker;
    NSButton *_allDayCheckbox;
    AgendaPopoverField *_calendarField;
}

- (instancetype)init
{
    // Convenience functions.
    NSTextField* (^label)(void) = ^NSTextField* {
        NSTextField *lbl = [NSTextField wrappingLabelWithString:@""];
        lbl.drawsBackground = NO;
        lbl.textColor = Theme.currentMonthTextColor;
        [lbl setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        return lbl;
    };
    NSTextField* (^token)(NSString *) = ^NSTextField* (NSString *text) {
        NSTextField *lbl = [NSTextField labelWithString:text];
        [lbl setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        return lbl;
    };
    self = [super init];
    if (self) {
        __weak AgendaPopoverVC *weakSelf = self;
        _changes = [NSMutableDictionary new];
        _alertRowPool = [NSMutableArray new];
        _dateLayout = -1;

        // The title wraps, like a wrapping label.
        _title = [AgendaPopoverField wrappingLabelWithString:@""];
        _title.drawsBackground = NO;
        _title.delegate = self;
        _title.beganEditing = ^{ [weakSelf titleBeganEditing]; };
        [_title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        _duration = label();
        // The title is pinned above the scroll view, so a very long one
        // could push everything else out of the popover. Cap it.
        _title.maximumNumberOfLines = 5;
        _title.cell.truncatesLastVisibleLine = YES;

        // The days and times.
        AgendaPopoverField* (^dateField)(void) = ^AgendaPopoverField* {
            AgendaPopoverField *field = [AgendaPopoverField new];
            field.editable = YES;
            field.usesSingleLineMode = YES;
            field.cell.scrollable = YES;
            field.lineBreakMode = NSLineBreakByClipping;
            field.hugsText = YES;
            field.minEditingWidth = 70;
            field.delegate = self;
            [field setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
            return field;
        };
        _startDateField = dateField();
        _endDateField = dateField();
        _startDateField.beganEditing = ^{ [weakSelf dateFieldBeganEditing:YES]; };
        _endDateField.beganEditing = ^{ [weakSelf dateFieldBeganEditing:NO]; };
        _startTimePicker = [AgendaPopoverTimePicker new];
        _endTimePicker = [AgendaPopoverTimePicker new];
        for (AgendaPopoverTimePicker *picker in @[_startTimePicker, _endTimePicker]) {
            BOOL isStart = picker == _startTimePicker;
            picker.target = self;
            picker.action = @selector(timeChanged:);
            __weak AgendaPopoverTimePicker *weakPicker = picker;
            picker.beganEditing = ^{ [weakSelf timePickerBeganEditing:weakPicker]; };
            picker.endedEditing = ^{ [weakSelf timePickerEndedEditing:isStart]; };
            picker.cancelled = ^{ [weakSelf timePickerCancelled]; };
        }
        _dateComma1 = token(@", ");
        _dateComma2 = token(@", ");
        _dateDash = token(@" – ");
        NSStackView* (^dateLine)(void) = ^NSStackView* {
            NSStackView *line = [NSStackView new];
            line.alignment = NSLayoutAttributeFirstBaseline;
            // See -spaceLine:.
            line.spacing = 0;
            return line;
        };
        _dateLine1 = dateLine();
        _dateLine2 = dateLine();
        [_dateLine1 addArrangedSubview:_startDateField];
        _dateRow = [NSStackView stackViewWithViews:@[_dateLine1, _dateLine2]];
        _dateRow.orientation = NSUserInterfaceLayoutOrientationVertical;
        _dateRow.alignment = NSLayoutAttributeLeading;
        _dateRow.spacing = 0;

        // How it repeats, and its alerts.
        _repeatRow = [[AgendaPopoverMenuRow alloc] initWithSpacing:5];
        _repeatRow.icon.image = [NSImage imageWithSystemSymbolName:@"repeat" accessibilityDescription:nil];
        _repeatRow.menuProvider = ^NSMenu *{ return [weakSelf repeatMenuForAdding:NO]; };
        _alertRows = [NSStackView new];
        _alertRows.orientation = NSUserInterfaceLayoutOrientationVertical;
        _alertRows.alignment = NSLayoutAttributeLeading;

        _location = [AgendaPopoverTextView new];
        _note = [AgendaPopoverTextView new];
        _URL = [AgendaPopoverTextView new];
        _location.singleLine = YES;
        _URL.singleLine = YES;
        _location.placeholder = NSLocalizedString(@"Location", @"Placeholder of an event's location in the event popover, while it's empty");
        _note.placeholder = NSLocalizedString(@"Notes", @"Placeholder of an event's notes in the event popover, while they're empty");
        _URL.placeholder = NSLocalizedString(@"URL", @"Placeholder of an event's URL in the event popover, while it's empty");
        for (AgendaPopoverTextView *textView in @[_location, _note, _URL]) {
            __weak AgendaPopoverTextView *weakTextView = textView;
            textView.beganEditing = ^{ [weakSelf beginEditingView:weakTextView]; };
            textView.endedEditing = ^(NSString *text, NSString *before) { [weakSelf textView:weakTextView endedEditing:text before:before]; };
            textView.textChanged = ^{ [weakSelf sizeChanged]; };
        }

        _btnDelete = [NSButton new];
        _btnDelete.image = [NSImage imageWithSystemSymbolName:@"delete.backward" accessibilityDescription:NSLocalizedString(@"Delete This Event", @"")];
        _btnDelete.imagePosition = NSImageOnly;
        _btnDelete.title = @"";
        _btnDelete.focusRingType = NSFocusRingTypeNone;
        _btnDelete.bordered = NO;
        _btnDelete.contentTintColor = NSColor.systemRedColor;
        _btnDelete.hasDestructiveAction = YES;
        _btnDelete.target = self;
        _btnDelete.action = @selector(deleteClicked:);
        _btnDelete.keyEquivalent = BackspaceKeyEquivalent();

        NSView *titleHolder = [NSView new];
        [titleHolder addSubview:_title];
        [titleHolder addSubview:_btnDelete];
        MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:titleHolder metrics:nil views:NSDictionaryOfVariableBindings(_title, _btnDelete)];
        // The title fills the row, so all of it can be clicked.
        [vfl :@"H:|[_title]-10-[_btnDelete]|" :NSLayoutFormatAlignAllCenterY];
        [vfl :@"V:|[_title]|"];

        _attendees = [NSStackView new];
        _attendees.orientation = NSUserInterfaceLayoutOrientationVertical;
        _attendees.alignment = NSLayoutAttributeLeft;
        _attendees.spacing = 4;
        _attendees.detachesHiddenViews = NO;
        [_attendees setClippingResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        // The details of a meeting can only be changed in Calendar,
        // which can tell the invitees.
        _lockRow = [[AgendaPopoverMenuRow alloc] initWithSpacing:5];
        _lockRow.icon.image = [NSImage imageWithSystemSymbolName:@"lock" accessibilityDescription:nil];
        _lockRow.label.stringValue = NSLocalizedString(@"Meetings with invitees can only be changed in Calendar", @"Note below the invitees in the event popover");

        // A video meeting (Zoom, Teams, etc.): an icon, the meeting's
        // host and a button to join it, like Calendar.
        _meetingIcon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"video" accessibilityDescription:nil]];
        _meetingIcon.accessibilityElement = NO;
        _meetingIcon.contentTintColor = Theme.agendaEventTextColor;
        _meetingHost = [NSTextField labelWithString:@""];
        _meetingHost.lineBreakMode = NSLineBreakByTruncatingTail;
        [_meetingHost setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSButton *joinButton = [NSButton buttonWithTitle:NSLocalizedString(@"Join", @"Button in the event popover that joins the event's video meeting (Zoom, Teams, etc.)") target:self action:@selector(joinMeeting:)];
        joinButton.controlSize = NSControlSizeSmall;
        joinButton.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
        // The blue of the agenda's video button when it's enabled.
        joinButton.bezelColor = Theme.todayCellColor;
        _meetingRow = [NSStackView stackViewWithViews:@[_meetingIcon, _meetingHost]];
        [_meetingRow addView:joinButton inGravity:NSStackViewGravityTrailing];
        _meetingRow.alignment = NSLayoutAttributeCenterY;
        _meetingRow.spacing = 7;

        // The calendar (or a reminder's list): its color as a dot and
        // its name, like Calendar.
        _calendarRow = [[AgendaPopoverMenuRow alloc] initWithSpacing:7];
        _calendarRow.menuProvider = ^NSMenu *{ return [weakSelf calendarMenu]; };

        // Adds a part the event doesn't have yet.
        _addRow = [[AgendaPopoverMenuRow alloc] initWithSpacing:4];
        _addRow.icon.image = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil];
        _addRow.label.stringValue = NSLocalizedString(@"Add", @"Last row of the event popover: adds a part the event doesn't have yet, like a location");
        _addRow.canEdit = YES;
        _addRow.menuProvider = ^NSMenu *{ return [weakSelf addMenu]; };

        // Adds an alert, below the alerts. Its text starts where
        // theirs does: its icon is as wide as their bell.
        _addAlertRow = [[AgendaPopoverMenuRow alloc] initWithSpacing:5];
        _addAlertRow.icon.image = [NSImage imageWithSystemSymbolName:@"plus" accessibilityDescription:nil];
        _addAlertRow.label.stringValue = NSLocalizedString(@"Add Alert", @"Row below an event's alerts in the event popover: adds an alert");
        _addAlertRow.canEdit = YES;
        _addAlertRow.menuProvider = ^NSMenu *{ return [weakSelf alertMenuForIndex:-1]; };
        [_addAlertRow.icon setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        _addAlertIconWidth = [_addAlertRow.icon.widthAnchor constraintEqualToConstant:0];
        _addAlertIconWidth.active = YES;

        NSStackView* (^stack)(NSArray<NSView *> *, NSEdgeInsets) = ^NSStackView* (NSArray<NSView *> *views, NSEdgeInsets insets) {
            NSStackView *stack = [NSStackView stackViewWithViews:views];
            stack.orientation = NSUserInterfaceLayoutOrientationVertical;
            stack.alignment = NSLayoutAttributeLeading;
            stack.edgeInsets = insets;
            stack.translatesAutoresizingMaskIntoConstraints = NO;
            return stack;
        };

        // Like Calendar, the title and time stay at the top and
        // the other sections scroll below them.
        _header = stack(@[[[AgendaPopoverSection alloc] initWithRows:@[titleHolder] separator:NO],
                          [[AgendaPopoverSection alloc] initWithRows:@[_dateRow, _duration, _repeatRow, _alertRows, _addAlertRow] separator:YES]],
                        NSEdgeInsetsMake(kInset, kInset, kInset, kInset));
        _body = stack(@[[[AgendaPopoverSection alloc] initWithRows:@[_location] separator:YES],
                        [[AgendaPopoverSection alloc] initWithRows:@[_meetingRow] separator:YES],
                        [[AgendaPopoverSection alloc] initWithRows:@[_attendees, _lockRow] separator:YES],
                        [[AgendaPopoverSection alloc] initWithRows:@[_calendarRow] separator:YES],
                        [[AgendaPopoverSection alloc] initWithRows:@[_note] separator:YES],
                        [[AgendaPopoverSection alloc] initWithRows:@[_URL] separator:YES],
                        [[AgendaPopoverSection alloc] initWithRows:@[_addRow] separator:YES]],
                      NSEdgeInsetsMake(0, kInset, kInset, kInset));
        _sections = [_header.arrangedSubviews arrayByAddingObjectsFromArray:_body.arrangedSubviews];

        _scrollView = [NSScrollView new];
        _scrollView.drawsBackground = NO;
        _scrollView.hasVerticalScroller = YES;
        _scrollView.autohidesScrollers = YES;
        _scrollView.documentView = _body;

        _linkDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL];
        _hiddenLinksRegex = [NSRegularExpression regularExpressionWithPattern:@"<((https?|rdar):\\/\\/[^\\s]+)>" options:NSRegularExpressionCaseInsensitive error:NULL];
        _messageLinksRegex = [NSRegularExpression regularExpressionWithPattern:@"message:%3\\S+" options:NSRegularExpressionCaseInsensitive error:NULL];
        // An opening or closing tag a rich text editor would write,
        // e.g. <br>, <a href="...">, </p>. Not <https://...>.
        _htmlTagRegex = [NSRegularExpression regularExpressionWithPattern:@"</?(a|b|i|u|s|em|strong|br|p|div|span|ul|ol|li|font|h[1-6]|table|thead|tbody|tr|th|td|hr|img|blockquote|pre|code|sup|sub|strike|center|html|html-blob|body)(\\s[^<>]*)?/?>" options:NSRegularExpressionCaseInsensitive error:NULL];
    }
    return self;
}

- (void)dealloc
{
    if (_clickMonitor) [NSEvent removeMonitor:_clickMonitor];
}

- (void)viewDidAppear
{
    [super viewDidAppear];
    // Clicks in the details: see -handleClick:.
    if (_clickMonitor == nil) {
        __weak AgendaPopoverVC *weakSelf = self;
        _clickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
            [weakSelf handleClick:event];
            return event;
        }];
    }
}

- (void)viewDidDisappear
{
    [super viewDidDisappear];
    if (_clickMonitor) {
        [NSEvent removeMonitor:_clickMonitor];
        _clickMonitor = nil;
    }
}

- (void)loadView
{
    NSView *view = [NSView new];
    [view addSubview:_header];
    [view addSubview:_scrollView];
    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:view metrics:nil views:NSDictionaryOfVariableBindings(_header, _scrollView)];
    [vfl :@"H:|[_header]|"];
    [vfl :@"H:|[_scrollView]|"];
    [vfl :@"V:|[_header][_scrollView]|"];

    // The popover has hasFullSizeContent=YES. Use the
    // safeAreaLayoutGuide of a view that paints its background
    // according to the Theme to inset our content. This paints
    // the popover's full background, including the arrow.
    view.translatesAutoresizingMaskIntoConstraints = NO;
    MoThemeView *v = [MoThemeView new];
    [v addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.bottomAnchor],
        [view.leftAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.leftAnchor],
        [view.rightAnchor constraintEqualToAnchor:v.safeAreaLayoutGuide.rightAnchor],
    ]];
    self.view = v;
}

- (NSSize)size
{
    // The header and body (see -loadView), plus the safe area. The
    // body is hidden when none of its sections show.
    CGFloat h = self.view.safeAreaInsets.left + self.view.safeAreaInsets.right;
    CGFloat v = self.view.safeAreaInsets.top + self.view.safeAreaInsets.bottom;
    NSSize header = _header.fittingSize;
    CGFloat bodyHeight = _scrollView.hidden ? 0 : _body.fittingSize.height;
    return NSMakeSize(header.width + h, MIN(header.height + bodyHeight + v, kMaxPopoverHeight));
}

- (void)popoverDidShow
{
    [self makeRoomForScroller];

    NSView *docView = _scrollView.documentView;
    [docView scrollPoint:NSMakePoint(0, NSHeight(docView.bounds))];
    [_scrollView flashScrollers];

    // Prevent _note from eating key presses (like esc and delete).
    [self.view.window makeFirstResponder:_btnDelete];
}

- (void)deleteClicked:(NSButton *)sender
{
    [self endEditing];
    if (self.deleteHandler) self.deleteHandler();
}

- (void)makeRoomForScroller
{
    // When scroll bars always show, the scroller sits beside the body
    // instead of over it, and only when the body has to scroll, that
    // is, when the popover is as tall as it can be. Then, like
    // Calendar, narrow the body's sections to make room, and keep the
    // header full width. (On macOS 27, +scrollerWidthForControlSize:
    // scrollerStyle: is 17 for overlay scrollers too, so check the
    // style.)
    if (_scrollView.hidden || _scrollView.scrollerStyle != NSScrollerStyleLegacy) return;
    [self.view layoutSubtreeIfNeeded];
    if (NSHeight(_body.frame) <= NSHeight(_scrollView.contentView.bounds)) return;
    [self setBodyWidth:kTextWidth - [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy]];
    // The text is taller now. Lay the body out at its new height, so
    // -popoverDidShow scrolls to its real top.
    [self.view layoutSubtreeIfNeeded];
}

// Set the width of the body's rows and the width its text wraps to.
- (void)setBodyWidth:(CGFloat)width
{
    for (AgendaPopoverSection *section in _body.arrangedSubviews) {
        [section setRowWidth:width];
    }
    for (AgendaPopoverTextView *textView in @[_location, _note, _URL]) {
        [textView setWrapWidth:width];
    }
}

// Size the text, icons and spacing to the agenda's text size setting.
- (void)updateSizes
{
    // Space above and below a separator, and between a section's rows.
    CGFloat spacing = SizePref.agendaPopoverSectionSpacing;
    _header.spacing = spacing;
    _body.spacing = spacing;
    for (AgendaPopoverSection *section in _sections) {
        section.spacing = spacing;
    }
    // Rows that go together are closer.
    CGFloat closeSpacing = MAX(2, round(spacing / 2));
    AgendaPopoverSection *whenSection = (AgendaPopoverSection *)_dateRow.superview;
    for (NSView *row in @[_dateRow, _duration, _repeatRow, _alertRows]) {
        [whenSection setCustomSpacing:closeSpacing afterView:row];
    }
    [(AgendaPopoverSection *)_attendees.superview setCustomSpacing:closeSpacing afterView:_attendees];
    _alertRows.spacing = closeSpacing;

    CGFloat fontSize = SizePref.fontSize;
    NSFont *font = [NSFont systemFontOfSize:fontSize];
    _title.font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold];
    _duration.font = font;
    for (NSControl *control in @[_startDateField, _endDateField, _dateComma1, _dateComma2, _dateDash]) {
        control.font = font;
    }
    // Every time is as wide, so the gaps around them don't change.
    _startTimePicker.font = [NSFont monospacedDigitSystemFontOfSize:fontSize weight:NSFontWeightRegular];
    _endTimePicker.font = _startTimePicker.font;
    _meetingHost.font = font;
    for (AgendaPopoverMenuRow *row in [_alertRowPool arrayByAddingObjectsFromArray:@[_repeatRow, _calendarRow]]) {
        [row setTextFont:font iconSize:fontSize - 1];
    }
    [_lockRow setTextFont:[NSFont systemFontOfSize:fontSize - 2] iconSize:fontSize - 3];
    [_addRow setTextFont:[NSFont systemFontOfSize:fontSize - 1] iconSize:fontSize - 4];
    [_addAlertRow setTextFont:[NSFont systemFontOfSize:fontSize - 1] iconSize:fontSize - 4];
    NSImageSymbolConfiguration *bellSize = [NSImageSymbolConfiguration configurationWithPointSize:fontSize - 1 weight:NSFontWeightRegular];
    _addAlertIconWidth.constant = [[NSImage imageWithSystemSymbolName:@"bell" accessibilityDescription:nil] imageWithSymbolConfiguration:bellSize].size.width;
    // The size of the text, and the meeting icon's weight.
    NSImageSymbolConfiguration *iconSize = [NSImageSymbolConfiguration configurationWithPointSize:fontSize weight:NSFontWeightMedium];
    _btnDelete.symbolConfiguration = iconSize;
    _meetingIcon.symbolConfiguration = iconSize;
    // The title wraps at the width it has beside the delete button. An
    // editable field doesn't find that width by itself, as a label does.
    _title.preferredMaxLayoutWidth = kTextWidth - 10 - _btnDelete.intrinsicContentSize.width;
}

#pragma mark -
#pragma mark Showing an event

- (void)populateWithEventInfo:(EventInfo *)info
{
    // Save changes to the event shown before, e.g. when hovering
    // shows another.
    [self saveChanges];

    _info = info;
    _event = info.event;
    // Meetings with invitees can only be changed in Calendar, which
    // can tell the invitees. Invitations can still be deleted.
    _editable = _event != nil && _event.calendar.allowsContentModifications && !_event.hasAttendees;
    [_changes removeAllObjects];
    _showsEndDate = NO;

    [self updateSizes];

    // Attendees
    if (info.event.hasAttendees) {

        // Block returns YES if participant is the event's organizer.
        BOOL (^ParticipantIsOrganizer)(EKParticipant*, EKParticipant*) = ^BOOL(EKParticipant *participant, EKParticipant *organizer) {
            // https://stackoverflow.com/a/17222036/111418
            return [participant.URL.resourceSpecifier isEqualToString:organizer.URL.resourceSpecifier];
        };

        // Sometimes info.event.organizer isn't in info.event.attendees.
        // Make an array of participants that definitely has the organizer.
        NSMutableArray<EKParticipant *> *participants = [NSMutableArray new];
        if (info.event.organizer) {
            [participants addObject:info.event.organizer];
        }
        for (EKParticipant *p in info.event.attendees) {
            // Don't double-add the organizer.
            if (!ParticipantIsOrganizer(p, info.event.organizer)) {
                [participants addObject:p];
            }
        }
        // Sort participants with organizer first, then accepted, pending,
        // and the rest (like declined). The sort is stable, so participants
        // with the same rank stay in the event's order.
        NSInteger (^Rank)(EKParticipant *) = ^NSInteger(EKParticipant *participant) {
            if (ParticipantIsOrganizer(participant, info.event.organizer)) return 0;
            if (participant.participantStatus == EKParticipantStatusAccepted) return 1;
            if (participant.participantStatus == EKParticipantStatusPending) return 2;
            return 3;
        };
        NSArray<EKParticipant *> *sortedParticipants = [participants sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(EKParticipant *p1, EKParticipant *p2) {
            NSInteger rank1 = Rank(p1), rank2 = Rank(p2);
            return rank1 < rank2 ? NSOrderedAscending : rank1 > rank2 ? NSOrderedDescending : NSOrderedSame;
        }];
        // Too many to show? Leave room for the line saying how many more,
        // which is then at least 2, never "1 more".
        NSArray<EKParticipant *> *shownParticipants = sortedParticipants;
        if (sortedParticipants.count > kMaxAttendeeLines) {
            shownParticipants = [sortedParticipants subarrayWithRange:NSMakeRange(0, kMaxAttendeeLines - 1)];
        }
        NSMutableArray<NSView *> *attendeesArray = [NSMutableArray new];
        for (EKParticipant *participant in shownParticipants) {
            NSString *orgIcon = ParticipantIsOrganizer(participant, info.event.organizer) ? @"•" : @"";
            NSString *statusIcon = @"􀁜"; // questionmark.circle (Requires SF fonts to see)
            NSColor *textColor = Theme.agendaEventDateTextColor;
            if (participant.participantStatus == EKParticipantStatusAccepted) {
                statusIcon = @"􀁢"; // checkmark.circle (Requires SF fonts to see)
                textColor = NSColor.systemGreenColor;
            }
            if (participant.participantStatus == EKParticipantStatusDeclined) {
                statusIcon = @"􀁐"; // x.circle (Requires SF fonts to see)
                textColor = NSColor.systemRedColor;
            }

            // Status icons are in the embedded font Mow.otf, CANNOT compress.
            NSTextField *statusLabel = [NSTextField labelWithString:statusIcon];
            statusLabel.textColor = textColor;
            statusLabel.font = [NSFont fontWithName:@"Mow" size:SizePref.fontSize];
            [statusLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

            // EKParticipant name and URL.resourceSpecifier (email addr)
            // are nullable (why?...). Make sure we don't try to create
            // a label with a null string.
            NSString *participantString = participant.name;
            if (!participantString) {
                participantString = participant.URL.resourceSpecifier; // email addr
                if (!participantString) participantString = @"***";
            }

            // Participant uses system font, CAN compress.
            NSTextField *participantLabel = [NSTextField labelWithString:participantString];
            participantLabel.selectable = YES;
            participantLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            participantLabel.textColor = Theme.agendaEventTextColor;
            participantLabel.font = [NSFont systemFontOfSize:SizePref.fontSize];
            [participantLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

            // Organizer icon uses system font, CANNOT compress.
            NSTextField *organizerLabel = [NSTextField labelWithString:orgIcon];
            organizerLabel.textColor = Theme.agendaEventTextColor;
            organizerLabel.font = [NSFont systemFontOfSize:SizePref.fontSize];
            [organizerLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

            // Horizontally stack status icon, participant, organizer indicator.
            NSStackView *attendee = [NSStackView stackViewWithViews:@[statusLabel, participantLabel, organizerLabel]];
            attendee.alignment = NSLayoutAttributeBaseline;
            attendee.detachesHiddenViews = NO;
            [attendee setHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
            [attendee setClippingResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
            [attendeesArray addObject:attendee];
        }
        // Say how many attendees aren't shown.
        if (shownParticipants.count < sortedParticipants.count) {
            NSString *count = [NSNumberFormatter localizedStringFromNumber:@(sortedParticipants.count - shownParticipants.count) numberStyle:NSNumberFormatterDecimalStyle];
            NSTextField *moreLabel = [NSTextField labelWithString:[NSString stringWithFormat:NSLocalizedString(@"%@ more", @"Last line of a long list of invitees in the event popover: the number of invitees not shown, e.g. 1,650 more"), count]];
            moreLabel.textColor = Theme.agendaEventDateTextColor;
            moreLabel.font = [NSFont systemFontOfSize:SizePref.fontSize];
            [attendeesArray addObject:moreLabel];
        }
        // Vertically stack attendees.
        [_attendees setViews:attendeesArray inGravity:NSStackViewGravityBottom];
    }

    // Only events have meetings. Show the host, like teams.microsoft.com.
    _meetingURL = info.meetingURL;
    NSString *host = _meetingURL.host.lowercaseString;
    if ([host hasPrefix:@"www."]) host = [host substringFromIndex:4];
    _meetingHost.stringValue = host ?: _meetingURL.absoluteString ?: @"";
    _meetingHost.textColor = Theme.agendaEventTextColor;

    // Full width, unless the body turns out to need room for a
    // scroller. See -makeRoomForScroller.
    [self setBodyWidth:kTextWidth];

    [self render];
}

// Show the event as it is with the changes made so far, except the
// part being changed, which shows what's typed.
- (void)render
{
    EKCalendarItem *item = _info.item;
    NSColor *textColor = Theme.agendaEventTextColor;
    NSColor *iconColor = NSColor.secondaryLabelColor;

    // Title
    _title.editable = _editable;
    _title.selectable = YES;
    if (_editingView != _title) _title.stringValue = [self currentTitle] ?: @"";
    _title.textColor = textColor;

    // When
    BOOL allDay = [self currentAllDay];
    NSDate *start = [self currentStart];
    NSDate *end = [self currentEnd];
    _dateRow.hidden = !_editable;
    _duration.hidden = _editable;
    if (_editable) {
        [self renderDateRowFrom:start to:end allDay:allDay];
    }
    else {
        _duration.stringValue = start && end ? DurationText(start, end, allDay) : @"";
    }
    _duration.textColor = textColor;

    // How it repeats
    EKRecurrenceRule *rule = [self currentRule];
    _repeatRow.hidden = rule == nil;
    _repeatRow.label.stringValue = rule ? RepeatText(rule) : @"";
    _repeatRow.canEdit = _editable;

    // Alerts, a row each. Only events' alerts show.
    NSArray *alarms = _event ? [self currentAlarms] : @[];
    while (_alertRowPool.count < alarms.count) {
        [self addAlertRow];
    }
    for (NSUInteger i = 0; i < _alertRowPool.count; i++) {
        AgendaPopoverMenuRow *row = _alertRowPool[i];
        row.hidden = i >= alarms.count;
        row.label.stringValue = i < alarms.count ? AlertTitle(alarms[i], allDay) : @"";
        row.canEdit = _editable;
    }
    _alertRows.hidden = alarms.count == 0;
    _addAlertRow.hidden = !(_editable && [self alertMenuForIndex:-1].numberOfItems > 0);

    // Location, notes and URL
    NSString *location = [self currentLocation];
    [self renderTextView:_location text:location ? [self textWithString:location isHTML:NO] : nil];
    [self renderTextView:_note text:[self currentNotesText]];
    NSURL *URL = [self currentURL];
    [self renderTextView:_URL text:URL ? [self textWithString:URL.absoluteString isHTML:NO] : nil];

    // Calendar
    EKCalendar *calendar = [self currentCalendar];
    _calendarRow.hidden = calendar == nil;
    _calendarRow.icon.image = CalendarDotImage(calendar.color);
    _calendarRow.label.stringValue = calendar.title ?: @"";
    _calendarRow.canEdit = _editable;

    // Meetings, invitations, and what they can't do here.
    _meetingRow.hidden = _info.meetingURL == nil;
    _attendees.hidden = !_event.hasAttendees;
    _lockRow.hidden = !(_event.hasAttendees && _event.calendar.allowsContentModifications);
    _addRow.hidden = !_editable;

    for (AgendaPopoverMenuRow *row in [_alertRowPool arrayByAddingObjectsFromArray:@[_repeatRow, _calendarRow]]) {
        row.label.textColor = textColor;
        row.icon.contentTintColor = iconColor;
    }
    _lockRow.label.textColor = NSColor.secondaryLabelColor;
    _lockRow.icon.contentTintColor = NSColor.secondaryLabelColor;
    for (AgendaPopoverMenuRow *row in @[_addRow, _addAlertRow]) {
        row.label.textColor = NSColor.tertiaryLabelColor;
        row.icon.contentTintColor = NSColor.tertiaryLabelColor;
    }

    // Hide delete button IF event doesn't allow modification.
    _btnDelete.hidden = !item || !_event.calendar.allowsContentModifications;

    [self updateSectionsHidden];
}

// Hide the sections with no rows showing, and the body if none of its
// sections show.
- (void)updateSectionsHidden
{
    for (AgendaPopoverSection *section in _sections) {
        [section updateHidden];
    }
    _scrollView.hidden = !AnyViewShows(_body.arrangedSubviews);
    // Below the header: the space above the body's first separator, or
    // the popover's edge if there's no body.
    _header.edgeInsets = NSEdgeInsetsMake(kInset, kInset, _scrollView.hidden ? kInset : SizePref.agendaPopoverSectionSpacing, kInset);
}

- (void)renderTextView:(AgendaPopoverTextView *)textView text:(NSAttributedString *)text
{
    textView.canEdit = _editable;
    if (_editingView == textView) return;
    textView.hidden = text == nil;
    [textView setAttributedText:text ?: [NSAttributedString new]];
}

// The days and times, each of which can be clicked. Their order
// depends on whether the event is all-day and on more than one day.
- (void)renderDateRowFrom:(NSDate *)start to:(NSDate *)end allDay:(BOOL)allDay
{
    BOOL oneDay = [NSCalendar.currentCalendar isDate:start inSameDayAsDate:end] && !_showsEndDate;
    NSInteger layout = allDay ? (oneDay ? 2 : 3) : (oneDay ? 0 : 1);
    if (layout != _dateLayout) {
        _dateLayout = layout;
        NSArray *line1 = nil, *line2 = @[];
        switch (layout) {
            case 0: // 6 Nov 2026, 12:30 – 13:30
                line1 = @[_startDateField, _dateComma1, _startTimePicker, _dateDash, _endTimePicker];
                break;
            case 1: // 6 Nov 2026, 23:00 –
                    // 7 Nov 2026, 01:00
                line1 = @[_startDateField, _dateComma1, _startTimePicker, _dateDash];
                line2 = @[_endDateField, _dateComma2, _endTimePicker];
                break;
            case 2: // 6 Nov 2026
                line1 = @[_startDateField];
                break;
            default: // 6 Nov 2026 – 8 Nov 2026
                line1 = @[_startDateField, _dateDash, _endDateField];
                break;
        }
        _dateDash.stringValue = layout == 1 ? @" –" : @" – ";
        [self arrangeViews:line1 inLine:_dateLine1];
        [self arrangeViews:line2 inLine:_dateLine2];
        [self spaceLine:_dateLine1];
        [self spaceLine:_dateLine2];
        _dateLine2.hidden = line2.count == 0;
    }
    if (_editingView != _startDateField) _startDateField.stringValue = DayString(start);
    if (_editingView != _endDateField) _endDateField.stringValue = DayString(end);
    if (_editingView != _startTimePicker) _startTimePicker.dateValue = start;
    if (_editingView != _endTimePicker) _endTimePicker.dateValue = end;
    for (NSControl *control in @[_startDateField, _endDateField, _startTimePicker, _endTimePicker, _dateComma1, _dateComma2, _dateDash]) {
        if ([control isKindOfClass:[NSDatePicker class]]) {
            ((NSDatePicker *)control).textColor = Theme.agendaEventTextColor;
        }
        else {
            ((NSTextField *)control).textColor = Theme.agendaEventTextColor;
        }
        [control invalidateIntrinsicContentSize];
    }
}

// Space a line of the date row like text: the labels' and fields'
// alignment rects are as wide as their text, and a time picker's text
// is inset from its edges.
- (void)spaceLine:(NSStackView *)line
{
    NSArray<NSView *> *views = line.arrangedSubviews;
    for (NSUInteger i = 0; i + 1 < views.count; i++) {
        CGFloat spacing = 0;
        // A date field's width is its text's, rounded up.
        if ([views[i] isKindOfClass:[AgendaPopoverField class]]) spacing -= 1;
        if ([views[i] isKindOfClass:[NSDatePicker class]]) spacing -= kTimePickerTrailingInset;
        if ([views[i + 1] isKindOfClass:[NSDatePicker class]]) spacing -= kTimePickerLeadingInset;
        [line setCustomSpacing:spacing afterView:views[i]];
    }
}

// Make views line's views, moving only the views that have to move, so
// a view being edited stays where it is.
- (void)arrangeViews:(NSArray<NSView *> *)views inLine:(NSStackView *)line
{
    for (NSView *view in [line.arrangedSubviews copy]) {
        if (![views containsObject:view]) {
            [line removeArrangedSubview:view];
            [view removeFromSuperview];
        }
    }
    [views enumerateObjectsUsingBlock:^(NSView *view, NSUInteger i, BOOL *stop) {
        NSArray<NSView *> *arranged = line.arrangedSubviews;
        if (i < arranged.count && arranged[i] == view) return;
        if ([view.superview isKindOfClass:[NSStackView class]]) {
            [(NSStackView *)view.superview removeArrangedSubview:view];
            [view removeFromSuperview];
        }
        [line insertArrangedSubview:view atIndex:i];
    }];
}

- (void)addAlertRow
{
    __weak AgendaPopoverVC *weakSelf = self;
    NSInteger index = _alertRowPool.count;
    AgendaPopoverMenuRow *row = [[AgendaPopoverMenuRow alloc] initWithSpacing:5];
    row.icon.image = [NSImage imageWithSystemSymbolName:@"bell" accessibilityDescription:nil];
    row.menuProvider = ^NSMenu *{ return [weakSelf alertMenuForIndex:index]; };
    [row setTextFont:[NSFont systemFontOfSize:SizePref.fontSize] iconSize:SizePref.fontSize - 1];
    [_alertRows addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:_alertRows.widthAnchor].active = YES;
    [_alertRowPool addObject:row];
}

- (void)joinMeeting:(id)sender
{
    // Open the meeting in its app if it's installed, like the
    // agenda's video button.
    if (_meetingURL) [NSWorkspace.sharedWorkspace openURL:AppLinkForMeetingURL(_meetingURL)];
}

#pragma mark -
#pragma mark The event with the changes made so far

// The value staged for key, or value if there's none.
- (id)current:(NSString *)key or:(id)value
{
    id staged = _changes[key];
    if (staged == nil) return value;
    return staged == NSNull.null ? nil : staged;
}

- (NSString *)currentTitle { return [self current:kChangeTitle or:_info.item.title]; }
- (NSDate *)currentStart { return [self current:kChangeStart or:_info.startDate]; }
- (NSDate *)currentEnd { return [self current:kChangeEnd or:_info.endDate]; }
- (BOOL)currentAllDay { return [[self current:kChangeAllDay or:@(_info.isRealAllDay)] boolValue]; }
- (NSString *)currentLocation { return Trimmed([self current:kChangeLocation or:_info.item.location]); }
- (NSURL *)currentURL { return [self current:kChangeURL or:_info.item.URL]; }
- (EKRecurrenceRule *)currentRule { return [self current:kChangeRule or:_info.item.recurrenceRules.firstObject]; }
- (EKCalendar *)currentCalendar { return [self current:kChangeCalendar or:_info.item.calendar]; }
- (NSArray *)currentAlarms { return [self current:kChangeAlarms or:AlarmValues(_event.alarms)] ?: @[]; }

- (NSAttributedString *)currentNotesText
{
    id staged = _changes[kChangeNotes];
    if (staged == nil) return [self notesTextOfItem:_info.item];
    return staged == NSNull.null ? nil : [self textWithString:staged isHTML:NO];
}

// Keep value as the change to the part key, or no change if it's the
// event's value.
- (void)stage:(NSString *)key value:(id)value original:(id)original
{
    if (value == original || [value isEqual:original]) {
        [_changes removeObjectForKey:key];
    }
    else {
        _changes[key] = value ?: NSNull.null;
    }
}

- (void)stageStart:(NSDate *)start end:(NSDate *)end allDay:(BOOL)allDay
{
    [self stage:kChangeStart value:start original:_event.startDate];
    [self stage:kChangeEnd value:end original:_event.endDate];
    [self stage:kChangeAllDay value:@(allDay) original:@(_event.allDay)];
}

- (BOOL)isEditing
{
    return _editingView != nil || _changes.count > 0;
}

#pragma mark -
#pragma mark Editing

// view started being changed.
- (void)beginEditingView:(NSView *)view
{
    if (view == nil) return;
    _editingView = view;
    // Backspace is for the text now, not for deleting the event.
    _btnDelete.keyEquivalent = @"";
}

// view stopped being changed.
- (void)endEditingView:(NSView *)view
{
    if (_editingView != view) return;
    _editingView = nil;
    _btnDelete.keyEquivalent = BackspaceKeyEquivalent();
    // Back to the delete button, as when the popover shows, unless
    // another part is being changed now.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSWindow *window = self.view.window;
        if (window && window.firstResponder == window && self->_editingView == nil) {
            [window makeFirstResponder:self->_btnDelete];
        }
    });
}

// Finish changing the part being changed, keeping what's typed.
- (void)endEditing
{
    NSWindow *window = self.view.window;
    if (window == nil || _editingView == nil) return;
    [window makeFirstResponder:_btnDelete];
}

// A click in the details, before the window handles it.
- (void)handleClick:(NSEvent *)event
{
    NSWindow *window = self.view.window;
    if (window == nil || event.window != window) return;
    NSView *contentView = window.contentView;
    NSPoint point = contentView.superview ? [contentView.superview convertPoint:event.locationInWindow fromView:nil] : event.locationInWindow;
    NSView *hit = [contentView hitTest:point];
    // A click anywhere else finishes changing a part.
    if (_editingView && !(hit && [hit isDescendantOf:_editingView])) {
        [self endEditing];
    }
    // A click on a date shows the calendar, before the window starts
    // the date's editing. See -showCalendarForField:.
    for (AgendaPopoverField *field in @[_startDateField, _endDateField]) {
        if (hit == field && field.editable && field.currentEditor == nil) {
            [self showCalendarForField:field];
        }
    }
}

- (void)sizeChanged
{
    if (self.sizeChangedHandler) self.sizeChangedHandler();
}

- (void)renderAndResize
{
    [self render];
    [self sizeChanged];
}

#pragma mark Title and dates (text fields)

- (void)titleBeganEditing
{
    if (_title.currentEditor == nil) return;
    _titleBeforeEditing = _title.stringValue;
    [self beginEditingView:_title];
}

- (void)titleEndedEditing
{
    [self endEditingView:_title];
    // An empty title isn't kept.
    NSString *title = Trimmed(_title.stringValue);
    if (title) [self stage:kChangeTitle value:title original:_event.title];
    [self renderAndResize];
}

- (void)dateFieldBeganEditing:(BOOL)isStart
{
    AgendaPopoverField *field = isStart ? _startDateField : _endDateField;
    if (field.currentEditor == nil) return;
    [self beginEditingView:field];
    _dateFieldText = field.stringValue;
    _startBeforeEditing = [self currentStart];
    _endBeforeEditing = [self currentEnd];
    _allDayBeforeEditing = [self currentAllDay];
    // Typing replaces the day.
    [field.currentEditor selectAll:nil];
}

- (void)dateFieldEndedEditing:(AgendaPopoverField *)field
{
    BOOL isStart = field == _startDateField;
    [self closeCalendar];
    [self endEditingView:field];
    NSString *text = field.stringValue;
    if (![text isEqualToString:_dateFieldText]) {
        NSDate *day = nil;
        if (!isStart && Trimmed(text) == nil) {
            // Without an end date, it ends on the day it starts.
            day = [self currentStart];
        }
        else {
            // Without a year, the date nearest the event's.
            NSDate *near = isStart ? [self currentStart] : [self currentEnd];
            day = [NLEventParser dateFromTypedString:text near:near calendar:NSCalendar.currentCalendar];
        }
        if (day == nil || ![self setDay:day isStart:isStart]) NSBeep();
    }
    // An end date that was added goes again if it's the start's day.
    if (!isStart) _showsEndDate = NO;
    [self renderAndResize];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    id field = notification.object;
    if (field == _title) {
        [self titleEndedEditing];
    }
    else if (field == _startDateField || field == _endDateField) {
        [self dateFieldEndedEditing:field];
    }
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    AgendaPopoverField *field = notification.object;
    if (field == _title) {
        // A longer title can take another line.
        [self sizeChanged];
        return;
    }
    if (field != _startDateField && field != _endDateField) return;
    // The calendar follows the typing.
    NSString *text = field.currentEditor.string ?: field.stringValue;
    NSDate *near = field == _startDateField ? [self currentStart] : [self currentEnd];
    NSDate *day = [NLEventParser dateFromTypedString:text near:near calendar:NSCalendar.currentCalendar];
    if (day && _calendarField == field) _calendarPicker.dateValue = day;
    [self sizeChanged];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)selector
{
    if (selector == @selector(insertNewline:) || selector == @selector(insertTab:) || selector == @selector(insertBacktab:)) {
        [self endEditing];
        return YES;
    }
    if (selector == @selector(cancelOperation:)) {
        // Esc puts it back as it was.
        if (control == _title) {
            textView.string = _titleBeforeEditing ?: @"";
        }
        else {
            [self stageStart:_startBeforeEditing end:_endBeforeEditing allDay:_allDayBeforeEditing];
            _dateFieldText = DayString(control == _startDateField ? _startBeforeEditing : _endBeforeEditing);
            textView.string = _dateFieldText;
        }
        [self endEditing];
        return YES;
    }
    return NO;
}

// Move the event to day, keeping its times and length, or end it on
// day. NO if it would end before it starts.
- (BOOL)setDay:(NSDate *)day isStart:(BOOL)isStart
{
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *start = [self currentStart];
    NSDate *end = [self currentEnd];
    BOOL allDay = [self currentAllDay];
    if (isStart) {
        NSInteger days = [calendar components:NSCalendarUnitDay fromDate:[calendar startOfDayForDate:start] toDate:[calendar startOfDayForDate:day] options:0].day;
        if (days == 0) return YES;
        start = [calendar dateByAddingUnit:NSCalendarUnitDay value:days toDate:start options:0];
        end = [calendar dateByAddingUnit:NSCalendarUnitDay value:days toDate:end options:0];
    }
    else {
        NSDate *newEnd = allDay ? EndOfDay(calendar, day) : DayAtTimeOf(calendar, day, end);
        if ([newEnd compare:start] == NSOrderedAscending) return NO;
        end = newEnd;
    }
    [self stageStart:start end:end allDay:allDay];
    return YES;
}

// Make the event all-day, on the days it's on, or timed: at the times
// it had if it had them, otherwise 9:00, for an hour if it's on one
// day.
- (void)setAllDay:(BOOL)allDay
{
    if (allDay == [self currentAllDay]) return;
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDate *start = [self currentStart];
    NSDate *end = [self currentEnd];
    if (allDay) {
        // A timed event that ends at midnight ends the day before.
        NSDate *last = [end compare:start] == NSOrderedDescending ? [end dateByAddingTimeInterval:-1] : start;
        [self stageStart:[calendar startOfDayForDate:start] end:EndOfDay(calendar, last) allDay:YES];
        return;
    }
    NSDate *timedStart, *timedEnd;
    if (!_event.allDay) {
        timedStart = DayAtTimeOf(calendar, start, _event.startDate);
        timedEnd = [timedStart dateByAddingTimeInterval:[_event.endDate timeIntervalSinceDate:_event.startDate]];
    }
    else {
        timedStart = [calendar dateBySettingHour:9 minute:0 second:0 ofDate:start options:0] ?: start;
        timedEnd = [calendar isDate:start inSameDayAsDate:end]
            ? [timedStart dateByAddingTimeInterval:3600]
            : ([calendar dateBySettingHour:10 minute:0 second:0 ofDate:end options:0] ?: end);
    }
    [self stageStart:timedStart end:timedEnd allDay:NO];
}

#pragma mark Calendar below a date

// Show the calendar below field, before field is edited (see
// -handleClick:): when a
// popover's window first shows with nothing in it that can have
// focus, AppKit takes focus away from the part of its parent window
// that has it, which would end the typing in the field.
- (void)showCalendarForField:(AgendaPopoverField *)field
{
    if (_calendarPopover == nil) {
        _calendarPicker = [NSDatePicker new];
        _calendarPicker.datePickerStyle = NSDatePickerStyleClockAndCalendar;
        _calendarPicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
        _calendarPicker.bezeled = NO;
        _calendarPicker.bordered = NO;
        _calendarPicker.drawsBackground = NO;
        // Typing stays in the date field.
        _calendarPicker.refusesFirstResponder = YES;
        _calendarPicker.target = self;
        _calendarPicker.action = @selector(dayPicked:);
        _allDayCheckbox = [NSButton checkboxWithTitle:NSLocalizedString(@"All-day", @"Checkbox below the calendar in the event popover") target:self action:@selector(allDayClicked:)];
        _allDayCheckbox.refusesFirstResponder = YES;
        NSStackView *stack = [NSStackView stackViewWithViews:@[_calendarPicker, _allDayCheckbox]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 8;
        stack.edgeInsets = NSEdgeInsetsMake(10, 10, 10, 10);
        NSViewController *vc = [NSViewController new];
        vc.view = stack;
        _calendarPopover = [MoPopover new];
        _calendarPopover.contentViewController = vc;
        _calendarPopover.behavior = NSPopoverBehaviorApplicationDefined;
        _calendarPopover.animates = NO;
    }
    _calendarField = field;
    BOOL isStart = field == _startDateField;
    _calendarPicker.dateValue = isStart ? [self currentStart] : [self currentEnd];
    // All-day is for the whole event, so only below its start.
    _allDayCheckbox.hidden = !isStart;
    _allDayCheckbox.state = [self currentAllDay] ? NSControlStateValueOn : NSControlStateValueOff;
    _calendarPopover.contentSize = _calendarPopover.contentViewController.view.fittingSize;
    [_calendarPopover showRelativeToRect:field.bounds ofView:field preferredEdge:field.isFlipped ? NSRectEdgeMaxY : NSRectEdgeMinY];
    // Typing goes on in the date field.
    [self.view.window makeKeyWindow];
}

- (void)closeCalendar
{
    _calendarField = nil;
    if (_calendarPopover.isShown) [_calendarPopover close];
}

- (void)dayPicked:(NSDatePicker *)picker
{
    AgendaPopoverField *field = _calendarField;
    if (field == nil || _editingView != field) return;
    BOOL isStart = field == _startDateField;
    NSDate *before = isStart ? [self currentStart] : [self currentEnd];
    NSDate *picked = picker.dateValue;
    if (![self setDay:picked isStart:isStart]) {
        NSBeep();
        picker.dateValue = before;
        return;
    }
    // Show the day in the field, as if it was typed.
    _dateFieldText = DayString(isStart ? [self currentStart] : [self currentEnd]);
    field.currentEditor.string = _dateFieldText;
    [field.currentEditor selectAll:nil];
    [field invalidateIntrinsicContentSize];
    [self renderAndResize];
    // The arrows at the top go to the same day of the next or previous
    // month. Leave the calendar open for those, and close it when a
    // day is clicked.
    NSCalendar *calendar = NSCalendar.currentCalendar;
    NSDateComponents *b = [calendar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:before];
    NSDateComponents *p = [calendar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:picked];
    BOOL steppedMonth = b.day == p.day && b.month != p.month;
    if (steppedMonth) {
        [self.view.window makeKeyWindow];
    }
    else {
        [self endEditing];
        [self.view.window makeKeyWindow];
    }
}

- (void)allDayClicked:(NSButton *)checkbox
{
    [self setAllDay:checkbox.state == NSControlStateValueOn];
    _dateFieldText = DayString([self currentStart]);
    if (_editingView == _startDateField) {
        _startDateField.currentEditor.string = _dateFieldText;
        [_startDateField.currentEditor selectAll:nil];
    }
    _calendarPicker.dateValue = [self currentStart];
    [self renderAndResize];
    [self.view.window makeKeyWindow];
}

#pragma mark Times

- (void)timePickerBeganEditing:(AgendaPopoverTimePicker *)picker
{
    if (picker == nil) return;
    [self beginEditingView:picker];
    _startBeforeEditing = [self currentStart];
    _endBeforeEditing = [self currentEnd];
    _allDayBeforeEditing = NO;
}

// The start keeps the event's length; the end changes its length.
- (void)timeChanged:(AgendaPopoverTimePicker *)picker
{
    NSDate *start = [self currentStart];
    NSDate *end = [self currentEnd];
    if (picker == _startTimePicker) {
        NSTimeInterval duration = [end timeIntervalSinceDate:start];
        start = picker.dateValue;
        end = [start dateByAddingTimeInterval:duration];
    }
    else {
        end = picker.dateValue;
    }
    [self stageStart:start end:end allDay:NO];
    [self renderAndResize];
}

- (void)timePickerCancelled
{
    if (_startBeforeEditing == nil || _endBeforeEditing == nil) return;
    [self stageStart:_startBeforeEditing end:_endBeforeEditing allDay:NO];
    _startTimePicker.dateValue = _startBeforeEditing;
    _endTimePicker.dateValue = _endBeforeEditing;
}

- (void)timePickerEndedEditing:(BOOL)isStart
{
    [self endEditingView:isStart ? _startTimePicker : _endTimePicker];
    // An end before the start is on the next day, e.g. 23:00 – 01:00.
    NSDate *start = [self currentStart];
    NSDate *end = [self currentEnd];
    if (!isStart && [end compare:start] == NSOrderedAscending) {
        end = [NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:end options:0];
        [self stageStart:start end:end allDay:NO];
    }
    [self renderAndResize];
}

#pragma mark Location, notes and URL

- (void)textView:(AgendaPopoverTextView *)textView endedEditing:(NSString *)text before:(NSString *)before
{
    if (textView == nil) return;
    [self endEditingView:textView];
    if (![text isEqualToString:before]) {
        if (textView == _location) {
            [self stage:kChangeLocation value:Trimmed(text) original:Trimmed(_event.location)];
        }
        else if (textView == _note) {
            // Notes with HTML are saved as the plain text shown.
            [self stage:kChangeNotes value:Trimmed(text) original:_event.notes];
        }
        else if (textView == _URL) {
            NSString *string = Trimmed(text);
            NSURL *URL = nil;
            if (string) {
                URL = [NSURL URLWithString:string];
                // example.com is https://example.com.
                if (URL.scheme == nil) URL = [NSURL URLWithString:[@"https://" stringByAppendingString:string]];
            }
            if (string && URL == nil) {
                NSBeep();
            }
            else {
                [self stage:kChangeURL value:URL original:_event.URL];
            }
        }
    }
    [self renderAndResize];
}

// Show a text part the event doesn't have yet, empty, to type in.
- (void)addTextPart:(AgendaPopoverTextView *)textView
{
    [self endEditing];
    textView.hidden = NO;
    [textView setAttributedText:[NSAttributedString new]];
    [self updateSectionsHidden];
    [self sizeChanged];
    [self.view layoutSubtreeIfNeeded];
    [textView beginEditingAtIndex:0];
    [textView scrollRectToVisible:textView.bounds];
}

// Show the end date of an event on one day, with its calendar, to
// type or pick the day it ends.
- (void)addEndDate:(id)sender
{
    [self endEditing];
    _showsEndDate = YES;
    [self renderAndResize];
    [self.view layoutSubtreeIfNeeded];
    // The calendar shows before the typing starts. See
    // -showCalendarForField:.
    [self showCalendarForField:_endDateField];
    [self.view.window makeFirstResponder:_endDateField];
}

- (void)addLocation:(id)sender { [self addTextPart:_location]; }
- (void)addNotes:(id)sender { [self addTextPart:_note]; }
- (void)addURL:(id)sender { [self addTextPart:_URL]; }

#pragma mark Menus

static NSMenuItem *MenuItem(NSString *title, id target, SEL action, id representedObject)
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = target;
    item.representedObject = representedObject;
    return item;
}

// How it repeats: None and the presets, and the event's own way of
// repeating if it's none of those. For adding, just the presets.
- (NSMenu *)repeatMenuForAdding:(BOOL)adding
{
    NSMenu *menu = [NSMenu new];
    EKRecurrenceRule *rule = adding ? nil : [self currentRule];
    NSMutableArray<NSMenuItem *> *presets = [NSMutableArray new];
    BOOL matched = NO;
    for (NSInteger i = 0; i < kRepeatPresetCount; i++) {
        RepeatPreset preset = kRepeatPresets[i];
        NSMenuItem *item = MenuItem(FrequencyText(preset.frequency, preset.interval), self, @selector(repeatPicked:), @(i));
        if (rule && RuleIsSimple(rule) && rule.frequency == preset.frequency && rule.interval == preset.interval) {
            item.state = NSControlStateValueOn;
            matched = YES;
        }
        [presets addObject:item];
    }
    if (rule && !matched) {
        NSString *title = [RepeatText(rule) componentsSeparatedByString:@"\n"].firstObject;
        NSMenuItem *item = MenuItem(title, self, @selector(repeatPicked:), nil);
        item.state = NSControlStateValueOn;
        [menu addItem:item];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    if (!adding) {
        [menu addItem:MenuItem(NSLocalizedString(@"None", @"Repeat none"), self, @selector(repeatPicked:), NSNull.null)];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    for (NSMenuItem *item in presets) {
        [menu addItem:item];
    }
    return menu;
}

- (void)repeatPicked:(NSMenuItem *)item
{
    // The ticked item is how it repeats already.
    if (item.state == NSControlStateValueOn || item.representedObject == nil) return;
    EKRecurrenceRule *current = [self currentRule];
    EKRecurrenceRule *original = _event.recurrenceRules.firstObject;
    EKRecurrenceRule *rule = nil;
    if ([item.representedObject isKindOfClass:[NSNumber class]]) {
        RepeatPreset preset = kRepeatPresets[[item.representedObject integerValue]];
        // Keep when it stops repeating.
        rule = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:preset.frequency interval:preset.interval end:current.recurrenceEnd];
        // Back to how it repeated?
        if (original && RuleIsSimple(original) && original.frequency == preset.frequency && original.interval == preset.interval) {
            rule = original;
        }
    }
    [self stage:kChangeRule value:rule original:original];
    [self renderAndResize];
}

// An alert's menu: None and the alerts offered. For adding (index -1),
// the alerts offered that the event doesn't have.
- (NSMenu *)alertMenuForIndex:(NSInteger)index
{
    NSMenu *menu = [NSMenu new];
    BOOL allDay = [self currentAllDay];
    NSArray *alarms = [self currentAlarms];
    id current = index >= 0 && index < (NSInteger)alarms.count ? alarms[index] : nil;
    NSArray<NSNumber *> *offsets = AlertOffsets(allDay);
    if (index >= 0) {
        [menu addItem:MenuItem(NSLocalizedString(@"None", @"Alert none"), self, @selector(alertPicked:), @[@(index), NSNull.null])];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    if (current && ![offsets containsObject:current]) {
        NSMenuItem *item = MenuItem(AlertTitle(current, allDay), self, @selector(alertPicked:), @[@(index), current]);
        item.state = NSControlStateValueOn;
        [menu addItem:item];
        [menu addItem:[NSMenuItem separatorItem]];
    }
    for (NSNumber *offset in offsets) {
        if (index < 0 && [alarms containsObject:offset]) continue;
        NSMenuItem *item = MenuItem(AlertTitle(offset, allDay), self, @selector(alertPicked:), @[@(index), offset]);
        if ([offset isEqual:current]) item.state = NSControlStateValueOn;
        [menu addItem:item];
    }
    return menu;
}

- (void)alertPicked:(NSMenuItem *)item
{
    NSInteger index = [item.representedObject[0] integerValue];
    id value = item.representedObject[1];
    NSMutableArray *alarms = [[self currentAlarms] mutableCopy];
    if (index < 0) {
        if (value != NSNull.null) [alarms addObject:value];
    }
    else if (index < (NSInteger)alarms.count) {
        if (value == NSNull.null) [alarms removeObjectAtIndex:index];
        else alarms[index] = value;
    }
    [self stage:kChangeAlarms value:alarms original:AlarmValues(_event.alarms)];
    [self renderAndResize];
}

// The calendars the event can be moved to, under their accounts.
- (NSMenu *)calendarMenu
{
    NSMenu *menu = [NSMenu new];
    EKCalendar *current = [self currentCalendar];
    NSArray<EKCalendar *> *calendars = self.calendarsHandler ? self.calendarsHandler() : @[];
    NSMutableSet<NSString *> *sources = [NSMutableSet new];
    for (EKCalendar *calendar in calendars) {
        [sources addObject:calendar.source.title ?: @""];
    }
    NSString *source = nil;
    for (EKCalendar *calendar in calendars) {
        NSString *calendarSource = calendar.source.title ?: @"";
        if (sources.count > 1 && ![calendarSource isEqualToString:source]) {
            if (source) [menu addItem:[NSMenuItem separatorItem]];
            [menu addItem:[NSMenuItem sectionHeaderWithTitle:calendarSource]];
            source = calendarSource;
        }
        NSMenuItem *item = MenuItem(calendar.title ?: @"", self, @selector(calendarChosen:), calendar);
        item.image = CalendarDotImage(calendar.color);
        if (calendar == current || [calendar.calendarIdentifier isEqualToString:current.calendarIdentifier]) {
            item.state = NSControlStateValueOn;
        }
        [menu addItem:item];
    }
    return menu;
}

- (void)calendarChosen:(NSMenuItem *)item
{
    if (item.state == NSControlStateValueOn) return;
    [self stage:kChangeCalendar value:item.representedObject original:_event.calendar];
    [self renderAndResize];
}

// "+ Add": the parts the event doesn't have yet.
- (NSMenu *)addMenu
{
    NSMenu *menu = [NSMenu new];
    // An event on one day only shows the day it starts.
    if ([NSCalendar.currentCalendar isDate:[self currentStart] inSameDayAsDate:[self currentEnd]]) {
        [menu addItem:MenuItem(NSLocalizedString(@"End Date", @"+ Add menu in the event popover: the day an event on one day ends, to make it longer"), self, @selector(addEndDate:), nil)];
    }
    if ([self currentRule] == nil) {
        NSMenuItem *repeat = MenuItem(NSLocalizedString(@"Repeat", @"+ Add menu in the event popover: how the event repeats"), nil, nil, nil);
        repeat.submenu = [self repeatMenuForAdding:YES];
        [menu addItem:repeat];
    }
    // Alerts are added with "+ Add Alert", below them.
    if (_location.hidden) {
        [menu addItem:MenuItem(NSLocalizedString(@"Location", @"+ Add menu in the event popover"), self, @selector(addLocation:), nil)];
    }
    if (_note.hidden) {
        [menu addItem:MenuItem(NSLocalizedString(@"Notes", @"+ Add menu in the event popover"), self, @selector(addNotes:), nil)];
    }
    if (_URL.hidden) {
        [menu addItem:MenuItem(NSLocalizedString(@"URL", @"+ Add menu in the event popover"), self, @selector(addURL:), nil)];
    }
    return menu;
}

#pragma mark -
#pragma mark Saving

- (void)saveChanges
{
    [self endEditing];
    [self closeCalendar];
    if (_changes.count == 0) return;
    NSDictionary<NSString *, id> *changes = [_changes copy];
    [_changes removeAllObjects];
    EKEvent *event = _event;
    // It may have been changed or deleted elsewhere since it was
    // shown. Refresh it; NO means it no longer exists.
    if (event == nil || (!event.isNew && ![event refresh])) {
        [self render];
        return;
    }
    // A change to how it repeats is for this and all future events,
    // as Calendar does.
    BOOL ruleChanged = changes[kChangeRule] != nil;
    EKSpan span = ruleChanged ? EKSpanFutureEvents : EKSpanThisEvent;
    if (event.hasRecurrenceRules) {
        NSString *title = changes[kChangeTitle] ?: event.title ?: @"";
        NSAlert *alert = [NSAlert new];
        alert.messageText = [NSString stringWithFormat:NSLocalizedString(@"“%@” is a repeating event.", @"Asked when saving changes to a repeating event"), title];
        if (ruleChanged) {
            alert.informativeText = NSLocalizedString(@"Changing how it repeats changes this and all future events.", @"");
            [alert addButtonWithTitle:NSLocalizedString(@"All Future Events", @"")];
        }
        else {
            alert.informativeText = NSLocalizedString(@"Save your changes to this event only, or to this and all future events?", @"");
            [alert addButtonWithTitle:NSLocalizedString(@"Only This Event", @"")];
            [alert addButtonWithTitle:NSLocalizedString(@"All Future Events", @"")];
        }
        NSButton *dontSave = [alert addButtonWithTitle:NSLocalizedString(@"Don't Save", @"")];
        dontSave.keyEquivalent = @"\033";
        [NSApp activate];
        NSModalResponse response = [alert runModal];
        if (ruleChanged) {
            if (response != NSAlertFirstButtonReturn) {
                [self render];
                return;
            }
        }
        else {
            if (response != NSAlertFirstButtonReturn && response != NSAlertSecondButtonReturn) {
                [self render];
                return;
            }
            span = response == NSAlertSecondButtonReturn ? EKSpanFutureEvents : EKSpanThisEvent;
        }
    }
    if (self.saveHandler) {
        self.saveHandler(event, span, ^(EKEvent *e) { ApplyChanges(e, changes); });
    }
    [self render];
}

#pragma mark -
#pragma mark Text

// The item's notes as text to show, or nil if there's nothing to show.
- (NSAttributedString *)notesTextOfItem:(EKCalendarItem *)item
{
    NSString *notes = [item.notes stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (notes.length == 0) return nil;
    // Notes are plain text, except those made in a rich text
    // editor (like Google Calendar's), which are HTML. Parsing
    // plain text as HTML would drop anything in <angle brackets>
    // and change text like &copy, so only parse notes with tags.
    BOOL isHTML = [_htmlTagRegex firstMatchInString:notes options:kNilOptions range:NSMakeRange(0, notes.length)] != nil;
    NSAttributedString *text = [self textWithString:notes isHTML:isHTML];
    // HTML can show nothing, like the <br> Google Calendar can leave
    // when a description is cleared.
    NSString *shown = [text.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return shown.length > 0 ? text : nil;
}

// The string as text to show, with links.
- (NSAttributedString *)textWithString:(NSString *)string isHTML:(BOOL)isHTML
{
    // We will detect mail message URLs with _messageLinksRegex. These URLs
    // link directly to specific messages. They may contain fragments that look
    // like standard URLs that are picked up by _linkDetector. In order to avoid
    // conflicts, we keep an array of NSRanges for matched message URLs. When
    // we go to match standard URLs, we will only match those whose NSRanges
    // don't intersect (overlap) with message URLs.
    NSMutableArray *messageLinkRanges = [NSMutableArray new];

    NSMutableAttributedString *attrString;
    if (isHTML) {
        // Ugly hack to deal with Microsoft's insane habit of putting links
        // in angle brackets, making them invisible when rendereed as HTML.
        string = [_hiddenLinksRegex stringByReplacingMatchesInString:string options:kNilOptions range:NSMakeRange(0, string.length) withTemplate:@"&lt;$1&gt;"];

        string = [string stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
        NSData *htmlData = [string dataUsingEncoding:NSUnicodeStringEncoding];
        attrString = [[NSMutableAttributedString alloc] initWithHTML:htmlData documentAttributes:nil];
    }
    else {
        attrString = [[NSMutableAttributedString alloc] initWithString:string];
    }

    [attrString addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:SizePref.fontSize] range:NSMakeRange(0, attrString.length)];
    [attrString addAttribute:NSForegroundColorAttributeName value:Theme.agendaEventTextColor range:NSMakeRange(0, attrString.length)];
    [_messageLinksRegex enumerateMatchesInString:attrString.string options:kNilOptions range:NSMakeRange(0, attrString.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        NSString *link = [attrString.string substringWithRange:result.range];
        [attrString addAttribute:NSLinkAttributeName value:link range:result.range];
        [messageLinkRanges addObject:[NSValue valueWithRange:result.range]];
    }];
    [_linkDetector enumerateMatchesInString:attrString.string options:kNilOptions range:NSMakeRange(0, attrString.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        // Make sure result.range doesn't intersect (overlap) with the
        // range of a message URL matched by _messageLinksRegex.
        BOOL resultOverlapsAMessageLink = NO;
        for (NSValue *val in messageLinkRanges) {
            NSRange intersection = NSIntersectionRange(val.rangeValue, result.range);
            if (intersection.length != 0) {
                resultOverlapsAMessageLink = YES;
                break;
            }
        }
        if (!resultOverlapsAMessageLink) {
            [attrString addAttribute:NSLinkAttributeName value:result.URL.absoluteString range:result.range];
        }
    }];
    return attrString;
}

@end
