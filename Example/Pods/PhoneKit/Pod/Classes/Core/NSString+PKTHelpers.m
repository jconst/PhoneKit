#import "ReactiveCocoa.h"
#import "NSString+PKTHelpers.h"

@implementation NSString (PKTHelpers)

- (BOOL)isClientNumber
{
    // (This isn't precise E.164 parsing, but it's easy enough for now.)
	NSCharacterSet* charsetForClient = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789+-()  "] invertedSet];
	return [self rangeOfCharacterFromSet:charsetForClient].location != NSNotFound;
}

- (BOOL)equalsPhoneNumber:(NSString *)number
{
    if (!number)
        return NO;
    
    NSString* stripped = [number stripToDigitsOnly];
    
    return [[self stripToDigitsOnly] isEqualToString:stripped];
}

- (NSString *)stripToDigitsOnly
{
    NSCharacterSet *strippingCharSet = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    return [[self componentsSeparatedByCharactersInSet:strippingCharSet] componentsJoinedByString:@""];
}

- (NSString *)sanitizeNumber
{
    if ([self isClientNumber]) {
        NSRange clientColonRange = [self rangeOfString:@"client:"];
        if (clientColonRange.location != NSNotFound &&
            [self length] > clientColonRange.location + clientColonRange.length) {
            return [self substringFromIndex:clientColonRange.location + clientColonRange.length];
        } else {
            return self;
        }
    } else {
        return [self stripToDigitsOnly];
    }
}

- (NSString *)sanitizeNumberAndRemoveOne
{
    NSString *sanitized = self;
    sanitized = [self sanitizeNumber];
    if (!sanitized.length)
        return sanitized;
    if (![self isClientNumber] &&
        [sanitized characterAtIndex:0] == '1') {
        sanitized = [sanitized substringFromIndex:1];
    }
    return sanitized;
}

@end
