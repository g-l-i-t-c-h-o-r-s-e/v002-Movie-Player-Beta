//
//  v002IOSurfaceImageProvider.m
//  v002 MoviePlayer
//
//  Created by Tom on 06/01/2011.
//  Copyright 2011 Tom Butterworth. All rights reserved.
//

#import "v002IOSurfaceImageProvider.h"
#import <OpenGL/OpenGL.h>
#import <OpenGL/CGLMacro.h>
#import <OpenGL/CGLIOSurface.h>

@implementation v002IOSurfaceImageProvider

- (id)initWithSurfaceID:(IOSurfaceID)surfaceID pixelFormat:(NSString *)format colorSpace:(CGColorSpaceRef)cspace shouldColorMatch:(BOOL)shouldMatch
{
    self = [super init];
	if (self)
	{
		_surface = IOSurfaceLookup(surfaceID);
		if (!_surface)
		{
			[self release];
			return nil;
		}
		_format = [format retain];
		_cspace = CGColorSpaceRetain(cspace);
		_cmatch = shouldMatch;
		_width = IOSurfaceGetWidth(_surface);
		_height = IOSurfaceGetHeight(_surface);
	}
	return self;
}

- (void)finalize
{
	if (_surface) CFRelease(_surface);
	CGColorSpaceRelease(_cspace);
	[super finalize];
}

- (void)dealloc
{
	if (_surface) CFRelease(_surface);
	CGColorSpaceRelease(_cspace);
	[_format release];
	[super dealloc];
}

- (NSRect) imageBounds
{
	return NSMakeRect(0, 0, _width, _height);
}

/*
 Returns the colorspace of the image.
 */
- (CGColorSpaceRef) imageColorSpace
{
	return _cspace;
}

/*
 Returns NO if the image should not be color matched (e.g. it's a mask or gradient) - YES by default.
 */
- (BOOL) shouldColorMatch
{
	return _cmatch;
}

/*
 Returns the list of memory buffer pixel formats supported by -renderToBuffer (or nil if not supported) - nil by default.
 */
- (NSArray*) supportedBufferPixelFormats
{
	return [NSArray arrayWithObject:_format];
}

/*
 Renders a subregion of the image into a memory buffer of a given pixel format or returns NO on failure.
 The base address is guaranteed to be 16 bytes aligned and the bytes per row a multiple of 16 as well.
 */
- (BOOL) renderToBuffer:(void*)baseAddress withBytesPerRow:(NSUInteger)rowBytes pixelFormat:(NSString*)format forBounds:(NSRect)bounds
{
	if ([format isEqualToString:_format])
	{
		NSInteger rowLength;
		if (bounds.origin.x + bounds.size.width > _width)
			rowLength = _width - bounds.origin.x;
		else
			rowLength = bounds.size.width;

		NSInteger rowCount;
		if (bounds.origin.y + bounds.size.height > _height)
			rowCount = _height - bounds.origin.y;
		else
			rowCount = bounds.size.height;

		if (rowCount < 1 || rowLength < 1)
		{
			// nothing to do
			return YES;
		}
		size_t bytesPerPixel;
		size_t filledBytesPerRow;
		if ([format isEqualToString:QCPlugInPixelFormatARGB8]
			|| [format isEqualToString:QCPlugInPixelFormatBGRA8]
			|| [format isEqualToString:QCPlugInPixelFormatIf])
		{
			bytesPerPixel = 4;
		}
		else if ([format isEqualToString:QCPlugInPixelFormatI8])
		{
			bytesPerPixel = 1;
		}
		else if ([format isEqualToString:QCPlugInPixelFormatRGBAf])
		{
			bytesPerPixel = 16;
		}
		else {
			return NO;
		}
		filledBytesPerRow = bytesPerPixel * rowLength;
		
		if (kIOReturnSuccess == IOSurfaceLock(_surface, kIOSurfaceLockReadOnly, NULL))
		{
			void *surfaceBuffer = IOSurfaceGetBaseAddress(_surface);
			size_t surfaceRowBytes = IOSurfaceGetBytesPerRow(_surface);
			
			surfaceBuffer += (size_t)(surfaceRowBytes * (bounds.origin.y + bounds.size.height));
			surfaceBuffer -= (size_t)bounds.size.width * bytesPerPixel;
			
			for (unsigned int bufferRow = 0; bufferRow < rowCount; bufferRow++)
			{
				memcpy(baseAddress, surfaceBuffer, filledBytesPerRow);
				baseAddress += rowBytes;
				surfaceBuffer -= surfaceRowBytes;
			}
			IOSurfaceUnlock(_surface, kIOSurfaceLockReadOnly, NULL);
			return YES;
		}
	}
	return NO;
}

