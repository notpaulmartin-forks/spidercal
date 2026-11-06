//
//  MoCalEvents.h
//  Spidercal
//
//  The month calendar's Lines and Details styles (see CalendarStyle
//  in Sizer.h): events laid out in lanes under each date, week by
//  week, with an event that spans days drawn across them.
//

#import <AppKit/AppKit.h>
#import "MoDate.h"

@class MoCalGrid;

// An event as the month calendar shows it.
@interface MoCalEvent : NSObject

@property (nonatomic) MoDate startDate; // its first day
@property (nonatomic) MoDate endDate;   // its last day; startDate for a one-day event
@property (nonatomic) BOOL hasTime;     // NO for an all-day event, or a reminder without a time
@property (nonatomic, copy) NSString *title;
@property (nonatomic) NSColor *color;   // nil for the theme's color

@end

// Where a calendar's events go, for the current style and size.
@interface MoCalEventLayout : NSObject

// events: the events on the calendar's days, a day's events in the
// order the agenda lists them. firstDate: the first cell's date.
- (instancetype)initWithEvents:(NSArray<MoCalEvent *> *)events firstDate:(MoDate)firstDate rows:(NSInteger)rows;

@end

// Draws a layout's events. It goes under the date grid's cells, so
// their outlines are on top, and it has the grid's frame.
@interface MoCalEventsView : NSView

@property (nonatomic, weak) MoCalGrid *grid;
@property (nonatomic) MoCalEventLayout *layout;

@end
