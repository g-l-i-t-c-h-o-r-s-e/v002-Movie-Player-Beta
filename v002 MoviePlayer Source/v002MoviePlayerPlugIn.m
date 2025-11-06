//
//  v002MoviePlayerPlugIn.m
//  v002 MoviePlayer
//
//  Created by vade on 5/18/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

/* It's highly recommended to use CGL macros instead of changing the current context for plug-ins that perform OpenGL rendering */
#import <OpenGL/CGLMacro.h>


#import "v002MoviePlayerPlugIn.h"

#if v002MoviePlayerPluginUseGLUpload
	#import "v002IOSurfaceImageProvider.h"
#endif

#define kv002DescriptionAddOnText @"\n\rv002 Plugins : http://v002.info\n\nCopyright:\nvade - Anton Marini.\nbangnoise - Tom Butterworth\n\n2010 - Creative Commons Non Commercial Share Alike Attribution 3.0\n\nFixed by Pandela /) - 2025 \nhttps://github.com/g-l-i-t-c-h-o-r-s-e/"

#define	kQCPlugIn_Name				@"v002 Movie Player (fixed)"
#define	kQCPlugIn_Description		@"v002 Movie Player - Play Quicktime movie files, stream RTSP movies as well as fast start progressive download movies over HTTP."

#define kv002DefaultApertureMode 0
#define kv002DefaultLoopMode 0
//#define kv002DefaultEnableWaveformOutput NO
#define kv002DefaultWaveformOutputMode 0
#define kv002DefaultVolume 1.0
#define kv002DefaultBalance 0.0
#define kv002DefaultRate 1.0	

static void _BufferReleaseCallback (const void* address, void * context)
{
	CVPixelBufferRelease(context);
}

// Quicky UUID
@interface NSString (v002MoviePlayerQCPluginUUID)
+ (NSString*) v002MoviePlayerQCPluginStringWithUUID;
@end

@implementation v002MoviePlayerPlugIn

@synthesize cvPoolSize;

@dynamic inputMoviePath;
@dynamic inputVolume;
@dynamic inputBalance;
@dynamic inputTrackVolumes;
@dynamic inputTrackBalances;
@dynamic inputLoopMode;
@dynamic inputPlayhead;
@dynamic inputRate;
@dynamic inputPlay;
@dynamic inputColorCorrection;
@dynamic inputApertureMode;
@dynamic inputDeinterlaceHint;
@dynamic inputHighQualityHint;
@dynamic inputSingleFieldHint;
@dynamic inputImageDecodeQuality;

@dynamic inputAudioDevice;

//@dynamic inputEnableWaveformOutput;
@dynamic inputWaveformOutputMode;
@dynamic inputNumberOfBands;
@dynamic outputWaveform;

@dynamic outputImage;
@dynamic outputPlayheadPosition;
@dynamic outputMovieTitle;
@dynamic outputDuration;
@dynamic outputMovieTime;
@dynamic outputMovieDidEnd;

+ (NSDictionary*) attributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:kQCPlugIn_Name, QCPlugInAttributeNameKey, [kQCPlugIn_Description stringByAppendingString:kv002DescriptionAddOnText], QCPlugInAttributeDescriptionKey, nil];
}

