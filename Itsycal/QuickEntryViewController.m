//
//  QuickEntryViewController.m
//  Spidercal
//

#import "QuickEntryViewController.h"
#import "EventViewController.h"
#import "EventCenter.h"
#import "NLEventParser.h"
#import "LocationSuggestionsView.h"
#import "Themer.h"
#import "Sizer.h"

static const CGFloat kSideMargin = 8;
static const CGFloat kPillGap = 6;
static const CGFloat kPillPadding = 5;   // above and below the text
static const CGFloat kSwapDuration = 0.18;

#pragma mark -
#pragma mark QEPill

// A rounded, filled field background. Collapsed, it is a square
// button showing only its icon.
@interface QEPill : NSView
@property (nonatomic) BOOL collapsed;
@property (nonatomic, copy) void (^onClick)(void);
@end

@implementation QEPill

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;
        self.layer.masksToBounds = YES;
    }
    return self;
}

- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateLayer
{
    self.layer.backgroundColor = Theme.pendingBackgroundColor.CGColor;
}

- (NSView *)hitTest:(NSPoint)point
{
    NSView *hit = [super hitTest:point];
    if (!hit) return nil;
    // Collapsed, the whole pill is a button. Expanded, so is its icon.
    if (self.collapsed || [hit isKindOfClass:[NSImageView class]]) return self;
    return hit;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }

- (void)mouseDown:(NSEvent *)event
{
    if (self.onClick) self.onClick();
}

@end

#pragma mark -
#pragma mark QETextView

// The New Event field: a text view so long entries wrap.
@interface QETextView : NSTextView
@property (nonatomic, copy) NSString *placeholder;
// Called with an arrow key pressed while the field is empty.
@property (nonatomic, copy) void (^onNavigationKey)(NSEvent *event);
@end

@implementation QETextView

- (BOOL)becomeFirstResponder
{
    // An empty NSTextView gets focus but shows no cursor.
    // See HackyTextView in EventViewController.m.
    BOOL result = [super becomeFirstResponder];
    if (result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.string.length) {
                self.string = @" ";
                self.string = @"";
            }
            self.needsDisplay = YES;
        });
    }
    return result;
}

- (BOOL)resignFirstResponder
{
    self.needsDisplay = YES;
    return [super resignFirstResponder];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if (self.string.length == 0 && self.placeholder.length) {
        NSDictionary *attrs = @{NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:13],
                                NSForegroundColorAttributeName: Theme.placeholderColor};
        NSPoint origin = self.textContainerOrigin;
        origin.x += self.textContainer.lineFragmentPadding;
        [self.placeholder drawAtPoint:origin withAttributes:attrs];
    }
}

- (void)keyDown:(NSEvent *)event
{
    if (self.string.length == 0 && self.onNavigationKey && event.charactersIgnoringModifiers.length == 1) {
        unichar key = [event.charactersIgnoringModifiers characterAtIndex:0];
        if (key == NSUpArrowFunctionKey || key == NSDownArrowFunctionKey ||
            key == NSLeftArrowFunctionKey || key == NSRightArrowFunctionKey ||
            key == NSPageUpFunctionKey || key == NSPageDownFunctionKey) {
            self.onNavigationKey(event);
            return;
        }
    }
    // ⌘N, ⌘F and ⌘, are the window's shortcuts, not text editing.
    NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    if ((flags & NSEventModifierFlagCommand) && !(flags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl)) &&
        [@[@"n", @"f", @","] containsObject:event.charactersIgnoringModifiers ?: @""]) {
        [self.nextResponder keyDown:event];
        return;
    }
    [super keyDown:event];
}

@end

#pragma mark -
#pragma mark QuickEntryViewController

@interface QuickEntryViewController () <NSTextViewDelegate, NSTextFieldDelegate>
@end

