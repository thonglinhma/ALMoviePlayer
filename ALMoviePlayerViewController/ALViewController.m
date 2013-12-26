//
//  ALViewController.m
//  ALMoviePlayerViewController
//
//  Created by Mike Tran on 26/12/13.
//  Copyright (c) 2013 Abcdefghijk Lab. All rights reserved.
//

#import "ALViewController.h"
#import "ALMoviePlayerViewController.h"
#import "ALVimeoExtractor.h"


@interface ALViewController ()

@end

@implementation ALViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
     [[UIApplication sharedApplication] setStatusBarHidden:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (IBAction)playButtonPressed:(id)sender
{
    __weak __typeof(self) weakSelf = self;
    
    [ALVimeoExtractor fetchVideoURLFromID:@"80672309" quality:ALVimeoVideoQualityLow completionHandler:^(NSURL *videoURL, NSError *error, ALVimeoVideoQuality quality) {
        __strong __typeof(self) strongSelf = weakSelf;
        
        if (!error) {
            
            ALMoviePlayerViewController *moviePlayerViewController = [[ALMoviePlayerViewController alloc] initWithContentURL:videoURL];
            //[moviePlayerViewController setContentURL:videoURL];
            [strongSelf presentViewController:moviePlayerViewController animated:YES completion:nil];
            
        } else {
            UIAlertView *alerView = [[UIAlertView alloc] initWithTitle:[error localizedDescription] message:nil delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
            [alerView show];
        }
    }];
}

@end
