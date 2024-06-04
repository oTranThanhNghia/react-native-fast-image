#import "FFFastImageView.h"
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>
#import <SDWebImage/SDImageCache.h>
#import <SDWebImage/UIImage+MultiFormat.h>
#import <SDWebImage/UIView+WebCache.h>

@interface FFFastImageView ()

@property(nonatomic, assign) BOOL hasSentOnLoadStart;
@property(nonatomic, assign) BOOL hasCompleted;
@property(nonatomic, assign) BOOL hasErrored;
// Whether the latest change of props requires the image to be reloaded
@property(nonatomic, assign) BOOL needsReload;

@property(nonatomic, strong) NSDictionary* onLoadEvent;

@end

@implementation FFFastImageView

- (id) init {
    self = [super init];
    self.resizeMode = RCTResizeModeCover;
    self.clipsToBounds = YES;
    return self;
}

- (void) setResizeMode: (RCTResizeMode)resizeMode {
    if (_resizeMode != resizeMode) {
        _resizeMode = resizeMode;
        self.contentMode = (UIViewContentMode) resizeMode;
    }
}

- (void) setOnFastImageLoadEnd: (RCTDirectEventBlock)onFastImageLoadEnd {
    _onFastImageLoadEnd = onFastImageLoadEnd;
    if (self.hasCompleted) {
        _onFastImageLoadEnd(@{});
    }
}

- (void) setOnFastImageLoad: (RCTDirectEventBlock)onFastImageLoad {
    _onFastImageLoad = onFastImageLoad;
    if (self.hasCompleted) {
        _onFastImageLoad(self.onLoadEvent);
    }
}

- (void) setOnFastImageError: (RCTDirectEventBlock)onFastImageError {
    _onFastImageError = onFastImageError;
    if (self.hasErrored) {
        _onFastImageError(@{});
    }
}

- (void) setOnFastImageLoadStart: (RCTDirectEventBlock)onFastImageLoadStart {
    if (_source && !self.hasSentOnLoadStart) {
        _onFastImageLoadStart = onFastImageLoadStart;
        onFastImageLoadStart(@{});
        self.hasSentOnLoadStart = YES;
    } else {
        _onFastImageLoadStart = onFastImageLoadStart;
        self.hasSentOnLoadStart = NO;
    }
}

- (void) setImageColor: (UIColor*)imageColor {
    if (imageColor != nil) {
        _imageColor = imageColor;
        if (super.image) {
            super.image = [self makeImage: super.image withTint: self.imageColor];
        }
    }
}

- (UIImage*) makeImage: (UIImage*)image withTint: (UIColor*)color {
    UIImage* newImage = [image imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format];

    UIImage *resultImage = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
        [color set];
        [newImage drawInRect:rect];
    }];
    return newImage;
}

- (void) setImage: (UIImage*)image {
    if (self.imageColor != nil) {
        super.image = [self makeImage: image withTint: self.imageColor];
    } else {
        super.image = image;
    }
}

- (void) sendOnLoad: (UIImage*)image {
    self.onLoadEvent = @{
            @"width": [NSNumber numberWithDouble: image.size.width],
            @"height": [NSNumber numberWithDouble: image.size.height]
    };
    if (self.onFastImageLoad) {
        self.onFastImageLoad(self.onLoadEvent);
    }
}

- (void) setSource: (FFFastImageSource*)source {
    if (_source != source) {
        _source = source;
        _needsReload = YES;
    }
}

- (void) setDefaultSource: (UIImage*)defaultSource {
    if (_defaultSource != defaultSource) {
        _defaultSource = defaultSource;
        _needsReload = YES;
    }
}

- (void) didSetProps: (NSArray<NSString*>*)changedProps {
    if (_needsReload) {
        [self reloadImage];
    }
}

