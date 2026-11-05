//
//  LocationSuggestionsView.m
//  Spidercal
//

#import "LocationSuggestionsView.h"
#import <MapKit/MapKit.h>
#import "Themer.h"
#import "Sizer.h"

static const NSInteger kMaxSuggestions = 4;
static const CGFloat kWindowInset = 8;    // from the window's sides
static const CGFloat kGapBelowAnchor = 3;

#pragma mark -
#pragma mark SuggestionRow

@interface SuggestionRow : NSView
@property (nonatomic) BOOL highlighted;
@property (nonatomic, copy) void (^onClick)(void);
- (instancetype)initWithName:(NSString *)name detail:(NSString *)detail;
@end

@implementation SuggestionRow
{
    NSTrackingArea *_trackingArea;
    BOOL _hovered;
}

- (instancetype)initWithName:(NSString *)name detail:(NSString *)detail
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;

        NSImage *pinImage = [NSImage imageWithSystemSymbolName:@"mappin.and.ellipse" accessibilityDescription:nil];
        NSImageView *pin = [NSImageView imageViewWithImage:pinImage];
        pin.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:SizePref.fontSize - 2 weight:NSFontWeightRegular];
        pin.contentTintColor = Theme.buttonTintColor;
        pin.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:pin];

        NSTextField *nameLabel = [NSTextField labelWithString:name ?: @""];
        nameLabel.font = [NSFont systemFontOfSize:SizePref.fontSize];
        nameLabel.textColor = Theme.agendaEventTextColor;
        NSTextField *detailLabel = [NSTextField labelWithString:detail ?: @""];
        detailLabel.font = [NSFont systemFontOfSize:SizePref.fontSize];
        detailLabel.textColor = Theme.agendaEventDateTextColor;
        detailLabel.hidden = detail.length == 0;
        for (NSTextField *label in @[nameLabel, detailLabel]) {
            label.lineBreakMode = NSLineBreakByTruncatingTail;
            // Never widen the window; truncate instead.
            [label setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
        }
        NSStackView *labels = [NSStackView stackViewWithViews:@[nameLabel, detailLabel]];
        labels.orientation = NSUserInterfaceLayoutOrientationVertical;
        labels.alignment = NSLayoutAttributeLeading;
        labels.spacing = 0;
        labels.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:labels];

        [NSLayoutConstraint activateConstraints:@[
            [pin.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:6],
            [pin.centerYAnchor constraintEqualToAnchor:nameLabel.centerYAnchor],
            [pin.widthAnchor constraintEqualToConstant:SizePref.fontSize],
            [labels.leadingAnchor constraintEqualToAnchor:pin.trailingAnchor constant:5],
            [labels.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-6],
            [labels.topAnchor constraintEqualToAnchor:self.topAnchor constant:4],
            [labels.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        ]];
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
    _highlighted = highlighted;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    if (_highlighted || _hovered) {
        [Theme.agendaHoverColor set];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:4 yRadius:4] fill];
    }
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)mouseEntered:(NSEvent *)event { _hovered = YES; self.needsDisplay = YES; }
- (void)mouseExited:(NSEvent *)event  { _hovered = NO;  self.needsDisplay = YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)mouseDown:(NSEvent *)event { /* wait for mouseUp */ }

- (void)mouseUp:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(point, self.bounds) && self.onClick) self.onClick();
}

@end

#pragma mark -
#pragma mark LocationSuggestionsView

@interface LocationSuggestionsView () <MKLocalSearchCompleterDelegate>
@end

@implementation LocationSuggestionsView
{
    MKLocalSearchCompleter *_completer;
    NSStackView *_stack;
    id _clickMonitor;
    NSArray<MKLocalSearchCompletion *> *_results;
    NSInteger _highlightedIndex; // -1 = none
    NSString *_dismissedQuery;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 6;
        self.layer.borderWidth = 1;
        self.hidden = YES;
        _highlightedIndex = -1;
        _results = @[];

        _stack = [NSStackView new];
        _stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        _stack.alignment = NSLayoutAttributeLeading;
        _stack.spacing = 1;
        _stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_stack];

        NSShadow *shadow = [NSShadow new];
        // Barely there: the hairline border does most of the work,
        // in keeping with the window's flat look.
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.08];
        shadow.shadowBlurRadius = 3;
        shadow.shadowOffset = NSMakeSize(0, -1);
        self.shadow = shadow;

        [NSLayoutConstraint activateConstraints:@[
            [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
            [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3],
            [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:3],
            [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-3],
        ]];
    }
    return self;
}

- (void)dealloc
{
    [self removeClickMonitor];
}

- (void)updateLayer
{
    // Opaque: the calendar is underneath.
    self.layer.backgroundColor = Theme.tooltipBackgroundColor.CGColor;
    self.layer.borderColor = Theme.agendaDividerColor.CGColor;
}

