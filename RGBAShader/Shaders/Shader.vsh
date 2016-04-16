//
//  Shader.vsh
//  RGBAShader
//
//  Created by Moses DeJong on 7/31/13.
//  This software has been placed in the public domain.
//

attribute vec4 position;
attribute mediump vec4 textureCoordinate;
varying mediump vec2 coordinate;

void main()
{
	gl_Position = position;
	coordinate = textureCoordinate.xy;
}
