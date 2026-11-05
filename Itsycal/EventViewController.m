//
//  EventViewController.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/25/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "EventViewController.h"
#import "EventCenter.h"
#import "MoThemeView.h"
#import "MoVFLHelper.h"
#import "Themer.h"
#import "Sizer.h"
#import "NLEventParser.h"
#import "LocationSuggestionsView.h"

@interface HackyTextView : NSTextView
// The placeholderAttributedString property in NSTextView
// isn't exposed publicly.
// https://stackoverflow.com/a/47223845/111418
@property NSAttributedString *placeholderAttributedString;
@end

@implementation HackyTextView
- (BOOL)becomeFirstResponder
{
    // Empty NSTextView gets focus but no cursor is visible
    // https://stackoverflow.com/a/39167917
    // https://stackoverflow.com/a/77020301/111418
    BOOL result = [super becomeFirstResponder];
    if (result) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!self.string.length) {
                self.string = @" ";
                self.string = @"";
            }
        });
    }
    return result;
}
@end

// These values map to _alertAllDayStrings and _alertRegularStrings.
enum {
    kAlertAllDayNumOffsets = 5,
    kAlertRegularNumOffsets = 10
};
const NSTimeInterval kAlertAllDayRelativeOffsets[kAlertAllDayNumOffsets] = {
    MAXFLOAT, // None
    32400,    // On day of event (9 AM)
    -54000,   // 1 day before (9 AM)
    -140400,  // 2 days before (9 AM)
    -572400   // 1 week before
};
const NSTimeInterval kAlertRegularRelativeOffsets[kAlertRegularNumOffsets] = {
    MAXFLOAT, // None
    0,        // At time of event
    -300,     // 5 minutes before
    -600,     // 10 minutes before
    -900,     // 15 minutes before
    -1800,    // 30 minutes before
    -3600,    // 1 hour before
    -7200,    // 2 hours before
    -86400,   // 1 day before
    -172800   // 2 days before
};

@interface EventViewController ()
- (CalendarInfo *)selectedCalendarInfo;
@end

@implementation EventViewController
{
    NSTextField *_title, *_location, *_url, *_repEndLabel;
    NSButton *_allDayCheckbox, *_saveButton;
    NSDatePicker *_startDate, *_endDate, *_repEndDate;
    NSPopUpButton *_repPopup, *_repEndPopup, *_alertPopup, *_calPopup;
    NSArray<NSString *> *_alertAllDayStrings, *_alertRegularStrings;
    HackyTextView *_notes;
    NSScrollView *_notesScrollView;
    NSLayoutConstraint *_notesScrollViewHeightConstraint;
    CGFloat _notesHeightOfOneLine;
    // Spidercal
    NSPopUpButton *_tzPopup;
    NSTimeZone *_timeZone;          // the time zone the pickers show
    NSDate *_defaultStart, *_defaultEnd;
    LocationSuggestionsView *_suggestions;
    NSArray<NSControl *> *_sizedControls; // follow the size preference
    NSButton *_collapseButton;
    NSButton *_calButton;
    NSArray<NSLayoutConstraint *> *_repEndRowConstraints;
    NSArray<NSLayoutConstraint *> *_noRepEndRowConstraints;
    NSArray<NSLayoutConstraint *> *_repEndDateConstraints;
    NSArray<NSLayoutConstraint *> *_dateInsetConstraints;
    NSArray<NSLayoutConstraint *> *_rowPitchConstraints;
}

