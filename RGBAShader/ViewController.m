//
//  ViewController.m
//  RGBAShader
//
//  Created by Moses DeJong on 7/31/13.
//  This software has been placed in the public domain.
//
// This view controller shows how to render a large texture image using an 8 bit table
// lookup to find the color of each pixel. The initial input is a grayscale image where
// the gray level is used to determine how much of a speciifc color should be added.
// These gray values are then used to construct a color table that is looked up in the
// fragment shader. The table contains 256 full color values indexed by an 8 bit number.
// A large texture that contains all the table indexes is initially uploaded, but then
// to cycle colors in the image we only need to cycle the colors in the color table.
// The result is that each time the color changed, a new 256 entry set of color table
// values is uploaded. The downside to this example is slow startup time since the
// color table must be constructed by scanning all the pixels of the very large texture.
// The grayscale texture is the max size supported on the hardware.
//
// On an iPad2 and iPhone4 this code runs at 60 FPS with only about 10% CPU usage for a max size texture

#import "ViewController.h"

#import <AVFoundation/AVUtilities.h>

#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

#define BUFFER_OFFSET(i) ((char *)NULL + (i))

// Attribute index.
enum
{
	ATTRIB_VERTEX,
	ATTRIB_TEXCOORD,
	NUM_ATTRIBUTES
};

// Uniform index.
enum
{
	UNIFORM_INDEXES,
	UNIFORM_LUT,
	UNIFORM_LUTSCALE,
	UNIFORM_LUTHALFPIXOFF,
	NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// class ViewController

@interface ViewController () {
  GLuint _program;
  float _rotation;
  
  float _curRed;
  
  NSData *_indexesData;
  CGSize _indexesSize;
  NSData *_lutData;
  NSData *_grayscaleLutData;
  
  GLuint quadVBO;
  GLuint quadVBOIndexes;
  GLuint textureVBO;
  
  GLuint _activeLutTexture;
  GLuint _activeIndexesTexture;
  
  BOOL _increasing;
  BOOL _hasRedExt;
  BOOL _hasRectExt;
  BOOL _hasClientStorageExt;
}

@property (nonatomic, strong) EAGLContext *context;

@property (nonatomic, retain) NSData *indexesData;
@property (nonatomic, retain) NSData *lutData;
@property (nonatomic, retain) NSData *grayscaleLutData;

@end

@implementation ViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  
  self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
  
  if (!self.context) {
    NSLog(@"Failed to create ES context");
  }
  
  GLKView *view = (GLKView *)self.view;
  view.context = self.context;
  
  _increasing = YES;
  _curRed = 0.0;
  
  quadVBO = 0;
  quadVBOIndexes = 0;
  textureVBO = 0;
  
  _activeLutTexture = 0;
  _activeIndexesTexture = 0;
  
  _indexesSize = CGSizeZero;
  
  self.preferredFramesPerSecond = 60;
  
  [self setupGL];
  
  [self loadPalette];
}

