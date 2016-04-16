//
//  Shader.fsh
//  RGBAShader
//
//  Created by Moses DeJong on 7/31/13.
//  This software has been placed in the public domain.
//

varying highp vec2 coordinate;
// GL_TEXTURE0 = indexes
uniform sampler2D indexes;
// GL_TEXTURE1 = lut
uniform sampler2D lut;

uniform highp float lutScale;
uniform highp float lutHalfPixelOffset;

void main()
{
  highp float val = texture2D(indexes, coordinate.xy).r;
  highp float denormalized = (val * lutScale) + lutHalfPixelOffset;
  highp vec2 lookupCoord = vec2(denormalized, 0.0);
  gl_FragColor = texture2D(lut, lookupCoord);
}
