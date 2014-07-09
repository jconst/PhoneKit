//
//  ScopeURI.m
//  TwilioSDK
//
//  Created by Chris Wendel on 8/1/12.
//
//

#import "ScopeURI.h"

@implementation ScopeURI

@synthesize service = _service;
@synthesize privilege = _privilege;
@synthesize params = _params;

-(id)initWithString:(NSString *)scopeURIString
{
	if ( [scopeURIString length] == 0 )
		return nil; // fail!
	
	if ( self = [super init] )
	{
		if ( [scopeURIString rangeOfString:@"scope:"].length == 0 ) // error
			return nil;
		
		NSArray* stringParts = [scopeURIString componentsSeparatedByString:@":"];
		if ( [stringParts count] != 3 )
		{
			NSLog(@"scope URI should have 3 parts");
			return nil;
		}
		
		// "scope:" is the first part of the string; we don't care about that.
		
		// Get the value for "service"
		self.service = [stringParts objectAtIndex:1];
        
		// Get the value for "privilege", which is the portion up to but not including the optional ?
		NSString* privilegeWithParams = [stringParts objectAtIndex:2];
		NSRange paramsRange = [privilegeWithParams rangeOfString:@"?"];
		if ( paramsRange.length == 0 )
			self.privilege = [stringParts objectAtIndex:2];
		else
			self.privilege = [privilegeWithParams substringToIndex:paramsRange.location];
        
		// Get the value for "params", which is the portion after the optional ?,
		// a set of key=value pairs, where the values are URL-encoded.
		if ( paramsRange.length != 0 )
		{
			NSString* paramsString = [privilegeWithParams substringFromIndex:paramsRange.location+1];
			
			NSMutableDictionary* parameters = [NSMutableDictionary dictionaryWithCapacity:1]; // autoreleased
			for (NSString* queryPart in [paramsString componentsSeparatedByString:@"&"])
			{
				NSArray* keyValue = [queryPart componentsSeparatedByString:@"="];
                if( keyValue.count > 1) // If keyValue only has 0 or 1 elements, objectAtIndex:1 is out of bounds
                    [parameters setObject:[keyValue objectAtIndex:1] forKey:[keyValue objectAtIndex:0]];
			}
			
			self.params = parameters; //retains
		}
	}
	
    //		NSLog(@"Scope URI service is %@", self.service );
    //		NSLog(@"        privilege is %@", self.privilege );
    //		NSLog(@"		   params is %@", [self.params description] );
	
	return self;
}

-(void)dealloc
{
	self.service = nil;
	self.privilege = nil;
	self.params = nil;
	[super dealloc];
}


-(NSString*)toString
{
	// don't return anything if the object hasn't been initialized.
	if ( _service == nil && _privilege == nil )
		return nil;
	
	NSMutableString* string = [[[NSMutableString alloc] init] autorelease];
	[string appendString:@"scope:"];
	[string appendString:self.service];
	[string appendString:@":"];
	[string appendString:self.privilege];
	
	NSUInteger paramsCount = [self.params count];
	if ( paramsCount > 0 )
	{
		[string appendString:@"?"];
		
		NSArray* keys = [self.params allKeys];
		NSUInteger loopIndex = 0;
		for ( NSString* key in keys )
		{
			loopIndex++;
			[string appendString:key];
			[string appendString:@"="];
			[string appendString:[self.params objectForKey:key]];
			if ( loopIndex != paramsCount )
				[string appendString:@"&"];
		}
	}
	return string;
}

@end