- (void)loadView
{
    // View controller content view
    NSView *v = [NSView new];
    NSMutableArray<NSControl *> *sized = [NSMutableArray new];
    
    // TextField maker
    NSTextField* (^txt)(NSString*, BOOL) = ^NSTextField* (NSString *stringValue, BOOL isEditable) {
        NSTextField *txt;
        if (isEditable) {
            txt = [NSTextField textFieldWithString:@""];
            txt.placeholderString = stringValue;
            txt.bezeled = NO;
            txt.focusRingType = NSFocusRingTypeNone;
            txt.drawsBackground = NO;
        }
        else {
            txt = [NSTextField labelWithString:stringValue];
            txt.alignment = NSTextAlignmentRight;
        }
        [sized addObject:txt];
        // Long text scrolls in the field; it doesn't widen the window.
        if (isEditable) [txt setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [v addSubview:txt];
        return txt;
    };

    // DatePicker maker
    NSDatePicker* (^picker)(void) = ^NSDatePicker* () {
        NSDatePicker *picker = [NSDatePicker new];
        picker.datePickerStyle = NSDatePickerStyleTextField;
        picker.locale = NSLocale.currentLocale;
        picker.bezeled  = NO;
        picker.bordered = NO;
        picker.drawsBackground = NO;
        picker.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
        [sized addObject:picker];
        [v addSubview:picker];
        return picker;
    };

    // PopUpButton maker
    NSPopUpButton* (^popup)(SEL) = ^NSPopUpButton* (SEL action) {
        NSPopUpButton *pop = [NSPopUpButton new];
        pop.target = self;
        pop.action = action;
        pop.menu.autoenablesItems = NO;
        [sized addObject:pop];
        // Long titles truncate; they don't widen the window.
        [pop setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [v addSubview:pop];
        return pop;
    };
    
    // Button maker
    NSButton* (^btn)(NSString*, id, SEL) = ^NSButton* (NSString *title, id target, SEL action) {
        NSButton *btn = [NSButton buttonWithTitle:title target:target action:action];
        [sized addObject:btn];
        [v addSubview:btn];
        return btn;
    };

    // Title, location, and URL text fields
    _title = txt(NSLocalizedString(@"New Event", @""), YES);
    _title.delegate = self;
    _title.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
    _location = txt(NSLocalizedString(@"Add Location or Video Call", @""), YES);
    _url = txt(NSLocalizedString(@"Add URL", @""), YES);

    // Place suggestions under the location field
    _location.delegate = self;
    _suggestions = [LocationSuggestionsView new];
    _suggestions.anchorView = _location;
    __weak NSTextField *weakLocation = _location;
    _suggestions.onSelect = ^(NSString *name, NSString *location) {
        weakLocation.stringValue = location;
    };
    
    // All-day checkbox
    _allDayCheckbox = [NSButton new];
    _allDayCheckbox.title = @"";
    _allDayCheckbox.target = self;
    _allDayCheckbox.action = @selector(allDayClicked:);
    [_allDayCheckbox setButtonType:NSButtonTypeSwitch];
    [sized addObject:_allDayCheckbox];
    [v addSubview:_allDayCheckbox];
    
    // Static labels
    NSTextField *allDayLabel = txt(NSLocalizedString(@"All-day:", @""), NO);
    NSTextField *startsLabel = txt(NSLocalizedString(@"Starts:", @""), NO);
    NSTextField *endsLabel   = txt(NSLocalizedString(@"Ends:", @""), NO);
    NSTextField *tzLabel     = txt(NSLocalizedString(@"Time Zone:", @""), NO);
    NSTextField *repLabel    = txt(NSLocalizedString(@"Repeat:", @""), NO);
                _repEndLabel = txt(NSLocalizedString(@"End Repeat:", @""), NO);
    NSTextField *alertLabel  = txt(NSLocalizedString(@"Alert:", @""), NO);
    
    // Date pickers
    _startDate = picker();
    _startDate.target = self;
    _startDate.action = @selector(startDateChanged:);
    _endDate    = picker();
    _repEndDate = picker();
    _repEndDate.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    
    // Popups
    _tzPopup = popup(@selector(tzPopupChanged:));
    _repPopup = popup(@selector(repPopupChanged:));
    [_repPopup addItemsWithTitles:@[NSLocalizedString(@"None", @"Repeat none"),
                                    NSLocalizedString(@"Every Day", @""),
                                    NSLocalizedString(@"Every Week", @""),
                                    [NSString stringWithFormat:NSLocalizedString(@"Every %zd Weeks", nil), (NSInteger)2],
                                    NSLocalizedString(@"Every Month", @""),
                                    NSLocalizedString(@"Every Year", @"")]];
    
    _repEndPopup = popup(@selector(repEndPopupChanged:));
    [_repEndPopup addItemsWithTitles:@[NSLocalizedString(@"Never", @"Repeat ends never"),
                                       NSLocalizedString(@"On Date", @"")]];
    
    _alertPopup = popup(NULL);
    _alertAllDayStrings = @[
        NSLocalizedString(@"None", @"Alert none"),
        NSLocalizedString(@"On day of event (9 AM)", @""),
        NSLocalizedString(@"1 day before (9 AM)", @""),
        NSLocalizedString(@"2 days before (9 AM)", @""),
        NSLocalizedString(@"1 week before", @"")];
    _alertRegularStrings = @[
        NSLocalizedString(@"None", @"Alert none"),
        NSLocalizedString(@"At time of event", @""),
        NSLocalizedString(@"5 minutes before", @""),
        NSLocalizedString(@"10 minutes before", @""),
        NSLocalizedString(@"15 minutes before", @""),
        NSLocalizedString(@"30 minutes before", @""),
        NSLocalizedString(@"1 hour before", @""),
        NSLocalizedString(@"2 hours before", @""),
        NSLocalizedString(@"1 day before", @""),
        NSLocalizedString(@"2 days before", @"")];
    // This is a hack.
    // Populate the alert with all possible values (there are
    // different values for regular vs. all-day events) so the
    // Autolayout engine can calculate the correct maximum
    // width of the button. The real values will be repopulated
    // in -viewWillAppear. Without this hack, the view may
    // change width when the user toggles between regular and
    // all-day events as the popup gets wider or narrower.
    [_alertPopup addItemsWithTitles:_alertAllDayStrings];
    [_alertPopup addItemsWithTitles:_alertRegularStrings];

    // Notes (NSTextView embedded in NSScrollView)
    _notesScrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 100, 44)];
    _notesScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _notesScrollView.focusRingType = NSFocusRingTypeExterior;
    _notesScrollView.borderType = NSNoBorder;
    _notesScrollView.verticalScrollElasticity = NSScrollElasticityNone;
    _notesScrollView.drawsBackground = NO;
    _notesScrollView.hasVerticalScroller = NO; // see -textDidChange:
    [v addSubview:_notesScrollView];

    NSSize noteContentSize = _notesScrollView.contentSize;
    _notes = [[HackyTextView alloc] initWithFrame:NSMakeRect(0, 0, noteContentSize.width, noteContentSize.height)];
    _notes.delegate = self;
    _notes.font = _location.font; // _title.font is too big
    _notes.placeholderAttributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Add Notes", @"") attributes:@{NSFontAttributeName: _notes.font, NSForegroundColorAttributeName: NSColor.disabledControlTextColor}];
    _notes.allowsUndo = YES;
    _notes.drawsBackground = NO;
    _notes.richText = NO;
    _notes.focusRingType = NSFocusRingTypeNone;
    _notes.minSize = NSMakeSize(0, noteContentSize.height);
    _notes.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _notes.verticallyResizable = YES;
    _notes.horizontallyResizable = NO;
    _notes.autoresizingMask = NSViewWidthSizable;
    _notes.textContainer.widthTracksTextView = YES;
    [_notes.textContainer setLineFragmentPadding:0];
    [_notes.textContainer setContainerSize:NSMakeSize(noteContentSize.width, FLT_MAX)];

    _notesScrollView.documentView = _notes;

    _calPopup = popup(@selector(calPopupChanged:));
    // Holds the choice. What shows is _calButton, the same control
    // as the summary's, so it doesn't shift when the details open.
    _calPopup.hidden = YES;
    [sized removeObject:_calPopup];
    _calButton = [NSButton buttonWithTitle:@"" target:self action:@selector(showCalendarMenu:)];
    _calButton.bordered = NO;
    _calButton.imagePosition = NSImageLeading;
    _calButton.imageHugsTitle = YES;
    _calButton.lineBreakMode = NSLineBreakByTruncatingTail;
    _calButton.refusesFirstResponder = YES;
    [_calButton setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [v addSubview:_calButton];
    
    // This is a hack.
    // Populate _calPopup with a dummy item so the Autolayout
    // engine can calculate its correct width. The real values
    // will be repopulated in -viewWillAppear.
    NSMenuItem *calItem = [NSMenuItem new];
    calItem.image = [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect dstRect) { return YES; }];
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 270000
    calItem.preferredImageVisibility = NSMenuItemImageVisibilityVisible;
#endif
    [_calPopup.menu addItem:calItem];
    
    // Save and Cancel buttons
    _saveButton = btn(NSLocalizedString(@"Save Event", @""), self, @selector(saveEvent:));
    _saveButton.enabled = NO; // we'll enable when the form is valid.
    NSButton *cancelButton = btn(NSLocalizedString(@"Cancel", @""), self, @selector(cancelOperation:));
    if (self.embedded) {
        // Embedded in the main window: a chevron that hides the
        // details takes the place of Cancel.
        cancelButton.title = @"";
        cancelButton.bordered = NO;
        cancelButton.image = [NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:NSLocalizedString(@"Hide Details", @"")];
        cancelButton.imagePosition = NSImageOnly;
        cancelButton.contentTintColor = Theme.buttonTintColor;
        cancelButton.refusesFirstResponder = YES;
        [sized removeObject:cancelButton];
        _collapseButton = cancelButton;
    }
    _sizedControls = sized;

    // The embedded form is compact so it fits the main window. m is
    // the margin for text and rm for controls, the same as the summary,
    // the month title and the search button above. Top and bottom match
    // the summary's so nothing moves when the details open.
    NSDictionary *metrics = self.embedded
        ? @{@"m": @10, @"rm": @8, @"g": @6, @"r": @2, @"t": @2, @"loc": @6, @"notes": @8, @"url": @4, @"save": @6, @"b": @2, @"notesW": @60}
        : @{@"m": @20, @"rm": @20, @"g": @8, @"r": @8, @"t": @20, @"loc": @11, @"notes": @20, @"url": @10, @"save": @15, @"b": @20, @"notesW": @200};
    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:metrics views:NSDictionaryOfVariableBindings(_title, _calButton, _location, _allDayCheckbox, allDayLabel, startsLabel, endsLabel, tzLabel, _startDate, _endDate, _tzPopup, repLabel, alertLabel, _repPopup, _repEndLabel, _repEndPopup, _repEndDate, _alertPopup, _notesScrollView, _url, cancelButton, _saveButton)];

    [vfl :@"V:|-t-[_title]-r-[_location]-loc-[_allDayCheckbox]"];
    [vfl :@"V:[_alertPopup]-notes-[_notesScrollView]-url-[_url]-save-[_saveButton]-b-|"];
    [vfl :@"H:|-m-[_title]-m-|"];
    [vfl :@"H:|-m-[_location]-m-|"];
    [vfl :@"H:|-m-[allDayLabel]-g-[_allDayCheckbox]-(>=rm)-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-m-[startsLabel]"];
    [vfl :@"H:|-m-[endsLabel]"];
    [vfl :@"H:|-m-[tzLabel]-g-[_tzPopup]-rm-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-m-[repLabel]-g-[_repPopup]-rm-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-m-[_repEndLabel]-g-[_repEndPopup(>=50)]-(>=rm)-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-m-[alertLabel]-g-[_alertPopup]-rm-|" :NSLayoutFormatAlignAllBaseline];
    [vfl :@"H:|-m-[_notesScrollView(>=notesW)]-m-|"];
    [vfl :@"H:|-m-[_url]-m-|"];
    // The calendar is where the summary shows it.
    [vfl :@"H:|-m-[cancelButton]-g-[_calButton]-(>=8)-[_saveButton]-rm-|" :NSLayoutFormatAlignAllCenterY];

    // One value column. Dates start where the popups' titles do.
    CGFloat sideMargin = [metrics[@"rm"] doubleValue], labelGap = [metrics[@"g"] doubleValue];
    _dateInsetConstraints = @[
        [_startDate.leadingAnchor constraintEqualToAnchor:_tzPopup.leadingAnchor],
        [_endDate.leadingAnchor constraintEqualToAnchor:_tzPopup.leadingAnchor],
    ];
    [NSLayoutConstraint activateConstraints:_dateInsetConstraints];
    [NSLayoutConstraint activateConstraints:@[
        [_allDayCheckbox.leadingAnchor constraintEqualToAnchor:_tzPopup.leadingAnchor],
        [_repPopup.leadingAnchor constraintEqualToAnchor:_tzPopup.leadingAnchor],
        [_repEndPopup.leadingAnchor constraintEqualToAnchor:_tzPopup.leadingAnchor],
        [_alertPopup.leadingAnchor constraintEqualToAnchor:_tzPopup.leadingAnchor],
        [startsLabel.trailingAnchor constraintEqualToAnchor:_tzPopup.leadingAnchor constant:-labelGap],
        [endsLabel.trailingAnchor constraintEqualToAnchor:_tzPopup.leadingAnchor constant:-labelGap],
        [_startDate.firstBaselineAnchor constraintEqualToAnchor:startsLabel.firstBaselineAnchor],
        [_endDate.firstBaselineAnchor constraintEqualToAnchor:endsLabel.firstBaselineAnchor],
        // The pickers have padding on the right, so these can run
        // closer to the edge. They shouldn't set the window's width.
        [_startDate.trailingAnchor constraintLessThanOrEqualToAnchor:v.trailingAnchor],
        [_endDate.trailingAnchor constraintLessThanOrEqualToAnchor:v.trailingAnchor],
        [_repEndDate.firstBaselineAnchor constraintEqualToAnchor:_repEndPopup.firstBaselineAnchor],
    ]];

    // Every row is the same distance from the next, whatever its
    // control's height: baseline to baseline. Set in -applySizePreference.
    NSLayoutConstraint* (^pitch)(NSTextField *, NSTextField *) = ^NSLayoutConstraint* (NSTextField *below, NSTextField *above) {
        return [below.firstBaselineAnchor constraintEqualToAnchor:above.firstBaselineAnchor];
    };
    NSArray<NSLayoutConstraint *> *fixedRows = @[pitch(startsLabel, allDayLabel), pitch(endsLabel, startsLabel), pitch(tzLabel, endsLabel), pitch(repLabel, tzLabel)];
    [NSLayoutConstraint activateConstraints:fixedRows];

    // The End Repeat row takes up no room until it is needed, and
    // its date picker no width until "On Date" is chosen.
    _repEndRowConstraints = @[pitch(_repEndLabel, repLabel), pitch(alertLabel, _repEndLabel)];
    _noRepEndRowConstraints = @[pitch(alertLabel, repLabel)];
    _rowPitchConstraints = [[fixedRows arrayByAddingObjectsFromArray:_repEndRowConstraints] arrayByAddingObjectsFromArray:_noRepEndRowConstraints];
    _repEndDateConstraints = @[
        [_repEndDate.leadingAnchor constraintEqualToAnchor:_repEndPopup.trailingAnchor constant:labelGap],
        [_repEndDate.trailingAnchor constraintLessThanOrEqualToAnchor:v.trailingAnchor constant:-sideMargin],
    ];
    [NSLayoutConstraint activateConstraints:_noRepEndRowConstraints];
    
    // Get height of one line in _notes
    [_notes.layoutManager ensureLayoutForTextContainer:_notes.textContainer];
    _notesHeightOfOneLine = [_notes.layoutManager usedRectForTextContainer:_notes.textContainer].size.height;

    // Set height of _notesScrollView to height of single line
    _notesScrollViewHeightConstraint = [_notesScrollView.heightAnchor constraintEqualToConstant:_notesHeightOfOneLine];
    _notesScrollViewHeightConstraint.active = YES;

    [self applySizePreference];
    if (self.embedded) REGISTER_FOR_SIZE_CHANGE;

    // Require All-day checkbox height to hug the checkbox. Without this,
    // the layout will look funny when the title is multi-line.
    [_allDayCheckbox setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationVertical];
    
    // Pickers' width will change depending on state of _allDayCheckbox.
    // We don't want the size of the picker control to change (shrink)
    // when this happens so we set a very low hugging priority.
    [_startDate setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_endDate   setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    
    // The popover has hasFullSizeContent=YES. Use the
    // safeAreaLayoutGuide of a view that paints its background
    // according to the Theme to inset our content. This paints
    // the popover's full background, including the arrow.
    v.translatesAutoresizingMaskIntoConstraints = NO;
    MoThemeView *view = [MoThemeView new];
    [view addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [v.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.bottomAnchor],
        [v.leftAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.leftAnchor],
        [v.rightAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.rightAnchor],
    ]];
    self.view = view;
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    // The embedded form is reset by the quick entry field, not
    // each time the window appears (that would lose a draft).
    if (self.embedded) return;

    self.view.window.defaultButtonCell = _saveButton.cell;
    [self resetForm];
}

