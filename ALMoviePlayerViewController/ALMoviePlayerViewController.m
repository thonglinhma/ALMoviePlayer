//
//  ALMoviePlayerViewController.m
//  FlairInteriors
//
//  The MIT License (MIT)
//
//  Copyright (c) 2013 Abcdefghijk Lab. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//



#import "ALMoviePlayerViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <MobileCoreServices/MobileCoreServices.h>

BOOL ALIsLandscapePhoneOrientation(UIInterfaceOrientation orientation)
{
    return UIInterfaceOrientationIsLandscape(orientation);
}

/*
 Player view backed by an AVPlayerLayer
 */
@interface ALPlayerView : UIView

@property (nonatomic, strong) AVPlayer *player;

@end

@implementation ALPlayerView

+ (Class)layerClass
{
	return [AVPlayerLayer class];
}

- (AVPlayer *)player
{
	return [(AVPlayerLayer *)[self layer] player];
}

- (void)setPlayer:(AVPlayer *)player
{
	[(AVPlayerLayer *)[self layer] setPlayer:player];
}

@end

static NSString* const ALMoviePlayerViewControllerStatusObservationContext	= @"ALMoviePlayerViewControllerStatusObservationContext";
static NSString* const ALMoviePlayerViewControllerRateObservationContext = @"ALMoviePlayerViewControllerRateObservationContext";

@interface ALMoviePlayerViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;


- (void)updatePlayPauseButton;
- (void)updateScrubber;
- (void)updateTimeLabel;
- (CMTime)playerItemDuration;
- (void)scrubToSliderValue:(float)sliderValue;

- (void)setUpPlaybackOfAsset:(AVAsset *)asset withKeys:(NSArray *)keys;
- (void)synchronizePlayerWithEditor;

- (void)addTimeObserverToPlayer;
- (void)removeTimeObserverFromPlayer;

- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated permanent:(BOOL)permanent;
- (BOOL)areControlsHidden;
- (void)hideControls;
- (void)toggleControls;
- (void)cancelControlHiding;

- (UIImage*)takeScreenshot;
- (UIImage*)rotateImageToCurrentOrientation:(UIImage*)image;

- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation;
- (CGRect)frameForDoneButtonAtOrientation:(UIInterfaceOrientation)orientation;

- (void)reportError:(NSError *)error;

- (void)dismissAnimated:(BOOL)animated;

- (void)handleTapGesture:(UITapGestureRecognizer *)tapGestureRecognizer;
- (void)handlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer;
- (void)togglePlayPause:(id)sender;

- (void)beginScrubbing:(id)sender;
- (void)scrub:(id)sender;
- (void)endScrubbing:(id)sender;

- (void)doneButtonPressed:(id)sender;

@end

@implementation ALMoviePlayerViewController {
@private
	BOOL _playing;
	BOOL _scrubInFlight;
	BOOL _seekToZeroBeforePlaying;
	float _lastScrubSliderValue;
	float _playRateToRestore;
	id	 _timeObserver;
    BOOL _autoHide;
    
    ALPlayerView *_playerView;
    
    UIButton *_doneButton;
    UIToolbar *_toolbar;
    UISlider *_scrubber;
    UIBarButtonItem *_playPauseButton;
    UILabel *_currentTimeLabel;
    UILabel *_elapsedTimeLabel;
    
    NSTimer *_controlVisibilityTimer;
    AVAsset *_inputAsset;
    UIImage *_backgroundScreenshot;
    UIImageView *_backgroundScreenshotView;
    UIView *_overlayBackgroundView;
    
    UIWindow *_applicationWindow;
    
    UIActivityIndicatorView *_loadingSpinner;
    
    UIPanGestureRecognizer *_panGesture;
    UITapGestureRecognizer *_tapGesture;
}


- (instancetype)init
{
    return [self initWithContentURL:nil];
}

