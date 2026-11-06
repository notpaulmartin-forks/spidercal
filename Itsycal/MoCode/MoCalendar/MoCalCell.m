//
//  MoCalCell.m
//
//
//  Created by Sanjay Madan on 12/3/14.
//  Copyright (c) 2014 mowglii.com. All rights reserved.
//

#import "MoCalCell.h"
#import "Themer.h"
#import "Sizer.h"

@implementation MoCalCell
{
    NSLayoutConstraint *_textFieldVerticalSpace;
}

- (instancetype)init
{
    CGFloat sz = SizePref.cellSize;
    self = [super initWithFrame:NSMakeRect(0, 0, sz, sz)];
    if (self) {
        _textField = [NSTextField labelWithString:@""];
        [_textField setFont:[NSFont systemFontOfSize:SizePref.fontSize weight:NSFontWeightMedium]];
        [_textField setTextColor:[NSColor blackColor]];
        [_textField setAlignment:NSTextAlignmentCenter];
        [_textField setTranslatesAutoresizingMaskIntoConstraints:NO];

        [self addSubview:_textField];

        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_textField]|" options:0 metrics:nil views:NSDictionaryOfVariableBindings(_textField)]];
        
        _textFieldVerticalSpace = [NSLayoutConstraint constraintWithItem:_textField attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeTop multiplier:1 constant:SizePref.dateCellTextFieldVerticalSpace];
        [self addConstraint:_textFieldVerticalSpace];

        
        REGISTER_FOR_SIZE_CHANGE;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)sizeChanged:(id)sender
{
    [_textField setFont:[NSFont systemFontOfSize:SizePref.fontSize weight:NSFontWeightMedium]];
    _textFieldVerticalSpace.constant = self.textFieldVerticalSpace;
}

- (CGFloat)textFieldVerticalSpace {
    return self.isDayOfWeek ? SizePref.cellTextFieldVerticalSpace : SizePref.dateCellTextFieldVerticalSpace;
}

- (void)setIsDayOfWeek:(BOOL)isDayOfWeek {
    _isDayOfWeek = isDayOfWeek;
    _textFieldVerticalSpace.constant = self.textFieldVerticalSpace;
}

- (void)setIsToday:(BOOL)isToday {
    _isToday = isToday;
    [self setNeedsDisplay:YES];
}

- (void)setIsHighlighted:(BOOL)isHighlighted {
    _isHighlighted = isHighlighted;
    [self updateTextColor];
}

- (void)setIsInCurrentMonth:(BOOL)isInCurrentMonth {
    _isInCurrentMonth = isInCurrentMonth;
    [self updateTextColor];
}

- (void)setIsSelected:(BOOL)isSelected
{
    if (isSelected != _isSelected) {
        _isSelected = isSelected;
        [self setNeedsDisplay:YES];
    }
}

- (void)setIsHovered:(BOOL)isHovered
{
    if (isHovered != _isHovered) {
        _isHovered = isHovered;
        [self setNeedsDisplay:YES];
    }
}

- (void)setDotColors:(NSArray<NSColor *> *)dotColors
{
    _dotColors = dotColors;
    [self setNeedsDisplay:YES];
}

- (void)updateTextColor {
    self.textField.textColor = self.isInCurrentMonth ? Theme.currentMonthTextColor : Theme.noncurrentMonthTextColor;
}

- (void)drawRect:(NSRect)dirtyRect
{
    CGFloat radius = SizePref.cellRadius;
    // Details: the events' titles reach close to the cell's sides, so
    // the outline goes around them, just inside the month's outline.
    // Above and below, it stops short of the lines between the weeks.
    BOOL details = SizePref.calendarStyle == CalendarStyleDetails;
    CGFloat dx = details ? 1.5 : 3;
    CGFloat dy = details ? 2.75 : 3;
    CGFloat lineWidth = details ? 1.5 : 2;
    NSColor *outlineColor = self.isToday ? Theme.todayCellColor
                          : self.isSelected ? Theme.selectedCellColor
                          : self.isHovered ? Theme.hoveredCellColor
                          : nil;
    if (outlineColor) {
        [outlineColor set];
        NSRect r = NSInsetRect(self.bounds, dx, dy);
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius];
        [p setLineWidth:lineWidth];
        [p stroke];
    }
    if (self.dotColors) {
        CGFloat midX = NSMidX(self.bounds);
        CGFloat dotWidth = SizePref.cellDotWidth;
        CGFloat dotSpacing = 1.5*dotWidth;
        NSRect r = NSMakeRect(0, 0, dotWidth, dotWidth);
        r.origin.y = self.bounds.origin.y + dotWidth + 2;
        NSArray<NSColor *> *colors = self.dotColors.count ? self.dotColors : @[self.textField.textColor];
        NSInteger count = MIN(colors.count, 3);
        for (NSInteger i = 0; i < count; i++) {
            [colors[i] set];
            r.origin.x = midX + (i - (count - 1) / 2.0) * dotSpacing - dotWidth / 2.0;
            [[NSBezierPath bezierPathWithOvalInRect:r] fill];
        }
    }
}

@end