- (void)dealloc
{    
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (void)setupGL
{
  [EAGLContext setCurrentContext:self.context];
  
  _hasRedExt = [self.class checkForExtension:@"GL_EXT_texture_rg"];
    
  [self loadShaders];
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
  
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
  
  glDeleteBuffers(1, &quadVBO);
  glDeleteBuffers(1, &quadVBOIndexes);
  glDeleteBuffers(1, &textureVBO);
  
  if (self->_activeLutTexture > 0) {
    GLuint texName = self->_activeLutTexture;
    self->_activeLutTexture = 0;
    glDeleteTextures(1, &texName);
  }
  if (self->_activeIndexesTexture > 0) {
    GLuint texName = self->_activeIndexesTexture;
    self->_activeIndexesTexture = 0;
    glDeleteTextures(1, &texName);
  }
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
  if (_increasing) {
    _curRed += 0.1 * self.timeSinceLastUpdate;
  } else {
    _curRed -= 0.1 * self.timeSinceLastUpdate;
  }
  if (_curRed >= 1.0) {
    _curRed = 1.0;
    _increasing = NO;
  }
  if (_curRed <= 0.0) {
    _curRed = 0.0;
    _increasing = YES;
  }
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
  //NSLog(@"draw");
  
//  glClearColor(0.0, 0.0, 0.0, 1.0);
//  glClear(GL_COLOR_BUFFER_BIT);
  
  _rotation += 1.0f;
  if (_rotation > 255.0) {
    _rotation = 0;
  }
  
  if (1) {
    float percentDoneNormalized = _rotation/255.0f;
    float howBlue;
    float howGreen;
    
    if (percentDoneNormalized <= 0.5f) {
      // 0.0 -> 0.5 : blue to darker blue : 1.0 -> 0.5
      howBlue = 1.0 - percentDoneNormalized;
      howGreen = 0.0f;
    } else if (percentDoneNormalized <= 0.75f) {
      // 0.5 -> 0.75 : green from 0.0 -> 1.0
      howBlue = percentDoneNormalized;
      float amountFromBase = (percentDoneNormalized - 0.5f);
      howGreen = (amountFromBase * 4.0);
    } else {
      // 0.75 -> 1.0 : green from 1.0 -> 0.0
      howBlue = percentDoneNormalized;
      float amountFromBase = (percentDoneNormalized - 0.75f);
      howGreen = 1.0 - (amountFromBase * 4.0);
    }
    
    //NSLog(@"rotation %0.4f, percent %0.4f -> howBlue %0.4f , howGreen %0.4f", _rotation, percentDoneNormalized, howBlue, howGreen);
    //howBlue = 1.0f;
    //howBlue = 0.5f;
    [self makePalette:howBlue howGreenNormalized:howGreen];
  }
  
  uint32_t *pixel_lut = (uint32_t*)self.lutData.bytes;
  uint32_t pixel_lut_num = self.lutData.length / sizeof(uint32_t);
  
  uint32_t width  = _indexesSize.width;
  uint32_t height = _indexesSize.height;
  CGRect presentationRect = CGRectMake(0, 0, width, height);

  // Update table texture, only need to upload main texture the first time
  
  if (self->_activeIndexesTexture == 0) {
    uint8_t *indexesPtr = (uint8_t*)self.indexesData.bytes;
    [self makeOrUpdateIndexesTexture:indexesPtr width:width height:height];
    
    // Once the texture containing index values has been pased to OpenGL, the large (20 meg at 4096)
    // buffer can be deallocated. OpenGL will maintain a copy of this 20 meg buffer inside a texture
    // mapped memory segment, but it will not count against normal app memory.
    
    self.indexesData = nil;
  }
  
  [self makeOrUpdateLutTexture:pixel_lut numLutEntries:pixel_lut_num];
  
  // FIXME: an optimization here could be to always use a 256 entry palette, so that the normalized
  // coords for the RED byte directly map to the same coordinates for the lut. Currently, additional
  // mults are needed to adjust to the lut size, but that might be slower as opposed to just filling
  // the lut table with zero valuse and then not accessing them.
  
  // (255.0 * (1.0 - 1.0/7.0) / (7.0 - 1.0));
  
  float lutScale = (255.0 * (1.0 - 1.0/pixel_lut_num)) / (pixel_lut_num - 1.0);
  float lutHalfPixelOffset = 1.0 / (2.0 * pixel_lut_num);
  
  // done with texture setup
  
  CGRect bounds = self.view.bounds;
    
  // Must call glUseProgram() before attaching uniform properties
  
  glUseProgram(_program);
  
	glUniform1i(uniforms[UNIFORM_INDEXES], 0);
	glUniform1i(uniforms[UNIFORM_LUT], 1);
	glUniform1f(uniforms[UNIFORM_LUTSCALE], lutScale);
	glUniform1f(uniforms[UNIFORM_LUTHALFPIXOFF], lutHalfPixelOffset);

  // http://duriansoftware.com/joe/An-intro-to-modern-OpenGL.-Chapter-2.1:-Buffers-and-Textures.html
  
  // Set up the quad vertices with respect to the orientation and aspect ratio of the video.
	CGRect vertexSamplingRect = AVMakeRectWithAspectRatioInsideRect(presentationRect.size, bounds);
	
	// Compute normalized quad coordinates to draw the frame into.
	CGSize normalizedSamplingSize = CGSizeMake(0.0, 0.0);
	CGSize cropScaleAmount = CGSizeMake(vertexSamplingRect.size.width/bounds.size.width, vertexSamplingRect.size.height/bounds.size.height);
	
	// Normalize the quad vertices.
	if (cropScaleAmount.width > cropScaleAmount.height) {
		normalizedSamplingSize.width = 1.0;
		normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
	}
	else {
		normalizedSamplingSize.width = 1.0;
		normalizedSamplingSize.height = cropScaleAmount.width/cropScaleAmount.height;
	}
	
  // The quad vertex data defines the region of 2D plane onto which we draw our pixel buffers.
  // Vertex data formed using (-1,-1) and (1,1) as the bottom left and top right coordinates respectively.
  // covers the entire screen.
  
	GLfloat quadVertexData[] = {
		-1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
    normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
		-1 * normalizedSamplingSize.width, normalizedSamplingSize.height,
    normalizedSamplingSize.width, normalizedSamplingSize.height,
	};
  
  static const GLushort quadVertexDataIndexes[] = { 0, 1, 2, 3 };
	
  if (quadVBO == 0) {
    glGenBuffers(1, &quadVBO);
    glBindBuffer(GL_ARRAY_BUFFER, quadVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quadVertexData), &quadVertexData[0], GL_STATIC_DRAW);
    //glEnableClientState(GL_VERTEX_ARRAY);
  }
  
  if (quadVBOIndexes == 0) {
    glGenBuffers(1, &quadVBOIndexes);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, quadVBOIndexes);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(quadVertexDataIndexes), &quadVertexDataIndexes[0], GL_STATIC_DRAW);
  }
  
  // Bind vertex coordinates buffer, connect shader to already allocated vertex buffer
  
  glBindBuffer(GL_ARRAY_BUFFER, quadVBO);
  //glEnableClientState(GL_VERTEX_ARRAY);
  glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 0, BUFFER_OFFSET(0));
  glEnableVertexAttribArray(ATTRIB_VERTEX);
  
  // Bind vertex coordinate indexes
  
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, quadVBOIndexes);
  
  // The texture vertices are set up such that we flip the texture vertically.
  // This is so that our top left origin buffers match OpenGL's bottom left texture coordinate system.
  
	CGRect textureSamplingRect = CGRectMake(0.0f, 0.0f, 1.0f, 1.0f);
	GLfloat quadTextureData[] =  {
		CGRectGetMinX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
		CGRectGetMaxX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
		CGRectGetMinX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
		CGRectGetMaxX(textureSamplingRect), CGRectGetMinY(textureSamplingRect)
	};
  
  if (textureVBO == 0) {
    glGenBuffers(1, &textureVBO);
    glBindBuffer(GL_ARRAY_BUFFER, textureVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(quadTextureData), &quadTextureData[0], GL_STATIC_DRAW);
    //glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  }

  // Connection from shader program to VBO buffer must be made on each render,
  // but the data itself does not need to be loaded into the buffer on each render.
  
  glBindBuffer(GL_ARRAY_BUFFER, textureVBO);
  //glEnableClientState(GL_TEXTURE_COORD_ARRAY);
  glVertexAttribPointer(ATTRIB_TEXCOORD, 2, GL_FLOAT, GL_FALSE, 0, BUFFER_OFFSET(0));
	glEnableVertexAttribArray(ATTRIB_TEXCOORD);
  
  glDrawElements(GL_TRIANGLE_STRIP, 4, GL_UNSIGNED_SHORT, BUFFER_OFFSET(0));
  return;
}
                    