- (instancetype)initWithContentURL:(NSURL *)contentURL
{
    self = [super init];
    if (self) {
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        self.automaticallyAdjustsScrollViewInsets = NO;
        
        self->_applicationWindow = [[[UIApplication sharedApplication] delegate] window];
        self->_autoHide = YES;
        
        AVURLAsset *asset = [AVURLAsset assetWithURL:contentURL];
        self->_inputAsset = asset;
        
        NSArray *assetKeysToLoadAndTest = @[@"tracks", @"duration", @"composable"];
        
        [asset loadValuesAsynchronouslyForKeys:assetKeysToLoadAndTest completionHandler:^(){
            dispatch_async( dispatch_get_main_queue(), ^{
                // IMPORTANT: Must dispatch to main queue in order to operate on the AVPlayer and AVPlayerItem.
                [self setUpPlaybackOfAsset:asset withKeys:assetKeysToLoadAndTest];
            });
        }];
    }
    
    return self;
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    self->_backgroundScreenshotView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:_backgroundScreenshotView];
    
    self->_overlayBackgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    _overlayBackgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:1];
    [self.view addSubview:_overlayBackgroundView];
    
    UIInterfaceOrientation currentOrientation = [UIApplication sharedApplication].statusBarOrientation;
    
    self->_playerView = [[ALPlayerView alloc] initWithFrame:self.view.bounds];
    _playerView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_playerView];
    
    self->_loadingSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _loadingSpinner.hidesWhenStopped = YES;
    _loadingSpinner.center = _playerView.center;
    [_playerView addSubview:_loadingSpinner];

    
    self->_toolbar = ({
        UIToolbar *toolbar = [[UIToolbar alloc] init];
        toolbar.backgroundColor = [UIColor clearColor];
        toolbar.tintColor = [UIColor whiteColor];
        toolbar.frame = [self frameForToolbarAtOrientation:currentOrientation];
        toolbar.clipsToBounds = YES;
        toolbar.translucent = YES;
        [toolbar setBackgroundImage:[UIImage new]
                  forToolbarPosition:UIToolbarPositionAny
                          barMetrics:UIBarMetricsDefault];
        

        self->_currentTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 45, 33)];
        _currentTimeLabel.textAlignment = NSTextAlignmentCenter;
        _currentTimeLabel.backgroundColor = [UIColor clearColor];
        _currentTimeLabel.font  = [UIFont systemFontOfSize:14];
        
        self->_elapsedTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 45, 33)];
        _elapsedTimeLabel.textAlignment = NSTextAlignmentCenter;
        _elapsedTimeLabel.backgroundColor = [UIColor clearColor];
        _elapsedTimeLabel.font  = [UIFont systemFontOfSize:14];

        
        self->_scrubber = ({
            UISlider *scrubber = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 150, 33)];
            [scrubber setThumbImage:[UIImage imageNamed:@"FBVideoScrubber_Thumb"] forState:UIControlStateNormal];
            [scrubber addTarget:self action:@selector(endScrubbing:) forControlEvents:UIControlEventTouchUpInside];
            [scrubber addTarget:self action:@selector(endScrubbing:) forControlEvents:UIControlEventTouchUpOutside];
            [scrubber addTarget:self action:@selector(beginScrubbing:) forControlEvents:UIControlEventTouchDown];
            [scrubber addTarget:self action:@selector(endScrubbing:) forControlEvents:UIControlEventTouchCancel];
            [scrubber addTarget:self action:@selector(scrub:) forControlEvents:UIControlEventValueChanged];
            scrubber;
        });
        
        self->_playPauseButton = ({
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.frame = CGRectMake(0, 0, 24, 24);
            [button setImage:[UIImage imageNamed:@"videoPlayButton"] forState:UIControlStateNormal];
            [button addTarget:self action:@selector(togglePlayPause:) forControlEvents:UIControlEventTouchUpInside];
            
            UIBarButtonItem *buttonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
            buttonItem;
        });
        
        UIBarButtonItem *currentTimeButton = [[UIBarButtonItem alloc] initWithCustomView:_currentTimeLabel];
        UIBarButtonItem *eslapsedTimeButton = [[UIBarButtonItem alloc] initWithCustomView:_elapsedTimeLabel];
        UIBarButtonItem *scrubberButton = [[UIBarButtonItem alloc] initWithCustomView:_scrubber];
        
        toolbar.items = @[ _playPauseButton, currentTimeButton, scrubberButton, eslapsedTimeButton ];
        
        toolbar;
    });

    [_playerView addSubview:_toolbar];
    
    self->_doneButton = ({
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = [self frameForDoneButtonAtOrientation:currentOrientation];
        [button addTarget:self action:@selector(doneButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [button setTitleColor:[UIColor colorWithWhite:0.9 alpha:0.9] forState:UIControlStateNormal|UIControlStateHighlighted];
        [button setTitle:NSLocalizedString(@"Done", nil) forState:UIControlStateNormal];
        [button.titleLabel setFont:[UIFont boldSystemFontOfSize:11.0f]];
        [button setBackgroundColor:[UIColor colorWithWhite:0.1 alpha:0.5]];
        button.layer.cornerRadius = 3.0f;
        button.layer.borderColor = [UIColor colorWithWhite:0.9 alpha:0.9].CGColor;
        button.layer.borderWidth = 1.0f;
        button;
    });
    [_playerView addSubview:_doneButton];
    
    self->_panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    [_panGesture setMinimumNumberOfTouches:1];
    [_panGesture setMaximumNumberOfTouches:1];
    [self.view addGestureRecognizer:_panGesture];
    
    self->_tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    _tapGesture.delegate = self;
    [self.view addGestureRecognizer:_tapGesture];
    
	[self updateScrubber];
	[self updateTimeLabel];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self->_backgroundScreenshot = [self takeScreenshot];
    _backgroundScreenshotView.image = [self rotateImageToCurrentOrientation:_backgroundScreenshot];
    
    // Update UI
	[self hideControlsAfterDelay];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	
	if (!self.player) {
		_seekToZeroBeforePlaying = NO;
		self.player = [[AVPlayer alloc] init];
		[self.player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:(__bridge void *)(ALMoviePlayerViewControllerRateObservationContext)];
		[_playerView setPlayer:self.player];
	}
	
	[self addTimeObserverToPlayer];
	
	// Build AVComposition and AVVideoComposition objects for playback
    [self synchronizePlayerWithEditor];

}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	
	[self.player pause];
    [self.player removeObserver:self forKeyPath:@"rate" context:(__bridge void *)(ALMoviePlayerViewControllerRateObservationContext)];
    [self.playerItem removeObserver:self forKeyPath:@"status" context:(__bridge void *)(ALMoviePlayerViewControllerStatusObservationContext)];
	[self removeTimeObserverFromPlayer];
    
}

