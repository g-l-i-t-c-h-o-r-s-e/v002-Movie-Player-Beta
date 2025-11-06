//
//  v002MoviePlayerHelper.m
//  v002 MoviePlayer
//
//  Created by vade on 5/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "v002MoviePlayerHelper.h"

#import <OpenGL/CGLMacro.h>

#define kv002DefaultApertureMode 0
#define kv002DefaultLoopMode 0
#define kv002DefaultEnableWaveformOutput NO
#define kv002DefaultVolume 1.0
#define kv002DefaultBalance 0.0
#define kv002DefaultRate 1.0

#pragma mark -
#pragma mark Qucktime Visual Context Frame Available callback

static void frameImageAvailable(QTVisualContextRef vContext, const CVTimeStamp *frameTime, void *refCon)
{
		// this is our instance of the below class
	v002MoviePlayerHelper* helper = refCon;
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	[helper render];
	
	[pool release];
}

@implementation v002MoviePlayerHelper
@synthesize movieHasDuration;

@synthesize doUUID;
@synthesize apertureMode;
@synthesize loopMode;
//@synthesize enableWaveformOutput;
@synthesize volume;
@synthesize balance;
@synthesize rate;



#pragma mark Helper App Startup

- (id) init
{
    self = [super init];
	if(self)
	{
		visualContext = NULL;
		surfaceRef = NULL;
		surfaceID = 0;
#if	v002MoviePlayerPluginHelperUseGLVisualContext

		surfaceTextureAttachment = 0;
		surfaceFBO = 0;
		// create a GL context
		CGLPixelFormatAttribute attributes[] = {kCGLPFAAccelerated, kCGLPFANoRecovery, 0};
		
		CGLError err = kCGLNoError;
		GLint numPixelFormats = 0;
		
		err = CGLChoosePixelFormat(attributes, &pfObject, &numPixelFormats);
		
		if(err != kCGLNoError)
		{
			DLog(@"Error choosing pixel format %s", CGLErrorString(err));
		}
		
		err = CGLCreateContext(pfObject, NULL, &cgl_ctx);
		if(err != kCGLNoError)
		{
			DLog(@"Error creating context %s", CGLErrorString(err));
		}
		
		// now we set our GL context, and create the resources we need.
		
		// create a new FBO, we will render our CVOpenGLTextureRef into this. Our IOSurface (made below) is our texture attachment.
		// This lets us use fast path, YUV crazy quicktime speed to OpenGL, but still supply BGRA, 32 to Quartz Composer.
		glGenFramebuffersEXT(1, &surfaceFBO);
		
#endif
		_RGBSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		_RGBLinearSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGBLinear	);

		
		decodeQuality = 1.0f;
			
		_movie = nil;
		movieSize = NSMakeSize(640, 480);
		
		movieLoadState = 0L;
		movieWasPlaying = NO;
		movieHasDuration = NO;
        _shuttingDown = NO;
		
		audioDeviceUID = nil;
		
		[self setMovieTitle:@""];
		
		// 32 audio ivars
		// audio additions
		numberOfChannels = 0; // force mono for waveform fft output
		numberOfBandLevels = 7; // temp. will be input key
		freqResults = NULL;
		
		// we have private copies of some of our inputs so
		// we can use them outside of executeAtTime:
		// here we set them to their default values
	
		self.apertureMode = kv002DefaultApertureMode;
		self.loopMode = kv002DefaultLoopMode;
//		self.enableWaveformOutput = kv002DefaultEnableWaveformOutput;
		waveformOutputMode = v002WaveformOutputNone;
		self.volume = kv002DefaultVolume;
		self.balance = kv002DefaultBalance;
		self.rate = kv002DefaultRate;
#if v002MOVIEPLAYER_SURFACE_PER_FRAME
		surfaceAttributes = nil; // we create it once we have dimensions
#endif
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(movieLoadStateDidChange:)
													 name:QTMovieLoadStateDidChangeNotification
												   object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(movieSizeDidChange:)
													 name: QTMovieNaturalSizeDidChangeNotification	//QTMovieSizeDidChangeNotification	//QTMovieSizeDidChangeNotification
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(handleMovieDidEnd:)
													 name:QTMovieDidEndNotification
												   object:nil];
		/*		[[NSNotificationCenter defaultCenter] addObserver:self
		 selector:@selector(movieApertureDidChange:)
		 name:QTMovieApertureModeDidChangeNotification
		 object:nil];
		*/
	}
	return self;
}

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
    parentID = getppid();
    theConnection = [[NSConnection new] retain];
    [theConnection setRootObject:self];
    if (![theConnection registerName:[NSString stringWithFormat:@"info.v002.v002MoviePlayerHelper-%@", doUUID]]) {
        DLog(@"Error opening NSConnection - exiting");
    }
    [self setupPollParentTimer];
}


#pragma mark -
#pragma mark Rendering/DisplayLink

#if	v002MoviePlayerPluginHelperUseGLVisualContext

