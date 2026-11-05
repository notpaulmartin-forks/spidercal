//
//  NLEventParser.m
//  Spidercal
//

#import "NLEventParser.h"

@implementation NLEventDraft
@end

// Country code -> the time zone most people there mean.
static NSDictionary<NSString *, NSString *> *CountryZones(void)
{
    static NSDictionary *zones;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zones = @{
            @"DE": @"Europe/Berlin",    @"UK": @"Europe/London",   @"GB": @"Europe/London",
            @"FR": @"Europe/Paris",     @"ES": @"Europe/Madrid",   @"IT": @"Europe/Rome",
            @"NL": @"Europe/Amsterdam", @"BE": @"Europe/Brussels", @"CH": @"Europe/Zurich",
            @"AT": @"Europe/Vienna",    @"PL": @"Europe/Warsaw",   @"SE": @"Europe/Stockholm",
            @"NO": @"Europe/Oslo",      @"DK": @"Europe/Copenhagen", @"FI": @"Europe/Helsinki",
            @"IE": @"Europe/Dublin",    @"PT": @"Europe/Lisbon",   @"GR": @"Europe/Athens",
            @"CZ": @"Europe/Prague",    @"HU": @"Europe/Budapest", @"RO": @"Europe/Bucharest",
            @"TR": @"Europe/Istanbul",  @"UA": @"Europe/Kyiv",     @"IL": @"Asia/Jerusalem",
            @"AE": @"Asia/Dubai",       @"IN": @"Asia/Kolkata",    @"SG": @"Asia/Singapore",
            @"HK": @"Asia/Hong_Kong",   @"CN": @"Asia/Shanghai",   @"JP": @"Asia/Tokyo",
            @"KR": @"Asia/Seoul",       @"TH": @"Asia/Bangkok",    @"ID": @"Asia/Jakarta",
            @"AU": @"Australia/Sydney", @"NZ": @"Pacific/Auckland",
            @"ZA": @"Africa/Johannesburg", @"EG": @"Africa/Cairo", @"NG": @"Africa/Lagos",
            @"KE": @"Africa/Nairobi",
            @"US": @"America/New_York", @"CA": @"America/Toronto", @"MX": @"America/Mexico_City",
            @"BR": @"America/Sao_Paulo", @"AR": @"America/Argentina/Buenos_Aires",
            @"CL": @"America/Santiago", @"CO": @"America/Bogota",
        };
    });
    return zones;
}

// Lowercased city and country names -> time zone name.
static NSDictionary<NSString *, NSString *> *NamedZones(void)
{
    static NSDictionary *named;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *d = [NSMutableDictionary new];
        // Cities: the last part of each zone name, e.g. "new york".
        for (NSString *zone in [NSTimeZone knownTimeZoneNames]) {
            NSString *city = [[zone lastPathComponent] stringByReplacingOccurrencesOfString:@"_" withString:@" "];
            d[city.lowercaseString] = zone;
        }
        // Countries, in English and in the user's language.
        NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        [CountryZones() enumerateKeysAndObjectsUsingBlock:^(NSString *code, NSString *zone, BOOL *stop) {
            NSString *isoCode = [code isEqualToString:@"UK"] ? @"GB" : code;
            for (NSLocale *locale in @[english, NSLocale.currentLocale]) {
                NSString *country = [locale localizedStringForCountryCode:isoCode];
                if (country.length) d[country.lowercaseString] = zone;
            }
        }];
        d[@"uk"] = @"Europe/London";
        d[@"britain"] = @"Europe/London";
        d[@"england"] = @"Europe/London";
        d[@"usa"] = @"America/New_York";
        named = d;
    });
    return named;
}

