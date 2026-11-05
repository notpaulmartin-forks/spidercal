//
//  LocationSuggestionsView.h
//  Spidercal
//
//  A pane of place suggestions for the text the user is typing.
//  It floats over the window's content, under anchorView, so
//  nothing else moves when it appears.
//

#import <Cocoa/Cocoa.h>

@interface LocationSuggestionsView : NSView

// The field the pane appears under.
@property (nonatomic, weak) NSView *anchorView;

// What the user has typed so far. nil or empty hides the pane.
@property (nonatomic, copy) NSString *query;

// The user picked a place. name is its short name, location its
// name and address.
@property (nonatomic, copy) void (^onSelect)(NSString *name, NSString *location);

@property (nonatomic, readonly) BOOL hasSuggestions;

// Move the highlight down (+1) or up (-1). Nothing is highlighted
// until the user moves into the pane. Returns NO if there is
// nothing to move to.
- (BOOL)moveHighlightBy:(NSInteger)delta;

// Pick the highlighted place. Returns NO if none is highlighted.
- (BOOL)acceptHighlighted;

// Hide the pane until the query changes.
- (void)dismiss;

@end