- (void) makeOrUpdateIndexesTexture:(uint8_t*)indexesPtr
                              width:(uint32_t)width
                             height:(uint32_t)height
{
  if (self->_activeIndexesTexture != 0) {
    // Upload data to existing texture
    
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, self->_activeIndexesTexture);

    // If the grayscale texture upload is disabled, CPU usage goes from 20% to 10%
    // not a practical concern when image data is already in memory, the GPU seems
    // to just map the memory anyway so it is not clear that this is doing a copy.
    
    if (_hasRedExt) {
      // GL_RED_EXT depends on EXT_texture_rg extension, supported on iPAd2 but not iPhone 4
      
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_RED_EXT, GL_UNSIGNED_BYTE, indexesPtr);
    } else {
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_LUMINANCE, GL_UNSIGNED_BYTE, indexesPtr);
    }
    
    return;
  }
  
  // Generate texture for the indexes into the lookup table
  
  GLuint texIndexesName;
  glGenTextures(1, &texIndexesName);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, texIndexesName);
  
  // Set texture parameters for "indexes" texture
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); // not GL_LINEAR
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); // not GL_LINEAR
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  
  if (_hasRedExt) {
    // GL_RED_EXT depends on EXT_texture_rg extension, supported on iPad 2 but not iPhone 4
    
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED_EXT, width, height, 0, GL_RED_EXT, GL_UNSIGNED_BYTE, indexesPtr);
  } else {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, width, height, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, indexesPtr);
  }

  self->_activeIndexesTexture = texIndexesName;
}

