// Created by Sanjay Madan on 7/27/18
// Copyright (c) 2018 mowglii.com

#import <Foundation/Foundation.h>

// NSUserDefaults key
extern NSString * const kSizePreference;

// Notification name
extern NSString * const kSizeDidChangeNotification;

#define FONT_SIZE_SMALL 11
#define FONT_SIZE_MEDIUM 13
#define FONT_SIZE_LARGE 15

// Convenience macro for notification observer for sizeable components
#define REGISTER_FOR_SIZE_CHANGE [[NSNotificationCenter defaultCenter] \
                                   addObserver:self \
                                   selector:@selector(sizeChanged:) \
                                   name:kSizeDidChangeNotification \
                                   object:nil]

typedef NS_ENUM(NSInteger, SizePreference) {
    SizePreferenceSmall = 0,
    SizePreferenceMedium = 1,
    SizePreferenceLarge = 2
};

// Spidercal: how the month calendar shows events. Lines and Details
// need bigger date cells, so the calendar's size depends on it.
typedef NS_ENUM(NSInteger, CalendarStyle) {
    CalendarStyleDots = 0,    // up to 3 dots under the date
    CalendarStyleLines = 1,   // a line for each all-day or multi-day
                              // event (across its days), and dots for
                              // events at a time
    CalendarStyleDetails = 2, // each event's title
};

@interface Sizer : NSObject

// Global constant for shared controller instance (like NSApp).
extern Sizer *SizePref;

@property (nonatomic) SizePreference sizePreference;

// Bound to kShowEventDots and kCalendarEventStyle. Without events,
// the calendar uses Dots' size.
@property (nonatomic) BOOL showsEventsInCalendar;
@property (nonatomic) NSInteger calendarEventStyle;
@property (nonatomic, readonly) CalendarStyle calendarStyle;
@property (nonatomic, readonly) CGFloat fontSize;
@property (nonatomic, readonly) CGFloat calendarTitleFontSize;
@property (nonatomic, readonly) CGFloat cellSize;
// The calendar's date cells. cellSize square for Dots; bigger for
// Lines and Details.
@property (nonatomic, readonly) CGFloat dateCellWidth;
@property (nonatomic, readonly) CGFloat dateCellHeight;
// Lines and Details: events go in lanes, from calendarLaneTop below a
// date cell's top edge down.
@property (nonatomic, readonly) NSInteger calendarLaneCount;
@property (nonatomic, readonly) CGFloat calendarLaneTop;
@property (nonatomic, readonly) CGFloat calendarLaneHeight;
@property (nonatomic, readonly) CGFloat calendarLaneGap;
// Details: the titles' font size.
@property (nonatomic, readonly) CGFloat calendarEventFontSize;
@property (nonatomic, readonly) CGFloat cellTextFieldVerticalSpace;     // the days of the week
@property (nonatomic, readonly) CGFloat dateCellTextFieldVerticalSpace; // dates and week numbers
@property (nonatomic, readonly) CGFloat cellDotWidth;
@property (nonatomic, readonly) CGFloat cellRadius;
@property (nonatomic, readonly) CGFloat tooltipWidth;
@property (nonatomic, readonly) CGFloat agendaEventLeadingMargin;
@property (nonatomic, readonly) CGFloat agendaDotWidth;
@property (nonatomic, readonly) CGFloat agendaPopoverSectionSpacing;

+ (instancetype)shared;

@end
