<?xml version="1.0" encoding="UTF-8"?>
<!--
	SABR v3.0 Shader

	Optimized Joshua Street's SABR v3.0 shader for lowp precision, branchless execution,
	reorderred calculations during texture read.
	Targetting GBA upscale on Nexus 4.

	This program is free software; you can redistribute it and/or
	modify it under the terms of the GNU General Public License
	as published by the Free Software Foundation; either version 2
	of the License, or (at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software
	Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
-->

<shader language="GLSL">
<vertex><![CDATA[
#version 300 es

in vec2 aPosition;
in vec2 aTexCoord;
out vec2 vTexCoord;

void main()
{
	gl_Position = vec4(aPosition, 0.0, 1.0);
	vTexCoord = aTexCoord;
}
]]></vertex>

<fragment filter="nearest" output_width="400%" output_height="400%"><![CDATA[
#version 300 es

#define TEXCOORD_PRECISION mediump
precision lowp float;

#define SCALE 4.0

/*
	Inequation coefficients for interpolation
		Equations are in the form: Ay + Bx = C
		45, 30, and 60 denote the angle from x each line the cooeficient variable set builds
*/
const vec4 Ai  = vec4( 0.5 , -0.5 , -0.5 ,  0.5 );
const vec4 B45 = vec4( 0.5 ,  0.5 , -0.5 , -0.5 );
const vec4 C45 = vec4( 0.75,  0.25, -0.25,  0.25);
const vec4 B30 = vec4( 0.25,  1.0 , -0.25, -1.0 );
const vec4 C30 = vec4( 0.5 ,  0.5 , -0.25,  0.0 );
const vec4 B60 = vec4( 1.0 ,  0.25, -1.0 , -0.25);
const vec4 C60 = vec4( 1.0 ,  0.0 , -0.5 ,  0.25);

const vec4 M45 = vec4(1.0 / SCALE);
const vec4 M30 = vec4(0.5 / SCALE, 1.0 / SCALE, 0.5 / SCALE, 1.0 / SCALE);
const vec4 M60 = M30.yxwz;
const vec4 Mshift = vec4(0.5 / SCALE);

// Coefficient for weighted edge detection
const vec4 coef = vec4(0.5);

const vec4 threshold = vec4(0.3125);

// Conversion from RGB to Luminance (from BT.709)
const vec3 lum = vec3(0.2126, 0.7152, 0.0722);

vec4 _not_(vec4 A)
{
	return vec4(1.0) - A;
}

vec4 _and_(vec4 A, vec4 B)
{
	return A * B;
}

vec4 _or_(vec4 A, vec4 B)
{
	return max(A, B);
}

vec4 _ne_(vec4 A, vec4 B)
{
	return abs(sign(A - B));
}

vec4 _lte_(vec4 A, vec4 B)
{
	return step(A, B);
}

vec4 _gte_(vec4 A, vec4 B)
{
	return _lte_(B, A);
}

vec4 _lt_(vec4 A, vec4 B)
{
	return _not_(_gte_(A, B));
}

// Converts 4 3-color vectors into 1 4-value luminance vector
vec4 lum_to(vec3 v0, vec3 v1, vec3 v2, vec3 v3) {
	return vec4(dot(lum, v0), dot(lum, v1), dot(lum, v2), dot(lum, v3));
}

// Gets the difference between 2 4-value luminance vectors
vec4 lum_df(vec4 A, vec4 B) {
	return abs(A - B);
}

// Determines if 2 4-value luminance vectors are "equal" based on threshold
vec4 lum_eq(vec4 A, vec4 B) {
	return _lt_(lum_df(A, B), threshold);
}

vec4 lum_wd(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e, vec4 f, vec4 g, vec4 h) {
	return 0.125 * lum_df(a, b) + 0.125 * lum_df(a, c) + 0.125 * lum_df(d, e) + 0.125 * lum_df(d, f) + 0.5 * lum_df(g, h);
}

// Gets the difference between 2 3-value rgb colors
float c_df(vec3 c1, vec3 c2) {
	return dot(vec3(1.0/3.0), abs(c1 - c2));
}

uniform sampler2D rubyTexture;
uniform TEXCOORD_PRECISION vec2 rubyTextureSize;
in TEXCOORD_PRECISION vec2 vTexCoord;
out vec4 fragmentColour;

void main()
{
	/*
		Mask for algorithm
		+-----+-----+-----+-----+-----+
		|     |  1  |  2  |  3  |     |
		+-----+-----+-----+-----+-----+
		|  5  |  6  |  7  |  8  |  9  |
		+-----+-----+-----+-----+-----+
		| 10  | 11  | 12  | 13  | 14  |
		+-----+-----+-----+-----+-----+
		| 15  | 16  | 17  | 18  | 19  |
		+-----+-----+-----+-----+-----+
		|     | 21  | 22  | 23  |     |
		+-----+-----+-----+-----+-----+
	*/
	// Store mask values
	vec3 P1  = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2(-1,-2)).rgb;
	vec3 P2  = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 0,-2)).rgb;
	vec3 P3  = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 1,-2)).rgb;

	vec3 P6  = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2(-1,-1)).rgb;
	vec3 P7  = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 0,-1)).rgb;
	vec3 P8  = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 1,-1)).rgb;

	vec3 P11 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2(-1, 0)).rgb;
	vec3 P12 = textureLod(rubyTexture, vTexCoord, 0.0).rgb;
	vec3 P13 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 1, 0)).rgb;

	vec3 P16 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2(-1, 1)).rgb;
	vec3 P17 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 0, 1)).rgb;
	vec3 P18 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 1, 1)).rgb;

	vec3 P21 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2(-1, 2)).rgb;
	vec3 P22 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 0, 2)).rgb;
	vec3 P23 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 1, 2)).rgb;

	vec3 P5  = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2(-2,-1)).rgb;
	vec3 P10 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2(-2, 0)).rgb;
	vec3 P15 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2(-2, 1)).rgb;

	vec3 P9  = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 2,-1)).rgb;
	vec3 P14 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 2, 0)).rgb;
	vec3 P19 = textureLodOffset(rubyTexture, vTexCoord, 0.0, ivec2( 2, 1)).rgb;

	// Scale current texel coordinate to [0..1]
	vec2 fp = fract(vTexCoord * rubyTextureSize);

	// Determine amount of "smoothing" or mixing that could be done on texel corners
	vec4 ma45 = smoothstep(C45 - M45, C45 + M45, Ai * fp.y + B45 * fp.x);
	vec4 ma30 = smoothstep(C30 - M30, C30 + M30, Ai * fp.y + B30 * fp.x);
	vec4 ma60 = smoothstep(C60 - M60, C60 + M60, Ai * fp.y + B60 * fp.x);
	vec4 marn = smoothstep(C45 - M45 + Mshift, C45 + M45 + Mshift, Ai * fp.y + B45 * fp.x);

	// Store luminance values of each point in groups of 4
	// so that we may operate on all four corners at once
	vec4 p7  = lum_to(P7,  P11, P17, P13);
	vec4 p8  = lum_to(P8,  P6,  P16, P18);
	vec4 p11 = p7.yzwx;					  // P11, P17, P13, P7
	vec4 p12 = lum_to(P12, P12, P12, P12);
	vec4 p13 = p7.wxyz;					  // P13, P7,  P11, P17
	vec4 p14 = lum_to(P14, P2,  P10, P22);
	vec4 p16 = p8.zwxy;					  // P16, P18, P8,  P6
	vec4 p17 = p7.zwxy;					  // P11, P17, P13, P7
	vec4 p18 = p8.wxyz;					  // P18, P8,  P6,  P16
	vec4 p19 = lum_to(P19, P3,  P5,  P21);
	vec4 p22 = p14.wxyz;					 // P22, P14, P2,  P10
	vec4 p23 = lum_to(P23, P9,  P1,  P15);

	// Perform edge weight calculations
	vec4 e45   = lum_wd(p12, p8, p16, p18, p22, p14, p17, p13);
	vec4 econt = lum_wd(p17, p11, p23, p13, p7, p19, p12, p18);
	vec4 e30   = lum_df(p13, p16);
	vec4 e60   = lum_df(p8, p17);

	// Calculate rule results for interpolation
	vec4 r45 = _and_(
	    _and_(_ne_(p12, p13), _ne_(p12, p17)),
	    _or_(
			_or_(
			    _and_(_not_(lum_eq(p13, p7)), _not_(lum_eq(p13, p8))),
				_and_(_not_(lum_eq(p17, p11)), _not_(lum_eq(p17, p16)))),
			_or_(
				_and_(
				    lum_eq(p12, p18),
				    _or_(
				        _and_(_not_(lum_eq(p13, p14)), _not_(lum_eq(p13, p19))),
					    _and_(_not_(lum_eq(p17, p22)), _not_(lum_eq(p17, p23))))),
			    _or_(lum_eq(p12, p16), lum_eq(p12, p8)))));
	vec4 r30 = _and_(_ne_(p12, p16), _ne_(p11, p16));
	vec4 r60 = _and_(_ne_(p12, p8), _ne_(p7, p8));

	// Combine rules with edge weights
	vec4 edr45 = _and_(_lt_(e45, econt), r45);
	vec4 edrrn = _lte_(e45, econt);
	vec4 edr30 = _and_(_lte_(e30, coef * e60), r30);
	vec4 edr60 = _and_(_lte_(e60, coef * e30), r60);

	// Finalize interpolation rules
	vec4 final45 = _and_(_and_(_not_(edr30), _not_(edr60)), edr45);
	vec4 final30 = _and_(_and_(edr45, edr30), _not_(edr60));
	vec4 final60 = _and_(_and_(edr45, edr60), _not_(edr30));
	vec4 final36 = _and_(_and_(edr45, edr30), edr60);
	vec4 finalrn = _and_(_not_(edr45), edrrn);

	// Determine the color to mix with for each corner
	vec4 px = step(lum_df(p12, p17), lum_df(p12, p13));

	// Determine the mix amounts by combining the final rule result and corresponding
	// mix amount for the rule in each corner
	vec4 mac = final36 * max(ma30, ma60) + final30 * ma30 + final60 * ma60 + final45 * ma45 + finalrn * marn;

	/*
		Calculate the resulting color by traversing clockwise and counter-clockwise around
		the corners of the texel

		Finally choose the result that has the largest difference from the texel's original
		color
	*/
	vec3 res1 = P12;
	res1 = mix(res1, mix(P13, P17, px.x), mac.x);
	res1 = mix(res1, mix(P7 , P13, px.y), mac.y);
	res1 = mix(res1, mix(P11, P7 , px.z), mac.z);
	res1 = mix(res1, mix(P17, P11, px.w), mac.w);

	vec3 res2 = P12;
	res2 = mix(res2, mix(P17, P11, px.w), mac.w);
	res2 = mix(res2, mix(P11, P7 , px.z), mac.z);
	res2 = mix(res2, mix(P7 , P13, px.y), mac.y);
	res2 = mix(res2, mix(P13, P17, px.x), mac.x);

	fragmentColour.rgb = mix(res1, res2, step(c_df(P12, res1), c_df(P12, res2)));
	fragmentColour.a = 1.0;
}
]]></fragment>
</shader>