// we can only call this once we know our movies size.
- (void) setupIOSurfaceHavingLockedContext
{
	// destroy any previous surface
	if (surfaceRef != NULL)
	{
		glDeleteTextures(1, &surfaceTextureAttachment);
		glFlush();
		surfaceTextureAttachment = 0;
		
		CFRelease(surfaceRef);
	}
	
	// init our texture and IOSurface
#if !v002MOVIEPLAYER_SURFACE_PER_FRAME
	NSMutableDictionary* surfaceAttributes = [NSMutableDictionary dictionaryWithCapacity:4];
#else
	if (!surfaceAttributes)
	{
		surfaceAttributes = [[NSMutableDictionary alloc] initWithCapacity:4];
	}
#endif
	[surfaceAttributes setObject:[NSNumber numberWithBool:YES] forKey:(NSString*)kIOSurfaceIsGlobal];
	[surfaceAttributes setObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)movieSize.width] forKey:(NSString*)kIOSurfaceWidth];
	[surfaceAttributes setObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)movieSize.height] forKey:(NSString*)kIOSurfaceHeight];
	[surfaceAttributes setObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)4] forKey:(NSString*)kIOSurfaceBytesPerElement];
		
	surfaceRef =  IOSurfaceCreate((CFDictionaryRef) surfaceAttributes);

	// make a new texture.
	
	glGenTextures(1, &surfaceTextureAttachment);
	glEnable(GL_TEXTURE_RECTANGLE_ARB);
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, surfaceTextureAttachment);
//	NSLog(@"setup with surface ID: %u", IOSurfaceGetID((IOSurfaceRef)surfaceRef));
	CGLError err = CGLTexImageIOSurface2D(cgl_ctx, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, (GLsizei)movieSize.width, (GLsizei) movieSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, surfaceRef, 0);
	if(err != kCGLNoError)
	{
		DLog(@"Error creating IOSurface texture: %s & %x", CGLErrorString(err), glGetError());
	}
//	glFlush(); // TODO: do we need this flush? No, (says Tom)
	
	// now make the surface a texture attachment to our previously created FBO
	
	glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, surfaceFBO);
    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_EXT, surfaceTextureAttachment, 0);
    
    GLenum status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
    if(status != GL_FRAMEBUFFER_COMPLETE_EXT)
    {
        DLog(@"Cannot create FBO");
        DLog(@"OpenGL error %04X", status);
	}
}

#endif

- (BOOL) setupVisualContext
{
	// 32 only QTVisualContext setup
	if(visualContext == NULL)
	{
		
#if	v002MoviePlayerPluginHelperUseGLVisualContext
		
		DLog(@"setting up new openGL ");

		// create our OpenGL based visual context - defaults are fine here, we want it to choose on its own, so no conversion happens
		OSStatus error = QTOpenGLTextureContextCreate(kCFAllocatorDefault, cgl_ctx, pfObject, NULL, &visualContext);

#else
		// make sure we request proper IOSurface properties for our pixel buffer based visual context.
		NSDictionary* ioSurfaceProperties = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithBool: YES], (NSString *) kIOSurfaceIsGlobal,nil];
		
		NSDictionary* pixelBufferAttributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:ioSurfaceProperties, (NSString *) kCVPixelBufferIOSurfacePropertiesKey,
														 [NSNumber numberWithBool:YES], (NSString *) kCVPixelBufferOpenGLCompatibilityKey,
														 [NSNumber numberWithBool:YES], (NSString *) kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey,
														 [NSNumber numberWithBool:YES], (NSString *) kCVPixelBufferIOSurfaceOpenGLFBOCompatibilityKey,		// incase QC does any trickery behind the scenes...
														 [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], (NSString *) kCVPixelBufferPixelFormatTypeKey,
														 [NSNumber numberWithBool:NO], (NSString *) kCVPixelBufferIOSurfaceCoreAnimationCompatibilityKey,nil];
		
		NSDictionary *pixelBufferContextDictionary = [NSDictionary dictionaryWithObjectsAndKeys:pixelBufferAttributesDictionary, (NSString *) kQTVisualContextPixelBufferAttributesKey, nil];

		// create a new CVPixelBuffer based visual context with our requested format.
		OSStatus error = QTPixelBufferContextCreate(kCFAllocatorDefault, (CFDictionaryRef) pixelBufferContextDictionary, &visualContext);
#endif
		
		if(error != noErr)
		{
			DLog(@"v002MoviePlayerHelper couldn't create QTOpenGLTextureContext");
			return NO;
		}
		
		// this turns off any weird colorspace conversions and thus extra overhead.
		QTVisualContextSetAttribute(visualContext,kQTVisualContextWorkingColorSpaceKey, _RGBSpace);
		QTVisualContextSetAttribute(visualContext,kQTVisualContextOutputColorSpaceKey, _RGBSpace);
		
		// Timer-less callback.
		QTVisualContextSetImageAvailableCallback(visualContext, frameImageAvailable, self);
	}	
	return YES;
}

- (BOOL) setupAudioContext:(NSString*)deviceUID
{
	// Lifted from Technical Q&A QA1578 by toby*spark

	// Pass in a fully initialized QTKit QTMovie object and an Audio Device UID CFStringRef
	// NOTE: The Audio Device UID String is the persistent kAudioDevicePropertyDeviceUID property returned
	//       using AudioDeviceGetProperty.
	
	Movie aMovie;
	QTAudioContextRef audioContext;
	OSStatus status = paramErr;
	
	aMovie = [_movie quickTimeMovie];
	if (NULL == aMovie) return status;
	
	// create a QT Audio Context and set it on a Movie
	status = QTAudioContextCreateForAudioDevice(kCFAllocatorDefault, ([deviceUID length] == 0 ? NULL : (CFStringRef)deviceUID), NULL, &audioContext);
	if (status) NSLog(@"QTAudioContextCreateForAudioDevice failed: %d\n", (int)status);
	
	if (NULL != audioContext && noErr == status) 
	{
		status = SetMovieAudioContext(aMovie, audioContext);
		if (status) NSLog(@"SetMovieAudioContext failed: %d\n", (int)status);
		
		// release the Audio Context since SetMovieAudioContext will retain it
		CFRelease(audioContext);
	}
	return status;
}