- (void)resetForm
{
    (void)self.view; // make sure the view is loaded
    if (!self.calSelectedDate) self.calSelectedDate = [NSDate new];

    // If self.calSelectedDate is today, the initialStart is set to
    // the next whole hour. Otherwise, 8am of self.calselectedDate.
    // Default duration is same as setting in Calendar.app.
    NSDate *initialStart, *initialEnd, *today = [NSDate new];
    if ([self.cal isDate:self.calSelectedDate inSameDayAsDate:today]) {
        NSInteger hour;
        [self.cal getHour:&hour minute:NULL second:NULL nanosecond:NULL fromDate:today];
        hour = (hour == 23) ? 0 : hour+1;
        initialStart = [self.cal nextDateAfterDate:today matchingUnit:NSCalendarUnitHour value:hour options:NSCalendarMatchNextTimePreservingSmallerUnits];
    }
    else {
        initialStart = [self.cal dateBySettingHour:8 minute:0 second:0 ofDate:self.calSelectedDate options:0];
    }
    NSInteger newEventDuration = [self defaultDurationInMinutesForNewEvent];
    initialEnd = [self.cal dateByAddingUnit:NSCalendarUnitMinute
                                      value:newEventDuration
                                     toDate:initialStart
                                    options:0];
    
    _defaultStart = initialStart;
    _defaultEnd = initialEnd;
    [self populateTimeZonePopup];
    [self selectTimeZone:[NSTimeZone localTimeZone]];
    _tzPopup.enabled = YES;
    _suggestions.query = nil;

    // Initial values for form fields.
    _title.stringValue = @"";
    _location.stringValue = @"";
    _url.stringValue = @"";
    _notes.string = @"";
    _allDayCheckbox.state = NSControlStateValueOff;
    _startDate.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
    _endDate.datePickerElements   = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
    _startDate.dateValue = initialStart;
    _endDate.minDate     = initialStart; // !! Must set minDate before dateValue !!
    _endDate.dateValue   = initialEnd;
    _repEndDate.minDate  = initialStart;
    _repEndDate.dateValue = initialEnd;
    [_repPopup selectItemAtIndex:0];     // 'None' selected
    [_repEndPopup selectItemAtIndex:0];  // 'Never' selected
    [self updateRepeatRows];
    [_alertPopup selectItemAtIndex:0];   // 'None' selected
    _saveButton.enabled  = NO;
    
    // Function to make colored dots for calendar popup.
    NSImage* (^coloredDot)(NSColor *) = ^NSImage* (NSColor *color) {
        return [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
            [color set];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, 8, 8)] fill];
            return YES;
        }];
    };
    
    // Populate calendar popup.
    NSString *defaultCalendarIdentifier = [self.ec defaultCalendarIdentifier];
    NSArray *sourcesAndCalendars = [self.ec sourcesAndCalendars];
    EKSource *currentSource = nil;
    [_calPopup.menu removeAllItems];
    for (id obj in sourcesAndCalendars) {
        if ([obj isKindOfClass:[NSString class]]) continue; // Skip Sources
        CalendarInfo *calInfo = obj;
        // Only add menu items for calendars that can be modified
        // and hold events (not reminder lists).
        if (calInfo.calendar.allowsContentModifications &&
            (calInfo.calendar.allowedEntityTypes & EKEntityMaskEvent)) {
            // Add a Source item to the menu if necessary.
            if (![calInfo.calendar.source isEqualTo:currentSource]) {
                if (_calPopup.menu.itemArray.count != 0) {
                    [_calPopup.menu addItem:[NSMenuItem separatorItem]];
                }
                NSMenuItem *sourceItem = [NSMenuItem new];
                // MacOS 13 sometimes returns nil for non-iCloud source titles.
                sourceItem.title   = calInfo.calendar.source.title ?: @"???";
                sourceItem.enabled = NO;
                [_calPopup.menu addItem:sourceItem];
                currentSource = calInfo.calendar.source;
            }
            NSMenuItem *calItem = [NSMenuItem new];
            calItem.title = calInfo.calendar.title;
            calItem.image = coloredDot(calInfo.calendar.color);
            calItem.tag   = [sourcesAndCalendars indexOfObject:obj];
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 270000
            calItem.preferredImageVisibility = NSMenuItemImageVisibilityVisible;
#endif
            [_calPopup.menu addItem:calItem];
            if ([calInfo.calendar.calendarIdentifier isEqualToString:defaultCalendarIdentifier]) {
                [_calPopup selectItemWithTag:calItem.tag];
            }
        }
    }
    
    // Populate alert popup AFTER calendar popup since its
    // contents depends on which calendar is selected.
    [self populateAlertPopup];
    [self updateCalendarButton];
}

