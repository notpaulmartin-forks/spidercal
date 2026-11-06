//
//  MoCalCell.h
//
//
//  Created by Sanjay Madan on 12/3/14.
//  Copyright (c) 2014 mowglii.com. All rights reserved.
//

#import <AppKit/AppKit.h>
#import "MoDate.h"

@interface MoCalCell : NSView

@property (nonatomic) NSTextField *textField;
@property (nonatomic) MoDate date;
@property (nonatomic) BOOL isToday;
@property (nonatomic) BOOL isHighlighted;
@property (nonatomic) BOOL isInCurrentMonth;
@property (nonatomic) BOOL isHovered;
@property (nonatomic) BOOL isSelected;

// A day of the week's name over the dates, rather than a date or a
// week number. Its text doesn't move down for the Details style.
@property (nonatomic) BOOL isDayOfWeek;

// An array of up to 3 colors.
// - Nil means do not draw a dot.
// - An empty array means draw a single dot in the default theme color.
// - Otherwise, draw up to 3 dots with the given colors.
@property (nonatomic) NSArray<NSColor *> *dotColors;

@end