- (void) render
{
    if (_shuttingDown || visualContext == NULL) return;
    
    CVImageBufferRef frame = NULL;
    OSStatus err = QTVisualContextCopyImageForTime(visualContext, NULL, NULL, &frame);
    if (err == kCVReturnSuccess) {
#if v002MoviePlayerPluginHelperUseGLVisualContext
        [self renderFBO:frame];
        CVBufferRelease(frame);
#else
        IOSurfaceRef ref = CVPixelBufferGetIOSurface(frame);
        [self setSurfaceID: IOSurfaceGetID(ref)];
        CVBufferRelease(currentFrameRef);
        currentFrameRef = frame;
#endif
    } else {
        DLog(@"error requesting frame, error %i:", (int)err);
        [self setSurfaceID:0];
#if !v002MoviePlayerPluginHelperUseGLVisualContext
        CVBufferRelease(currentFrameRef);
        currentFrameRef = NULL;
#endif
    }
    if (visualContext) QTVisualContextTask(visualContext);
}


#if	v002MoviePlayerPluginHelperUseGLVisualContext
- (void) renderFBO:(CVOpenGLTextureRef) frame
{
    CGLLockContext(cgl_ctx);
	
#if v002MOVIEPLAYER_SURFACE_PER_FRAME
	if (surfaceRef)
	{
		//		NSLog(@"release surface ID: %u", IOSurfaceGetID((IOSurfaceRef)surfaceRef));
		CFRelease(surfaceRef);
		surfaceRef = NULL;
	}
	if (surfaceAttributes) // We can't produce a frame until we have received the correct dimensions from the movie
	{
		surfaceRef = IOSurfaceCreate((CFDictionaryRef)surfaceAttributes);
	//	NSLog(@"draw to new (?) surface ID: %u", IOSurfaceGetID((IOSurfaceRef)newSurface));
		glEnable(GL_TEXTURE_RECTANGLE_ARB);
		GLuint tex;
		glGenTextures(1, &tex);
	//	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, surfaceTextureAttachment);
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, tex);
		CGLError err = CGLTexImageIOSurface2D(cgl_ctx, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, (GLsizei)movieSize.width, (GLsizei) movieSize.height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, surfaceRef, 0);
		if(err != kCGLNoError)
		{
			DLog(@"width: %f height: %f description: %@", movieSize.width, movieSize.height, surfaceAttributes);
			DLog(@"Error creating IOSurface texture: %s & %x", CGLErrorString(err), glGetError());
		}
		glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
//		glFlush(); // TODO: do we need this flush? (No, says Tom)
		
#endif
		// bind our FBO / and thus our IOSurface
		glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, surfaceFBO);
	#if v002MOVIEPLAYER_SURFACE_PER_FRAME
		glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_TEXTURE_RECTANGLE_EXT, tex, 0);
	#endif
		   
		GLenum status = glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
		if(status == GL_FRAMEBUFFER_COMPLETE_EXT)
		{
			// Setup OpenGL states
			glViewport(0, 0, movieSize.width,  movieSize.height);
			glMatrixMode(GL_PROJECTION);
			glPushMatrix();
			glLoadIdentity();
			glOrtho(0, movieSize.width, 0, movieSize.height, -1, 1);
			
			glMatrixMode(GL_MODELVIEW);
			glPushMatrix();
			glLoadIdentity();
			
			// dont bother clearing. we dont have any alpha so we just write over the buffer contents. saves us an expensive write.
			glClearColor(0.0, 0.0, 0.0, 0.0);
			glClear(GL_COLOR_BUFFER_BIT);
			
			glActiveTexture(GL_TEXTURE0);
			glEnable(CVOpenGLTextureGetTarget(frame));
			glBindTexture(CVOpenGLTextureGetTarget(frame), CVOpenGLTextureGetName(frame));
			
			// do a nearest linear interp.
			glTexParameteri(CVOpenGLTextureGetTarget(frame), GL_TEXTURE_MIN_FILTER, GL_NEAREST);
			glTexParameteri(CVOpenGLTextureGetTarget(frame), GL_TEXTURE_MAG_FILTER, GL_NEAREST);
			
			glColor4f(1.0, 1.0, 1.0, 1.0);
			
			// why do we need it ?
			glDisable(GL_BLEND);
			
			GLfloat ll[2]; 
			GLfloat lr[2];
			GLfloat ur[2];
			GLfloat ul[2];
			
			CVOpenGLTextureGetCleanTexCoords(frame, ll, lr, ur, ul);
			
			GLfloat tex_coords[] = 
			{
				ll[0], ll[1],
				lr[0], lr[1],
				ur[0], ur[1],
				ul[0], ul[1]
			};
			
			GLfloat verts[] = 
			{
				0.0f, 0.0f,
				movieSize.width, 0.0f,
				movieSize.width, movieSize.height,
				0.0f, movieSize.height
			};
			
			glEnableClientState( GL_TEXTURE_COORD_ARRAY );
			glTexCoordPointer(2, GL_FLOAT, 0, tex_coords );
			glEnableClientState(GL_VERTEX_ARRAY);
			glVertexPointer(2, GL_FLOAT, 0, verts );
			glDrawArrays( GL_TRIANGLE_FAN, 0, 4 );
			glDisableClientState( GL_TEXTURE_COORD_ARRAY );
			glDisableClientState(GL_VERTEX_ARRAY);
			
			// Restore OpenGL states
			glMatrixMode(GL_MODELVIEW);
			glPopMatrix();
			
			glMatrixMode(GL_PROJECTION);
			glPopMatrix();
			
			// flush to make sure IOSurface updates are seen in parent app.
			glFlushRenderAPPLE();
			
			// get the updated surfaceID to pass to STDOut...
			[self setSurfaceID:IOSurfaceGetID(surfaceRef)]; // TODO: for v002MOVIEPLAYER_SURFACE_PER_FRAME 0 we probably don't need to do this except to flag that we have a new frame
		}
		if(status != GL_FRAMEBUFFER_COMPLETE_EXT)
		{
			DLog(@"OpenGL error %04X in renderFBO:", status);
			//glDeleteTextures(1, &gameTexture);
			//gameTexture = 0;
		}