- (NSInteger)defaultDurationInMinutesForNewEvent {
    NSUserDefaults *calendarDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.iCal"];
    NSNumber *durationMinutes = [calendarDefaults objectForKey:@"Default duration in minutes for new event"];

    // Check if the value was found.
    if (durationMinutes != nil) {
        return [durationMinutes longValue];
    }
    // Return the system default (60 minutes) if the
    // setting isn't explicitly defined.
    return 60;
}

- (void)cancelOperation:(id)sender
{
    // User hit 'esc' or pressed Cancel button.
    if (self.embedded) {
        if (self.onCollapse) self.onCollapse();
        return;
    }
    [self.enclosingPopover close];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
    // Enable the Save button if the title is non-whitespace.
    NSString *trimmedTitle = [_title.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _saveButton.enabled = ![trimmedTitle isEqualToString:@""];

    // Suggest places as the user types a location.
    if (obj.object == _location) {
        _suggestions.query = _location.stringValue;
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)obj
{
    if (obj.object == _location) [_suggestions dismiss];
}

- (void)dismissSuggestions
{
    [_suggestions dismiss];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    // Arrow keys, Return and Esc work the place suggestions
    // while they are showing.
    if (control != _location || !_suggestions.hasSuggestions) return NO;
    if (commandSelector == @selector(moveDown:)) return [_suggestions moveHighlightBy:1];
    if (commandSelector == @selector(moveUp:)) return [_suggestions moveHighlightBy:-1];
    if (commandSelector == @selector(insertNewline:)) return [_suggestions acceptHighlighted];
    if (commandSelector == @selector(cancelOperation:)) {
        [_suggestions dismiss];
        return YES;
    }
    return NO;
}

- (void)allDayClicked:(NSButton *)allDayCheckbox
{
    // The All-day checkbox toggles the hour/minute controls of the date pickers.
    if (allDayCheckbox.state == NSControlStateValueOn) {
        _startDate.datePickerElements = NSDatePickerElementFlagYearMonthDay;
        _endDate.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    }
    else {
        _startDate.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
        _endDate.datePickerElements = NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute;
    }
    
    // All-day events have no time zone.
    _tzPopup.enabled = allDayCheckbox.state != NSControlStateValueOn;

    // All-day events have different alert options from regular events.
    [self populateAlertPopup];
}

- (void)startDateChanged:(NSDatePicker *)startPicker
{
    // Make sure endDate is never before startDate.
    // Make sure repeatEndDate is never before endDate.
    // Default duration is same as setting in Calendar.app.
    NSInteger newEventDuration = [self defaultDurationInMinutesForNewEvent];
    _endDate.minDate    = _startDate.dateValue;
    _repEndDate.minDate = _startDate.dateValue;
    _endDate.dateValue = [self.cal dateByAddingUnit:NSCalendarUnitMinute
                                              value:newEventDuration
                                             toDate:_startDate.dateValue
                                            options:0];
}

- (void)repPopupChanged:(id)sender
{
    if ([_repPopup indexOfItem:_repPopup.selectedItem] == 0) {
        [_repEndPopup selectItemAtIndex:0];
    }
    [self updateRepeatRows];
}

- (void)repEndPopupChanged:(id)sender
{
    [self updateRepeatRows];
}

- (void)updateRepeatRows
{
    BOOL repeats = [_repPopup indexOfItem:_repPopup.selectedItem] != 0;
    BOOL endsOnDate = repeats && [_repEndPopup indexOfItem:_repEndPopup.selectedItem] != 0;
    _repEndLabel.hidden = !repeats;
    _repEndPopup.hidden = !repeats;
    _repEndDate.hidden  = !endsOnDate;
    [NSLayoutConstraint deactivateConstraints:repeats ? _noRepEndRowConstraints : _repEndRowConstraints];
    [NSLayoutConstraint activateConstraints:repeats ? _repEndRowConstraints : _noRepEndRowConstraints];
    for (NSLayoutConstraint *constraint in _repEndDateConstraints) {
        constraint.active = endsOnDate;
    }
    if (self.onLayoutChange) self.onLayoutChange();
}

#pragma mark -
#pragma mark Size preference

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)sizeChanged:(id)sender
{
    [self applySizePreference];
}

// The embedded form uses the same type scale as the rest of the
// window: fontSize for everything, calendarTitleFontSize for the title.
- (void)applySizePreference
{
    if (!self.embedded) return;
    NSControlSize controlSize = SizePref.sizePreference == SizePreferenceSmall ? NSControlSizeSmall
                              : SizePref.sizePreference == SizePreferenceLarge ? NSControlSizeLarge
                              : NSControlSizeRegular;
    NSFont *font = [NSFont systemFontOfSize:SizePref.fontSize];
    for (NSControl *control in _sizedControls) {
        control.controlSize = controlSize;
        control.font = font;
    }
    _title.font = [NSFont systemFontOfSize:SizePref.calendarTitleFontSize weight:NSFontWeightMedium];
    _calButton.font = font;

    // The pickers reserve a fixed width for each number. With
    // proportional digits, narrow ones like 11 leave a gap: "12/ 11/2026".
    NSFont *digitsFont = [NSFont monospacedDigitSystemFontOfSize:SizePref.fontSize weight:NSFontWeightRegular];
    for (NSDatePicker *picker in @[_startDate, _endDate, _repEndDate]) {
        picker.font = digitsFont;
    }

    // Rows, and dates lined up with the popups' titles.
    CGFloat rowPitch = SizePref.sizePreference == SizePreferenceSmall ? 24 : SizePref.sizePreference == SizePreferenceLarge ? 32 : 28;
    for (NSLayoutConstraint *constraint in _rowPitchConstraints) {
        constraint.constant = rowPitch;
    }
    CGFloat dateInset = SizePref.sizePreference == SizePreferenceSmall ? 7 : SizePref.sizePreference == SizePreferenceLarge ? 10 : 9;
    for (NSLayoutConstraint *constraint in _dateInsetConstraints) {
        constraint.constant = dateInset;
    }

    // All placeholders look alike.
    NSDictionary *placeholderAttributes = @{NSFontAttributeName: font, NSForegroundColorAttributeName: Theme.placeholderColor};
    NSDictionary *titleAttributes = @{NSFontAttributeName: _title.font, NSForegroundColorAttributeName: Theme.placeholderColor};
    // A plain placeholder string would be drawn instead.
    _title.placeholderString = nil;
    _location.placeholderString = nil;
    _url.placeholderString = nil;
    _title.placeholderAttributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"New Event", @"") attributes:titleAttributes];
    _location.placeholderAttributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Add Location or Video Call", @"") attributes:placeholderAttributes];
    _url.placeholderAttributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Add URL", @"") attributes:placeholderAttributes];
    _notes.font = font;
    _notes.placeholderAttributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Add Notes", @"") attributes:placeholderAttributes];
    _notesHeightOfOneLine = ceil([[NSLayoutManager new] defaultLineHeightForFont:font]);
    _notesScrollViewHeightConstraint.constant = _notesHeightOfOneLine;
    [self textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:_notes]];
    _notes.needsDisplay = YES;

    if (_collapseButton) {
        NSButton *collapse = _collapseButton;
        collapse.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:SizePref.fontSize - 2 weight:NSFontWeightSemibold];
    }
    if (self.onLayoutChange) self.onLayoutChange();
}