+ (NSDictionary*) attributesForPropertyPortWithKey:(NSString*)key
{
	if([key isEqualToString:@"inputPlayhead"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Playhead", QCPortAttributeNameKey,
				[NSNumber numberWithFloat:0.0], QCPortAttributeMinimumValueKey,
				[NSNumber numberWithFloat:0.0], QCPortAttributeDefaultValueKey,
				[NSNumber numberWithFloat:1.0], QCPortAttributeMaximumValueKey,
				nil];
	}
		
	if([key isEqualToString:@"inputLoopMode"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Loop Mode", QCPortAttributeNameKey,
				[NSArray arrayWithObjects:@"Loop", @"Palindrome", @"No Loop", nil], QCPortAttributeMenuItemsKey,
				[NSNumber numberWithUnsignedInteger:kv002DefaultLoopMode], QCPortAttributeDefaultValueKey,
				[NSNumber numberWithUnsignedInteger:2], QCPortAttributeMaximumValueKey,
				[NSNumber numberWithUnsignedInteger:0], QCPortAttributeDefaultValueKey,
				nil];
	}
	
	if([key isEqualToString:@"inputRate"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Rate", QCPortAttributeNameKey,
				//	[NSNumber numberWithFloat:-10.0], QCPortAttributeMinimumValueKey,
				[NSNumber numberWithFloat:kv002DefaultRate], QCPortAttributeDefaultValueKey,
				//	[NSNumber numberWithFloat:10.0], QCPortAttributeMaximumValueKey,
				nil];
	}
	
	if([key isEqualToString:@"inputVolume"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Volume", QCPortAttributeNameKey,
				[NSNumber numberWithFloat:0.0], QCPortAttributeMinimumValueKey,
				[NSNumber numberWithFloat:kv002DefaultVolume], QCPortAttributeDefaultValueKey,
				[NSNumber numberWithFloat:1.0], QCPortAttributeMaximumValueKey,
				nil];
	}
	
	if([key isEqualToString:@"inputBalance"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Balance", QCPortAttributeNameKey,
				[NSNumber numberWithFloat:-1.0], QCPortAttributeMinimumValueKey,
				[NSNumber numberWithFloat:kv002DefaultBalance], QCPortAttributeDefaultValueKey,
				[NSNumber numberWithFloat:1.0], QCPortAttributeMaximumValueKey,
				nil];
	}
	if([key isEqualToString:@"inputTrackVolumes"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Per-Track Volume", QCPortAttributeNameKey,
				nil];
	}
	
	if([key isEqualToString:@"inputTrackBalances"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Per-Track Balance", QCPortAttributeNameKey,
				nil];
	}
	
	if([key isEqualToString:@"inputMoviePath"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Movie Source", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"inputStop"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Stop", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"inputPlay"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Play", QCPortAttributeNameKey,
				[NSNumber numberWithBool:YES], QCPortAttributeDefaultValueKey, nil];
	}	
	
	if([key isEqualToString:@"inputColorCorrection"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Color Correction", QCPortAttributeNameKey, 
				[NSNumber numberWithBool:YES], QCPortAttributeDefaultValueKey, nil];
	}	
	
	if([key isEqualToString:@"inputApertureMode"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Aperture Mode", QCPortAttributeNameKey,
				[NSArray arrayWithObjects:@"Clean", @"Production", @"Encoded Pixels", nil], QCPortAttributeMenuItemsKey,
				[NSNumber numberWithUnsignedInteger:kv002DefaultApertureMode], QCPortAttributeDefaultValueKey,
				[NSNumber numberWithUnsignedInteger:2], QCPortAttributeMaximumValueKey,
				[NSNumber numberWithUnsignedInteger:0], QCPortAttributeDefaultValueKey,
				nil];
	}

	if([key isEqualToString:@"inputAudioDevice"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Audio Device", QCPortAttributeNameKey,
				nil];
	}
	
/*	if([key isEqualToString:@"inputEnableWaveformOutput"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Waveform", QCPortAttributeNameKey, 
				[NSNumber numberWithBool:kv002DefaultEnableWaveformOutput], QCPortAttributeDefaultValueKey,
				nil];
	}	
*/
	if([key isEqualToString:@"inputWaveformOutputMode"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Waveform Output", QCPortAttributeNameKey,
				[NSArray arrayWithObjects:@"None", @"Mono Mix", @"Channels", nil], QCPortAttributeMenuItemsKey,
				[NSNumber numberWithUnsignedInteger:kv002DefaultWaveformOutputMode], QCPortAttributeDefaultValueKey,
				[NSNumber numberWithUnsignedInteger:2], QCPortAttributeMaximumValueKey,
				[NSNumber numberWithUnsignedInteger:0], QCPortAttributeDefaultValueKey,
				nil];
	}	
	if([key isEqualToString:@"inputNumberOfBands"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Frequency Bands", QCPortAttributeNameKey,
				[NSNumber numberWithFloat:0.0], QCPortAttributeMinimumValueKey,
				[NSNumber numberWithFloat:32.0], QCPortAttributeDefaultValueKey,
				//[NSNumber numberWithFloat:512.0], QCPortAttributeMaximumValueKey,
				nil];
	}	
	
	if([key isEqualToString:@"inputDeinterlaceHint"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Deinterlace Hint", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"inputHighQualityHint"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"High Quality Hint", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"inputSingleFieldHint"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Single Field Hint", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"inputImageDecodeQuality"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Decode Resolution", QCPortAttributeNameKey,
				[NSNumber numberWithFloat:0.1], QCPortAttributeMinimumValueKey,
				[NSNumber numberWithFloat:1.0], QCPortAttributeDefaultValueKey,
				[NSNumber numberWithFloat:1.0], QCPortAttributeMaximumValueKey,
				nil];
	}	
	
	if([key isEqualToString:@"outputImage"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Image", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"outputPlayheadPosition"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Normalized Time", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"outputMovieTitle"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Movie Title", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"outputDuration"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Movie Duration (seconds)", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"outputMovieTime"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Current Movie Time (seconds)", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"outputMovieDidEnd"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Movie Finished", QCPortAttributeNameKey, nil];
	}
	
	if([key isEqualToString:@"outputWaveform"])
	{
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Waveform", QCPortAttributeNameKey, nil];
	}
	
	
	return nil;
}