#pragma mark - Layout

- (void)viewWillLayoutSubviews
{
   
    UIInterfaceOrientation currentOrientation = [UIApplication sharedApplication].statusBarOrientation;
    
    _toolbar.frame = [self frameForToolbarAtOrientation:currentOrientation];
    _doneButton.frame = [self frameForDoneButtonAtOrientation:currentOrientation];
    _playerView.frame = self.view.bounds;
    _loadingSpinner.center = _playerView.center;
    _backgroundScreenshotView.frame = self.view.bounds;
    _backgroundScreenshotView.image = [self rotateImageToCurrentOrientation:_backgroundScreenshot];
    _overlayBackgroundView.frame = self.view.bounds;
    
    [super viewWillLayoutSubviews];
}


#pragma mark - Interface Orientation

- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
     return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskLandscapeLeft | UIInterfaceOrientationMaskLandscapeRight;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
}

#pragma mark - Private methods

- (UIImage*)takeScreenshot
{
    UIGraphicsBeginImageContext(_applicationWindow.bounds.size);
    [_applicationWindow.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

- (UIImage*)rotateImageToCurrentOrientation:(UIImage*)image
{
    if(UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation))
    {
        UIImageOrientation orientation = ([UIApplication sharedApplication].statusBarOrientation == UIInterfaceOrientationLandscapeLeft) ?UIImageOrientationLeft : UIImageOrientationRight;
        
        UIImage *rotatedImage = [[UIImage alloc] initWithCGImage:image.CGImage
                                                           scale:1.0
                                                     orientation:orientation];
        
        image = rotatedImage;
    }
    
    return image;
}

- (void)setUpPlaybackOfAsset:(AVAsset *)asset withKeys:(NSArray *)keys
{
	// This method is called when AVAsset has completed loading the specified array of keys.
	// playback of the asset is set up here.
	
	// Check whether the values of each of the keys we need has been successfully loaded.
	for (NSString *key in keys) {
		NSError *error = nil;
		
		if ([asset statusOfValueForKey:key error:&error] == AVKeyValueStatusFailed) {
			[self reportError:error];
			return;
		}
	}
	
	if (![asset isPlayable]) {
		// Asset cannot be played. Display the "Unplayable Asset" label.
		return;
	}
	
	if (![asset isComposable]) {
		// Asset cannot be used to create a composition (e.g. it may have protected content).
		return;
	}
    
    [self synchronizePlayerWithEditor];
}


- (void)synchronizePlayerWithEditor
{
    [_loadingSpinner startAnimating];
   	
    if ( self.player == nil )
        return;
    
    AVPlayerItem *playerItem = [[AVPlayerItem alloc] initWithAsset:_inputAsset];
    
    if (self.playerItem != playerItem) {
        if ( self.playerItem ) {
            [self.playerItem removeObserver:self forKeyPath:@"status"];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        }
        
        self.playerItem = playerItem;
        
        if ( self.playerItem ) {
            if ( [self.playerItem respondsToSelector:@selector(setSeekingWaitsForVideoCompositionRendering:)] )
                self.playerItem.seekingWaitsForVideoCompositionRendering = YES;
            
            // Observe the player item "status" key to determine when it is ready to play
            [self.playerItem addObserver:self forKeyPath:@"status" options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionInitial) context:(__bridge void *)(ALMoviePlayerViewControllerStatusObservationContext)];
            
            // When the player item has played to its end time we'll set a flag
            // so that the next time the play method is issued the player will
            // be reset to time zero first.
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
        }
        [self.player replaceCurrentItemWithPlayerItem:playerItem];
    }
}