@implementation QuickEntryViewController
{
    // Top row
    QEPill *_entryPill, *_searchPill;
    QETextView *_entry;
    NSTextField *_searchField;
    NSButton *_btnClearSearch;
    NSImageView *_plusIcon, *_glassIcon;
    NSLayoutConstraint *_entryCollapsedWidth, *_searchCollapsedWidth;
    NSLayoutConstraint *_entryHeight, *_searchHeight;
    NSLayoutConstraint *_plusX, *_plusY, *_glassX, *_glassY, *_entryLeading, *_searchLeading;
    CGFloat _lineHeight;
    NSLayoutConstraint *_formWidth; // only while the form is showing

    // Under the top row
    LocationSuggestionsView *_suggestions;
    NSView *_summary;
    NSTextField *_sumTitle, *_sumLocation, *_sumDate;
    NSButton *_btnExpand, *_btnCalendar, *_btnSave;
    EventViewController *_eventVC;
    NSBox *_separator;

    // State
    BOOL _searching;
    BOOL _draftActive;
    BOOL _expanded;
    NSRange _locationRange;        // the place's name in _entry
    NSString *_chosenName;         // a picked suggestion's name...
    NSString *_chosenLocation;     // ...and its name and address
    NSDate *_lastShownDate;
}

- (BOOL)isSearching { return _searching; }

#pragma mark View lifecycle