+ (NSArray*) sortedPropertyPortKeys
{
	return [NSArray arrayWithObjects:@"inputMoviePath",
			@"inputPlay",
			@"inputRate", 
			@"inputPlayhead",
			@"inputAudioDevice",
			@"inputVolume",
			@"inputBalance",
			@"inputTrackVolumes",
			@"inputTrackBalances",
			@"inputLoopMode",
			@"inputColorCorrection",
			@"inputApertureMode",
			@"inputDeinterlaceHint",
			@"inputHighQualityHint",
			@"inputSingleFieldHint",
			@"inputImageDecodeQuality",
//			@"inputEnableWaveformOutput",
			@"inputWaveformOutputMode",
			@"inputNumberOfBands",
			@"outputImage",
			@"outputPlayheadPosition",
			@"outputMovieTime",
			@"outputDuration",
			@"outputMovieTitle",nil];
}

+ (QCPlugInExecutionMode) executionMode
{
	return kQCPlugInExecutionModeProvider;
}

+ (QCPlugInTimeMode) timeMode
{
	return kQCPlugInTimeModeIdle;
}

- (id) init
{
    self = [super init];
	if(self)
	{
		cvPoolSize = NSZeroSize;
		rgbSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
	}
	return self;
}

- (void) dealloc
{
	CGColorSpaceRelease(rgbSpace);

	[super dealloc];
}


@end

@implementation v002MoviePlayerPlugIn (Execution)

- (BOOL) startExecution:(id<QCPlugInContext>)context
{	
	// run our background task. Get our IOSurface ids from its standard out.
	NSString *cliPath = [[NSBundle bundleForClass:[self class]] pathForResource: @"v002MoviePlayerHelper" ofType: @""];
	
	// generate a UUID string so we can have multiple screen capture background tasks running.
	NSString *taskUUIDForDOServer = [NSString v002MoviePlayerQCPluginStringWithUUID];
	// NSLog(@"helper tool UUID should be %@", taskUUIDForDOServer);
	
	NSArray *args = [NSArray arrayWithObjects: cliPath, taskUUIDForDOServer, nil];
	
	helper = [[v002MoviePlayerTaskWrapper alloc] initWithController:self arguments:args userInfo:nil];
	[helper startProcess];
	
	//	NSLog(@"launched task with environment: %@", [[helper task] environment]);
	
	// now that we launched the helper, start up our NSConnection for DO object vending and configure it
	// this is however a race condition if our helper process is not fully launched yet. 
	// we hack it out here. Normally this while loop is not noticable, its very fast
	
	NSConnection* taskConnection = nil;
	NSDate *start = [NSDate date];
	while(taskConnection == nil && -[start timeIntervalSinceNow] < 2.0)
	{
		taskConnection = [NSConnection connectionWithRegisteredName:[NSString stringWithFormat:@"info.v002.v002MoviePlayerHelper-%@", taskUUIDForDOServer, nil] host:nil];
	}
	
	// now that we have a valid connection...
	movieProxy = [[taskConnection rootProxy] retain];
	
	if(taskConnection == nil || movieProxy == nil)
	{
		[helper stopProcess];
		[helper release];
		helper = nil;
		[context logMessage:@"Could not start or connect to helper process."];
		return NO;
	}
	[movieProxy setProtocolForProxy:@protocol(v002MoviePlayerHelperProtocol)];
	
	return YES;
}