/*
 Returns the list of texture pixel formats supported by -copyRenderedTextureForCGLContext (or nil if not supported) - nil by default.
 If this methods returns nil, then -canRenderWithCGLContext / -renderWithCGLContext are called.
 */
- (NSArray*) supportedRenderedTexturePixelFormats
{
	return nil;
}

/*
 Returns the name of an OpenGL texture of type GL_TEXTURE_RECTANGLE_EXT that contains a subregion of the image in a given pixel format - 0 by default.
 The "flipped" parameter must be set to YES on output if the contents of the returned texture is vertically flipped.
 Use <OpenGL/CGLMacro.h> to send commands to the OpenGL context.
 Make sure to preserve all the OpenGL states except the ones defined by GL_CURRENT_BIT.
 */
- (GLuint) copyRenderedTextureForCGLContext:(CGLContextObj)cgl_ctx pixelFormat:(NSString*)format bounds:(NSRect)bounds isFlipped:(BOOL*)flipped
{
	return 0;
}

/*
 Called to release the previously copied texture.
 Use <OpenGL/CGLMacro.h> to send commands to the OpenGL context.
 Make sure to preserve all the OpenGL states except the ones defined by GL_CURRENT_BIT.
 */
- (void) releaseRenderedTexture:(GLuint)name forCGLContext:(CGLContextObj)cgl_ctx
{
	
}

/*
 Performs extra checkings on the capabilities of the OpenGL context (e.g check for supported extensions) and returns YES if the image can be rendered into this context - NO by default.
 Use <OpenGL/CGLMacro.h> to send commands to the OpenGL context.
 If this methods returns NO, then -renderToBuffer is called.
 */
- (BOOL) canRenderWithCGLContext:(CGLContextObj)cgl_ctx
{
	return YES;
}

/*
 Renders a subregion of the image with the provided OpenGL context or returns NO on failure.
 Use <OpenGL/CGLMacro.h> to send commands to the OpenGL context.
 The viewport is already set to the proper dimensions and the projection and modelview matrices are identity.
 The rendering must save / restore all the OpenGL states it changes except the ones defined by GL_CURRENT_BIT.
 */
- (BOOL) renderWithCGLContext:(CGLContextObj)cgl_ctx forBounds:(NSRect)bounds
{
	BOOL result = YES;
	
	glPushAttrib(GL_ENABLE_BIT | GL_TEXTURE_BIT | GL_TRANSFORM_BIT);
	glPushClientAttrib(GL_CLIENT_ALL_ATTRIB_BITS);
	
	glEnable(GL_TEXTURE_RECTANGLE_ARB);

	GLuint captureTexture;
	glGenTextures(1, &captureTexture);
	glBindTexture(GL_TEXTURE_RECTANGLE_ARB, captureTexture);
	
	CGLError err = CGLTexImageIOSurface2D(cgl_ctx, GL_TEXTURE_RECTANGLE_ARB, GL_RGBA8, _width, _height, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, _surface, 0);
	if(err == kCGLNoError)
	{
		glColor4f(1.0, 1.0, 1.0, 1.0);
		
		glMatrixMode(GL_PROJECTION);
		glPushMatrix();
		
		glOrtho(bounds.origin.x, bounds.origin.x + bounds.size.width, bounds.origin.y, bounds.origin.y + bounds.size.height, -1, 1);
				
		GLfloat coords[] = 
		{
			0.0,	0.0,
			_width,	0.0,
			_width,	_height,
			0.0,	_height
		};
		
		glEnableClientState( GL_TEXTURE_COORD_ARRAY );
		glTexCoordPointer(2, GL_FLOAT, 0, coords );
		glEnableClientState(GL_VERTEX_ARRAY);
		glVertexPointer(2, GL_FLOAT, 0, coords );
		glDrawArrays( GL_TRIANGLE_FAN, 0, 4 );
		glDisableClientState( GL_TEXTURE_COORD_ARRAY );
		glDisableClientState(GL_VERTEX_ARRAY);
		
		glPopMatrix();
	}
	else
	{
		result = NO;
	}

	glDeleteTextures(1, &captureTexture);
	glPopClientAttrib();
	glPopAttrib();
	return result;
}

@end