// If permanent then we don't set timers to hide again
- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated permanent:(BOOL)permanent
{
    [[UIApplication sharedApplication] setStatusBarHidden:hidden withAnimation:animated ? UIStatusBarAnimationFade : UIStatusBarAnimationNone];
    
    // Cancel any timers
    [self cancelControlHiding];
    
    // Hide/show bars
    [UIView animateWithDuration:(animated ? 0.35 : 0) animations:^(void) {
        CGFloat alpha = hidden ? 0 : 1;
        [self.navigationController.navigationBar setAlpha:alpha];
        [_toolbar setAlpha:alpha];
        [_doneButton setAlpha:alpha];
    } completion:^(BOOL finished) {}];
	
	// Control hiding timer
	// Will cancel existing timer but only begin hiding if they are visible
	if (!permanent) [self hideControlsAfterDelay];
}

// Enable/disable control visiblity timer
- (void)hideControlsAfterDelay
{
    if (![self areControlsHidden]) {
        [self cancelControlHiding];
		_controlVisibilityTimer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(hideControls) userInfo:nil repeats:NO];
	}
}

- (BOOL)areControlsHidden
{
    return (_toolbar.alpha == 0);
}

- (void)hideControls
{
    if(_autoHide) {
        [self setControlsHidden:YES animated:YES permanent:NO];
    }
}
- (void)toggleControls
{
    [self setControlsHidden:![self areControlsHidden] animated:YES permanent:NO];
}