- (void)loadView
{
    NSView *v = [NSView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;

    NSFont *font = [NSFont systemFontOfSize:SizePref.fontSize];
    _lineHeight = ceil([[NSLayoutManager new] defaultLineHeightForFont:font]);
    _locationRange = NSMakeRange(NSNotFound, 0);

    NSImageView* (^icon)(NSString *) = ^NSImageView* (NSString *symbol) {
        NSImageView *iv = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
        iv.contentTintColor = Theme.buttonTintColor;
        iv.translatesAutoresizingMaskIntoConstraints = NO;
        return iv;
    };

    __weak typeof(self) weakSelf = self;

    // ---- New Event pill
    _entryPill = [QEPill new];
    _entryPill.onClick = ^{ [weakSelf focusEntry]; };
    _entryPill.toolTip = NSLocalizedString(@"New Event", @"");
    _plusIcon = icon(@"plus");
    [_entryPill addSubview:_plusIcon];

    _entry = [[QETextView alloc] initWithFrame:NSMakeRect(0, 0, 100, _lineHeight)];
    _entry.translatesAutoresizingMaskIntoConstraints = NO;
    _entry.delegate = self;
    _entry.placeholder = NSLocalizedString(@"New Event", @"");
    _entry.font = font;
    _entry.textColor = Theme.monthTextColor;
    _entry.richText = NO;
    _entry.importsGraphics = NO;
    _entry.allowsUndo = YES;
    _entry.drawsBackground = NO;
    _entry.focusRingType = NSFocusRingTypeNone;
    _entry.textContainerInset = NSZeroSize;
    _entry.textContainer.lineFragmentPadding = 0;
    _entry.textContainer.widthTracksTextView = YES;
    _entry.verticallyResizable = NO;
    _entry.horizontallyResizable = NO;
    _entry.automaticQuoteSubstitutionEnabled = NO;
    _entry.automaticDashSubstitutionEnabled = NO;
    _entry.automaticTextReplacementEnabled = NO;
    _entry.automaticSpellingCorrectionEnabled = NO;
    _entry.continuousSpellCheckingEnabled = NO;
    _entry.onNavigationKey = ^(NSEvent *event) {
        [weakSelf.delegate quickEntryForwardKeyDown:event];
    };
    [_entryPill addSubview:_entry];

    // ---- Search pill
    _searchPill = [QEPill new];
    _searchPill.collapsed = YES;
    _searchPill.onClick = ^{ [weakSelf focusSearch]; };
    _searchPill.toolTip = NSLocalizedString(@"Search", @"");
    _glassIcon = icon(@"magnifyingglass");
    [_searchPill addSubview:_glassIcon];

    _searchField = [NSTextField textFieldWithString:@""];
    _searchField.translatesAutoresizingMaskIntoConstraints = NO;
    _searchField.font = font;
    _searchField.bezeled = NO;
    _searchField.drawsBackground = NO;
    _searchField.focusRingType = NSFocusRingTypeNone;
    _searchField.usesSingleLineMode = YES;
    _searchField.lineBreakMode = NSLineBreakByTruncatingTail;
    _searchField.delegate = self;
    _searchField.hidden = YES;
    [_searchField setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_searchPill addSubview:_searchField];

    _btnClearSearch = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:NSLocalizedString(@"Clear", @"")] target:self action:@selector(clearSearch:)];
    _btnClearSearch.translatesAutoresizingMaskIntoConstraints = NO;
    _btnClearSearch.bordered = NO;
    _btnClearSearch.contentTintColor = Theme.buttonTintColor;
    _btnClearSearch.hidden = YES;
    _btnClearSearch.refusesFirstResponder = YES;
    [_searchPill addSubview:_btnClearSearch];

    // ---- Top row
    NSView *topRow = [NSView new];
    topRow.translatesAutoresizingMaskIntoConstraints = NO;
    [topRow addSubview:_entryPill];
    [topRow addSubview:_searchPill];

    // Constants are set in -applySizePreference.
    _entryCollapsedWidth = [_entryPill.widthAnchor constraintEqualToConstant:0];
    _searchCollapsedWidth = [_searchPill.widthAnchor constraintEqualToConstant:0];
    _entryHeight = [_entry.heightAnchor constraintEqualToConstant:_lineHeight];
    _searchHeight = [_searchPill.heightAnchor constraintEqualToConstant:0];
    _plusX = [_plusIcon.centerXAnchor constraintEqualToAnchor:_entryPill.leadingAnchor];
    _plusY = [_plusIcon.centerYAnchor constraintEqualToAnchor:_entryPill.topAnchor];
    _glassX = [_glassIcon.centerXAnchor constraintEqualToAnchor:_searchPill.leadingAnchor];
    _glassY = [_glassIcon.centerYAnchor constraintEqualToAnchor:_searchPill.topAnchor];
    _entryLeading = [_entry.leadingAnchor constraintEqualToAnchor:_entryPill.leadingAnchor];
    _searchLeading = [_searchField.leadingAnchor constraintEqualToAnchor:_searchPill.leadingAnchor];

    // Text and field give way while their pill is collapsed.
    NSLayoutConstraint *entryTrailing = [_entry.trailingAnchor constraintEqualToAnchor:_entryPill.trailingAnchor constant:-7];
    entryTrailing.priority = 750;
    NSLayoutConstraint *clearTrailing = [_btnClearSearch.trailingAnchor constraintEqualToAnchor:_searchPill.trailingAnchor constant:-6];
    clearTrailing.priority = 750;
    NSLayoutConstraint *searchFieldTrailing = [_searchField.trailingAnchor constraintEqualToAnchor:_btnClearSearch.leadingAnchor constant:-4];
    searchFieldTrailing.priority = 750;
    NSLayoutConstraint *rowBottom = [topRow.bottomAnchor constraintEqualToAnchor:_entryPill.bottomAnchor];

    [NSLayoutConstraint activateConstraints:@[
        // Row: [entry pill]-[search pill]
        [_entryPill.leadingAnchor constraintEqualToAnchor:topRow.leadingAnchor constant:kSideMargin],
        [_searchPill.leadingAnchor constraintEqualToAnchor:_entryPill.trailingAnchor constant:kPillGap],
        [_searchPill.trailingAnchor constraintEqualToAnchor:topRow.trailingAnchor constant:-kSideMargin],
        [_entryPill.topAnchor constraintEqualToAnchor:topRow.topAnchor],
        [_searchPill.topAnchor constraintEqualToAnchor:topRow.topAnchor],
        rowBottom,
        _searchCollapsedWidth,
        // The search pill is always one line high.
        _searchHeight,
        // Entry pill: [+] text
        _plusX, _plusY, _entryLeading,
        entryTrailing,
        [_entry.topAnchor constraintEqualToAnchor:_entryPill.topAnchor constant:kPillPadding],
        [_entry.bottomAnchor constraintEqualToAnchor:_entryPill.bottomAnchor constant:-kPillPadding],
        _entryHeight,
        // Search pill: [glass] field [x]
        _glassX, _glassY, _searchLeading,
        searchFieldTrailing,
        [_searchField.centerYAnchor constraintEqualToAnchor:_searchPill.centerYAnchor],
        clearTrailing,
        [_btnClearSearch.centerYAnchor constraintEqualToAnchor:_searchPill.centerYAnchor],
    ]];

    // ---- Place suggestions for the New Event field
    _suggestions = [LocationSuggestionsView new];
    _suggestions.onSelect = ^(NSString *name, NSString *location) {
        [weakSelf suggestionChosenWithName:name location:location];
    };
    _suggestions.anchorView = _entryPill;

    // ---- Summary of the event being typed
    NSTextField* (^label)(NSFont *, NSColor *) = ^NSTextField* (NSFont *labelFont, NSColor *color) {
        NSTextField *lbl = [NSTextField labelWithString:@""];
        lbl.font = labelFont;
        lbl.textColor = color;
        lbl.lineBreakMode = NSLineBreakByTruncatingTail;
        // Truncate rather than widen the window.
        [lbl setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        return lbl;
    };
    _sumTitle = label(font, Theme.monthTextColor);
    _sumLocation = label(font, Theme.agendaEventDateTextColor);
    _sumDate = label(font, Theme.agendaEventDateTextColor);

    _btnExpand = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:NSLocalizedString(@"Show Details", @"")] target:self action:@selector(toggleExpanded:)];
    _btnExpand.bordered = NO;
    _btnExpand.contentTintColor = Theme.buttonTintColor;
    _btnExpand.refusesFirstResponder = YES;
    _btnExpand.toolTip = NSLocalizedString(@"Show Details", @"");

    _btnCalendar = [NSButton buttonWithTitle:@"" target:self action:@selector(showCalendarMenu:)];
    _btnCalendar.bordered = NO;
    _btnCalendar.font = font;
    _btnCalendar.imagePosition = NSImageLeading;
    _btnCalendar.imageHugsTitle = YES;
    _btnCalendar.lineBreakMode = NSLineBreakByTruncatingTail;
    _btnCalendar.refusesFirstResponder = YES;
    [_btnCalendar setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];

    _btnSave = [NSButton buttonWithTitle:NSLocalizedString(@"Save Event", @"") target:self action:@selector(save:)];
    _btnSave.refusesFirstResponder = YES;
    [_btnSave setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSView *spacer = [NSView new];
    [spacer setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[_btnExpand, _btnCalendar, spacer, _btnSave]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.spacing = 6;

    NSStackView *summaryStack = [NSStackView stackViewWithViews:@[_sumTitle, _sumLocation, _sumDate, buttons]];
    summaryStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    summaryStack.alignment = NSLayoutAttributeLeading;
    summaryStack.spacing = 2;
    [summaryStack setCustomSpacing:6 afterView:_sumDate];
    summaryStack.translatesAutoresizingMaskIntoConstraints = NO;
    _summary = [NSView new];
    _summary.translatesAutoresizingMaskIntoConstraints = NO;
    [_summary addSubview:summaryStack];
    [NSLayoutConstraint activateConstraints:@[
        [summaryStack.leadingAnchor constraintEqualToAnchor:_summary.leadingAnchor constant:kSideMargin + 2],
        [summaryStack.trailingAnchor constraintEqualToAnchor:_summary.trailingAnchor constant:-kSideMargin],
        [summaryStack.topAnchor constraintEqualToAnchor:_summary.topAnchor constant:2],
        [summaryStack.bottomAnchor constraintEqualToAnchor:_summary.bottomAnchor constant:-2],
        [buttons.widthAnchor constraintEqualToAnchor:summaryStack.widthAnchor],
    ]];

    // ---- The full form, shown in place of the summary
    _eventVC = [EventViewController new];
    _eventVC.embedded = YES;
    _eventVC.onSaved = ^{ [weakSelf clearDraft]; };
    _eventVC.onCollapse = ^{ [weakSelf setExpanded:NO]; };
    _eventVC.onLayoutChange = ^{ [weakSelf.delegate quickEntryLayoutChanged]; };
    [self addChildViewController:_eventVC];
    NSView *form = _eventVC.view;
    form.translatesAutoresizingMaskIntoConstraints = NO;

    // ---- A line between the draft and the calendar
    _separator = [NSBox new];
    _separator.boxType = NSBoxSeparator;
    _separator.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *separatorWrap = [NSView new];
    separatorWrap.translatesAutoresizingMaskIntoConstraints = NO;
    [separatorWrap addSubview:_separator];
    [NSLayoutConstraint activateConstraints:@[
        [_separator.leadingAnchor constraintEqualToAnchor:separatorWrap.leadingAnchor constant:kSideMargin + 2],
        [_separator.trailingAnchor constraintEqualToAnchor:separatorWrap.trailingAnchor constant:-(kSideMargin + 2)],
        [_separator.topAnchor constraintEqualToAnchor:separatorWrap.topAnchor constant:2],
        [_separator.bottomAnchor constraintEqualToAnchor:separatorWrap.bottomAnchor constant:-2],
    ]];

    // ---- Stack it all up
    NSArray<NSView *> *rows = @[topRow, _summary, form, separatorWrap];
    NSStackView *stack = [NSStackView stackViewWithViews:rows];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    // Always exactly as tall as what's showing. A stack view hugs
    // weakly by default, so when the agenda got shorter it stretched
    // to hold the window's height, leaving a gap above the calendar,
    // instead of the window shrinking.
    [stack setHuggingPriority:NSLayoutPriorityRequired - 1 forOrientation:NSLayoutConstraintOrientationVertical];
    [v addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:v.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:v.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:v.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:v.bottomAnchor],
    ]];
    for (NSView *row in rows) {
        NSLayoutConstraint *width = [row.widthAnchor constraintEqualToAnchor:stack.widthAnchor];
        // The form is the one row with a minimum width. While it's
        // hidden, that must not hold the window open.
        if (row == form) _formWidth = width;
        else width.active = YES;
    }

    self.view = v;
    [self applySizePreference];
    [self updatePanels];
    REGISTER_FOR_SIZE_CHANGE;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)sizeChanged:(id)sender
{
    [self applySizePreference];
}

