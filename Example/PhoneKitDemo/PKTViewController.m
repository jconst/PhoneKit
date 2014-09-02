//
//  PKTViewController.m
//  PhoneKit
//
//  Created by Joseph Constantakis on 07/08/2014.
//  Copyright (c) 2014 Joseph Constantakis. All rights reserved.
//

#import "PKTViewController.h"
#import "UIView+FrameAccessor.h"
#import "AFNetworking.h"
#import "PKTPhone.h"
#import "PKTCallViewController.h"
#import "NSString+PKTHelpers.h"

#warning replace with the URL of your server
#define kServerBaseURL @"https://twilio-client-server.herokuapp.com"
#define kTokenEndpoint @"auth.php"

@implementation PKTViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    NSURL *baseURL = [NSURL URLWithString:kServerBaseURL];
    AFHTTPRequestOperationManager *manager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:baseURL];
    
    [manager GET:kTokenEndpoint parameters:@{@"clientName": @"demo"}
    success:^(AFHTTPRequestOperation *operation, id responseObject) {
        [self setupPhoneKitWithToken:responseObject[@"token"]];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"error: %@", error);
    }];
}

- (void)setupPhoneKitWithToken:(NSString *)token
{
    [PKTPhone sharedPhone].capabilityToken = token;
    NSLog(@"Token has been set with capabilities: %@", [PKTPhone sharedPhone].phoneDevice.capabilities);

    self.callViewController = [PKTCallViewController new];
    [PKTPhone sharedPhone].delegate = self.callViewController;
}

- (void)didTapCall:(id)sender
{
    if (self.calleeField.text.length &&
        !self.callerIdField.text.length &&
        ![self.calleeField.text isClientNumber]) {
        [[[UIAlertView alloc] initWithTitle:@"Set a caller id first"
                                    message:@"To call a real phone, you need to set the caller id "
                                             "(to a number verified for your Twilio account) first."
                                   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        return;
    }
    
    self.callViewController.mainText = self.calleeField.text;
    [PKTPhone sharedPhone].callerId = self.callerIdField.text;
    [[PKTPhone sharedPhone] call:self.calleeField.text];
}

@end