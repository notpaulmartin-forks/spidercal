//
//  NLEventParser.h
//  Spidercal
//
//  Turns a line of natural language, e.g.
//  "Flight to London on 12 Nov at 4pm, DE time",
//  into the details of a new event.
//

#import <Foundation/Foundation.h>

@interface NLEventDraft : NSObject
// What is left of the text once dates, times, time zones and the
// location are taken out.
@property (nonatomic, copy) NSString *title;
// nil if the text has no date or time.
@property (nonatomic) NSDate *startDate;
@property (nonatomic) NSDate *endDate;
// The text has a date but no time.
@property (nonatomic) BOOL allDay;
// nil if the text doesn't name a time zone.
@property (nonatomic) NSTimeZone *timeZone;
// nil if the text has no "at <place>".
@property (nonatomic, copy) NSString *location;
// Where the place's name is in the text ({NSNotFound, 0} if none).
@property (nonatomic) NSRange locationRange;
// The parts of the text that were understood (NSRange values).
@property (nonatomic) NSArray<NSValue *> *tokenRanges;
@end

@interface NLEventParser : NSObject
+ (NLEventDraft *)parse:(NSString *)text
               calendar:(NSCalendar *)calendar
                    now:(NSDate *)now
 defaultDurationMinutes:(NSInteger)defaultDurationMinutes;
// The time zone a word or phrase names ("DE", "CET", "Berlin",
// "Germany"), or nil.
+ (NSTimeZone *)timeZoneForName:(NSString *)name;
@end