- (void) makeOrUpdateLutTexture:(uint32_t*)lutPtr
                  numLutEntries:(uint32_t)pixel_lut_num
{
  if (self->_activeLutTexture != 0) {
    // Upload data to existing texture
    
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, self->_activeLutTexture);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, pixel_lut_num, 1, GL_BGRA_EXT, GL_UNSIGNED_BYTE, lutPtr);
    
    return;
  }
  
  // Generate 2D texture for the lut, no glTexImage1D() on iOS
  
  GLuint texLutName;
  glGenTextures(1, &texLutName);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, texLutName);
  
  // Set texture parameters for lut texture
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST); // not GL_LINEAR
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST); // not GL_LINEAR
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, pixel_lut_num, 1, 0, GL_BGRA_EXT, GL_UNSIGNED_BYTE, lutPtr);
  
  self->_activeLutTexture = texLutName;
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    _program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(_program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(_program, fragShader);
    
    // Bind attribute offset to name.
    // This needs to be done prior to linking.
    glBindAttribLocation(_program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(_program, ATTRIB_TEXCOORD, "textureCoordinate");
  
    // Link program.
    if (![self linkProgram:_program]) {
        NSLog(@"Failed to link program: %d", _program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }
        
        return NO;
    }

  // Link textures to named textures variables in the shader program
	uniforms[UNIFORM_INDEXES] = glGetUniformLocation(_program, "indexes");
	uniforms[UNIFORM_LUT] = glGetUniformLocation(_program, "lut");
	uniforms[UNIFORM_LUTSCALE] = glGetUniformLocation(_program, "lutScale");
	uniforms[UNIFORM_LUTHALFPIXOFF] = glGetUniformLocation(_program, "lutHalfPixelOffset");
  
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }
  
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

+ (BOOL) checkForExtension:(NSString*)name
{
  // For performance, the array can be created once and cached. Must be invoked after GL has been set as context
  
  char *cStr = (char *)glGetString(GL_EXTENSIONS);
  
  NSString *extensionsString = [NSString stringWithCString:cStr encoding:NSASCIIStringEncoding];
  
  NSArray *extensionsNames = [extensionsString componentsSeparatedByString:@" "];
  
  BOOL hasExtension = [extensionsNames containsObject:name];
  if (hasExtension) {
    return TRUE;
  } else {
    return FALSE;
  }
}

// Given an image, query the BGRA format pixels (native endian).
// Note that for a large image, the returned buffer will be massive
// (it is 64 megs at 4096 x 4096) so it is critial that the app
// deallocate this huge memory allocation when finished with it.

+ (uint32_t*) imageToBGRAData:(UIImage*)img
                    sizePtr:(CGSize*)sizePtr
{
  // Create the bitmap context
  
  size_t w = CGImageGetWidth(img.CGImage);
  size_t h = CGImageGetHeight(img.CGImage);
  
  CGSize size = CGSizeMake(w, h);
  
  CGContextRef context = [self createBGRABitmapContextWithSize:size data:NULL];
  if (context == NULL) {
    return nil;
  }
  
  CGRect rect = {{0,0},{w,h}};
  *sizePtr = CGSizeMake(w, h);
  
  // Draw the image to the bitmap context. Once we draw, the memory
  // allocated for the context for rendering will then contain the
  // raw image data in the specified color space.
  CGContextDrawImage(context, rect, img.CGImage);
  
  // Now we can get a pointer to the image data associated with the bitmap
  // context.

  uint32_t *pixels = NULL;
  void *data = CGBitmapContextGetData(context);
  if (data != NULL)
  {
    pixels = malloc(w*h*sizeof(uint32_t));
    assert(pixels);
    memcpy(pixels, data, w*h*sizeof(uint32_t));
  }
  
  CGContextRelease(context);
  
  return pixels;
}

+ (CGContextRef) createBGRABitmapContextWithSize:(CGSize)inSize
                                            data:(uint32_t*)data
{
  CGContextRef    context = NULL;
  CGColorSpaceRef colorSpace;
  int             bitmapByteCount;
  int             bitmapBytesPerRow;
  
  size_t pixelsWide = inSize.width;
  size_t pixelsHigh = inSize.height;
  
  // Declare the number of bytes per row. Each pixel in the bitmap in this
  // example is represented by 4 bytes; 8 bits each of red, green, blue, and
  // alpha.
  bitmapBytesPerRow   = (pixelsWide * sizeof(uint32_t));
  bitmapByteCount     = (bitmapBytesPerRow * pixelsHigh);
  
  // Use the generic RGB color space.
  colorSpace = CGColorSpaceCreateDeviceRGB();
  if (colorSpace == NULL)
  {
    fprintf(stderr, "Error allocating color space\n");
    return NULL;
  }
  
  size_t bitsPerComponent = 8;
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst;
  
  context = CGBitmapContextCreate (data,
                                   pixelsWide,
                                   pixelsHigh,
                                   bitsPerComponent,
                                   bitmapBytesPerRow,
                                   colorSpace,
                                   bitmapInfo);
  if (context == NULL)
  {
    fprintf (stderr, "Context not created!");
  }
  
  // Make sure and release colorspace before returning
  CGColorSpaceRelease(colorSpace);
  
  return context;
}

- (void) loadPalette
{
  // Load Smiley face image from data attached to the project and generate
  // a palette that contains the image data

  NSString *resFilename;
  
  //resFilename = @"SmileyFace8bit";
  //resFilename = @"SmileyFace8bitGray";
  
  // 60 FPS on iPhone 4
  //resFilename = @"SmileyFace8bitGray_512";
  
  // 60 FPS on iphone 4
  //resFilename = @"SmileyFace8bitGray_1024";

  // 60 FPS on iphone 4
  //resFilename = @"SmileyFace8bitGray_2048";
  
  // Does not seem to be working on iPhone4, over max limit?
  // Runs at about 27 FPS on an iPad2 with 2 texture uploads
  //resFilename = @"SmileyFace8bitGray_4096";
  
  // Choose the largest size supported by the hardware
  
  int maxTextureSize = 0;
  glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTextureSize);
  
  if (maxTextureSize == 4096) {
    resFilename = @"SmileyFace8bitGray_4096";
  } else {
    resFilename = @"SmileyFace8bitGray_2048";
  }
  
  UIImage *textureImage = [UIImage imageNamed:resFilename];
  NSAssert(textureImage, @"could not load image %@", resFilename);
  
  if (0) {
    NSString *filename = [NSString stringWithFormat:@"TabledSmileyIn.png"];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    NSData *data = [NSData dataWithData:UIImagePNGRepresentation(textureImage)];
    [data writeToFile:path atomically:YES];
    
    NSLog(@"wrote IN image %@", path);
  }

  CGSize size;
  
  size = textureImage.size;
  _indexesSize = size;

  NSLog(@"loading texture with dimensions %d x %d", (int)size.width, (int)size.height);
    
  if (size.width > maxTextureSize || size.height > maxTextureSize) {
    NSAssert(FALSE, @"maxTextureSize of %d exceeded, cannot load texture with dimensions %d x %d", maxTextureSize, (int)size.width, (int)size.height);
  }

  CGSize sizeArg;
  uint32_t *pixels = [self.class imageToBGRAData:textureImage sizePtr:&sizeArg];
  
  // Create "map" for every pixel value found in the image
  
  NSMutableDictionary *table = [NSMutableDictionary dictionary];
  
  uint32_t prev = 0x0;
  
  if (pixels[0] == 0x0) {
    // Watch for goofy special case of all pixels being 0x0 and getting ignored
    prev = 0xFFFFFFFF;
  }
  
  // Opt this table iteration to process a row at a time, so that the autorelease
  // pool can run once after each row.

  for (int i = 0, row=0; row < size.height; row++) @autoreleasepool {
    for (int col=0; col < size.width; col++) {
      uint32_t pixel = pixels[i];
      if (pixel == prev) {
        // This pixel value is exactly the same as the previous one, so it is safe to
        // ignore this pixel without accessing the table, since the previous loop
        // would have created a zero entry for the pixel.
        
        i++;
        continue;
      }
      
      NSNumber *pixelNum = [NSNumber numberWithUnsignedInt:pixel];
      
      if ([table objectForKey:pixelNum] == nil) {
        // set value to zero for now, will be updated with table index later
        [table setObject:[NSNumber numberWithInt:0] forKey:pixelNum];
      }
      
      prev = pixel;
      i++;
    }
  }
  
  // Table must contain <= 256 entries
  NSAssert(table.count <= 256, @"palette would be larger than 256 entries at size %d", table.count);
  
  NSArray *allKeys = [table allKeys];
  NSAssert(allKeys, @"must be at least 1 pixel in table");
  
  // Sort the keys in the table in terms of ascending pixel value, black first, white last
  
  NSArray *sortedPixels = [allKeys sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
    NSNumber *first = (NSNumber*)a;
    NSNumber *second = (NSNumber*)b;
    return [first compare:second];
  }];

  // Write sorted array of pixels as lut table and indexes

  NSMutableData *mLutData = [NSMutableData data];
  NSMutableData *mIndexesData = [NSMutableData dataWithCapacity:size.width * size.height * sizeof(uint8_t)];
  
  [mLutData setLength:table.count*sizeof(uint32_t)];
  [mIndexesData setLength:size.width * size.height * sizeof(uint8_t)];

  uint32_t *mLutDataPtr = (uint32_t*)mLutData.bytes;
  uint8_t *mIndexesDataPtr = (uint8_t*)mIndexesData.bytes;
  
  int index = 0;
  for (NSNumber *num in sortedPixels) @autoreleasepool {
    uint32_t pixel = [num unsignedIntValue];
    mLutDataPtr[index] = pixel;
    
    // Reset the index value for the specifix pixel in the table, this
    // will be used to lookup the lut index for each pixel in the
    // next loop.
    
    assert(index <= 256);
    
    [table setObject:[NSNumber numberWithInt:index] forKey:num];
    
    index++;
  }
  
  // Iterate over each pixel again and lookup the lut index for each pixel. Note that
  // this loop has a really huge number of iterations, so optimize by not doing the
  // same work over for the next pixel.

  prev = 0x0;
  uint32_t prev_index = 0;;
  
  if (pixels[0] == 0x0) {
    // Watch for goofy special case of all pixels being 0x0 and getting ignored
    prev = 0xFFFFFFFF;
  }
  
  for (int i = 0, row=0; row < size.height; row++) @autoreleasepool {
    for (int col=0; col < size.width; col++) {
      uint32_t pixel = pixels[i];
      
      if (pixel == prev) {
        // This pixel is the same as the previous pixel and the table
        // index lookup was just done in the last loop.
        
        mIndexesDataPtr[i] = prev_index;
        
        i++;
        continue;
      }
      
      NSNumber *pixelNum = [NSNumber numberWithUnsignedInt:pixel];
      
      // get table index for this specific pixel
      
      prev_index = [[table objectForKey:pixelNum] intValue];
      
      mIndexesDataPtr[i] = prev_index;
      
      prev = pixel;
      i++;
    }
  }

  free(pixels);
  
  self.lutData = [NSData dataWithData:mLutData];
  self.grayscaleLutData = self.lutData;
  self.indexesData = [NSData dataWithData:mIndexesData];
  
  // Color adjust the values in the color table. This is basically a "multiply" type
  // effect except that the code needs to operate directly on the color table values
  // as opposed to the colors in an image.
  
  [self makePalette:1.0 howGreenNormalized:0.0];
  
  NSLog(@"done with texture prep");
  
  return;
}