// One type scale for the whole bar: SizePref.fontSize for text,
// calendarTitleFontSize for the event's title, as in the calendar.
- (void)applySizePreference
{
    NSFont *font = [NSFont systemFontOfSize:SizePref.fontSize];
    _lineHeight = ceil([[NSLayoutManager new] defaultLineHeightForFont:font]);
    CGFloat pillSize = _lineHeight + 2 * kPillPadding;

    _entry.font = font;
    _searchField.font = font;
    _searchField.placeholderAttributedString = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Search", @"") attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: Theme.placeholderColor}];
    _sumTitle.font = [NSFont systemFontOfSize:SizePref.calendarTitleFontSize weight:NSFontWeightMedium];
    _sumLocation.font = font;
    _sumDate.font = font;
    _btnCalendar.font = font;
    _btnSave.font = font;
    _btnSave.controlSize = SizePref.sizePreference == SizePreferenceSmall ? NSControlSizeSmall
                         : SizePref.sizePreference == SizePreferenceLarge ? NSControlSizeLarge
                         : NSControlSizeRegular;

    NSImageSymbolConfiguration *iconConfig = [NSImageSymbolConfiguration configurationWithPointSize:SizePref.fontSize - 1 weight:NSFontWeightSemibold];
    _plusIcon.symbolConfiguration = iconConfig;
    _glassIcon.symbolConfiguration = iconConfig;
    _btnClearSearch.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:SizePref.fontSize - 1 weight:NSFontWeightRegular];
    _btnExpand.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:SizePref.fontSize - 2 weight:NSFontWeightSemibold];

    _entryCollapsedWidth.constant = pillSize;
    _searchCollapsedWidth.constant = pillSize;
    _searchHeight.constant = pillSize;
    _plusX.constant = pillSize / 2;
    _plusY.constant = pillSize / 2;
    _glassX.constant = pillSize / 2;
    _glassY.constant = pillSize / 2;
    _entryLeading.constant = pillSize - 2;
    _searchLeading.constant = pillSize - 2;
    [self updateEntryHeight];
    _entry.needsDisplay = YES;
}