- (void)cancelControlHiding
{
	// If a timer exists then cancel and release
	if (_controlVisibilityTimer) {
		[_controlVisibilityTimer invalidate];
		_controlVisibilityTimer = nil;
	}
}


- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation
{
    CGFloat height = 44;
    if (ALIsLandscapePhoneOrientation(orientation))
        height = 33;
    
    return CGRectMake(0, self.view.bounds.size.height - height, self.view.bounds.size.width, height);
}

- (CGRect)frameForDoneButtonAtOrientation:(UIInterfaceOrientation)orientation
{
    CGRect screenBound = self.view.bounds;
    CGFloat screenWidth = screenBound.size.width;
    
    return CGRectMake(screenWidth - 75, 30, 55, 26);
}


- (void)reportError:(NSError *)error
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if (error) {
			UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:[error localizedDescription]
																message:[error localizedRecoverySuggestion]
															   delegate:nil
													  cancelButtonTitle:NSLocalizedString(@"OK", nil)
													  otherButtonTitles:nil];
            
			[alertView show];
		}
	});
}


- (void)updatePlayPauseButton
{
    UIImage *image = _playing ? [UIImage imageNamed:@"videoPauseButton"] : [UIImage imageNamed:@"videoPlayButton"];
    UIBarButtonItem *newPlayPauseButton = ({
        
        UIButton *buton = [UIButton buttonWithType:UIButtonTypeCustom];
        buton.frame = CGRectMake(0, 0, 28, 28);
        [buton setImage:image forState:UIControlStateNormal];
        [buton addTarget:self action:@selector(togglePlayPause:) forControlEvents:UIControlEventTouchUpInside];
        
        UIBarButtonItem *buttonItem = [[UIBarButtonItem alloc] initWithCustomView:buton];
        buttonItem;
    });
	
	NSMutableArray *items = [NSMutableArray arrayWithArray:_toolbar.items];
	[items replaceObjectAtIndex:[items indexOfObject:_playPauseButton] withObject:newPlayPauseButton];
	[_toolbar setItems:items];
	
	_playPauseButton = newPlayPauseButton;
}

- (void)updateScrubber
{
	double duration = CMTimeGetSeconds([self playerItemDuration]);
	
	if (isfinite(duration)) {
		double time = CMTimeGetSeconds([self.player currentTime]);
		[_scrubber setValue:time / duration];
	}
	else {
		[_scrubber setValue:0.0];
	}
}

- (void)updateTimeLabel
{
	double seconds = CMTimeGetSeconds([self.player currentTime]);
	if (!isfinite(seconds)) {
		seconds = 0;
	}
	
	int secondsInt = round(seconds);
	int minutes = secondsInt/60;
	secondsInt -= minutes*60;
	
	_currentTimeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:1.0];
	_currentTimeLabel.textAlignment = NSTextAlignmentCenter;
	_currentTimeLabel.text = [NSString stringWithFormat:@"%.2i:%.2i", minutes, secondsInt];
    
    seconds = CMTimeGetSeconds([self playerItemDuration]) - CMTimeGetSeconds([self.player currentTime]);
    if (!isfinite(seconds)) {
		seconds = 0;
	}
    
    secondsInt = round(seconds);
	minutes = secondsInt/60;
	secondsInt -= minutes*60;

    _elapsedTimeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:1.0];
	_elapsedTimeLabel.textAlignment = NSTextAlignmentCenter;
	_elapsedTimeLabel.text = [NSString stringWithFormat:@"-%.2i:%.2i", minutes, secondsInt];
}

