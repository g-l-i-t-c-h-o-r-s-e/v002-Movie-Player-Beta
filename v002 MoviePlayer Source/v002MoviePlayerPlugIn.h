//
//  v002MoviePlayerPlugIn.h
//  v002 MoviePlayer
//
//  Created by vade on 5/18/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Quartz/Quartz.h>
#import <IOSurface/IOSurface.h>
#import <CoreVideo/CoreVideo.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/CGLIOSurface.h>

#import <IOKit/IOKitLib.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <IOKit/graphics/IOFramebufferShared.h>
#import <IOKit/graphics/IOGraphicsInterface.h>

#import "v002MoviePlayerTaskWrapper.h"
#import "v002MoviePlayerHelperProtocol.h"

@interface v002MoviePlayerPlugIn : QCPlugIn 
{
	CGColorSpaceRef	colorspace;
	
	// we will need a way to do IPC, for now its this.
	v002MoviePlayerTaskWrapper *helper;
	NSString *inputRemainder;
	
	// this is our connection to the background helper
	id movieProxy;
	
	// internal state caching
	BOOL movieWasPlaying;
	
	// for color correction (or lack thereof).
	CGColorSpaceRef rgbSpace;
	
	// CVPixelBuffer Pool for creating temp CVPixelBuffers
	CVPixelBufferPoolRef cvPool;
	NSSize cvPoolSize;
}
@property (readwrite) NSSize cvPoolSize;

// input ports
@property (assign) NSString * inputMoviePath;
@property (assign) double inputVolume;
@property (assign) NSArray* inputTrackVolumes;
@property (assign) double inputBalance;
@property (assign) NSArray* inputTrackBalances;
@property (assign) double inputPlayhead;
@property (assign) double inputRate;
@property (assign) BOOL inputPlay;
@property (assign) NSUInteger inputLoopMode;
@property (assign) BOOL inputColorCorrection;
@property (assign) NSUInteger inputApertureMode;
@property (assign) BOOL inputDeinterlaceHint;
@property (assign) BOOL inputHighQualityHint;
@property (assign) BOOL inputSingleFieldHint;
@property (assign) double inputImageDecodeQuality;

// additions for audio playback device
@property (assign) NSString* inputAudioDevice;

// additions for Audio Waveform handling
//@property (assign) BOOL inputEnableWaveformOutput;
@property (assign) NSUInteger inputWaveformOutputMode;
@property (assign) NSUInteger inputNumberOfBands;
@property (assign) NSArray* outputWaveform;

// output ports
@property (assign) id <QCPlugInOutputImageProvider> outputImage;
@property (assign) double outputPlayheadPosition;
@property (assign) double outputDuration;
@property (assign) double outputMovieTime;
@property (assign) NSString *  outputMovieTitle;
@property (assign) BOOL  outputMovieDidEnd;

@end


@interface v002MoviePlayerPlugIn (Execution) <v002MoviePlayerTaskWrapperController>

- (void) createPixelBufferPoolWithSize:(NSSize)size;

- (void)appendOutput:(NSString *)output fromProcess: (v002MoviePlayerTaskWrapper *)aTask;
- (void)processStarted: (v002MoviePlayerTaskWrapper *)aTask;
- (void)processFinished: (v002MoviePlayerTaskWrapper *)aTask withStatus: (int)statusCode;

@end