- (void)viewDidLayout
{
    [super viewDidLayout];
    // The field's width may have changed, and with it the wrapping.
    [self updateEntryHeight];
}

- (void)setEc:(EventCenter *)ec { _ec = ec; _eventVC.ec = ec; }
- (void)setCal:(NSCalendar *)cal { _cal = cal; _eventVC.cal = cal; }
- (void)setEventUndoManager:(NSUndoManager *)um { _eventUndoManager = um; _eventVC.eventUndoManager = um; }

#pragma mark Switching between New Event and Search

- (void)focusEntry
{
    if (_searching) [self setSearching:NO];
    _eventVC.eventUndoManager = self.eventUndoManager ?: self.view.window.undoManager;
    [self.view.window makeFirstResponder:_entry];
}

- (void)focusSearch
{
    if (!_searching) [self setSearching:YES];
    [self.view.window makeFirstResponder:_searchField];
}

- (void)setSearching:(BOOL)searching
{
    if (_searching == searching) return;
    _searching = searching;

    [self dismissSuggestions];

    // The wide field shrinks to a button and the button grows
    // into a field.
    [self.view layoutSubtreeIfNeeded];
    if (searching) {
        _searchCollapsedWidth.active = NO;
        _entryCollapsedWidth.active = YES;
    }
    else {
        _entryCollapsedWidth.active = NO;
        _searchCollapsedWidth.active = YES;
    }
    _entryPill.collapsed = searching;
    _searchPill.collapsed = !searching;
    _entry.hidden = searching;
    _searchField.hidden = !searching;
    _btnClearSearch.hidden = !searching || _searchField.stringValue.length == 0;
    [self updateEntryHeight];
    [self updatePanels];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = kSwapDuration;
        context.allowsImplicitAnimation = YES;
        [self.view layoutSubtreeIfNeeded];
    }];

    [self.delegate quickEntrySearchChanged:searching ? [self searchQuery] : nil];
}

