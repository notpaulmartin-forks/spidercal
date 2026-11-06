// Created by Sanjay Madan on 7/27/18
// Copyright (c) 2018 mowglii.com

#import "Sizer.h"

// NSUserDefaults key
NSString * const kSizePreference = @"SizePreference";

// Notification names
NSString * const kSizeDidChangeNotification = @"SizeDidChangeNotification";

#define SML_MED_LRG(sml, med, lrg) \
            (self.sizePreference == SizePreferenceMedium ? med \
            : (self.sizePreference == SizePreferenceLarge ? lrg : sml))

@implementation Sizer

Sizer *SizePref = nil;

+ (instancetype)shared {
    static Sizer *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[Sizer alloc] init];
        SizePref = shared;
    });
    return shared;
}

- (void)setSizePreference:(SizePreference)sizePreference {
    _sizePreference = sizePreference;
    // Post notification on the main thread because the selector,
    // @selector(sizeChanged:), updates the UI and therefore must
    // run on the main thread. See the REGISTER_FOR_SIZE_CHANGE
    // macro in Sizer.h.
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
         postNotificationName:kSizeDidChangeNotification object:nil];
    });
}

- (void)setShowsEventsInCalendar:(BOOL)showsEventsInCalendar {
    CalendarStyle old = self.calendarStyle;
    _showsEventsInCalendar = showsEventsInCalendar;
    [self calendarStyleMayHaveChangedFrom:old];
}

- (void)setCalendarEventStyle:(NSInteger)calendarEventStyle {
    CalendarStyle old = self.calendarStyle;
    _calendarEventStyle = calendarEventStyle;
    [self calendarStyleMayHaveChangedFrom:old];
}

- (CalendarStyle)calendarStyle {
    if (!self.showsEventsInCalendar) return CalendarStyleDots;
    switch (self.calendarEventStyle) {
        case CalendarStyleLines:   return CalendarStyleLines;
        case CalendarStyleDetails: return CalendarStyleDetails;
        default:                   return CalendarStyleDots;
    }
}

- (void)calendarStyleMayHaveChangedFrom:(CalendarStyle)old {
    // The cells change size, as they do for a new size preference.
    if (self.calendarStyle != old) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter]
             postNotificationName:kSizeDidChangeNotification object:nil];
        });
    }
}

- (CGFloat)fontSize {
    return SML_MED_LRG(FONT_SIZE_SMALL, FONT_SIZE_MEDIUM, FONT_SIZE_LARGE);
}

- (CGFloat)calendarTitleFontSize {
    return SML_MED_LRG(14, 16, 18);
}

- (CGFloat)cellSize {
    // Spidercal: a little roomier than Itsycal's 23, 28, 32. The new
    // event form and place suggestions need the width. (Window width
    // is 7 cells + 16.)
    return SML_MED_LRG(27, 30, 34);
}

- (CGFloat)dateCellWidth {
    switch (self.calendarStyle) {
        case CalendarStyleDetails: return SML_MED_LRG(42, 48, 56);
        default:                   return self.cellSize;
    }
}

- (CGFloat)dateCellHeight {
    CGFloat lanes = self.calendarLaneTop + self.calendarLaneCount * self.calendarLaneHeight
                  + (self.calendarLaneCount - 1) * self.calendarLaneGap;
    switch (self.calendarStyle) {
        // The dots for events at a time go under a day's lines.
        case CalendarStyleLines:   return ceil(lanes + self.calendarLaneGap + 1.5 + self.cellDotWidth + 3);
        // Room under the last lane, above the line to the next week.
        case CalendarStyleDetails: return ceil(lanes + 5);
        default:                   return self.cellSize;
    }
}

- (NSInteger)calendarLaneCount {
    return 3;
}

- (CGFloat)calendarLaneTop {
    // Just under the date.
    return self.calendarStyle == CalendarStyleDetails ? SML_MED_LRG(20, 22, 24) : SML_MED_LRG(17, 19, 21);
}

- (CGFloat)calendarLaneHeight {
    return self.calendarStyle == CalendarStyleDetails ? SML_MED_LRG(12, 14, 16) : SML_MED_LRG(2.5, 3, 3.5);
}

- (CGFloat)calendarLaneGap {
    return self.calendarStyle == CalendarStyleDetails ? 2 : SML_MED_LRG(1.5, 2, 2);
}

- (CGFloat)calendarEventFontSize {
    return self.calendarStyle == CalendarStyleDetails ? SML_MED_LRG(10, 11, 13) : self.fontSize - 1;
}

- (CGFloat)cellTextFieldVerticalSpace {
    return SML_MED_LRG(2, 2, 2);
}

- (CGFloat)dateCellTextFieldVerticalSpace {
    // Details: clear of the line to the week above.
    return self.calendarStyle == CalendarStyleDetails ? 4 : self.cellTextFieldVerticalSpace;
}

- (CGFloat)cellDotWidth {
    return SML_MED_LRG(3, 4, 5);
}

- (CGFloat)cellRadius {
    return SML_MED_LRG(3, 4, 5);
}

- (CGFloat)tooltipWidth {
    return SML_MED_LRG(200, 236, 264);
}

- (CGFloat)agendaDotWidth {
    return SML_MED_LRG(6, 7, 8);
}

- (CGFloat)agendaPopoverSectionSpacing {
    return SML_MED_LRG(4, 6, 8);
}

- (CGFloat)agendaEventLeadingMargin {
    return SML_MED_LRG(21, 22, 24);
}

@end
