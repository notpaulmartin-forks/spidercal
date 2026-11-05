//
//  AgendaResizeHandle.h
//  Spidercal
//
//  An invisible strip along the window's bottom edge. Dragging it
//  makes the agenda taller or shorter, as if resizing the window by
//  its edge. (The window's height comes from its content, and native
//  resizing would make its sides draggable too.)
//

#import <Cocoa/Cocoa.h>

@interface AgendaResizeHandle : NSView

@property (nonatomic, copy) void (^onDragBegan)(void);
// How far the pointer has moved since the drag began, in points.
// Positive is down: a taller agenda.
@property (nonatomic, copy) void (^onDrag)(CGFloat delta);
@property (nonatomic, copy) void (^onDragEnded)(void);
@property (nonatomic, copy) void (^onDoubleClick)(void);

@end
