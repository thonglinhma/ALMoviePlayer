//
//  ALVimeoExtractor.h
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



#import <Foundation/Foundation.h>

extern NSString *const ALVimeoPlayerConfigURL;
extern NSString *const ALVimeoExtractorErrorDomain;

enum {
    ALVimeoExtractorErrorCodeNotInitialized,
    ALVimeoExtractorErrorInvalidIdentifier,
    ALVimeoExtractorErrorUnsupportedCodec,
    ALVimeoExtractorErrorUnavailableQuality,
};

typedef NS_ENUM(NSUInteger, ALVimeoVideoQuality) {
    ALVimeoVideoQualityLow,
    ALVimeoVideoQualityMedium,
    ALVimeoVideoQualityHigh
};

typedef void (^ALVimeoExtractorCompletionHandler) (NSURL *videoURL, NSError *error, ALVimeoVideoQuality quality);

@interface ALVimeoExtractor : NSObject
@property (nonatomic, assign, readonly) BOOL running;
@property (nonatomic, assign, readonly) ALVimeoVideoQuality quality;
@property (nonatomic, strong, readonly) NSURL *vimeoURL;

- (instancetype)initWithVideoURL:(NSString *)videoURL quality:(ALVimeoVideoQuality)quality;
- (instancetype)initWithVideoID:(NSString *)videoID quality:(ALVimeoVideoQuality)quality;

+ (void)fetchVideoURLFromID:(NSString *)videoID quality:(ALVimeoVideoQuality)quality completionHandler:(ALVimeoExtractorCompletionHandler)handler;
+ (void)fetchVideoURLFromURL:(NSString *)videoURL quality:(ALVimeoVideoQuality)quality completionHandler:(ALVimeoExtractorCompletionHandler)handler;

@end