/* Update the scrubber and time label periodically. */
- (void)addTimeObserverToPlayer
{
	if (_timeObserver)
		return;
	
	if (self.player == nil)
		return;
	
	if (self.player.currentItem.status != AVPlayerItemStatusReadyToPlay)
		return;
	
	double duration = CMTimeGetSeconds([self playerItemDuration]);
	
	if (isfinite(duration)) {
		CGFloat width = CGRectGetWidth([_scrubber bounds]);
		double interval = 0.5 * duration / width;
		
		/* The time label needs to update at least once per second. */
		if (interval > 1.0)
			interval = 1.0;
		__weak __typeof(self) weakSelf = self;
		self->_timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(interval, NSEC_PER_SEC) queue:dispatch_get_main_queue() usingBlock:
                         ^(CMTime time) {
                             [weakSelf updateScrubber];
                             [weakSelf updateTimeLabel];
                         }];
	}
}

- (void)removeTimeObserverFromPlayer
{
	if (_timeObserver) {
		[self.player removeTimeObserver:_timeObserver];
		_timeObserver = nil;
	}
}

- (CMTime)playerItemDuration
{
	AVPlayerItem *playerItem = [self.player currentItem];
	CMTime itemDuration = kCMTimeInvalid;
	
	if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
		itemDuration = [playerItem duration];
	}
	
	/* Will be kCMTimeInvalid if the item is not ready to play. */
	return itemDuration;
}

- (void)dismissAnimated:(BOOL)animated
{
    _backgroundScreenshotView.alpha = 0.f;

    [self dismissViewControllerAnimated:animated completion:^{
    }];
}

- (void)scrubToSliderValue:(float)sliderValue
{
	double duration = CMTimeGetSeconds([self playerItemDuration]);
	
	if (isfinite(duration)) {
		CGFloat width = CGRectGetWidth([_scrubber bounds]);
		
		double time = duration*sliderValue;
		double tolerance = 1.0f * duration / width;
		
		_scrubInFlight = YES;
		
		[self.player seekToTime:CMTimeMakeWithSeconds(time, NSEC_PER_SEC)
				toleranceBefore:CMTimeMakeWithSeconds(tolerance, NSEC_PER_SEC)
				 toleranceAfter:CMTimeMakeWithSeconds(tolerance, NSEC_PER_SEC)
			  completionHandler:^(BOOL finished) {
				  _scrubInFlight = NO;
				  [self updateTimeLabel];
			  }];
	}
}


#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ( context == (__bridge void *)(ALMoviePlayerViewControllerRateObservationContext) ) {
		float newRate = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
		NSNumber *oldRateNum = [change objectForKey:NSKeyValueChangeOldKey];
		if ( [oldRateNum isKindOfClass:[NSNumber class]] && newRate != [oldRateNum floatValue] ) {
			_playing = ((newRate != 0.f) || (_playRateToRestore != 0.f));
			[self updatePlayPauseButton];
			[self updateScrubber];
			[self updateTimeLabel];
		}
    }
	else if ( context == (__bridge void *)(ALMoviePlayerViewControllerStatusObservationContext) ) {
		[_loadingSpinner stopAnimating];
        
        AVPlayerItem *playerItem = (AVPlayerItem *)object;
		if (playerItem.status == AVPlayerItemStatusReadyToPlay) {
			/* Once the AVPlayerItem becomes ready to play, i.e.
			 [playerItem status] == AVPlayerItemStatusReadyToPlay,
			 its duration can be fetched from the item. */
			
			[self addTimeObserverToPlayer];
		}
		else if (playerItem.status == AVPlayerItemStatusFailed) {
			[self reportError:playerItem.error];
		}
	}
	else {
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

#pragma mark - AVPlayerItemDidPlayToEndTimeNotification

/* Called when the player item has played to its end time. */
- (void)playerItemDidReachEnd:(NSNotification *)notification
{
	/* After the movie has played to its end time, seek back to time zero to play it again. */
	_seekToZeroBeforePlaying = YES;
}

#pragma mark - ()

- (void)togglePlayPause:(id)sender
{
    _playing = !_playing;
	if ( _playing ) {
		if ( _seekToZeroBeforePlaying ) {
			[self.player seekToTime:kCMTimeZero];
			_seekToZeroBeforePlaying = NO;
		}
		[self.player play];
	}
	else {
		[self.player pause];
	}
}

- (void)beginScrubbing:(id)sender
{
    _seekToZeroBeforePlaying = NO;
	_playRateToRestore = [self.player rate];
	[self.player setRate:0.0];
	
	[self removeTimeObserverFromPlayer];
}


- (void)scrub:(id)sender
{
    _lastScrubSliderValue = [_scrubber value];
	
	if ( ! _scrubInFlight )
		[self scrubToSliderValue:_lastScrubSliderValue];
}


- (void)endScrubbing:(id)sender
{
	if ( _scrubInFlight )
		[self scrubToSliderValue:_lastScrubSliderValue];
	[self addTimeObserverToPlayer];
	
	[self.player setRate:_playRateToRestore];
	_playRateToRestore = 0.f;
}


- (void)doneButtonPressed:(id)sender
{
    [self dismissAnimated:NO];
}

#pragma mark - Gesture recognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if (touch.view != _playerView) {
        // Ignore touch on toolbar.
        return NO;
    }
    return YES;
}