- (void) reloadImage {
    _needsReload = NO;

    if (_source) {
        // Load base64 images.
        NSString* url = [_source.url absoluteString];
        if (url && [url hasPrefix: @"data:image"]) {
            if (self.onFastImageLoadStart) {
                self.onFastImageLoadStart(@{});
                self.hasSentOnLoadStart = YES;
            } else {
                self.hasSentOnLoadStart = NO;
            }
            // Use SDWebImage API to support external format like WebP images
            UIImage* image = [UIImage sd_imageWithData: [NSData dataWithContentsOfURL: _source.url]];
            [self setImage: image];
            if (self.onFastImageProgress) {
                self.onFastImageProgress(@{
                        @"loaded": @(1),
                        @"total": @(1)
                });
            }
            self.hasCompleted = YES;
            [self sendOnLoad: image];

            if (self.onFastImageLoadEnd) {
                self.onFastImageLoadEnd(@{});
            }
            return;
        }

        // Set headers.
        NSDictionary* headers = _source.headers;
        SDWebImageDownloaderRequestModifier* requestModifier = [SDWebImageDownloaderRequestModifier requestModifierWithBlock: ^NSURLRequest* _Nullable (NSURLRequest* _Nonnull request) {
            NSMutableURLRequest* mutableRequest = [request mutableCopy];
            for (NSString* header in headers) {
                NSString* value = headers[header];
                [mutableRequest setValue: value forHTTPHeaderField: header];
            }
            return [mutableRequest copy];
        }];
        SDWebImageContext* context = @{SDWebImageContextDownloadRequestModifier: requestModifier};

        // Set priority.
        SDWebImageOptions options = SDWebImageRetryFailed | SDWebImageHandleCookies;
        switch (_source.priority) {
            case FFFPriorityLow:
                options |= SDWebImageLowPriority;
                break;
            case FFFPriorityNormal:
                // Priority is normal by default.
                break;
            case FFFPriorityHigh:
                options |= SDWebImageHighPriority;
                break;
        }

        switch (_source.cacheControl) {
            case FFFCacheControlWeb:
                options |= SDWebImageRefreshCached;
                break;
            case FFFCacheControlCacheOnly:
                options |= SDWebImageFromCacheOnly;
                break;
            case FFFCacheControlImmutable:
                break;
        }

        if (self.onFastImageLoadStart) {
            self.onFastImageLoadStart(@{});
            self.hasSentOnLoadStart = YES;
        } else {
            self.hasSentOnLoadStart = NO;
        }
        self.hasCompleted = NO;
        self.hasErrored = NO;

        if(_source != nil && [_source.url.scheme  isEqual: @"file"]) {
            NSString *sourcePath = [_source.url absoluteString];
            NSString *cachePath = [[SDImageCache sharedImageCache] cachePathForKey:sourcePath];
            // check file exist and check modification date of source.url vs check creation date of cachedFile
            UIImage *cachedImage = [[SDImageCache sharedImageCache] imageFromCacheForKey:sourcePath options:options context:context];
            if (cachedImage && [self isValidCache:sourcePath cacheFile:cachePath]) {
                // Use the cached image
//                NSLog(@"----> get from Cache");
                NSLog(@"----> get from Cache path = %@", cachePath);
                [self setImage:cachedImage];
            } else {
                // Handle the case where the image is not in the cache
                NSLog(@"----> generatePreviews");
                [self generatePreviews:_source];
            }
        } else {
            [self downloadImage: _source options: options context: context];
        }
    } else if (_defaultSource) {
        [self setImage: _defaultSource];
    }
}

- (bool) isValidCache:(NSString*)sourceFile cacheFile: (NSString*) cacheFile {
//    bool result = false;
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSDictionary* sourceFileAttribs = [fileManager attributesOfItemAtPath:sourceFile error:nil];
    NSDictionary* cacheFileAttribs = [fileManager attributesOfItemAtPath:cacheFile error:nil];
    
    NSDate* sourceFileModificationDate = [sourceFileAttribs objectForKey:NSFileModificationDate];
    NSDate* cacheFileCreationDate = [cacheFileAttribs objectForKey:NSFileCreationDate];
    
    return [sourceFileModificationDate compare:cacheFileCreationDate] == NSOrderedSame;
}

