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

#define kBasicPhoneBaseURL @"http://localhost"
#define kLoginEndpoint @"auth.php"

@interface PKTViewController ()

@property (strong, nonatomic) PKTCallViewController *callViewController;

@end

@implementation PKTViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    __block UIButton *callButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [callButton setTitle:@"Call Support" forState:UIControlStateNormal];
    callButton.frame = CGRectMake(0, 0, 100, 50);
    callButton.center = self.view.center;
    [callButton addTarget:self action:@selector(didTapCall:) forControlEvents:UIControlEventTouchUpInside];
    callButton.enabled = NO;
    [self.view addSubview:callButton];
    
    NSURL *baseURL = [NSURL URLWithString:kBasicPhoneBaseURL];
    AFHTTPRequestOperationManager *manager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:baseURL];
//    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
//    manager.responseSerializer.acceptableContentTypes =
//        [manager.responseSerializer.acceptableContentTypes setByAddingObject:@"text/html"];
    
//    [manager setCredential:[NSURLCredential credentialWithUser:@"" password:@"" persistence:NSURLCredentialPersistenceForSession]];
    
    [manager GET:kLoginEndpoint parameters:@{}
    success:^(AFHTTPRequestOperation *operation, id responseObject) {
//        NSString *token = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
        [self setupPhoneKitWithToken:responseObject[@"token"]];
        callButton.enabled = YES;
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"error: %@", error);
    }];

}

- (void)setupPhoneKitWithToken:(NSString *)token
{
    [PKTPhone sharedPhone].capabilityToken = token;
    self.callViewController = [PKTCallViewController new];
    self.callViewController.mainText = @"Support";
    [PKTPhone sharedPhone].delegate = self.callViewController;
}

- (void)didTapCall:(id)sender
{
    [[PKTPhone sharedPhone] callWithParams:@{}];
}

@end
