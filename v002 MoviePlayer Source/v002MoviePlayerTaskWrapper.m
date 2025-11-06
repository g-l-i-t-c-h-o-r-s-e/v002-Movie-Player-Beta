/*
 File:		TaskWrapper.m
 
 Description: 	This is the implementation of a generalized process handling class
 that that makes asynchronous interaction with an NSTask easier.
 Feel free to make use of this code in your own applications.
 TaskWrapper objects are one-shot (since NSTask is one-shot); if you need to
 run a task more than once, destroy/create new TaskWrapper objects.
 
 Author:		EP & MCF
 
 Copyright: 	© Copyright 2002 Apple Computer, Inc. All rights reserved.
 
 Disclaimer:	IMPORTANT:  This Apple software is supplied to you by Apple Computer, Inc.
 ("Apple") in consideration of your agreement to the following terms, and your
 use, installation, modification or redistribution of this Apple software
 constitutes acceptance of these terms.  If you do not agree with these terms,
 please do not use, install, modify or redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and subject
 to these terms, Apple grants you a personal, non-exclusive license, under Apple’s
 copyrights in this original Apple software (the "Apple Software"), to use,
 reproduce, modify and redistribute the Apple Software, with or without
 modifications, in source and/or binary forms; provided that if you redistribute
 the Apple Software in its entirety and without modifications, you must retain
 this notice and the following text and disclaimers in all such redistributions of
 the Apple Software.  Neither the name, trademarks, service marks or logos of
 Apple Computer, Inc. may be used to endorse or promote products derived from the
 Apple Software without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or implied,
 are granted by Apple herein, including but not limited to any patent rights that
 may be infringed by your derivative works or by other works in which the Apple
 Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE MAKES NO
 WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION THE IMPLIED
 WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
 COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
 GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
 OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY OF CONTRACT, TORT
 (INCLUDING NEGLIGENCE), STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 Version History: 1.1/1.2 released to fix a few bugs (not always removing the notification center,
 forgetting to release in some cases)
 1.3	   fixes a code error (no incorrect behavior) where we were checking for
 if (task) in the -getData: notification when task would always be true.
 Now we just do the right thing in all cases without the superfluous if check.
 */

// FIX: Pipe reader re-arm only on data (avoid EAGAIN + stray notifies)
// --------------------------------------------------------------------
// Problem:
//   The legacy Apple TaskWrapper re-armed background reads even on EOF.
//   After teardown, this can deliver NSFileHandleReadCompletionNotification
//   repeatedly with zero-length data and/or race with a final synchronous
//   drain in -stopProcess, leading to
//     *** -[NSConcreteFileHandle availableData]: Resource temporarily unavailable
//
// Change:
//   Re-arm the background read *only* when bytes > 0. On zero-length (EOF),
//   do *not* re-arm; call -stopProcess to finish cleanup.
//
// Result:
//   No more spurious notifications after EOF, and no more EAGAIN when we
//   synchronously drain during controlled shutdown on 10.14.

// FIX 2: Deterministic NSTask shutdown; no EAGAIN; idempotent
// ---------------------------------------------------------
// Goals:
//   • Stop receiving background read notifications before terminating.
//   • Let the child exit cleanly (close stdin), then wait for exit.
//   • Optionally drain remaining stdout without tripping EAGAIN.
//   • Make the method safe to call multiple times (idempotent).
//
// Steps:
//   1) Remove NSFileHandleReadCompletionNotification observer *first* so no
//      new async callbacks race in during teardown.
//   2) Close stdin to signal EOF to the child, then [task terminate] and
//      [task waitUntilExit] so pipes reach EOF predictably.
//   3) Best-effort synchronous drain of any remaining bytes inside @try,
//      swallowing EAGAIN ("Resource temporarily unavailable") that 10.14
//      pipes can throw if the fd is momentarily non-blocking.
//   4) Close remaining fds, send -processFinished:withStatus:, and nil out
//      'controller' so repeated calls become no-ops.
//
// Outcome:
//   • Eliminates "*** -[NSConcreteFileHandle availableData]: Resource temporarily
//     unavailable" on shutdown.
//   • Avoids dangling notifications after EOF.
//   • Prevents teardown races between the task and the reader.


#import "v002MoviePlayerTaskWrapper.h"


@interface v002MoviePlayerTaskWrapper (PrivateMethods)
// This method is called asynchronously when data is available from the task's file handle.
// We just pass the data along to the controller as an NSString.
- (void) getData: (NSNotification *)aNotification;
@end

@implementation v002MoviePlayerTaskWrapper