- (NSString *)searchQuery
{
    return [_searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)clearSearch:(id)sender
{
    _searchField.stringValue = @"";
    _btnClearSearch.hidden = YES;
    [self.delegate quickEntrySearchChanged:@""];
    [self.view.window makeFirstResponder:_searchField];
}

#pragma mark Panels under the fields

- (void)updatePanels
{
    BOOL drafting = _draftActive && !_searching;
    _summary.hidden = !drafting || _expanded;
    _eventVC.view.hidden = !drafting || !_expanded;
    _formWidth.active = !_eventVC.view.hidden;
    _separator.superview.hidden = !drafting;
    [self.delegate quickEntryLayoutChanged];
}

- (void)updateEntryHeight
{
    CGFloat height = _lineHeight;
    if (!_searching) {
        // While collapsed the field is too narrow to measure.
        CGFloat width = NSWidth(_entry.frame);
        if (width > 0) _entry.textContainer.containerSize = NSMakeSize(width, CGFLOAT_MAX);
        NSLayoutManager *lm = _entry.layoutManager;
        [lm ensureLayoutForTextContainer:_entry.textContainer];
        height = MAX(_lineHeight, ceil(NSHeight([lm usedRectForTextContainer:_entry.textContainer])));
    }
    if (fabs(_entryHeight.constant - height) > 0.5) {
        _entryHeight.constant = height;
        [self.delegate quickEntryLayoutChanged];
    }
}

- (void)dismissSuggestions
{
    [_suggestions dismiss];
    [_eventVC dismissSuggestions];
}

- (void)setExpanded:(BOOL)expanded
{
    [self dismissSuggestions];
    _expanded = expanded;
    [self refreshSummary];
    [self updatePanels];
    if (!expanded) [self.view.window makeFirstResponder:_entry];
}

- (void)toggleExpanded:(id)sender
{
    [self setExpanded:!_expanded];
}

- (void)refreshSummary
{
    _sumTitle.stringValue = _eventVC.summaryTitle ?: @"";
    NSString *location = [_eventVC.summaryLocation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _sumLocation.stringValue = location ?: @"";
    _sumLocation.hidden = location.length == 0;

    // "Thu 12 Nov, 16:00 – 17:00 CET". The zone goes with the time,
    // as a city here would read like the event's location.
    NSTimeZone *tz = _eventVC.summaryTimeZone;
    NSDateIntervalFormatter *formatter = [NSDateIntervalFormatter new];
    NSDate *start = _eventVC.summaryStart, *end = _eventVC.summaryEnd;
    // Leave out the year when it is this year, to keep it short.
    NSCalendar *cal = self.cal ?: [NSCalendar autoupdatingCurrentCalendar];
    BOOL thisYear = start && [cal isDate:start equalToDate:[NSDate new] toUnitGranularity:NSCalendarUnitYear];
    NSString *dayTemplate = thisYear ? @"EEEdMMM" : @"EEEdMMMy";
    formatter.dateTemplate = _eventVC.summaryAllDay ? dayTemplate : [dayTemplate stringByAppendingString:@"jm"];
    if (tz) formatter.timeZone = tz;
    NSString *when = (start && end) ? [formatter stringFromDate:start toDate:end] : @"";
    if (tz) {
        when = [NSString stringWithFormat:@"%@ %@", when, ShortTimeZoneName(tz, start)];
    }
    _sumDate.stringValue = when ?: @"";
    _sumDate.toolTip = when;
    _sumTitle.toolTip = _eventVC.summaryTitle;
    _sumLocation.toolTip = location;

    // The calendar: a colored dot and its name.
    NSColor *color = _eventVC.summaryCalendarColor ?: NSColor.secondaryLabelColor;
    _btnCalendar.title = _eventVC.summaryCalendarTitle ?: @"";
    _btnCalendar.image = [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [color set];
        [[NSBezierPath bezierPathWithOvalInRect:dstRect] fill];
        return YES;
    }];
    _btnSave.enabled = _eventVC.canSave;
}

- (void)showCalendarMenu:(id)sender
{
    NSMenu *menu = [_eventVC calendarMenuWithTarget:self action:@selector(calendarChosen:)];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(_btnCalendar.bounds) + 4) inView:_btnCalendar];
}