#if v002MOVIEPLAYER_SURFACE_PER_FRAME
		glDeleteTextures(1, &tex);
	}
#endif
    CGLUnlockContext(cgl_ctx);
}
#endif

#pragma mark Utility

- (void) setupPollParentTimer
{
	pollParentTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval) 1
													   target:self
													 selector:@selector(pollParent)
													 userInfo:nil
													  repeats:YES];
	
}

- (void) pollParent
{
	if([NSRunningApplication runningApplicationWithProcessIdentifier:parentID] == nil)
		[self quitHelperTool];
}

// TODO: stictly required these days?
- (void) task
{
	MoviesTask([_movie quickTimeMovie], 0);	
}

- (void)cleanUpForDealloc
{
    // Stop future work first
    _shuttingDown = YES;
    
    // Kill the parent poll timer
    if (pollParentTimer) { [pollParentTimer invalidate]; pollParentTimer = nil; }
    
    // Remove notifications early
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Stop movie and detach it from any visual context
    if (_movie) {
        [_movie setRate:0.0];
        SetMovieVisualContext([_movie quickTimeMovie], NULL);
        [_movie detachFromCurrentThread];
        [_movie release];
        _movie = nil;
    }
    
    // Cancel image-available callback before releasing the context
    if (visualContext) {
        QTVisualContextSetImageAvailableCallback(visualContext, NULL, NULL);
        CFRelease(visualContext);
        visualContext = NULL;
    }
    
#if !v002MoviePlayerPluginHelperUseGLVisualContext
    if (currentFrameRef) { CVBufferRelease(currentFrameRef); currentFrameRef = NULL; }
#endif
    
#if v002MOVIEPLAYER_SURFACE_PER_FRAME
    [surfaceAttributes release]; surfaceAttributes = nil;
#endif
    
#if v002MoviePlayerPluginHelperUseGLVisualContext
    CGLLockContext(cgl_ctx);
    if (surfaceFBO) { glDeleteFramebuffersEXT(1, &surfaceFBO); surfaceFBO = 0; }
    if (surfaceTextureAttachment) { glDeleteTextures(1, &surfaceTextureAttachment); surfaceTextureAttachment = 0; }
    CGLError err = kCGLNoError; (void)err;
    CGLUnlockContext(cgl_ctx);
    if (cgl_ctx) { CGLReleaseContext(cgl_ctx); cgl_ctx = NULL; }
#endif
    
    if (surfaceRef) { CFRelease(surfaceRef); surfaceRef = NULL; }
    if (_RGBSpace) { CGColorSpaceRelease(_RGBSpace); _RGBSpace = NULL; }
    if (_RGBLinearSpace) { CGColorSpaceRelease(_RGBLinearSpace); _RGBLinearSpace = NULL; }
    
    if (freqResults) { free(freqResults); freqResults = NULL; }
}


#pragma mark -
#pragma mark Handle Load State

// quicktime movies via QTKit load asyncronously, thus we have ought to handle these various states properly.
// http://devworld.apple.com/qa/qa2006/qa1469.html

// safe to query movie properties
- (void) handleQTMovieLoadStateLoaded
{
	
	[self setMovieTitle:[_movie attributeForKey:QTMovieDisplayNameAttribute]];
	
	// cache this value
	movieHasDuration = [[_movie attributeForKey:QTMovieHasDurationAttribute] boolValue];
}

- (void) handleQTMovieLoadStatePlayable
{
	
	// 32 bit only
	[self resetFFT];
	
	// set the movie aperture mode so we can handle things with non 1:1 pixel aspecrt ratios.
	[_movie generateApertureModeDimensions];	
	
	switch (self.apertureMode)
	{
			// production	
		case 1:
			[_movie setAttribute:QTMovieApertureModeProduction forKey:QTMovieApertureModeAttribute];
			break;
			// raw encoded pixels
		case 2:
			[_movie setAttribute:QTMovieApertureModeEncodedPixels forKey:QTMovieApertureModeAttribute];
			break;
			// clean
		case 0:
		default:
			[_movie setAttribute:QTMovieApertureModeClean forKey:QTMovieApertureModeAttribute];
			break;
	}
	[self setMovieLoop:self.loopMode];
	[self setMovieVolume:self.volume];
	[self setMovieBalance:self.balance];
	
	// reset visual context so that aperture size changes propogate. FUCK YOU.
	//SetMovieVisualContext([_movie quickTimeMovie], visualContext);
	
	// ping the pixel buffer attributes to make sure we get the right size. 
	// this fixes random size/offsets if opening movies with drastically different sizes.
	[self movieSizeDidChange:nil];

	// since we are now playable, relink to the callback
	QTVisualContextSetImageAvailableCallback(visualContext, frameImageAvailable, self);
	movieFinished = NO;
	[self setMovieRate:self.rate]; // This will start the movie if we're meant to be playing
}