- (void)calPopupChanged:(id)sender
{
    // Different calendars have different alert options.
    [self populateAlertPopup];
    [self updateCalendarButton];
}

- (void)updateCalendarButton
{
    NSColor *color = self.summaryCalendarColor ?: NSColor.secondaryLabelColor;
    _calButton.title = self.summaryCalendarTitle ?: @"";
    _calButton.image = [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [color set];
        [[NSBezierPath bezierPathWithOvalInRect:dstRect] fill];
        return YES;
    }];
}

- (void)showCalendarMenu:(id)sender
{
    NSMenu *menu = [self calendarMenuWithTarget:self action:@selector(calendarChosen:)];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(_calButton.bounds) + 4) inView:_calButton];
}

- (void)calendarChosen:(NSMenuItem *)item
{
    [self selectCalendarWithTag:item.tag];
}

- (void)populateAlertPopup
{
    [_alertPopup removeAllItems];
    
    NSInteger numOffsets = 0;
    const NSTimeInterval *offsets = nil;

    if (_allDayCheckbox.state == NSControlStateValueOn) {
        [_alertPopup addItemsWithTitles:_alertAllDayStrings];
        numOffsets = kAlertAllDayNumOffsets;
        offsets = kAlertAllDayRelativeOffsets;
    } else {
        [_alertPopup addItemsWithTitles:_alertRegularStrings];
        numOffsets = kAlertRegularNumOffsets;
        offsets = kAlertRegularRelativeOffsets;
    }

    [_alertPopup selectItemAtIndex:0];

    // Get the selected calendar.
    // No calendar to ask (e.g. calendar access not granted yet).
    CalendarInfo *calInfo = [self selectedCalendarInfo];
    if (!calInfo) return;

    // Make a dummy event for the selected calendar in order to get
    // the default alert time offset.
    EKEvent *dummyEvent  = [self.ec newEvent];
    dummyEvent.calendar  = calInfo.calendar;
    dummyEvent.allDay    = _allDayCheckbox.state == NSControlStateValueOn;

    // If the dummy event has an alert, try to set it as the default.
    if (dummyEvent.alarms.count > 0) {
        for (NSInteger i = 0; i < numOffsets; i++) {
            if (dummyEvent.alarms.firstObject.relativeOffset == offsets[i]) {
                [_alertPopup selectItemAtIndex:i];
                break;
            }
        }
    }
}