// On top of everything in the window, under the anchor. Done when
// there is something to show, as the anchor needs to be in a window.
- (void)attachToWindow
{
    NSView *anchor = self.anchorView;
    NSView *container = anchor.window.contentView;
    if (!container) return;
    if (self.superview != container) {
        [self removeFromSuperview];
        [container addSubview:self positioned:NSWindowAbove relativeTo:nil];
        [NSLayoutConstraint activateConstraints:@[
            [self.topAnchor constraintEqualToAnchor:anchor.bottomAnchor constant:kGapBelowAnchor],
            [self.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:kWindowInset],
            [self.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-kWindowInset],
        ]];
    }
}

// A click anywhere else closes the pane, and still does its usual thing.
- (void)installClickMonitor
{
    if (_clickMonitor) return;
    __weak typeof(self) weakSelf = self;
    _clickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^NSEvent *(NSEvent *event) {
        LocationSuggestionsView *pane = weakSelf;
        if (pane && event.window == pane.window) {
            NSPoint point = [pane convertPoint:event.locationInWindow fromView:nil];
            if (!NSPointInRect(point, pane.bounds)) [pane dismiss];
        }
        return event;
    }];
}

- (void)removeClickMonitor
{
    if (_clickMonitor) {
        [NSEvent removeMonitor:_clickMonitor];
        _clickMonitor = nil;
    }
}

- (BOOL)wantsUpdateLayer { return YES; }

- (BOOL)hasSuggestions
{
    return _results.count > 0;
}

- (void)setQuery:(NSString *)query
{
    query = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ((query ?: @"").length < 2) query = nil;
    if (query == _query || [query isEqualToString:_query]) return;
    _query = [query copy];
    if (!_query || [_query isEqualToString:_dismissedQuery]) {
        [_completer cancel];
        [self showResults:@[]];
        return;
    }
    _dismissedQuery = nil;
    if (!_completer) {
        // Created on first use: nothing is sent anywhere until the
        // user actually types a place.
        _completer = [MKLocalSearchCompleter new];
        _completer.delegate = self;
        _completer.resultTypes = MKLocalSearchCompleterResultTypeAddress | MKLocalSearchCompleterResultTypePointOfInterest;
    }
    _completer.queryFragment = _query;
}

- (void)dismiss
{
    _dismissedQuery = _query;
    [_completer cancel];
    [self showResults:@[]];
}

- (void)showResults:(NSArray<MKLocalSearchCompletion *> *)results
{
    if (results.count > kMaxSuggestions) {
        results = [results subarrayWithRange:NSMakeRange(0, kMaxSuggestions)];
    }
    BOOL wasEmpty = _results.count == 0;
    if (wasEmpty && results.count == 0) return;
    _results = results;
    _highlightedIndex = -1;
    for (NSView *row in [_stack.arrangedSubviews copy]) {
        [_stack removeArrangedSubview:row];
        [row removeFromSuperview];
    }
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)results.count; i++) {
        MKLocalSearchCompletion *result = results[i];
        SuggestionRow *row = [[SuggestionRow alloc] initWithName:result.title detail:result.subtitle];
        row.onClick = ^{ [weakSelf selectIndex:i]; };
        [_stack addArrangedSubview:row];
        [row.widthAnchor constraintEqualToAnchor:_stack.widthAnchor].active = YES;
    }
    if (results.count > 0) {
        [self attachToWindow];
        [self installClickMonitor];
    }
    else {
        [self removeClickMonitor];
    }
    self.hidden = results.count == 0;
}

- (void)selectIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)_results.count) return;
    MKLocalSearchCompletion *result = _results[index];
    NSString *name = result.title ?: @"";
    NSString *location = result.subtitle.length ? [NSString stringWithFormat:@"%@, %@", name, result.subtitle] : name;
    // The chosen name will come back as the query. Don't suggest for it.
    _dismissedQuery = name;
    _query = name;
    [_completer cancel];
    [self showResults:@[]];
    if (self.onSelect) self.onSelect(name, location);
}

- (BOOL)moveHighlightBy:(NSInteger)delta
{
    if (_results.count == 0) return NO;
    NSInteger index = _highlightedIndex + delta;
    if (index < -1) index = -1;
    if (index >= (NSInteger)_results.count) index = _results.count - 1;
    _highlightedIndex = index;
    NSArray *rows = _stack.arrangedSubviews;
    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        ((SuggestionRow *)rows[i]).highlighted = i == index;
    }
    return YES;
}

- (BOOL)acceptHighlighted
{
    if (_highlightedIndex < 0 || _highlightedIndex >= (NSInteger)_results.count) return NO;
    [self selectIndex:_highlightedIndex];
    return YES;
}

#pragma mark MKLocalSearchCompleterDelegate

- (void)completerDidUpdateResults:(MKLocalSearchCompleter *)completer
{
    if (!_query || ![completer.queryFragment isEqualToString:_query]) return;
    [self showResults:completer.results];
}

- (void)completer:(MKLocalSearchCompleter *)completer didFailWithError:(NSError *)error
{
    // Offline, or nothing found. No suggestions; typing still works.
    [self showResults:@[]];
}

@end