- (void) handleQTMovieLoadStatePlaythroughOK
{
	[self resetFFT];
	
	// audioDeviceUID will only exist if it has been set
	if (audioDeviceUID) 
	{
		[self setMovieAudioDevice:audioDeviceUID];
	}
	if (_playing)
	{
		[_movie setRate:self.rate];
	}
}

- (void) handleSizeChange
{
#if	v002MoviePlayerPluginHelperUseGLVisualContext
	// We have to lock and remain locked while movieSize != the sizes in our surface attributes dictionary
	// Otherwise we try to render with miss-matched sizes and generate errors
	CGLLockContext(cgl_ctx);
#endif
	[[_movie attributeForKey:QTMovieNaturalSizeAttribute] getValue:&movieSize];
	movieSize.width = movieSize.width * decodeQuality;
	movieSize.height = movieSize.height * decodeQuality;

	// if we need to, we must build our surface and attach to the FBO
	// since we know our movies size now.
#if	v002MoviePlayerPluginHelperUseGLVisualContext
	[self setupIOSurfaceHavingLockedContext];

	CGLUnlockContext(cgl_ctx);

	// This seems to only work in GLTextureContext scenario.
	// in order for our new  pixel buffer keys to take effect we have to dissassociate our movie from our QT visual context.
	SetMovieVisualContext([_movie quickTimeMovie], NULL);
	
	// this is the MAGIC CODE that dings the QTVisualContext into outputting "square pixel" textures that QC is happy with.
	NSMutableDictionary* pixelBufferDict = [NSMutableDictionary dictionary];
	[pixelBufferDict setValue:[NSNumber numberWithFloat:movieSize.width * decodeQuality] forKey:(NSString*)kCVPixelBufferWidthKey];
	[pixelBufferDict setValue:[NSNumber numberWithFloat:movieSize.height * decodeQuality] forKey:(NSString*)kCVPixelBufferHeightKey];
	
	QTVisualContextSetAttribute(visualContext,kQTVisualContextPixelBufferAttributesKey, (CFDictionaryRef)pixelBufferDict);

	//... and then reassociate so that movies which change their aperture or transport stream like the new size.
	SetMovieVisualContext([_movie quickTimeMovie], visualContext);
#endif		
	
	// TODO: is this required?
	// re apply hints
	//	SetMoviePlayHints([movie quickTimeMovie], 0L, hintsHighQuality);
	//	SetMoviePlayHints([movie quickTimeMovie], hintsSingleField, hintsSingleField);
	//	SetMoviePlayHints([movie quickTimeMovie], hintsDeinterlaceFields, hintsDeinterlaceFields);
	//	SetMoviePlayHints([movie quickTimeMovie], hintsFlushVideoInsteadOfDirtying, hintsFlushVideoInsteadOfDirtying);
	//	SetMoviePlayHints([movie quickTimeMovie], hintsLoop, hintsLoop );   
	
//	DLog(@"size change notification, %i, with size: %@", (int)movieLoadState, NSStringFromSize(movieSize));
}


#pragma mark Notification handling

- (void) handleMovieDidEnd:(NSNotification *)notification
{
	movieFinished = YES;
}

// http://devworld.apple.com/qa/qa2006/qa1469.html
- (void) movieLoadStateDidChange:(NSNotification*)aNotification
{
	// TWB need to check it's our movie, as we registered for all objects
	if ([aNotification object] == _movie)
	{
		movieLoadState = [[_movie attributeForKey:QTMovieLoadStateAttribute] longValue];
		
		// have atom to query and set basic info
		if(movieLoadState >= QTMovieLoadStateLoaded)
		{
			[self handleQTMovieLoadStateLoaded];
		}
		
		// have enough to output frames.
		if(movieLoadState >= QTMovieLoadStatePlayable)
		{
			[self handleQTMovieLoadStatePlayable];
		}
		
		if(movieLoadState >= QTMovieLoadStatePlaythroughOK)
		{
			[self handleQTMovieLoadStatePlaythroughOK];
		}
	}
}

- (void) movieSizeDidChange:(NSNotification*)aNotification;
{
	[self handleSizeChange];
}

- (void) movieApertureDidChange:(NSNotification*)aNotification;
{
	// recalculate size.
	[self movieSizeDidChange:nil];
}

#pragma mark -
#pragma mark v002MoviePlayerDOProtocol requirements

