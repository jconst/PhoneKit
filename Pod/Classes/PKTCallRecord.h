#import <Foundation/Foundation.h>

#ifdef COCOAPODS_POD_AVAILABLE_Mantle
# import "Mantle.h"
# define MODEL_SUPER MTLModel
#else
# define MODEL_SUPER NSObject
#endif

@interface PKTCallRecord : MODEL_SUPER

@property (nonatomic, assign) BOOL      incoming;
@property (nonatomic, assign) BOOL      missed;
@property (nonatomic, assign) NSInteger duration;
@property (nonatomic, strong) NSString  *number;
@property (nonatomic, strong) NSString  *city;
@property (nonatomic, strong) NSString  *state;
@property (nonatomic, strong) NSDate    *dateTime;


@end