- (BOOL) execute:(id<QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary*)arguments
{	
	// handle input port changes
	if([self didValueForInputKeyChange:@"inputMoviePath"])
	{
		DLog(@"Recieved new movie path");
		NSString * path = self.inputMoviePath;
		
		NSURL *pathURL;
		
		// relative to composition ?
		if(![path hasPrefix:@"/"] && ![path hasPrefix:@"http://"] && ![path hasPrefix:@"rtsp://"])
			path =  [NSString pathWithComponents:[NSArray arrayWithObjects:[[[context compositionURL] path]stringByDeletingLastPathComponent], path, nil]]; 
		
		path = [path stringByStandardizingPath];	
		
		if([[NSFileManager defaultManager] fileExistsAtPath:path])
		{
			pathURL = [NSURL fileURLWithPath:path]; // TWB no longer retained
			DLog(@"%@", pathURL);
		}
		else
		{
			pathURL =  [NSURL URLWithString:[self.inputMoviePath stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]; // TWB no longer retained.
			DLog(@"%@", pathURL);
		}
		
		[movieProxy openMovie:pathURL];
	}
	
	// basic playback

	if([self didValueForInputKeyChange:@"inputPlay"])
		[movieProxy setMovieIsPlaying:self.inputPlay];
	
	if([self didValueForInputKeyChange:@"inputRate"])
		[movieProxy setMovieRate:(float) self.inputRate];

	if([self didValueForInputKeyChange:@"inputPlayhead"])
		[movieProxy setMovieTime:(float) self.inputPlayhead];
	
	if([self didValueForInputKeyChange:@"inputLoopMode"])
		[movieProxy setMovieLoop:(float) self.inputLoopMode];
		
	// audio
	if([self didValueForInputKeyChange:@"inputAudioDevice"])
		[movieProxy setMovieAudioDevice:self.inputAudioDevice];
	
	if([self didValueForInputKeyChange:@"inputVolume"])
		[movieProxy setMovieVolume:(float) self.inputVolume];

	if ([self didValueForInputKeyChange:@"inputTrackVolumes"])
		[movieProxy setMovieVolumes:[self valueForInputKey:@"inputTrackVolumes"]];
	
	if([self didValueForInputKeyChange:@"inputBalance"])
		[movieProxy setMovieBalance:(float) self.inputBalance];

	if ([self didValueForInputKeyChange:@"inputTrackBalances"])
		[movieProxy setMovieBalances:[self valueForInputKey:@"inputTrackBalances"]];
	
	// FFT
/*	if([self didValueForInputKeyChange:@"inputEnableWaveformOutput"])
		[movieProxy enableWaveformOutput:self.inputEnableWaveformOutput];
 */
	if ([self didValueForInputKeyChange:@"inputWaveformOutputMode"])
		[movieProxy setWaveformOutputMode:self.inputWaveformOutputMode];
	
	if([self didValueForInputKeyChange:@"inputNumberOfBands"])
		[movieProxy setWaveformNumberOfBands:self.inputNumberOfBands];
	
	// hints
	if([self didValueForInputKeyChange:@"inputHighQualityHint"])
		[movieProxy setMovieHighQualityHint:self.inputHighQualityHint];
	
	if([self didValueForInputKeyChange:@"inputSingleFieldHint"])
		[movieProxy setMovieSingleFieldHint:self.inputSingleFieldHint];
	
	if([self didValueForInputKeyChange:@"inputDeinterlaceHint"])
		[movieProxy setMovieDeinterlaceHint:self.inputDeinterlaceHint];
	
	// aperture
	if([self didValueForInputKeyChange:@"inputApertureMode"])
		[movieProxy setMovieAperture:self.inputApertureMode];
		
	// decode quality 
	if([self didValueForInputKeyChange:@"inputImageDecodeQuality"])
		[movieProxy setMovieDecodeQuality:self.inputImageDecodeQuality];
	
	// according to CGLIOSurface we must rebind our texture every time we want a new stuff from it.
	// since our ID may change every frame we make a new texture each pass. 
	
	//	NSLog(@"Surface ID: %u", (NSUInteger) surfaceID);
	
	IOSurfaceID surfaceID = 0;
	if(movieProxy != nil)
	{	
		if ([movieProxy hasNewFrame])
		{
			surfaceID = [movieProxy surfaceID];
//			NSLog(@"output with surface ID: %u", surfaceID);
	
			id provider = nil;
			
				
#if v002MoviePlayerPluginUseGLUpload		
#pragma mark IOSurface to Texture, output Texure based Provider
			provider = [[v002IOSurfaceImageProvider alloc] initWithSurfaceID:surfaceID pixelFormat:QCPlugInPixelFormatBGRA8 colorSpace:(self.inputColorCorrection ? rgbSpace : [context colorSpace]) shouldColorMatch:YES];
			[provider autorelease];
#else	
#pragma mark IOSurface creates CVPixelBuffer, output Buffer based Provider
			// WHOA - This causes a retain. In v002MoviePlayerPluginUseGLUpload it is released in the provider's callback
			// Otherwise we release it after we have copied the buffer
			IOSurfaceRef surfaceRef = IOSurfaceLookup(surfaceID);
			
			// get our IOSurfaceRef from our passed in IOSurfaceID from our background process.
			if(surfaceRef)
			{			
				CVPixelBufferRef ioCVBuffer, tempBuffer; 
				CVReturn ret;
				
				// create a new pool, or resize our existing pool if we need to.
				[self createPixelBufferPoolWithSize:NSMakeSize(IOSurfaceGetWidth(surfaceRef),  IOSurfaceGetHeight(surfaceRef))];
				
				// this call retains the IOSurface, which is already retained from the lookup.
				// from header for some gotchas with this method:
				
				//	The CVPixelBuffer will retain the IOSurface.
				//	IMPORTANT NOTE: If you are using IOSurface to share CVPixelBuffers between processes
				//	and those CVPixelBuffers are allocated via a CVPixelBufferPool, it is important
				//	that the CVPixelBufferPool does not reuse CVPixelBuffers whose IOSurfaces are still
				//	in use in other processes.  
				//
				//	CoreVideo and IOSurface will take care of this for if you use IOSurfaceCreateMachPort 
				//	and IOSurfaceLookupFromMachPort, but NOT if you pass IOSurfaceIDs.
						
				if( (ret = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surfaceRef, nil, &ioCVBuffer)) == kCVReturnSuccess)
				{
					// retain our actual IOSurface Buffer
					CVPixelBufferRetain(ioCVBuffer);
					CVPixelBufferLockBaseAddress(ioCVBuffer, 0);
					
					// create our own CVPixelbuffer.
					CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, cvPool, &tempBuffer);
					
					// copy one to the other.
					CVPixelBufferLockBaseAddress(tempBuffer, 0);

					void* srcBaseAddress = CVPixelBufferGetBaseAddress(ioCVBuffer);
					void* dstBaseAddress = CVPixelBufferGetBaseAddress(tempBuffer);
					memcpy(dstBaseAddress, srcBaseAddress, CVPixelBufferGetDataSize(ioCVBuffer));
						
					// we release our CVPixelBuffer in the QC Buffer release callback.
					provider = [context outputImageProviderFromBufferWithPixelFormat:QCPlugInPixelFormatBGRA8 pixelsWide:CVPixelBufferGetWidth(tempBuffer) pixelsHigh:CVPixelBufferGetHeight(tempBuffer) baseAddress:CVPixelBufferGetBaseAddress(tempBuffer) bytesPerRow:CVPixelBufferGetBytesPerRow(tempBuffer) releaseCallback:_BufferReleaseCallback releaseContext:tempBuffer colorSpace:(self.inputColorCorrection) ? rgbSpace : [context colorSpace] shouldColorMatch:YES];
					// let our Buffers relax...
					CVPixelBufferUnlockBaseAddress(ioCVBuffer, 0);
					CVPixelBufferUnlockBaseAddress(tempBuffer, 0);

					// Duh. Release this too.
					CVPixelBufferRelease(ioCVBuffer);
					// balance with extra retain from CVPixelBufferCreateWithIOSurface
					CFRelease(surfaceRef);
				}
				else
				{
					DLog(@"Error creating pixel buffer from surface");
				}
				
				// release the surface
				CFRelease(surfaceRef);	
			}
			else
			{
				provider = nil;
			}
		#endif		
			self.outputImage = provider;
		
			// these ports can be accurate to the timeslie of the movies FPS
			if ([movieProxy hasNewInfo])
			{
				self.outputMovieTitle = [movieProxy movieTitle];
			}
			self.outputMovieDidEnd = [movieProxy movieDidEnd];
			self.outputDuration = [movieProxy movieDuration];
		}
		
		// these should be higher resolution, updating once per requested execution.
		self.outputMovieTime = [movieProxy movieTime];
		self.outputPlayheadPosition = (double)[movieProxy movieNormalizedTime];
		self.outputWaveform = [movieProxy waveForm];		
	}
	else
	{
		self.outputImage = nil;
	}

	return YES;
}


