@interface NSString (PKTHelpers)

- (BOOL)isClientNumber;
- (BOOL)equalsPhoneNumber:(NSString *)number;
- (NSString *)stripToDigitsOnly;
- (NSString *)sanitizeNumber;
- (NSString *)sanitizeNumberAndRemoveOne;

@end