- (void)saveEvent:(id)sender
{
    // Set startDate and endDate.
    NSDate *startDate = _startDate.dateValue;
    NSDate *endDate   = _endDate.dateValue;
    
    // Get the calendar.
    CalendarInfo *calInfo = [self selectedCalendarInfo];
    if (!calInfo) {
        NSBeep();
        return;
    }

    // Create the event.
    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    EKEvent *event  = [self.ec newEvent];
    event.title     = [_title.stringValue stringByTrimmingCharactersInSet:whitespaceSet];
    event.location  = [_location.stringValue stringByTrimmingCharactersInSet:whitespaceSet];
    event.URL       = [NSURL URLWithString:[_url.stringValue stringByTrimmingCharactersInSet:whitespaceSet]];
    event.allDay    = _allDayCheckbox.state == NSControlStateValueOn;
    event.startDate = startDate;
    event.endDate   = endDate;
    event.calendar  = calInfo.calendar;
    NSString *notes = [_notes.string stringByTrimmingCharactersInSet:whitespaceSet];
    if (![notes isEqualToString:@""]) {
        event.notes = notes;
    }
    // !Important! timeZone MUST be nil if it is an allDay event.
    // If you set timeZone after setting allDay, the start and end dates
    // will be wrong and it won't be an allDay event anymore.
    // Alternatively, we could have set timeZone before setting allDay
    // because setting allDay == YES sets timeZone to nil.
    event.timeZone  = event.isAllDay ? nil : (_timeZone ?: [NSTimeZone localTimeZone]);
    
    // Recurrence rule.
    EKRecurrenceFrequency frequency;
    NSInteger interval = 1;
    NSInteger repIndex = [_repPopup indexOfItem:_repPopup.selectedItem];
    switch (repIndex) {
        case 1: // Every Day
            frequency = EKRecurrenceFrequencyDaily;
            break;
        case 2: // Every Week
            frequency = EKRecurrenceFrequencyWeekly;
            break;
        case 3: // Every 2 Weeks
            frequency = EKRecurrenceFrequencyWeekly;
            interval  = 2;
            break;
        case 4: // Every Month
            frequency = EKRecurrenceFrequencyMonthly;
            break;
        case 5: // Every Year
            frequency = EKRecurrenceFrequencyYearly;
            break;
        default:
            frequency = EKRecurrenceFrequencyDaily;
            break;
    }
    EKRecurrenceEnd  *recurrenceEnd = nil;
    NSInteger repEndIndex = [_repEndPopup indexOfItem:_repEndPopup.selectedItem];
    if (repEndIndex != 0) {
        recurrenceEnd = [EKRecurrenceEnd recurrenceEndWithEndDate:_repEndDate.dateValue];
    }
    EKRecurrenceRule *recurrence = nil;
    if (repIndex != 0) {
        recurrence = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:frequency interval:interval end:recurrenceEnd];
    }
    if (recurrence != nil) {
        event.recurrenceRules = @[recurrence];
    }
    
    // Remove default alert(s) set on this event. We only add the
    // alert the user has selected - which may be the default alert
    // since we tried to set it in -populateAlertPopup. This avoids
    // having the default alert set twice.
    for (EKAlarm *alarm in event.alarms) {
        [event removeAlarm:alarm];
    }
    // Set the alert that was selected in the alert popup.
    NSInteger alertIndex = [_alertPopup indexOfItem:_alertPopup.selectedItem];
    if (alertIndex > 0) { // 0 == no alert
        NSTimeInterval offset = MAXFLOAT;
        if (event.isAllDay && alertIndex < kAlertAllDayNumOffsets) {
            offset = kAlertAllDayRelativeOffsets[alertIndex];
        }
        else if (!event.isAllDay && alertIndex < kAlertRegularNumOffsets) {
            offset = kAlertRegularRelativeOffsets[alertIndex];
        }
        if (offset != MAXFLOAT) {
            [event addAlarm:[EKAlarm alarmWithRelativeOffset:offset]];
        }
    }
    
    // Commit the event.
    NSError *error = NULL;
    BOOL saved = [self.ec saveNewEvent:event undoManager:self.eventUndoManager error:&error];
    if (saved == NO && error != nil) {
        [[NSAlert alertWithError:error] runModal];
    }
    else if (self.embedded) {
        if (self.onSaved) self.onSaved();
    }
    else {
        [self.enclosingPopover close];
    }
}