// Recolor the palette, adjusts the amount of "blue" color inserted into the grayscale
// image. This logic implements a very cheap "colorizer" like a multiply effect, except
// that it does not color in the white background. The impl is still a little blocky
// but it renders very quickly on the GPU.

- (void) makePalette:(float)howBlueNormalized
  howGreenNormalized:(float)howGreenNormalized
{
  // Color adjust the values in the color table. This is basically a "multiply" type
  // effect except that the code needs to operate directly on the color table values
  // as opposed to the colors in an image.
  
  uint32_t color = (uint32_t) round(0xFF * howBlueNormalized);
  
  if (1) {
    NSMutableData *mColoredLut = [NSMutableData dataWithData:self.grayscaleLutData];
    
    int numColorTableEntries = mColoredLut.length / sizeof(uint32_t);
    
    uint32_t *coloredLutDataPtr = (uint32_t *)mColoredLut.bytes;
    
    for (int i=0; i < numColorTableEntries; i++) @autoreleasepool {
      uint32_t pixel = coloredLutDataPtr[i];
      
      // The input image uses "white" as the very last element in the
      // color table. Use this knowledge to implement a special case
      // where the last table entry remains white while all the other
      // table entries take on a specific color. This is basically a
      // a mask operation using the color table. The edges are jaggy
      // with this logic, but it is not a big deal.
      
      if (i == (numColorTableEntries - 1)) {
        continue;
      }
      
      // Each pixel value is a grayscale percentage indicating how much
      // of the "color" value the image should take on. A pixel very
      // close to black takes on a very small amount of color while
      // a white pixel would take on the full color value.
      
      uint32_t val = pixel & 0xFF;
      float normalized;
      if (val == 0) {
        normalized = 0.0f;
      } else {
        normalized = val / 255.0f;
      }
      uint32_t resultAmount = (uint32_t) round(color * normalized);
      
      uint32_t alpha = 0xFF;
      uint32_t red = 0x0;
      uint32_t green = 0x0;
      uint32_t blue = resultAmount;
      
      if (howGreenNormalized > 0.0f) {
        green = resultAmount;
      }
      
      pixel = (alpha << 24) | (red << 16) | (green << 8) | (blue);
      
      //NSLog(@"lut[%d] RGB = [%d, %d, %d]", i, red, green, blue);
      
      coloredLutDataPtr[i] = pixel;
    }
    
    // Write the result to self.grayscaleLutData
    
    self.lutData = [NSData dataWithData:mColoredLut];
  }
  
  return;
}

// iOS 5.X compat

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
  if ((interfaceOrientation == UIInterfaceOrientationLandscapeLeft) ||
      (interfaceOrientation == UIInterfaceOrientationLandscapeRight)) {
    return YES;
  } else {
    return NO;
  }
}

@end
