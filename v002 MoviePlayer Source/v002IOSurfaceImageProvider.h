//
//  v002IOSurfaceImageProvider.h
//  v002 MoviePlayer
//
//  Created by Tom on 06/01/2011.
//  Copyright 2011 Tom Butterworth. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import <IOSurface/IOSurface.h>

#ifndef v002IOSurfaceImageProvider_Unique_Class_Name
#warning v002IOSurfaceImageProvider_Unique_Class_Name not defined. This must be defined if used in a plugin or other loadable code.
#endif

@interface v002IOSurfaceImageProvider_Unique_Class_Name : NSObject <QCPlugInOutputImageProvider> {
	NSUInteger _width;
	NSUInteger _height;
	IOSurfaceRef _surface;
	NSString *_format;
	CGColorSpaceRef _cspace;
	BOOL _cmatch;
}
- (id)initWithSurfaceID:(IOSurfaceID)surfaceID pixelFormat:(NSString *)format colorSpace:(CGColorSpaceRef)cspace shouldColorMatch:(BOOL)shouldMatch;
@end

@compatibility_alias v002IOSurfaceImageProvider v002IOSurfaceImageProvider_Unique_Class_Name;
