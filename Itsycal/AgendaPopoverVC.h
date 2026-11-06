//
//  Created by Sanjay Madan on 10/28/26.
//  Copyright © 2026 mowglii.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <EventKit/EventKit.h>

@class EventInfo;

// The details of an event or reminder. For an event the user can
// change (its calendar allows it and it has no invitees), each part
// of the details can be clicked to change it, and "+ Add" adds the
// parts it doesn't have yet. Changes are kept until -saveChanges.
@interface AgendaPopoverVC : NSViewController
// Called when the user clicks the delete button or presses delete.
// The button only shows for an event whose calendar can be changed.
@property (nonatomic, copy) void (^deleteHandler)(void);
// Called by -saveChanges: changes() makes the changes to event, which
// is then saved for span. Returns NO if they couldn't be saved.
@property (nonatomic, copy) BOOL (^saveHandler)(EKEvent *event, EKSpan span, void (^changes)(EKEvent *event));
// The calendars an event can be moved to.
@property (nonatomic, copy) NSArray<EKCalendar *> *(^calendarsHandler)(void);
// Called when the details need a different size, e.g. a part was
// added or removed. Set the popover's size to -size.
@property (nonatomic, copy) void (^sizeChangedHandler)(void);
// A part is being changed, or there are changes not yet saved.
@property (nonatomic, readonly) BOOL isEditing;
// Saves any changes to the event shown first.
- (void)populateWithEventInfo:(EventInfo *)info;
// Save the changes, if any: finish the part being changed and, for a
// repeating event, ask whether to change only this event or this
// and all future events. Call when the details close.
- (void)saveChanges;
// Call once the popover is shown at its final size.
- (void)popoverDidShow;
- (NSSize)size;
@end