- (oneway void) openMovie:(NSURL*)movieURL
{
	DLog(@"Open Movie - have texture context..  continuing");
	// if we already have a QTMovie release it
	if (nil != _movie)
	{
		DLog(@"have movie, removing");

		[_movie stop];
		
		// 32 bit only, turn off FFT audio metering.
		[self disableCurrentFFT];
		
		// destroy the texture context callback
		SetMovieVisualContext([_movie quickTimeMovie], NULL);
		QTVisualContextSetImageAvailableCallback(visualContext, NULL, NULL);
		
		[_movie release];
		_movie = nil;
	}
	[self setSurfaceID:0];
#if v002MOVIEPLAYER_SURFACE_PER_FRAME
#if v002MoviePlayerPluginHelperUseGLVisualContext
	// We clear the attributes until we have received correct dimensions
	CGLLockContext(cgl_ctx);
	[surfaceAttributes release];
	surfaceAttributes = nil;
	CGLUnlockContext(cgl_ctx);
#endif
#endif
	// Don't perform the canInitWithURL check as it fails for some valid URLs
	// Seemingly those without an extension to the resource name
	if(movieURL)
	{
		DLog(@"setting up new visual context");

		[self setupVisualContext];
		
		NSError* error;
		
		DLog(@"Quicktime says it can open this file.. continuing");
		
		NSMutableDictionary * movieInitDict = [NSMutableDictionary dictionary];
		[movieInitDict setObject:movieURL forKey:QTMovieURLAttribute];
		[movieInitDict setObject:[NSNumber numberWithBool:YES] forKey:QTMovieOpenAsyncOKAttribute];
		//[movieInitDict setObject:[NSNumber numberWithBool:YES] forKey:QTMovieOpenForPlaybackAttribute]; // requests QTX playback, but cannot use quicktimeMovie accessor.
						
		_movie = [[QTMovie alloc] initWithAttributes:movieInitDict error:&error];
#ifdef DEBUG_PRINT
		if (error) DLog(@"movie opening error: %@", error);
#endif
		//movie = [[QTMovie alloc] initWithURL:movieURL error:nil];
		
		movieLoadState = [[_movie attributeForKey:QTMovieLoadStateAttribute] longValue];
		
		// dont set a visual context yet, because the movie may not be outputting frames, and that may cause issues with slow movies downloading via HTTP etc
		// (? at least, this seems to be true but who the fuck knows... maybe its voodoo)
		SetMovieVisualContext([_movie quickTimeMovie], visualContext);
		
		// http://devworld.apple.com/qa/qa2006/qa1469.html
		// have atom to query and set basic info
		if(movieLoadState >= QTMovieLoadStateLoaded)
		{
			DLog(@"loaded");
			[self handleQTMovieLoadStateLoaded];
		}
		
		// have enough to output frames.
		if(movieLoadState >= QTMovieLoadStatePlayable)
		{
			DLog(@"playable");
			[self handleQTMovieLoadStatePlayable];
		}
		
		if(movieLoadState >= QTMovieLoadStatePlaythroughOK)
		{
			DLog(@"playthroughok");
			[self handleQTMovieLoadStatePlaythroughOK];
		}
	}
}

#pragma mark - setters for movie properties
- (oneway void) setMovieIsPlaying:(BOOL)flag
{
	if (_playing != flag)
	{
		_playing = flag;
		if (flag)
		{
			movieFinished = NO;
			[_movie setRate:self.rate];
		}
		else
		{
			[_movie stop];
		}
	}
}

- (oneway void) setMovieRate:(float)r
{
	self.rate = r;
	if (_playing && !movieFinished)
	{
		[_movie setRate:r];
	}
}

- (oneway void) setMovieTime:(float)time
{
	NSNumber *scale = [_movie attributeForKey:QTMovieTimeScaleAttribute];
	QTTime  duration = [_movie duration];
	QTTime currentTime = QTMakeTime(time * duration.timeValue, [scale doubleValue]); 
	[_movie setCurrentTime:currentTime];
	if (_playing && movieFinished)
	{
		movieFinished = NO;
		[_movie setRate:self.rate];
	}
}

- (oneway void) setMovieVolume:(float)v
{
	self.volume = v;
	[_movie setVolume:v];
}

- (oneway void) setMovieVolumes:(in NSArray*)volumes	// for multichannel/multitrack
{
	int i = 0;
	for(QTTrack* track in [_movie tracks])
	{
		if([[track media] hasCharacteristic:QTMediaCharacteristicAudio] && ([volumes count] >= i+1) )
		{
			DLog(@"changing volume for track %d", i);
			[track setVolume:[[volumes objectAtIndex:i] floatValue]];
		}
		else
		{
			[track setVolume:1.0];
		}
		i++;
	}	
}

- (oneway void) setMovieBalance:(float)b
{
	self.balance = b;
	SetMovieAudioBalance([_movie quickTimeMovie], b, 0);	
}

- (oneway void) setMovieBalances:(in NSArray*)balances	// for multichannel/multitrack
{
	// changes for stephen holmes
	int i = 0;
	for(QTTrack* track in [_movie tracks])
	{
		MediaHandler handler = GetMediaHandler([[track media] quickTimeMedia]);
		if([[track media] hasCharacteristic:QTMediaCharacteristicAudio] && ([balances count] >= i+1))
		{
			short trackBalance = (short) floor([[balances objectAtIndex:i] doubleValue] * 127);
			DLog(@"balance: %i", trackBalance);
			MediaSetSoundBalance(handler, trackBalance); // balance of audio track in array
		}
		else
		{
			MediaSetSoundBalance(handler, 0);
		}
		i++;
	}
}

