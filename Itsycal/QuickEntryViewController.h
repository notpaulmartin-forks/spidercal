//
//  QuickEntryViewController.h
//  Spidercal
//
//  The bar at the top of the window. It holds two fields, one of
//  them wide and the other collapsed to a button:
//
//   - New Event: type an event in natural language ("Flight to
//     Tokyo on 12 Nov at 4pm, New York time"). What was understood is
//     summarised underneath, with the full form one click away.
//   - Search: find events by title, location or notes. The
//     matches replace the agenda.
//

#import <Cocoa/Cocoa.h>

@class EventCenter;
@protocol QuickEntryDelegate;

@interface QuickEntryViewController : NSViewController

@property (nonatomic, weak) EventCenter *ec;
@property (nonatomic, weak) NSCalendar *cal;
@property (nonatomic, weak) NSUndoManager *eventUndoManager;
@property (nonatomic, weak) id<QuickEntryDelegate> delegate;

@property (nonatomic, readonly) BOOL isSearching;

// Put the cursor in the New Event field / the Search field,
// switching to it if the other one is showing.
- (void)focusEntry;
- (void)focusSearch;

// Close any place suggestions, e.g. because the window is hiding.
- (void)dismissSuggestions;

@end

@protocol QuickEntryDelegate <NSObject>

// The date selected in the calendar: a new event's default day.
- (NSDate *)quickEntrySelectedDate;

// Can events be created? If not, tell the user why and return NO.
- (BOOL)quickEntryCanCreateEvents;

// The user typed a date. Show it in the calendar.
- (void)quickEntryShowDate:(NSDate *)date;

// The search text changed. nil means the user left search.
- (void)quickEntrySearchChanged:(NSString *)query;

// An arrow key was pressed while the New Event field is empty.
// It should move the calendar's selection as usual.
- (void)quickEntryForwardKeyDown:(NSEvent *)event;

// The bar's height changed, so the agenda has a new limit.
- (void)quickEntryLayoutChanged;

// Esc was pressed with nothing to cancel.
- (void)quickEntryWantsToCloseWindow;

@end