- (void) stopExecution:(id<QCPlugInContext>)context
{
    DLog(@"got stop execution");
    
    [movieProxy quitHelperTool];
    
    [helper stopProcess];
    [helper release];
    helper = nil;
    [movieProxy release];
    movieProxy = nil;
}


- (void) enableExecution:(id<QCPlugInContext>)context
{
	DLog(@"got enable execution");
	if(movieWasPlaying)
		[movieProxy setMovieIsPlaying:YES];
}

- (void) disableExecution:(id<QCPlugInContext>)context
{
    DLog(@"got disable execution");
    
    // Only pause playback state here. Do not touch any output ports.
    if ([movieProxy movieRate] > 0) {
        movieWasPlaying = YES;
        [movieProxy setMovieIsPlaying:NO];
    } else {
        movieWasPlaying = NO;
    }
}





#pragma mark TaskWrapper delegates

- (void)appendOutput:(NSString *)output fromProcess: (v002MoviePlayerTaskWrapper *)aTask
{
#ifdef DEBUG_PRINT
	if (output) DLog(@"From Helper: %@", output);
#endif
}	

- (void)processStarted: (v002MoviePlayerTaskWrapper *)aTask
{
	
}

- (void)processFinished: (v002MoviePlayerTaskWrapper *)aTask withStatus: (int)statusCode
{
	
}