- (void)calendarChosen:(NSMenuItem *)item
{
    [_eventVC selectCalendarWithTag:item.tag];
    [self refreshSummary];
}

#pragma mark The draft

- (NSInteger)defaultDurationMinutes
{
    // Same setting Calendar uses. See EventViewController.
    NSUserDefaults *calendarDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.apple.iCal"];
    NSNumber *minutes = [calendarDefaults objectForKey:@"Default duration in minutes for new event"];
    return minutes ? minutes.integerValue : 60;
}

- (void)entryTextChanged
{
    [self updateEntryHeight];
    NSString *text = _entry.string ?: @"";
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        [self endDraft];
        return;
    }

    if (!_draftActive) {
        if (![self.delegate quickEntryCanCreateEvents]) {
            _entry.string = @"";
            [self updateEntryHeight];
            return;
        }
        _eventVC.calSelectedDate = [self.delegate quickEntrySelectedDate];
        [_eventVC resetForm];
        _draftActive = YES;
    }

    NSCalendar *cal = self.cal ?: [NSCalendar autoupdatingCurrentCalendar];
    NLEventDraft *draft = [NLEventParser parse:text calendar:cal now:[NSDate new] defaultDurationMinutes:[self defaultDurationMinutes]];

    // Tint what was understood.
    NSLayoutManager *lm = _entry.layoutManager;
    [lm removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:NSMakeRange(0, text.length)];
    for (NSValue *value in draft.tokenRanges) {
        NSRange range = value.rangeValue;
        if (NSMaxRange(range) <= text.length) {
            [lm addTemporaryAttribute:NSForegroundColorAttributeName value:Theme.todayCellColor forCharacterRange:range];
        }
    }

    // The place: a picked suggestion's full address if its name
    // is still what the text says, else what was typed.
    NSString *location = draft.location;
    BOOL isChosen = location && _chosenName && [location isEqualToString:_chosenName];
    if (isChosen) {
        location = _chosenLocation;
    }
    else {
        _chosenName = nil;
        _chosenLocation = nil;
    }
    _locationRange = draft.locationRange;
    [_eventVC applyDraft:draft location:location];

    // Suggest places while the user is still typing one.
    BOOL typingPlace = draft.location && !isChosen && NSMaxRange(draft.locationRange) == text.length;
    _suggestions.query = typingPlace ? draft.location : nil;

    [self refreshSummary];
    [self updatePanels];

    // Show the day in the calendar.
    if (draft.startDate && (!_lastShownDate || ![cal isDate:draft.startDate inSameDayAsDate:_lastShownDate])) {
        _lastShownDate = draft.startDate;
        [self.delegate quickEntryShowDate:draft.startDate];
    }
}

