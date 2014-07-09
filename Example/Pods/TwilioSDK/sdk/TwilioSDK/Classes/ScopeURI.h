//
//  ScopeURI.h
//  TwilioSDK
//
//  Created by Chris Wendel on 8/1/12.
//
//

//
// A ScopeURI is included in the JWT payload under the "scope" key.
// Multiple ScopeURIs may be attached to the key, separated by spaces.
// A ScopeURI is a string of the following format:
// "scope:<service>:<privilege>?<params>"
//
// For example:
// scope:client:incoming?name=jonas&foo=bar
// This class is a convenience class for splitting a scope URI string into
// its constituent parts.
//
@interface ScopeURI : NSObject
{
@private
	NSString*		_service;
	NSString*		_privilege;
	NSDictionary*	_params; // may be nil
}
@property (nonatomic, retain) NSString* service;
@property (nonatomic, retain) NSString* privilege;
@property (nonatomic, retain) NSDictionary* params;


-(id)initWithString:(NSString*)scopeURIString;
-(NSString*)toString;

@end