- (void) createPixelBufferPoolWithSize:(NSSize)size
{
	if(size.width != self.cvPoolSize.width || size.height != self.cvPoolSize.height)
	{
	   
		[self setCvPoolSize:size];
		
		if(cvPool != NULL)
		{
			CVPixelBufferPoolRelease(cvPool);
			cvPool = NULL;
		}
			
		NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
		[attributes setObject:[NSNumber numberWithUnsignedInt:k32ARGBPixelFormat] forKey:(NSString*)kCVPixelBufferPixelFormatTypeKey];
		[attributes setObject:[NSNumber numberWithUnsignedInt:self.cvPoolSize.width] forKey:(NSString*)kCVPixelBufferWidthKey];
		[attributes setObject:[NSNumber numberWithUnsignedInt:self.cvPoolSize.height] forKey:(NSString*)kCVPixelBufferHeightKey];
		[attributes setObject:[NSNumber numberWithBool:YES] forKey:(NSString *) kCVPixelBufferOpenGLCompatibilityKey];
		
		CVPixelBufferPoolCreate(kCFAllocatorDefault, NULL, (CFDictionaryRef)attributes, &cvPool);
	}
}

@end

@implementation NSString (v002MoviePlayerQCPluginUUID)

+ (NSString*) v002MoviePlayerQCPluginStringWithUUID 
{
	CFUUIDRef	uuidObj = CFUUIDCreate(nil);//create a new UUID
	//get the string representation of the UUID
	NSString	*uuidString = (NSString*)CFUUIDCreateString(nil, uuidObj);
	CFRelease(uuidObj);
	return [uuidString autorelease];
}
@end
