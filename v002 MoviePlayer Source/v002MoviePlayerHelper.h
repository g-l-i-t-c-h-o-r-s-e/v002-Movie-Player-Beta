//
//  v002MoviePlayerHelper.h
//  v002 MoviePlayer
//
//  Created by vade on 5/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QTKit/QTKit.h>
#import <OpenGL/OpenGL.h>
#import <CoreVideo/CoreVideo.h>

#import <OpenGL/CGLIOSurface.h>

#import <QuickTime/QuickTime.h>	// 32 bit safe 10.5 and 10.6 QT calls. 
#import <QuickTime/MediaHandlers.h>

// for mac port stuff. oh god.
//#include <mach/mach.h>

#import "v002MoviePlayerHelperProtocol.h"

#ifndef v002MoviePlayerPluginHelperUseGLVisualContext
#error v002MoviePlayerPluginHelperUseGLVisualContext is not defined. It should be defined somewhere.
#endif

// Our movie Player helper App Controller vends itself.
@interface v002MoviePlayerHelper : NSObject <NSApplicationDelegate, v002MoviePlayerHelperProtocol>
{
	pid_t parentID; // the process id of the parent app (QC, VDMX etc)

	// IOSurface requirements
	IOSurfaceRef surfaceRef;
	IOSurfaceID	surfaceID;
	mach_port_t surfacePort;
	
	// IPC
	NSString* doUUID;
	NSConnection* theConnection;
	
	// query ppid 
	NSTimer* pollParentTimer;
		
	BOOL _playing;
	// if we make a QTOpenGLTextureContext
    BOOL _shuttingDown;
	
#if	v002MoviePlayerPluginHelperUseGLVisualContext
	
	CGLContextObj cgl_ctx;	
	CGLPixelFormatObj pfObject;
	GLuint surfaceTextureAttachment;
	GLuint surfaceFBO;
#else
	CVImageBufferRef currentFrameRef;
#endif
	
/*****
	From Original Plugin
****/
	
	// for 32 bit QT on 10.5 and 10.6
	QTVisualContextRef visualContext;	// This is actually a QTPixelBufferContext now...
	
	QTMovie *_movie;						// our QT Movie
    NSSize movieSize;						// movie size
	BOOL movieFinished;
	
	NSString* movieTitle;
    CGColorSpaceRef _RGBSpace, _RGBLinearSpace;
    
	NSTimeInterval durationInterval;
	NSTimeInterval timeInterval;
	
	long movieLoadState;
	BOOL movieWasPlaying;
	BOOL movieHasDuration;
	
	double decodeQuality;
	
	// 32 bit only for now
	// additions for Audio waveform handling. Meant to be compatible with Kineme output.
	UInt32 numberOfBandLevels;	// may change
	UInt32 numberOfChannels;	// force mono FFT (for speed too)
	
	QTAudioFrequencyLevels * freqResults;
	
	// Private copies of input values we need outside renderAtTime:
	NSUInteger apertureMode;
//	BOOL enableWaveformOutput;
	NSUInteger waveformOutputMode;
	NSUInteger loopMode;
	double volume;
	double balance;
	double rate;
	BOOL hasNewFrame, hasNewInfo;
#if v002MOVIEPLAYER_SURFACE_PER_FRAME
	NSMutableDictionary *surfaceAttributes;
#endif
	NSString* audioDeviceUID;
}

@property (readwrite, retain) NSString* doUUID;
@property (readwrite, retain) NSString* movieTitle;
@property (readwrite) BOOL movieHasDuration;

// Local versions of inputs we need to access outside
// renderAtTime:
@property (assign, readwrite) NSUInteger apertureMode;
@property (assign, readwrite) NSUInteger loopMode;
//@property (assign, readwrite) BOOL enableWaveformOutput;
@property (assign, readwrite) double volume;
@property (assign, readwrite) double balance;
@property (assign, readwrite) double rate;



#pragma mark -
#pragma mark Rendering/DisplayLink

#if	v002MoviePlayerPluginHelperUseGLVisualContext
- (void) setupIOSurfaceHavingLockedContext;	// only needed for GL case, visual context handles IOSurface setup for us.
- (void) renderFBO:(CVOpenGLTextureRef) frame; // render our current frame to our surface.
#endif

- (void)setSurfaceID:(IOSurfaceID)surf;

- (BOOL) setupAudioContext:(NSString*)audioDeviceUID;
- (BOOL) setupVisualContext;
- (void) render;


#pragma mark Utility
- (void) setupPollParentTimer;
- (void) pollParent;
- (void) task;
- (void) cleanUpForDealloc;


- (void) resetFFT;
- (void)disableCurrentFFT;

// load state changes
- (void) handleQTMovieLoadStateLoaded;
- (void) handleQTMovieLoadStatePlayable;
- (void) handleQTMovieLoadStatePlaythroughOK;
- (void) handleSizeChange;

// notifications
- (void) movieLoadStateDidChange:(NSNotification*)aNotification;
- (void) movieSizeDidChange:(NSNotification*)aNotification;
- (void) movieApertureDidChange:(NSNotification*)aNotification;
- (void) handleMovieDidEnd:(NSNotification *)notification;
@end

