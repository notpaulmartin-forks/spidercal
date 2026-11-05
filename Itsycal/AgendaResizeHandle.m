//
//  AgendaResizeHandle.m
//  Spidercal
//

#import "AgendaResizeHandle.h"

@implementation AgendaResizeHandle
{
    NSTrackingArea *_trackingArea;
    CGFloat _dragStartY; // on screen
    BOOL _dragging;
    BOOL _hovered;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    return YES;
}

// A tracking area rather than a cursor rect, which only works while
// the app is active. Spidercal's window is usually key without that.
- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea) [self removeTrackingArea:_trackingArea];
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited | NSTrackingCursorUpdate | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void)cursorUpdate:(NSEvent *)event
{
    [NSCursor.resizeUpDownCursor set];
}

- (void)mouseEntered:(NSEvent *)event
{
    _hovered = YES;
    [NSCursor.resizeUpDownCursor set];
}

- (void)mouseExited:(NSEvent *)event
{
    _hovered = NO;
    if (!_dragging) [NSCursor.arrowCursor set];
}

- (CGFloat)screenYOfEvent:(NSEvent *)event
{
    // On screen, as the window's bottom edge moves with the drag.
    return [event.window convertPointToScreen:event.locationInWindow].y;
}

- (void)mouseDown:(NSEvent *)event
{
    if (event.clickCount == 2) {
        if (self.onDoubleClick) self.onDoubleClick();
        return;
    }
    _dragging = YES;
    _dragStartY = [self screenYOfEvent:event];
    if (self.onDragBegan) self.onDragBegan();
}

- (void)mouseDragged:(NSEvent *)event
{
    if (!_dragging) return;
    [NSCursor.resizeUpDownCursor set];
    if (self.onDrag) self.onDrag(_dragStartY - [self screenYOfEvent:event]);
}

- (void)mouseUp:(NSEvent *)event
{
    if (!_dragging) return;
    _dragging = NO;
    if (!_hovered) [NSCursor.arrowCursor set];
    if (self.onDragEnded) self.onDragEnded();
}

@end