- (void)handleTapGesture:(UITapGestureRecognizer *)tapGestureRecognizer
{
    [self toggleControls];
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)panGestureRecognizer
{
    static float firstX, firstY;
    
    float viewHeight = _playerView.frame.size.height;
    float viewHalfHeight = viewHeight/2;
    
    CGPoint translatedPoint = [panGestureRecognizer translationInView:self.view];
    
    // Gesture Began
    if ([panGestureRecognizer state] == UIGestureRecognizerStateBegan) {
        if (_playing) {
            [self.player pause];
        }
        
        [self setControlsHidden:YES animated:YES permanent:YES];
        
        firstX = [_playerView center].x;
        firstY = [_playerView center].y;
        
        //_senderViewForAnimation.hidden = (_currentPageIndex == _initalPageIndex);
    }
    
    translatedPoint = CGPointMake(firstX, firstY+translatedPoint.y);
    [_playerView setCenter:translatedPoint];
    
    float newY = _playerView.center.y - viewHalfHeight;
    float newAlpha = 1 - abs(newY)/viewHeight; //abs(newY)/viewHeight * 1.8;
    
    _overlayBackgroundView.opaque = YES;
    _overlayBackgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:newAlpha];
    
    // Gesture Ended
    if ([panGestureRecognizer state] == UIGestureRecognizerStateEnded) {
        if (_playerView.center.y > viewHalfHeight + 40 || _playerView.center.y < viewHalfHeight - 40) {
            
            CGFloat finalX = firstX, finalY;
            
            CGFloat windowsHeigt = [_applicationWindow frame].size.height;
            
            if(_playerView.center.y > viewHalfHeight+30) // swipe down
                finalY = windowsHeigt*2;
            else // swipe up
                finalY = -viewHalfHeight;
            
            CGFloat animationDuration = 0.35;
            
            [UIView beginAnimations:nil context:NULL];
            [UIView setAnimationDuration:animationDuration];
            [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
            [UIView setAnimationDelegate:self];
            [_playerView setCenter:CGPointMake(finalX, finalY)];
            _overlayBackgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
            [UIView commitAnimations];
            
            [self performSelector:@selector(doneButtonPressed:) withObject:self afterDelay:animationDuration];
            
        } else {
            _overlayBackgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:1];
            
            CGFloat velocityY = (.35*[panGestureRecognizer velocityInView:self.view].y);
            
            CGFloat finalX = firstX;
            CGFloat finalY = viewHalfHeight;
            
            CGFloat animationDuration = (ABS(velocityY)*.0002)+.2;
            
            [UIView beginAnimations:nil context:NULL];
            [UIView setAnimationDuration:animationDuration];
            [UIView setAnimationCurve:UIViewAnimationCurveEaseOut];
            [UIView setAnimationDelegate:self];
            [_playerView setCenter:CGPointMake(finalX, finalY)];
            [UIView commitAnimations];
            
            [self setControlsHidden:NO animated:YES permanent:YES];
        }
    }
}

@end
