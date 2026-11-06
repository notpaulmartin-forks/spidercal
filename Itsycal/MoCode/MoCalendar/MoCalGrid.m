//
//  MoCalGrid.m
//
//
//  Created by Sanjay Madan on 12/3/14.
//  Copyright (c) 2014 mowglii.com. All rights reserved.
//

#import "MoCalGrid.h"
#import "MoCalCell.h"
#import "Sizer.h"

@implementation MoCalGrid
{
    MoCalGridKind _kind;
    NSUInteger _rows, _cols, _hMargin, _vMargin;
}

- (instancetype)initWithKind:(MoCalGridKind)kind rows:(NSUInteger)rows columns:(NSUInteger)cols horizontalMargin:(NSUInteger)hMargin verticalMargin:(NSUInteger)vMargin
{
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _kind = kind;
        _rows  = rows;
        _cols  = cols;
        _hMargin = hMargin;
        _vMargin = vMargin;
        NSMutableArray *cells = [NSMutableArray new];
        for (NSUInteger i = 0; i < rows * cols; i++) {
            MoCalCell *cell = [MoCalCell new];
            [self addSubview:cell];
            [cells addObject:cell];
        }
        _cells = [NSArray arrayWithArray:cells];
        [self layoutCells];
        
        // Hug the cells tightly
        [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
        [self setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        
        REGISTER_FOR_SIZE_CHANGE;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (CGFloat)cellWidth
{
    return _kind == MoCalGridKindWeeks ? SizePref.cellSize : SizePref.dateCellWidth;
}

- (CGFloat)cellHeight
{
    return _kind == MoCalGridKindDOWs ? SizePref.cellSize : SizePref.dateCellHeight;
}

// Frame the cells: rows from the top, columns from the left.
- (void)layoutCells
{
    CGFloat w = self.cellWidth, h = self.cellHeight;
    for (NSUInteger row = 0; row < _rows; row++) {
        for (NSUInteger col = 0; col < _cols; col++) {
            CGFloat x = w * col + _hMargin;
            CGFloat y = h * _rows - h * (row + 1) + _vMargin;
            [_cells[row * _cols + col] setFrame:NSMakeRect(x, y, w, h)];
        }
    }
}

- (void)addRow
{
    NSMutableArray *cells = [_cells mutableCopy];
    for (NSUInteger col = 0; col < _cols; col++) {
        MoCalCell *cell = [MoCalCell new];
        [self addSubview:cell];
        [cells addObject:cell];
    }
    _rows += 1;
    _cells = [NSArray arrayWithArray:cells];
    [self layoutCells];
    [self invalidateIntrinsicContentSize];
}

- (void)removeRow
{
    NSMutableArray *cells = [_cells mutableCopy];

    // Remove last row of cells.
    for (NSUInteger col = 0; col < _cols; col++) {
        MoCalCell *cell = [cells lastObject];
        [cell removeFromSuperview];
        [cells removeLastObject];
    }

    _rows -= 1;
    _cells = [NSArray arrayWithArray:cells];
    [self layoutCells];
    [self invalidateIntrinsicContentSize];
}

- (MoCalCell *)cellAtPoint:(NSPoint)point
{
    NSInteger col = floor((point.x - _hMargin) / self.cellWidth);
    NSInteger row = floor((point.y - _vMargin) / self.cellHeight);
    row = _rows - row - 1; // flip row coordinate
    if (col < 0 || row < 0 || col >= _cols || row >= _rows) {
        return nil;
    }
    return _cells[_cols * row + col];
}

- (MoCalCell *)cellWithDate:(MoDate)date;
{
    for (MoCalCell *cell in self.cells) {
        if (CompareDates(date, cell.date) == 0) {
            return cell;
        }
    }
    return nil;
}

- (NSRect)cellsRect
{
    return NSInsetRect(self.bounds, _hMargin, _vMargin);
}

- (NSSize)intrinsicContentSize
{
    CGFloat width  = self.cellWidth  * _cols + 2 * _hMargin;
    CGFloat height = self.cellHeight * _rows + 2 * _vMargin;
    return NSMakeSize(width, height);
}

- (void)sizeChanged:(id)sender
{
    [self layoutCells];
    [self invalidateIntrinsicContentSize];
}

@end
