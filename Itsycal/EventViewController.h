//
//  EventViewController.h
//  Itsycal
//
//  Created by Sanjay Madan on 2/25/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class EventCenter, NLEventDraft;

@interface EventViewController : NSViewController <NSTextFieldDelegate, NSTextViewDelegate>

@property (nonatomic, weak) EventCenter *ec;
@property (nonatomic, weak) NSPopover *enclosingPopover;
@property (nonatomic, weak) NSCalendar *cal;
@property (nonatomic) NSDate *calSelectedDate;

// The Itsycal window's undo manager. Saving registers undo here
// so ⌘Z works after the popover closes.
@property (nonatomic, weak) NSUndoManager *eventUndoManager;

// Spidercal: the form sits inside the main window, under the quick
// entry field, instead of in a popover. Set before the view loads.
// An embedded form is compact, is filled in from what the user
// types in the quick entry field, and doesn't reset itself when
// the window appears.
@property (nonatomic) BOOL embedded;
@property (nonatomic, copy) void (^onSaved)(void);       // embedded: the event was saved
@property (nonatomic, copy) void (^onCollapse)(void);    // embedded: hide the details
@property (nonatomic, copy) void (^onLayoutChange)(void);// embedded: the form's height changed

// Back to a blank form for calSelectedDate.
- (void)resetForm;

// Fill in the form from the quick entry field. location is the
// place to save (a picked suggestion's full address, or what
// was typed), or nil.
- (void)applyDraft:(NLEventDraft *)draft location:(NSString *)location;

- (void)saveEvent:(id)sender;
- (void)focusFirstField;
- (void)dismissSuggestions;

// The form's current values, for the summary under the quick
// entry field.
@property (nonatomic, readonly) BOOL canSave;
@property (nonatomic, readonly) NSString *summaryTitle;
@property (nonatomic, readonly) NSString *summaryLocation;
@property (nonatomic, readonly) NSDate *summaryStart;
@property (nonatomic, readonly) NSDate *summaryEnd;
@property (nonatomic, readonly) BOOL summaryAllDay;
@property (nonatomic, readonly) NSTimeZone *summaryTimeZone; // nil if it is the Mac's time zone
@property (nonatomic, readonly) NSString *summaryCalendarTitle;
@property (nonatomic, readonly) NSColor *summaryCalendarColor;

// A copy of the calendar popup's menu whose items send action to
// target. Pass the chosen item's tag to -selectCalendarWithTag:.
- (NSMenu *)calendarMenuWithTarget:(id)target action:(SEL)action;
- (void)selectCalendarWithTag:(NSInteger)tag;

@end