- (oneway void) setMovieLoop:(NSUInteger)lm
{
	if (lm == 0)
	{
		[_movie setAttribute:[NSNumber numberWithBool:TRUE] forKey:@"QTMovieLoopsAttribute"]; 
	}
	else if (lm == 1)
	{
		[_movie setAttribute:[NSNumber numberWithBool:TRUE] forKey:@"QTMovieLoopsBackAndForthAttribute"];
	}	
	else if (lm == 2)
	{
		[_movie setAttribute:[NSNumber numberWithBool:FALSE] forKey:@"QTMovieLoopsAttribute"];			
	}
	
	[self setLoopMode:lm];
}

- (oneway void) setMovieDeinterlaceHint:(BOOL)hint
{
	SetMoviePlayHints([_movie quickTimeMovie], hint ? hintsDeinterlaceFields : 0L, hintsDeinterlaceFields);
}

- (oneway void) setMovieHighQualityHint:(BOOL)hint
{
	SetMoviePlayHints([_movie quickTimeMovie], hint ? hintsHighQuality : 0L, hintsHighQuality);

}

- (oneway void) setMovieSingleFieldHint:(BOOL)hint
{
	SetMoviePlayHints([_movie quickTimeMovie], hint ? hintsSingleField : 0L, hintsSingleField);
}

- (oneway void) setMovieAperture:(NSUInteger)aperture
{
	apertureMode = aperture;
	switch (aperture)
	{
			// clean
		case 0:
			[_movie setAttribute:QTMovieApertureModeClean forKey:QTMovieApertureModeAttribute];
			break;
			// production	
		case 1:
			[_movie setAttribute:QTMovieApertureModeProduction forKey:QTMovieApertureModeAttribute];
			break;
			// raw encoded pixels
		case 2:
			[_movie setAttribute:QTMovieApertureModeEncodedPixels forKey:QTMovieApertureModeAttribute];
			break;
			//clean
		default:
			[_movie setAttribute:QTMovieApertureModeClean forKey:QTMovieApertureModeAttribute];
			break;
	}
}

- (oneway void) setMovieDecodeQuality:(float)quality
{
	decodeQuality = quality;

#if	v002MoviePlayerPluginHelperUseGLVisualContext
	// only ping this if we have a GL context, which means we should have a texture and a surface.
	if(cgl_ctx != NULL)	
		[self handleSizeChange];
#endif
}

- (oneway void) setMovieAudioDevice:(NSString*)newAudioDeviceUID
{
	[newAudioDeviceUID retain];
	[audioDeviceUID release];
	audioDeviceUID = newAudioDeviceUID;
		
	DLog(@"setMovieAudioDevice: %@", audioDeviceUID);
		
	[self setupAudioContext:audioDeviceUID];
}

#pragma mark - getters for movie properties
- (float) movieRate
{
	return [_movie rate];
}

- (float) movieNormalizedTime
{
	if(movieHasDuration)
	{
		QTTime duration = [_movie duration];
		QTTime currentTime = [_movie currentTime];	
		return ((float)currentTime.timeValue/(float)duration.timeValue);	
	}
	return 0.0;
}

- (double) movieTime
{
	if(movieHasDuration)
	{
		QTTime currentTime = [_movie currentTime];
		QTGetTimeInterval(currentTime, & timeInterval); 	
		return (double)timeInterval;	
	}
	return 0.0;
}

- (double) movieDuration
{
	if(movieHasDuration)
	{
		QTTime durationTime = [_movie duration];
		QTGetTimeInterval(durationTime, & durationInterval); 
		return (double)durationInterval;
	}
	return 0.0;
}

- (void)setMovieTitle:(NSString *)title
{
	[title retain];
	[movieTitle release];
	movieTitle = title;
	hasNewInfo = YES;
}

- (NSString*) movieTitle
{
	hasNewInfo = NO;
	return movieTitle;
}

- (BOOL) movieDidEnd
{
	return movieFinished;
}

#pragma mark - features 

- (void) resetFFT // not strictly part of the protocol but we place it here for legibility
{
	if([[_movie attributeForKey:QTMovieHasAudioAttribute] boolValue])
	{
		OSStatus err;
		FourCharCode whatToMix;
		if (waveformOutputMode == v002WaveformOutputMono)
		{
			whatToMix = kQTAudioMeter_MonoMix;
			numberOfChannels = 1;
		}
		else if (waveformOutputMode == v002WaveformOutputChannels)
		{
			whatToMix = kQTAudioMeter_DeviceMix;
			AudioChannelLayout *layout = NULL;
			UInt32 size = 0;
			OSStatus err;
						
			// get the size of the device layout
			err = QTGetMoviePropertyInfo([_movie quickTimeMovie], kQTPropertyClass_Audio,
										 kQTAudioPropertyID_DeviceChannelLayout,
										 NULL, &size, NULL);
			
			if (err || (0 == size))
			{
				// We get size 0 here for RTSP, ugh
				if (size)
					DLog(@"Error QTGetMoviePropertyInfo %d", (int)err);
				else {
					DLog(@"0 size");
				}
				return; 
			}
			
			// allocate memory for the device layout
			layout = (AudioChannelLayout*)calloc(1, size);
			if (NULL == layout) {
				DLog(@"Error couldn't calloc");
				return;
			} 
			
			// get the device layout from the movie
			err = QTGetMovieProperty([_movie quickTimeMovie], kQTPropertyClass_Audio, 
									 kQTAudioPropertyID_DeviceChannelLayout, 
									 size, 
									 layout, 
									 NULL);
			if (err)
			{
				DLog(@"Error couldn't QTGetMovieProperty");
				return;
			}
			
			// now get the number of channels
			numberOfChannels = (layout->mChannelLayoutTag ==
								kAudioChannelLayoutTag_UseChannelDescriptions) ?
			layout->mNumberChannelDescriptions :
			AudioChannelLayoutTag_GetNumberOfChannels(layout->mChannelLayoutTag);
			
			free(layout);
		} else {
			free(freqResults);
			freqResults = NULL;
			return;
		}
		DLog(@"Number of channels %u", (unsigned int)numberOfChannels);
		
		err = SetMovieAudioFrequencyMeteringNumBands([_movie quickTimeMovie], whatToMix, &numberOfBandLevels);
		
		if(err)
		{
			DLog(@"Error setting Audio Frequency Metering..");
		}
		
		//TWB free up any previous allocation
		free(freqResults);
		// alloc
		freqResults = malloc(offsetof(QTAudioFrequencyLevels, level[numberOfBandLevels * numberOfChannels]));
		
		// configure
		freqResults->numChannels = numberOfChannels;
		freqResults->numFrequencyBands = numberOfBandLevels;			
	}
}