@synthesize task;

// Do basic initialization
- (id)initWithController: (id <v002MoviePlayerTaskWrapperController>)cont arguments: (NSArray *)args userInfo: (id)someInfo
{
    if ([super init]) {
		if ([args count] < 1)
		{
			[self release];
			return nil;
		}
		controller	= cont;
		arguments	= [args retain];
		userInfo	= [someInfo retain];
    }
    return self;
}

// tear things down
- (void)dealloc
{
    [self stopProcess];
	
	[userInfo release];
    [arguments release];
    [task release];
	
    [super dealloc];
}

// Here's where we actually kick off the process via an NSTask.
- (void) startProcess
{
    // We first let the controller know that we are starting
    [controller processStarted: self];
	
    task = [[NSTask alloc] init];
	
    // The output of stdin, stdout and stderr is sent to a pipe so that we can catch it later
    // and use it along to the controller
    [task setStandardInput: [NSPipe pipe]];
    [task setStandardOutput: [NSPipe pipe]];
    [task setStandardError: [task standardOutput]];
	
    // The path to the binary is the first argument that was passed in
    [task setLaunchPath: [arguments objectAtIndex:0]];
    // The rest of the task arguments are just grabbed from the array
	if ([arguments count] > 1)
	{
		[task setArguments: [arguments subarrayWithRange: NSMakeRange (1, ([arguments count] - 1))]];
	}
    // Here we register as an observer of the NSFileHandleReadCompletionNotification, which lets
    // us know when there is data waiting for us to grab it in the task's file handle (the pipe
    // to which we connected stdout and stderr above).  -getData: will be called when there
    // is data waiting.  The reason we need to do this is because if the file handle gets
    // filled up, the task will block waiting to send data and we'll never get anywhere.
    // So we have to keep reading data from the file handle as we go.
    [[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(getData:)
												 name: NSFileHandleReadCompletionNotification
											   object: [[task standardOutput] fileHandleForReading]];
    // We tell the file handle to go ahead and read in the background asynchronously, and notify
    // us via the callback registered above when we signed up as an observer.  The file handle will
    // send a NSFileHandleReadCompletionNotification when it has data that is available.
    [[[task standardOutput] fileHandleForReading] readInBackgroundAndNotify];
	
    // launch the task asynchronously
    [task launch];   
}

// If the task ends, there is no more data coming through the file handle even when the notification is
// sent, or the process object is released, then this method is called.
- (void) stopProcess
{
    // Stop if we already notified the controller
    if (!controller) return;
    
    NSFileHandle *outRead = [[task standardOutput] fileHandleForReading];
    NSFileHandle *inWrite = [[task standardInput]  fileHandleForWriting];
    
    // Stop notifications first
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSFileHandleReadCompletionNotification
                                                  object:outRead];
    
    // Close stdin so the child can exit cleanly
    @try { [inWrite closeFile]; } @catch (__unused id e) {}
    
    // Ask the task to terminate, then wait so pipes hit EOF
    @try { [task terminate]; } @catch (__unused id e) {}
    [task waitUntilExit];
    
    // Optionally drain any remaining stdout without crashing on EAGAIN
    @try {
        NSData *data = nil;
        while ((data = [outRead availableData]) && [data length]) {
            [controller appendOutput:[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]
                         fromProcess:self];
        }
    } @catch (__unused NSException *e) {
        // Ignore EAGAIN / "Resource temporarily unavailable" on 10.14 pipes
    }
    
    @try { [outRead closeFile]; } @catch (__unused id e) {}
    
    [controller processFinished:self withStatus:[task terminationStatus]];
    controller = nil;
}


- (void)sendToProcess: (NSString *)aString
{
	NSFileHandle	*outFile	= [[task standardInput] fileHandleForWriting];
	
	[outFile writeData: [aString dataUsingEncoding: NSUTF8StringEncoding]];
}

- (BOOL)isRunning
{
	return [task isRunning];
}

- (id)userInfo
{
	return userInfo;
}

@end

@implementation v002MoviePlayerTaskWrapper (PrivateMethods)

- (void) getData: (NSNotification *)aNotification
{
    NSFileHandle *fh = [aNotification object];
    NSData *data = [[aNotification userInfo] objectForKey:NSFileHandleNotificationDataItem];
    
    if ([data length] > 0) {
        [controller appendOutput:[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]
                     fromProcess:self];
        // Re-arm only when we actually received bytes.
        [fh readInBackgroundAndNotify];
    } else {
        // EOF — do NOT re-arm; finish up.
        [self stopProcess];
    }
}


@end