- (void) generatePreviews:(FFFastImageSource*)source {

    // Generate the best representation
    if (@available(iOS 13.0, *)) {
    //    QLPreviewController* previewVC = [[QLPreviewController alloc] init];
        QLThumbnailGenerator *previewGenerator = [QLThumbnailGenerator sharedGenerator];
        CGSize thumbnailSize = CGSizeMake(60, 90);
        CGFloat scale = [[UIScreen mainScreen] scale];
//        NSLog(@"----> create QLThumbnailGenerationRequest url = %@ ", source.url.absoluteString);
        QLThumbnailGenerationRequest *request = [[QLThumbnailGenerationRequest alloc] initWithFileAtURL:source.url
                                                                                             size:thumbnailSize
                                                                                           scale:scale
                                                                            representationTypes:QLThumbnailGenerationRequestRepresentationTypeThumbnail];
        
        __weak typeof(self) weakSelf = self; // Always use a weak reference to self in blocks
        [previewGenerator generateBestRepresentationForRequest:request completionHandler:^(QLThumbnailRepresentation * _Nullable thumbnailRep, NSError * _Nullable error) {
            NSLog(@"----> request generateBestRepresentationForRequest with url = %@", source.url.absoluteString);
            dispatch_async(dispatch_get_main_queue(), ^{
                if(weakSelf == nil) return;
                
                if (thumbnailRep) {
                    // Thumbnail generation succeeded, use the thumbnail representation
                    NSString* cachedKey = [source.url absoluteString];
                    UIImage *thumbnailImage = thumbnailRep.UIImage;
    //                NSLog(@"----> cache Thumbnail image to disk with key = %@ ", cachedKey);
                    [[SDImageCache sharedImageCache] storeImage:thumbnailImage forKey:cachedKey toDisk:true completion:nil];
                    //            [[SDImageCache sharedImageCache] storeImage:thumbnailImage imageData:nil forKey:cachedKey cacheType:SDImageCacheTypeAll completion:^{
                    //                NSLog(@"cache Thumbnail image done");
                    //            }];
                    // Do something with the thumbnail image
                    [weakSelf setImage:thumbnailImage];
    //                [previewGenerator ]
                } else {
                    // Thumbnail generation failed, handle the error
                    NSLog(@"Thumbnail generation error: %@", error);
                }
            });
            
        }];
    } else {
        // Fallback on earlier versions
    }
}

- (void) downloadImage: (FFFastImageSource*)source options: (SDWebImageOptions)options context: (SDWebImageContext*)context {
    __weak typeof(self) weakSelf = self; // Always use a weak reference to self in blocks
    [self sd_setImageWithURL: _source.url
            placeholderImage: _defaultSource
                     options: options
                     context: context
                    progress: ^(NSInteger receivedSize, NSInteger expectedSize, NSURL* _Nullable targetURL) {
                        if (weakSelf.onFastImageProgress) {
                            weakSelf.onFastImageProgress(@{
                                    @"loaded": @(receivedSize),
                                    @"total": @(expectedSize)
                            });
                        }
                    } completed: ^(UIImage* _Nullable image,
                    NSError* _Nullable error,
                    SDImageCacheType cacheType,
                    NSURL* _Nullable imageURL) {
                if (error) {
                    weakSelf.hasErrored = YES;
                    if (weakSelf.onFastImageError) {
                        weakSelf.onFastImageError(@{});
                    }
                    if (weakSelf.onFastImageLoadEnd) {
                        weakSelf.onFastImageLoadEnd(@{});
                    }
                } else {
                    weakSelf.hasCompleted = YES;
                    [weakSelf sendOnLoad: image];
                    if (weakSelf.onFastImageLoadEnd) {
                        weakSelf.onFastImageLoadEnd(@{});
                    }
                }
            }];
}

- (void) dealloc {
    [self sd_cancelCurrentImageLoad];
}

@end