// Lowercase words -> time zone name, for "<word> time": the people
// of a country ("german time") and names for zones ("pacific time").
static NSDictionary<NSString *, NSString *> *AdjectiveZones(void)
{
    static NSDictionary *zones;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        zones = @{
            @"german": @"Europe/Berlin",     @"british": @"Europe/London",   @"english": @"Europe/London",
            @"scottish": @"Europe/London",   @"welsh": @"Europe/London",     @"french": @"Europe/Paris",
            @"spanish": @"Europe/Madrid",    @"italian": @"Europe/Rome",     @"dutch": @"Europe/Amsterdam",
            @"belgian": @"Europe/Brussels",  @"swiss": @"Europe/Zurich",     @"austrian": @"Europe/Vienna",
            @"polish": @"Europe/Warsaw",     @"swedish": @"Europe/Stockholm", @"norwegian": @"Europe/Oslo",
            @"danish": @"Europe/Copenhagen", @"finnish": @"Europe/Helsinki", @"irish": @"Europe/Dublin",
            @"portuguese": @"Europe/Lisbon", @"greek": @"Europe/Athens",     @"czech": @"Europe/Prague",
            @"hungarian": @"Europe/Budapest", @"romanian": @"Europe/Bucharest", @"turkish": @"Europe/Istanbul",
            @"ukrainian": @"Europe/Kyiv",    @"israeli": @"Asia/Jerusalem",  @"emirati": @"Asia/Dubai",
            @"indian": @"Asia/Kolkata",      @"singaporean": @"Asia/Singapore", @"chinese": @"Asia/Shanghai",
            @"japanese": @"Asia/Tokyo",      @"korean": @"Asia/Seoul",       @"thai": @"Asia/Bangkok",
            @"indonesian": @"Asia/Jakarta",  @"australian": @"Australia/Sydney", @"egyptian": @"Africa/Cairo",
            @"nigerian": @"Africa/Lagos",    @"kenyan": @"Africa/Nairobi",   @"south african": @"Africa/Johannesburg",
            @"american": @"America/New_York", @"canadian": @"America/Toronto", @"mexican": @"America/Mexico_City",
            @"brazilian": @"America/Sao_Paulo", @"argentine": @"America/Argentina/Buenos_Aires",
            @"argentinian": @"America/Argentina/Buenos_Aires", @"chilean": @"America/Santiago",
            @"colombian": @"America/Bogota",
            @"central european": @"Europe/Berlin", @"eastern": @"America/New_York", @"central": @"America/Chicago",
            @"mountain": @"America/Denver",  @"pacific": @"America/Los_Angeles",
        };
    });
    return zones;
}

// Country codes and abbreviations that, in lowercase, are ordinary
// words: "arrive in time", "no time", "it's time", "pet time".
static NSSet<NSString *> *WordsThatAreNotZones(void)
{
    static NSSet *words;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        words = [NSSet setWithArray:@[@"in", @"no", @"it", @"at", @"be", @"us", @"id", @"co", @"ar", @"th", @"is", @"es",
                                      @"art", @"cat", @"cot", @"eat", @"pet", @"wet", @"wit", @"west", @"nst", @"ast"]];
    });
    return words;
}

