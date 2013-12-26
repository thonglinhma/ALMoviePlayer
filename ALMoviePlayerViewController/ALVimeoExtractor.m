//
//  ALVimeoExtractor.m
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


#import "ALVimeoExtractor.h"
#import <AFURLSessionManager.h>

NSString *const ALVimeoPlayerConfigURL = @"http://player.vimeo.com/v2/video/%@/config";
NSString *const ALVimeoExtractorErrorDomain = @"ALVimeoExtractorErrorDomain";

@interface ALVimeoExtractor()
@property (nonatomic, copy) ALVimeoExtractorCompletionHandler completionHandler;

- (void)extractorFailedWithMessage:(NSString*)message errorCode:(int)code;
- (void)start;

@end


@implementation ALVimeoExtractor

+ (void)fetchVideoURLFromURL:(NSString *)videoURL quality:(ALVimeoVideoQuality)quality completionHandler:(ALVimeoExtractorCompletionHandler)handler
{
    ALVimeoExtractor *extractor = [[ALVimeoExtractor alloc] initWithVideoURL:videoURL quality:quality];
    extractor.completionHandler = handler;
    
    [extractor start];
}

+ (void)fetchVideoURLFromID:(NSString *)videoID quality:(ALVimeoVideoQuality)quality completionHandler:(ALVimeoExtractorCompletionHandler)handler
{
    ALVimeoExtractor *extractor = [[ALVimeoExtractor alloc] initWithVideoID:videoID quality:quality];
    extractor.completionHandler = handler;
    
    [extractor start];
}

- (instancetype)initWithVideoID:(NSString *)videoID quality:(ALVimeoVideoQuality)quality;
{
    self = [super init];
    if (self) {
        self->_vimeoURL = [NSURL URLWithString:[NSString stringWithFormat:ALVimeoPlayerConfigURL, videoID]];
        self->_quality = quality;
        self->_running = NO;
    }
    
    return self;
}

- (instancetype)initWithVideoURL:(NSString *)videoURL quality:(ALVimeoVideoQuality)quality
{
    NSString *videoID = [[videoURL componentsSeparatedByString:@"/"] lastObject];
    return [self initWithVideoID:videoID quality:quality];
}


- (void)extractorFailedWithMessage:(NSString*)message errorCode:(int)code;
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    NSError *error = [NSError errorWithDomain:ALVimeoExtractorErrorDomain code:code userInfo:userInfo];
    
    if (self.completionHandler) {
        self.completionHandler(nil, error, self.quality);
    }
    self->_running = NO;
}

#pragma mark - Private methods

- (void)start
{
    if (!self.completionHandler || !self.vimeoURL) {
        [self extractorFailedWithMessage:@"Block or URL not specified" errorCode:ALVimeoExtractorErrorUnsupportedCodec];
        return;
    }
    
    if (self.running) {
        [self extractorFailedWithMessage:@"Already in progress" errorCode:ALVimeoExtractorErrorCodeNotInitialized];
        return;
    }
    
    self->_running = YES;
    
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    NSURLRequest *request = [NSURLRequest requestWithURL:self.vimeoURL];
    
    __weak __typeof(self) weakSelf = self;
    
    NSURLSessionDataTask *dataTask = [manager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id JSON, NSError *error) {
        if (error) {
            [self extractorFailedWithMessage:[error localizedDescription] errorCode:ALVimeoExtractorErrorInvalidIdentifier];
        } else {
            NSDictionary *filesInfo = [JSON valueForKeyPath:@"request.files.h264"];
            
            if (!filesInfo) {
                [self extractorFailedWithMessage:@"Unsupported video codec" errorCode:ALVimeoExtractorErrorUnsupportedCodec];
                return;
            }
            
            NSDictionary *videoInfo;
            ALVimeoVideoQuality videoQuality = self.quality;
            
            do {
                videoInfo = [filesInfo objectForKey:@[ @"mobile", @"sd", @"hd" ][videoQuality]];
                videoQuality--;
            } while (!videoInfo && videoQuality >= ALVimeoVideoQualityLow);
            
            if (!videoInfo) {
                [self extractorFailedWithMessage:@"Unavailable video quality" errorCode:ALVimeoExtractorErrorUnavailableQuality];
                return;
            }
            
            NSURL *video = [NSURL URLWithString:[videoInfo objectForKey:@"url"]];
            
            if (weakSelf.completionHandler) {
                weakSelf.completionHandler(video, nil, videoQuality);
            }
        }
    }];
    [dataTask resume];

}


@end
