//
//  DayPicker.h
//  Spidercal
//
//  A month calendar to pick a day from, shown below a date being typed
//  in an event's details. It looks like the main calendar, smaller.
//

#import <Cocoa/Cocoa.h>

@interface DayPicker : NSObject
// A day was clicked: the start of that day.
@property (nonatomic, copy) void (^dayPicked)(NSDate *day);
// The All-day checkbox was clicked: its new state.
@property (nonatomic, copy) void (^allDayClicked)(BOOL allDay);
// The day shown as picked. Setting it shows its month.
@property (nonatomic) NSDate *date;
// An All-day checkbox shows below the days.
@property (nonatomic) BOOL showsAllDay;
@property (nonatomic) BOOL allDay;
@property (nonatomic, readonly) BOOL isShown;
// Show it below view, lined up with view's text, or move it there if
// it shows. It never becomes the key window, so typing goes on in
// view, and clicking it doesn't end the typing.
- (void)showBelowView:(NSView *)view;
- (void)close;
@end