/*
- (void) enableWaveformOutput:(BOOL)waveform
{
	self.enableWaveformOutput = waveform;
	if(self.enableWaveformOutput)
		[self setupFFT];
}
 */

- (void)disableCurrentFFT
{
	if (_movie != NULL && waveformOutputMode != v002WaveformOutputNone)
	{
		SetMovieAudioFrequencyMeteringNumBands([_movie quickTimeMovie], waveformOutputMode == v002WaveformOutputMono ? kQTAudioMeter_MonoMix : kQTAudioMeter_DeviceMix, NULL);
	}
}

- (void)setWaveformOutputMode:(v002WaveformOutputMode)mode
{
	if (waveformOutputMode != mode)
	{
		[self disableCurrentFFT];
		waveformOutputMode = mode;
		if (mode != v002WaveformOutputNone)
		{
			[self resetFFT];
		}
	}
}

- (void) setWaveformNumberOfBands:(NSUInteger)num
{
	numberOfBandLevels = num;
	if(waveformOutputMode != v002WaveformOutputNone)
		[self resetFFT];
}

- (NSArray*) waveForm
{
	if(waveformOutputMode != v002WaveformOutputNone && [[_movie attributeForKey:QTMovieHasAudioAttribute] boolValue])
	{
		NSMutableArray *channelsArray = [NSMutableArray arrayWithCapacity:numberOfChannels];
		NSNumber* valueNumber;
		// call each time you are ready to display meter levels
		if (freqResults != NULL)
		{
			OSStatus err;
			FourCharCode whatToMix = waveformOutputMode == v002WaveformOutputMono ? kQTAudioMeter_MonoMix : kQTAudioMeter_DeviceMix;
			err = GetMovieAudioFrequencyLevels([_movie quickTimeMovie], whatToMix, freqResults);
			if (err)
			{
				//DLog(@"Error obtaining audio frequency levels");
			}
			
			for (NSInteger i = 0; i < freqResults->numChannels; i++)
			{
				NSMutableArray *waveFormArray = [NSMutableArray arrayWithCapacity:numberOfBandLevels];
				for (NSInteger j = 0; j < freqResults->numFrequencyBands; j++)
				{
					// the frequency levels are Float32 values between 0. and 1.
					Float32 value = freqResults->level[(i * freqResults->numFrequencyBands) + j];
					
					valueNumber = [NSNumber numberWithFloat:value]; 
					[waveFormArray addObject:valueNumber];
				}
				[channelsArray addObject:waveFormArray];
			}
		}
		if (waveformOutputMode == v002WaveformOutputMono)
		{
			if ([channelsArray count] > 1)
			{
				DLog(@"Unexpected channel count in waveform output");
			}
			return [channelsArray lastObject];
		}
		else
		{
			return channelsArray;
		}

		
	}
	return nil;
}

#pragma mark - IOSurface

- (BOOL) hasNewFrame
{
	return hasNewFrame;
}

- (BOOL) hasNewInfo
{
	return hasNewInfo;
}

- (void) setSurfaceID:(IOSurfaceID) surf
{
	surfaceID = surf;
	hasNewFrame = YES;
}

- (IOSurfaceID) surfaceID
{	
	hasNewFrame = NO;
	return surfaceID;
}

#pragma mark - cleanup
- (oneway void) quitHelperTool
{
    DLog(@"Quitting");
    [self cleanUpForDealloc];
    [[NSApplication sharedApplication] terminate:nil];
}


#pragma mark -


@end




v002MoviePlayerHelper *helper;

int main (int argc, const char * argv[])
{
	if (argc > 1)
	{
		//		DLog(@"Helper tool UUID is: %s", argv[1]);
		
		NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
		NSApplication *app = [NSApplication sharedApplication];
		helper	= [[v002MoviePlayerHelper alloc] init];
		
		[app setDelegate:helper];
		[helper setDoUUID:[NSString stringWithCString:argv[1] encoding:NSUTF8StringEncoding]];
		
		[app run];	
		
		[pool release];
	} else {
		DLog(@"Missing arguments for helper tool");
	}
	
	return 0;
}