#pragma mark -
#pragma mark Time zone

static NSString *TimeZoneTitle(NSTimeZone *tz)
{
    NSString *city = [[tz.name lastPathComponent] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    NSString *abbreviation = ShortTimeZoneName(tz, [NSDate new]);
    return abbreviation.length ? [NSString stringWithFormat:@"%@ (%@)", city, abbreviation] : city;
}

static NSMenuItem *TimeZoneMenuItem(NSTimeZone *tz)
{
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:TimeZoneTitle(tz) action:NULL keyEquivalent:@""];
    item.representedObject = tz;
    return item;
}

- (void)populateTimeZonePopup
{
    // The Mac's time zone first, then a short list of others.
    // A zone named in the quick entry field is added on demand.
    [_tzPopup removeAllItems];
    NSString *local = [NSTimeZone localTimeZone].name;
    [_tzPopup.menu addItem:TimeZoneMenuItem([NSTimeZone localTimeZone])];
    [_tzPopup.menu addItem:[NSMenuItem separatorItem]];
    for (NSString *name in @[@"Pacific/Honolulu", @"America/Anchorage", @"America/Los_Angeles",
                             @"America/Denver", @"America/Chicago", @"America/New_York",
                             @"America/Sao_Paulo", @"Atlantic/Reykjavik", @"Europe/London",
                             @"Europe/Berlin", @"Europe/Athens", @"Europe/Istanbul",
                             @"Asia/Dubai", @"Asia/Kolkata", @"Asia/Bangkok", @"Asia/Singapore",
                             @"Asia/Tokyo", @"Australia/Sydney", @"Pacific/Auckland"]) {
        NSTimeZone *tz = [NSTimeZone timeZoneWithName:name];
        if (tz && ![name isEqualToString:local]) {
            [_tzPopup.menu addItem:TimeZoneMenuItem(tz)];
        }
    }
}

// Show tz in the popup (adding it if it isn't listed) and have
// the date pickers show their dates in it.
- (void)selectTimeZone:(NSTimeZone *)tz
{
    NSMenuItem *found = nil;
    for (NSMenuItem *item in _tzPopup.menu.itemArray) {
        NSTimeZone *itemTZ = item.representedObject;
        if ([itemTZ.name isEqualToString:tz.name]) {
            found = item;
            break;
        }
    }
    if (!found) {
        found = TimeZoneMenuItem(tz);
        [_tzPopup.menu insertItem:found atIndex:MIN(2, _tzPopup.menu.numberOfItems)];
    }
    [_tzPopup selectItem:found];
    _timeZone = tz;
    for (NSDatePicker *picker in @[_startDate, _endDate, _repEndDate]) {
        picker.timeZone = tz;
    }
}

- (void)tzPopupChanged:(id)sender
{
    NSTimeZone *newTZ = _tzPopup.selectedItem.representedObject;
    if (!newTZ) return;
    // Keep the clock time the pickers show, as Calendar does:
    // 4 PM in New York becomes 4 PM in Tokyo.
    NSTimeZone *oldTZ = _timeZone ?: [NSTimeZone localTimeZone];
    NSCalendar *oldCal = [self.cal copy] ?: [NSCalendar currentCalendar];
    NSCalendar *newCal = [oldCal copy];
    oldCal.timeZone = oldTZ;
    newCal.timeZone = newTZ;
    NSCalendarUnit units = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute;
    NSDate *start = [newCal dateFromComponents:[oldCal components:units fromDate:_startDate.dateValue]];
    NSDate *end   = [newCal dateFromComponents:[oldCal components:units fromDate:_endDate.dateValue]];
    [self selectTimeZone:newTZ];
    _startDate.dateValue = start;
    _endDate.minDate     = start; // !! Must set minDate before dateValue !!
    _endDate.dateValue   = end;
    _repEndDate.minDate  = start;
}