static NSRegularExpression *Regex(NSString *pattern)
{
    return [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
}

@implementation NLEventParser

+ (NSTimeZone *)timeZoneForName:(NSString *)name
{
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (name.length < 2) return nil;
    BOOL isUppercase = [name isEqualToString:name.uppercaseString] &&
                       ![name isEqualToString:name.lowercaseString];
    if (isUppercase) {
        // Country codes and abbreviations must be typed in capitals
        // so words like "is", "in" and "est" are left alone.
        NSString *zone = name.length == 2 ? CountryZones()[name] : nil;
        if (zone) return [NSTimeZone timeZoneWithName:zone];
        if (name.length >= 3 && name.length <= 5) {
            NSString *abbreviated = [NSTimeZone abbreviationDictionary][name];
            if (abbreviated) return [NSTimeZone timeZoneWithName:abbreviated];
        }
    }
    NSString *zone = NamedZones()[name.lowercaseString];
    return zone ? [NSTimeZone timeZoneWithName:zone] : nil;
}

// The word(s) before "time" name the zone, which makes them safe to
// read more loosely than a bare word: any case, and "german" too.
+ (NSTimeZone *)timeZoneNamedBeforeTimeWord:(NSString *)name
{
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSTimeZone *zone = [self timeZoneForName:name];
    if (zone) return zone;
    NSString *lowercase = name.lowercaseString;
    if ([WordsThatAreNotZones() containsObject:lowercase]) return nil;
    NSString *adjective = AdjectiveZones()[lowercase];
    if (adjective) return [NSTimeZone timeZoneWithName:adjective];
    return [self timeZoneForName:name.uppercaseString];
}

+ (NLEventDraft *)parse:(NSString *)text calendar:(NSCalendar *)calendar now:(NSDate *)now defaultDurationMinutes:(NSInteger)defaultDurationMinutes
{
    NLEventDraft *draft = [NLEventDraft new];
    draft.locationRange = NSMakeRange(NSNotFound, 0);
    NSMutableArray<NSValue *> *tokens = [NSMutableArray new];
    // Same length as text. Understood parts are blanked out with
    // U+0001 so later steps skip them and ranges stay valid.
    NSMutableString *mask = [text mutableCopy];
    void (^claim)(NSRange) = ^(NSRange range) {
        [tokens addObject:[NSValue valueWithRange:range]];
        NSString *blank = [@"" stringByPaddingToLength:range.length withString:@"\x01" startingAtIndex:0];
        [mask replaceCharactersInRange:range withString:blank];
    };
    NSRange whole = NSMakeRange(0, text.length);

    // ---- Time zone: "<name> time" (DE time, Berlin time, New York time)
    NSTimeZone *timeZone = nil;
    for (NSTextCheckingResult *m in [Regex(@"\\btime\\b") matchesInString:mask options:0 range:whole]) {
        // Try the 3, 2 and 1 words before "time".
        NSString *before = [mask substringToIndex:m.range.location];
        NSArray<NSTextCheckingResult *> *words = [Regex(@"[\\p{L}.]+") matchesInString:before options:0 range:NSMakeRange(0, before.length)];
        for (NSInteger n = MIN(3, (NSInteger)words.count); n >= 1 && !timeZone; n--) {
            NSUInteger start = words[words.count - n].range.location;
            NSString *gap = [before substringFromIndex:NSMaxRange(words.lastObject.range)];
            if ([gap stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) break;
            // Letters at the end of a number aren't a word: "4th time".
            if (start > 0 && [NSCharacterSet.decimalDigitCharacterSet characterIsMember:[before characterAtIndex:start - 1]]) continue;
            NSString *name = [before substringFromIndex:start];
            timeZone = [self timeZoneNamedBeforeTimeWord:name];
            if (timeZone) claim(NSMakeRange(start, NSMaxRange(m.range) - start));
        }
        if (timeZone) break;
    }
    // ---- Time zone: a bare abbreviation in capitals (CET, PST, UTC)
    if (!timeZone) {
        NSRegularExpression *abbr = [NSRegularExpression regularExpressionWithPattern:@"\\b[A-Z]{3,5}\\b" options:0 error:NULL];
        for (NSTextCheckingResult *m in [abbr matchesInString:mask options:0 range:whole]) {
            NSString *name = [mask substringWithRange:m.range];
            if ([NSTimeZone abbreviationDictionary][name]) {
                timeZone = [self timeZoneForName:name];
                if (timeZone) { claim(m.range); break; }
            }
        }
    }
    draft.timeZone = timeZone;

    // ---- Duration: "for 2 hours", "for 45 min"
    NSTimeInterval duration = 0;
    NSTextCheckingResult *dm = [Regex(@"\\bfor\\s+(\\d+(?:[.,]\\d+)?)\\s*(hours?|hrs?|h|minutes?|mins?|m)\\b") firstMatchInString:mask options:0 range:whole];
    if (dm) {
        NSString *number = [[mask substringWithRange:[dm rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"," withString:@"."];
        NSString *unit = [mask substringWithRange:[dm rangeAtIndex:2]].lowercaseString;
        duration = number.doubleValue * ([unit hasPrefix:@"h"] ? 3600 : 60);
        claim(dm.range);
    }

    // ---- Dates and times
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate error:NULL];
    // The detector must not see the blanks as text.
    NSString *detectable = [mask stringByReplacingOccurrencesOfString:@"\x01" withString:@" "];
    NSRegularExpression *timeRegex = Regex(@"\\b\\d{1,2}(?:[:.]\\d{2})?\\s*(?:am|pm|a\\.m\\.|p\\.m\\.)|\\b\\d{1,2}:\\d{2}\\b|\\b(?:noon|midnight|morning|afternoon|evening|tonight)\\b");
    NSDate *dayDate = nil, *timeDate = nil;
    BOOL hasExplicitYear = NO;
    NSTimeInterval detectedDuration = 0;
    for (NSTextCheckingResult *m in [detector matchesInString:detectable options:0 range:whole]) {
        if (!m.date) continue;
        NSString *matched = [detectable substringWithRange:m.range];
        NSRange matchedRange = NSMakeRange(0, matched.length);
        BOOL hasTime = [timeRegex firstMatchInString:matched options:0 range:matchedRange] != nil;
        NSString *rest = [timeRegex stringByReplacingMatchesInString:matched options:0 range:matchedRange withTemplate:@""];
        rest = [Regex(@"\\b(?:at|on|from|to|until|till)\\b|[\\s,.\\-–]") stringByReplacingMatchesInString:rest options:0 range:NSMakeRange(0, rest.length) withTemplate:@""];
        BOOL hasDay = rest.length > 0;
        if (!hasTime && !hasDay) continue;
        if (hasDay && !dayDate) {
            dayDate = m.date;
            hasExplicitYear = [Regex(@"\\b\\d{4}\\b") firstMatchInString:matched options:0 range:matchedRange] != nil;
        }
        if (hasTime && !timeDate) {
            timeDate = m.date;
            detectedDuration = m.duration;
        }
        // Take the "on"/"at"/"from" in front of it too.
        NSRange range = m.range;
        NSTextCheckingResult *prep = [Regex(@"\\b(?:on|at|from)\\s+$") firstMatchInString:detectable options:0 range:NSMakeRange(0, range.location)];
        if (prep) range = NSMakeRange(prep.range.location, NSMaxRange(range) - prep.range.location);
        claim(range);
    }
    if (duration == 0) duration = detectedDuration;

    // ---- Location: "at <place>" or "@ <place>", up to the next
    // understood part or the end.
    NSRegularExpression *locRegex = [NSRegularExpression regularExpressionWithPattern:@"(?:^|\\s)(?:at|@)\\s+([^\\x01]*[^\\x01\\s,;])" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *lm = [locRegex firstMatchInString:mask options:0 range:whole];
    if (lm) {
        NSRange nameRange = [lm rangeAtIndex:1];
        draft.location = [text substringWithRange:nameRange];
        draft.locationRange = nameRange;
        NSRange range = lm.range;
        // Don't claim the space in front of "at".
        while (range.length && [NSCharacterSet.whitespaceCharacterSet characterIsMember:[text characterAtIndex:range.location]]) {
            range.location++; range.length--;
        }
        claim(range);
    }

    // ---- Title: what is left
    NSString *title = [mask stringByReplacingOccurrencesOfString:@"\x01" withString:@" "];
    title = [Regex(@"\\s+") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@" "];
    title = [Regex(@"\\s+([,;])") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@"$1"];
    title = [Regex(@"([,;])(?:\\s*[,;])+") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@"$1"];
    NSMutableCharacterSet *trim = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [trim addCharactersInString:@",;-–—"];
    title = [title stringByTrimmingCharactersInSet:trim];
    // A preposition left dangling at the end, e.g. "Lunch on".
    title = [Regex(@"\\s+(?:on|at|from|in)$") stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
    draft.title = [title stringByTrimmingCharactersInSet:trim];
    draft.tokenRanges = tokens;

    // ---- Start and end
    if (!dayDate && !timeDate) return draft;

    NSCalendarUnit ymd = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
    NSDateComponents *c = [calendar components:ymd fromDate:dayDate ?: timeDate];
    if (dayDate && !hasExplicitYear) {
        // "12 Nov" means the next 12 Nov, not one that has passed.
        NSDate *day = [calendar dateFromComponents:c];
        NSDate *today = [calendar startOfDayForDate:now];
        if ([day compare:today] == NSOrderedAscending &&
            [today timeIntervalSinceDate:day] > 2 * 86400) {
            NSDate *nextYear = [calendar dateByAddingUnit:NSCalendarUnitYear value:1 toDate:day options:0];
            NSDate *aYearAgo = [calendar dateByAddingUnit:NSCalendarUnitYear value:-1 toDate:today options:0];
            // Only if the detector guessed this year, not for
            // phrases like "last Friday".
            if ([day compare:aYearAgo] == NSOrderedDescending &&
                [Regex(@"\\b(?:last|yesterday|ago)\\b") firstMatchInString:text options:0 range:whole] == nil) {
                c = [calendar components:ymd fromDate:nextYear];
            }
        }
    }

    if (!timeDate) {
        draft.allDay = YES;
        draft.startDate = [calendar dateFromComponents:c];
        NSInteger extraDays = duration >= 86400 ? (NSInteger)(duration / 86400) : 0;
        draft.endDate = [calendar dateByAddingUnit:NSCalendarUnitDay value:extraDays toDate:draft.startDate options:0];
        return draft;
    }

    NSDateComponents *t = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:timeDate];
    c.hour = t.hour;
    c.minute = t.minute;
    // The wall-clock time is in the named time zone, if any.
    NSCalendar *zoned = [calendar copy];
    if (timeZone) zoned.timeZone = timeZone;
    NSDate *start = [zoned dateFromComponents:c];
    if (!dayDate && [start compare:now] == NSOrderedAscending) {
        // Just a time, and it has passed today: tomorrow.
        start = [zoned dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];
    }
    draft.startDate = start;
    if (duration <= 0) duration = MAX(defaultDurationMinutes, 1) * 60;
    draft.endDate = [start dateByAddingTimeInterval:duration];
    return draft;
}

@end
