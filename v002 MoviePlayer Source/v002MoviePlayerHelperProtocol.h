//
//  v002MoviePlayerHelperProtocol.h
//  v002 MoviePlayer
//
//  Created by vade on 5/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef NSUInteger v002WaveformOutputMode;
// Don't change the following values as they will be embedded in compositions
enum {
	v002WaveformOutputNone = 0,
	v002WaveformOutputMono = 1,
	v002WaveformOutputChannels = 2
};

@protocol v002MoviePlayerHelperProtocol

- (oneway void) openMovie:(NSURL*)movieURL;

#pragma mark - setters for movie properties
- (oneway void) setMovieIsPlaying:(BOOL)flag;
- (oneway void) setMovieRate:(float)rate;
- (oneway void) setMovieTime:(float)time;
- (oneway void) setMovieVolume:(float)volume;
- (oneway void) setMovieVolumes:(in NSArray*)volumes;	// for multichannel/multitrack
- (oneway void) setMovieBalance:(float)balance;
- (oneway void) setMovieBalances:(in NSArray*)balances;	// for multichannel/multitrack
- (oneway void) setMovieLoop:(NSUInteger)loopMode;
- (oneway void) setMovieDeinterlaceHint:(BOOL)hint;
- (oneway void) setMovieHighQualityHint:(BOOL)hint;
- (oneway void) setMovieSingleFieldHint:(BOOL)hint;
- (oneway void) setMovieAperture:(NSUInteger)aperture;
- (oneway void) setMovieDecodeQuality:(float)quality;
- (oneway void) setMovieAudioDevice:(NSString*)audioDeviceUID;

#pragma mark - getters for movie properties
- (float) movieRate;
- (double) movieTime;
- (float) movieNormalizedTime;
- (double) movieDuration;
- (NSString*) movieTitle;
- (BOOL) movieDidEnd;

#pragma mark - throttling
- (BOOL) hasNewFrame;
- (BOOL) hasNewInfo; // Currently only movieTitle

#pragma mark - features 
//- (oneway void) enableWaveformOutput:(BOOL)waveform;
- (oneway void) setWaveformOutputMode:(v002WaveformOutputMode)mode;
- (oneway void) setWaveformNumberOfBands:(NSUInteger)num;
- (NSArray*) waveForm;

#pragma mark - IOSurface
- (IOSurfaceID) surfaceID;
//- (mach_port_t) surfaceMachPort;

#pragma mark - cleanup
- (oneway void) quitHelperTool;

@end