#pragma mark -
#pragma mark Quick entry (embedded form)

- (void)applyDraft:(NLEventDraft *)draft location:(NSString *)location
{
    (void)self.view;
    _title.stringValue = draft.title ?: @"";
    _location.stringValue = location ?: @"";

    BOOL allDay = draft.startDate != nil && draft.allDay;
    BOOL wasAllDay = _allDayCheckbox.state == NSControlStateValueOn;
    if (allDay != wasAllDay) {
        _allDayCheckbox.state = allDay ? NSControlStateValueOn : NSControlStateValueOff;
        [self allDayClicked:_allDayCheckbox];
    }

    NSTimeZone *tz = (!allDay && draft.timeZone) ? draft.timeZone : [NSTimeZone localTimeZone];
    if (![tz.name isEqualToString:_timeZone.name]) {
        [self selectTimeZone:tz];
    }

    NSDate *start = draft.startDate ?: _defaultStart;
    NSDate *end   = draft.startDate ? draft.endDate : _defaultEnd;
    if (start && end) {
        _startDate.dateValue = start;
        _endDate.minDate     = start; // !! Must set minDate before dateValue !!
        _endDate.dateValue   = end;
        _repEndDate.minDate  = start;
    }

    NSString *trimmedTitle = [_title.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _saveButton.enabled = trimmedTitle.length > 0;
}

- (void)focusFirstField
{
    [self.view.window makeFirstResponder:_title];
}

- (BOOL)canSave { return _saveButton.enabled; }
- (NSString *)summaryTitle { return _title.stringValue; }
- (NSString *)summaryLocation { return _location.stringValue; }
- (NSDate *)summaryStart { return _startDate.dateValue; }
- (NSDate *)summaryEnd { return _endDate.dateValue; }
- (BOOL)summaryAllDay { return _allDayCheckbox.state == NSControlStateValueOn; }

- (NSTimeZone *)summaryTimeZone
{
    if (self.summaryAllDay || !_timeZone) return nil;
    return [_timeZone.name isEqualToString:[NSTimeZone localTimeZone].name] ? nil : _timeZone;
}

- (CalendarInfo *)selectedCalendarInfo
{
    NSMenuItem *item = _calPopup.selectedItem;
    NSArray *sourcesAndCalendars = [self.ec sourcesAndCalendars];
    if (!item || item.tag < 0 || item.tag >= (NSInteger)sourcesAndCalendars.count) return nil;
    id obj = sourcesAndCalendars[item.tag];
    return [obj isKindOfClass:[CalendarInfo class]] ? obj : nil;
}

- (NSString *)summaryCalendarTitle { return [self selectedCalendarInfo].calendar.title; }
- (NSColor *)summaryCalendarColor { return [self selectedCalendarInfo].calendar.color; }

- (NSMenu *)calendarMenuWithTarget:(id)target action:(SEL)action
{
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    for (NSMenuItem *item in _calPopup.menu.itemArray) {
        NSMenuItem *copy = [item copy];
        if (!copy.isSeparatorItem && copy.enabled) {
            // A calendar (source names are disabled items).
            copy.target = target;
            copy.action = action;
            copy.state = item == _calPopup.selectedItem ? NSControlStateValueOn : NSControlStateValueOff;
        }
        [menu addItem:copy];
    }
    return menu;
}

- (void)selectCalendarWithTag:(NSInteger)tag
{
    [_calPopup selectItemWithTag:tag];
    [self calPopupChanged:_calPopup];
}

#pragma mark -
#pragma mark NSTextViewDelegate

- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector
{
    // _notes textview handles Tab/Backtab like other controls
    // by navigating to next/previous control.
    // https://stackoverflow.com/a/2485987/111418
    if (aTextView != _notes) return NO;
    if (aSelector == @selector(insertTab:)) {
        [_notes.window makeFirstResponder:_url];
        return YES;
    }
    else if (aSelector == @selector(insertBacktab:)) {
        [_notes.window makeFirstResponder:_alertPopup];
        return YES;
    }
    return NO;
}

- (void)textDidChange:(NSNotification *)notification
{
    if (notification.object != _notes) return;

    // _notesScrollView will grow to at most this many lines
    // after which it will scroll.
    NSInteger maxVisibleLines = 16;

    // Get height of text in _notes
    [_notes.layoutManager ensureLayoutForTextContainer:_notes.textContainer];
    CGFloat height = [_notes.layoutManager usedRectForTextContainer:_notes.textContainer].size.height;
    
    // Grow _notesScrollView to at most maxVisibleLines * _notesHeightOfOneLine
    height = MAX(MIN(height, maxVisibleLines * _notesHeightOfOneLine), _notesHeightOfOneLine);
    _notesScrollViewHeightConstraint.constant = height;
    
    // Get number of lines in _notes
    // https://macosx-dev.omnigroup.narkive.com/RH9lsO7P/number-of-lines-in-nstextview#post2
    NSInteger numberOfLines, idx, numberOfGlyphs = [_notes.layoutManager numberOfGlyphs];
    NSRange lineRange;
    for (numberOfLines = 0, idx = 0; idx < numberOfGlyphs; numberOfLines++) {
        (void)[_notes.layoutManager lineFragmentRectForGlyphAtIndex:idx effectiveRange:&lineRange];
        idx = NSMaxRange(lineRange);
    }
    
    // Elasticity and a scroller only if not all lines are visible.
    // Not autohiding: it would show the scroller for a moment each
    // time _notes grows, before _notesScrollView does. The scroller
    // changes the text's width, so measure again when it changes.
    BOOL scrolls = numberOfLines > maxVisibleLines;
    _notesScrollView.verticalScrollElasticity = scrolls ? NSScrollElasticityAutomatic : NSScrollElasticityNone;
    if (_notesScrollView.hasVerticalScroller != scrolls) {
        _notesScrollView.hasVerticalScroller = scrolls;
        [self textDidChange:notification];
    }
}

@end