- (void)suggestionChosenWithName:(NSString *)name location:(NSString *)location
{
    NSRange range = _locationRange;
    if (range.location == NSNotFound || NSMaxRange(range) > _entry.string.length) return;
    _chosenName = name;
    _chosenLocation = location;
    if ([_entry shouldChangeTextInRange:range replacementString:name]) {
        [_entry replaceCharactersInRange:range withString:name];
        [_entry didChangeText];
    }
    [self.view.window makeFirstResponder:_entry];
}

- (void)endDraft
{
    _draftActive = NO;
    _expanded = NO;
    _chosenName = nil;
    _chosenLocation = nil;
    _lastShownDate = nil;
    _locationRange = NSMakeRange(NSNotFound, 0);
    _suggestions.query = nil;
    [self updatePanels];
}

- (void)clearDraft
{
    _entry.string = @"";
    [self endDraft];
    [self updateEntryHeight];
    _entry.needsDisplay = YES;
    [self.view.window makeFirstResponder:_entry];
}

- (void)save:(id)sender
{
    if (!_draftActive || !_eventVC.canSave) {
        NSBeep();
        return;
    }
    [_eventVC saveEvent:self]; // calls onSaved (-clearDraft) if it worked
}

#pragma mark NSTextViewDelegate (New Event field)

- (void)textDidChange:(NSNotification *)notification
{
    if (notification.object == _entry) [self entryTextChanged];
}

- (void)textDidEndEditing:(NSNotification *)notification
{
    if (notification.object == _entry) [_suggestions dismiss];
}

- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (textView != _entry) return NO;
    if (commandSelector == @selector(insertNewline:) ||
        commandSelector == @selector(insertNewlineIgnoringFieldEditor:) ||
        commandSelector == @selector(insertLineBreak:)) {
        // Return picks the highlighted place, else saves the event.
        if (![_suggestions acceptHighlighted]) [self save:self];
        return YES;
    }
    if (commandSelector == @selector(moveDown:) || commandSelector == @selector(moveUp:)) {
        if (!_suggestions.hasSuggestions) return NO;
        [_suggestions moveHighlightBy:commandSelector == @selector(moveDown:) ? 1 : -1];
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        // Esc backs out one step at a time.
        if (_suggestions.hasSuggestions) {
            [_suggestions dismiss];
        }
        else if (_entry.string.length) {
            [self clearDraft];
        }
        else {
            [self.delegate quickEntryWantsToCloseWindow];
        }
        return YES;
    }
    if (commandSelector == @selector(insertTab:)) {
        if (_draftActive && _expanded) [_eventVC focusFirstField];
        return YES;
    }
    if (commandSelector == @selector(insertBacktab:)) {
        return YES;
    }
    return NO;
}

#pragma mark NSTextFieldDelegate (Search field)

- (void)controlTextDidChange:(NSNotification *)notification
{
    if (notification.object != _searchField) return;
    _btnClearSearch.hidden = _searchField.stringValue.length == 0;
    [self.delegate quickEntrySearchChanged:[self searchQuery]];
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector
{
    if (control != _searchField) return NO;
    if (commandSelector == @selector(cancelOperation:)) {
        // Esc clears the search, then leaves it.
        if (_searchField.stringValue.length) {
            [self clearSearch:self];
        }
        else {
            [self focusEntry];
        }
        return YES;
    }
    return NO;
}

@end
