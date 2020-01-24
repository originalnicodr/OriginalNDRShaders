//SunsetFog shader by originalnicodr, a modified version of Adaptive fog by Otis with some code from the SunsetFilter by Jacob Maximilian Fober, all credits goes to them

///////////////////////////////////////////////////////////////////
// Simple depth-based fog powered with bloom to fake light diffusion.
// The bloom is borrowed from SweetFX's bloom by CeeJay.
//
// As Reshade 3 lets you tweak the parameters in-game, the mouse-oriented
// feature of the v2 Adaptive Fog is no longer needed: you can select the
// fog color in the reshade settings GUI instead.
//
///////////////////////////////////////////////////////////////////
// By Otis / Infuse Project
///////////////////////////////////////////////////////////////////

/* 
SunsetFilter PS v1.0.0 (c) 2018 Jacob Maximilian Fober, 

This work is licensed under the Creative Commons 
Attribution-ShareAlike 4.0 International License. 
To view a copy of this license, visit 
http://creativecommons.org/licenses/by-sa/4.0/.
*/
// Lightly optimized by Marot Satil for the GShade project.

#include "Reshade.fxh"
#include "ReShadeUI.fxh"

uniform float3 ColorA < __UNIFORM_COLOR_FLOAT3
	ui_label = "Colour (A)";
    ui_type = "color";
	ui_category = "Colors";
> = float3(1.0, 0.0, 0.0);

uniform float3 ColorB < __UNIFORM_COLOR_FLOAT3
	ui_label = "Colour (B)";
	ui_type = "color";
	ui_category = "Colors";
> = float3(0.0, 0.0, 0.0);

uniform bool Flip <
	ui_label = "Color flip";
	ui_category = "Colors";
> = false;

uniform int BlendM <
	ui_type = "combo";
	ui_label = "Blending Mode";
	ui_tooltip = "Select the blending mode used with the gradient on the screen.";
	ui_items = "Normal \0Multiply \0Screen \0Overlay \0Darken \0Lighten \0Color Dodge \0Color Burn \0Hard Light \0Soft Light \0Difference \0Exclusion \0Hue \0Saturation \0Color \0Luminosity";
> = 0;

uniform int Axis < __UNIFORM_SLIDER_INT1
	ui_label = "Angle";
	#if __RESHADE__ < 40000
		ui_step = 1;
	#endif
	ui_min = -180; ui_max = 180;
	ui_category = "Color controls";
> = -7;

uniform float Scale < __UNIFORM_SLIDER_FLOAT1
	ui_label = "Gradient sharpness";
	ui_min = 0.5; ui_max = 1.0; ui_step = 0.005;
	ui_category = "Color controls";
> = 1.0;

uniform float Offset < __UNIFORM_SLIDER_FLOAT1
	ui_label = "Position";
	#if __RESHADE__ < 40000
		ui_step = 0.002;
	#endif
	ui_min = 0.0; ui_max = 0.5;
	ui_category = "Color controls";
> = 0.0;

uniform bool FlipFog <
	ui_label = "Fog flip";
	ui_category = "Fog controls";
> = false;

uniform float MaxFogFactor <
	ui_type = "slider";
	ui_min = 0.000; ui_max=1.000;
	ui_tooltip = "The maximum fog factor. 1.0 makes distant objects completely fogged out, a lower factor will shimmer them through the fog.";
	ui_step = 0.001;
	ui_category = "Fog controls";
> = 0.8;

uniform float FogCurve <
	ui_type = "slider";
	ui_min = 0.00; ui_max=175.00;
	ui_step = 0.01;
	ui_tooltip = "The curve how quickly distant objects get fogged. A low value will make the fog appear just slightly. A high value will make the fog kick in rather quickly. The max value in the rage makes it very hard in general to view any objects outside fog.";
	ui_category = "Fog controls";
> = 1.5;

uniform float FogStart <
	ui_type = "slider";
	ui_min = 0.000; ui_max=1.000;
	ui_step = 0.001;
	ui_tooltip = "Start of the fog. 0.0 is at the camera, 1.0 is at the horizon, 0.5 is halfway towards the horizon. Before this point no fog will appear.";
> = 0.050;

uniform float BloomThreshold <
	ui_type = "slider";
	ui_min = 0.00; ui_max=50.00;
	ui_step = 0.1;
	ui_tooltip = "Threshold for what is a bright light (that causes bloom) and what isn't.";
	ui_category = "Bloom controls";
> = 10.25;

uniform float BloomPower <
	ui_type = "slider";
	ui_min = 0.000; ui_max=100.000;
	ui_step = 0.1;
	ui_tooltip = "Strength of the bloom";
	ui_category = "Bloom controls";
> = 10.0;

uniform float BloomWidth <
	ui_type = "slider";
	ui_min = 0.0000; ui_max=1.0000;
	ui_tooltip = "Width of the bloom";
	ui_category = "Bloom controls";
> = 0.2;

// Overlay blending mode
float Overlay(float Layer)
{
	float Min = min(Layer, 0.5);
	float Max = max(Layer, 0.5);
	return 2 * (Min * Min + 2 * Max - Max * Max) - 1.5;
}

// Screen blending mode
float3 Screen(float3 LayerA, float3 LayerB)
{ return 1.0 - (1.0 - LayerA) * (1.0 - LayerB); }

// Multiply blending mode
float3 Multiply(float3 LayerA, float3 LayerB)
{ return LayerA * LayerB; }

// Darken blending mode
float3 Darken(float3 LayerA, float3 LayerB)
{ return min(LayerA,LayerB); }

// Lighten blending mode
float3 Lighten(float3 LayerA, float3 LayerB)
{ return max(LayerA,LayerB); }

// Color Dodge blending mode
float3 ColorDodge(float3 LayerA, float3 LayerB)
{ if (LayerB.r < 1 && LayerB.g < 1 && LayerB.b < 1){
	return min(1.0,LayerA/(1.0-LayerB));
	}
  else {//LayerB=1
	return 1.0;
  }
}

// Color Burn blending mode
float3 ColorBurn(float3 LayerA, float3 LayerB)
{ if (LayerB.r > 0 && LayerB.g > 0 && LayerB.b > 0){
	return 1.0-min(1.0,(1.0-LayerA)/LayerB);
	}
  else {//LayerB=0
	return 0;
  }
}

// Hard light blending mode
float3 HardLight(float3 LayerA, float3 LayerB)
{ if (LayerB.r <= 0.5 && LayerB.g <=0.5 && LayerB.b <= 0.5){
	return Multiply(LayerA,2*LayerB);
	}
  else {//LayerB>5
	return Multiply(LayerA,2*LayerB-1);
  }
}

float3 Aux(float3 x)
{
	if (x.r<=0.25 && x.g<=0.25 && x.b<=0.25) {
		return ((16.0*x-12.0)*x+4)*x;
	}
	else {
		return sqrt(x);
	}
}

// Soft light blending mode
float3 SoftLight(float3 LayerA, float3 LayerB)
{ if (LayerB.r <= 0.5 && LayerB.g <=0.5 && LayerB.b <= 0.5){
	return LayerA-(1.0-2*LayerB)*LayerA*(1-LayerA);
	}
  else {//LayerB>5
	return LayerA+(2*LayerB-1.0)*(Aux(LayerA)-LayerA);
  }
}


// Difference blending mode
float3 Difference(float3 LayerA, float3 LayerB)
{ return LayerA-LayerB; }

// Exclusion blending mode
float3 Exclusion(float3 LayerA, float3 LayerB)
{ return LayerA+LayerB-2*LayerA*LayerB; }

// Overlay blending mode
float3 OverlayM(float3 LayerA, float3 LayerB)
{ return HardLight(LayerB,LayerA); }


float Lum(float3 c){
	return (0.3*c.r+0.59*c.g+0.11*c.b);}

float min3 (float a, float b, float c){
	return min(a,(min(b,c)));
}

float max3 (float a, float b, float c){
	return max(a,(max(b,c)));
}

float Sat(float3 c){
	return max3(c.r,c.g,c.b)-min3(c.r,c.g,c.b);}

float3 ClipColor(float3 c){
	float l=Lum(c);
	float n=min3(c.r,c.g,c.b);
	float x=max3(c.r,c.g,c.b);
	float cr=c.r;
	float cg=c.g;
	float cb=c.b;
	if (n<0){
		cr=l+(((cr-l)*l)/(l-n));
		cg=l+(((cg-l)*l)/(l-n));
		cb=l+(((cb-l)*l)/(l-n));
	}
	if (x>1){
		cr=l+(((cr-l)*(1-l))/(x-l));
		cg=l+(((cg-l)*(1-l))/(x-l));
		cb=l+(((cb-l)*(1-l))/(x-l));
	}
	return float3(cr,cg,cb);
}

float3 SetLum (float3 c, float l){
	float d= l-Lum(c);
	return float3(c.r+d,c.g+d,c.b+d);
}

float3 SetSat(float3 c, float s){
	float cr=c.r;
	float cg=c.g;
	float cb=c.b;
	if (cr==max3(cr,cg,cb) && cb==min3(cr,cg,cb)){//caso r->max g->mid b->min
		if (cr>cb){
			cg=(((cg-cb)*s)/(cr-cb));
			cr=s;
		}
		else{
			cg=0;
			cr=0;
		}
		cb=0;
	}
	else{
		if (cr==max3(cr,cg,cb) && cg==min3(cr,cg,cb)){//caso r->max b->mid g->min
			if (cr>cg){
				cb=(((cb-cg)*s)/(cr-cg));
				cr=s;
			}
			else{
				cb=0;
				cr=0;
			}
			cg=0;
		}
		else{
			if (cg==max3(cr,cg,cb) && cb==min3(cr,cg,cb)){//caso g->max r->mid b->min
				if (cg>cb){
					cr=(((cr-cb)*s)/(cg-cb));
					cg=s;
				}
				else{
					cr=0;
					cg=0;
				}
				cb=0;
			}
			else{
				if (cg==max3(cr,cg,cb) && cr==min3(cr,cg,cb)){//caso g->max b->mid r->min
					if (cg>cr){
						cb=(((cb-cr)*s)/(cg-cr));
						cg=s;
					}
					else{
						cb=0;
						cg=0;
					}
					cr=0;
				}
				else{
					if (cb==max3(cr,cg,cb) && cg==min3(cr,cg,cb)){//caso b->max r->mid g->min
						if (cb>cg){
							cr=(((cr-cg)*s)/(cb-cg));
							cb=s;
						}
						else{
							cr=0;
							cb=0;
						}
						cg=0;
					}
					else{
						if (cb==max3(cr,cg,cb) && cr==min3(cr,cg,cb)){//caso b->max g->mid r->min
							if (cb>cr){
								cg=(((cg-cr)*s)/(cb-cr));
								cb=s;
							}
							else{
								cg=0;
								cb=0;
							}
							cr=0;
						}
					}
				}
			}
		}
	}
	return float3(cr,cg,cb);
}

float3 Hue(float3 b, float3 s){
	return SetLum(SetSat(s,Sat(b)),Lum(b));
}

float3 Saturation(float3 b, float3 s){
	return SetLum(SetSat(b,Sat(s)),Lum(b));
}

float3 ColorM(float3 b, float3 s){
	return SetLum(s,Lum(b));
}

float3 Luminosity(float3 b, float3 s){
	return SetLum(b,Lum(s));
}

//////////////////////////////////////
// textures
//////////////////////////////////////
texture   Otis_BloomTarget 	{ Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8;};	

//////////////////////////////////////
// samplers
//////////////////////////////////////
sampler2D Otis_BloomSampler { Texture = Otis_BloomTarget; };

// pixel shader which performs bloom, by CeeJay. 
void PS_Otis_AFG_PerformBloom(float4 position : SV_Position, float2 texcoord : TEXCOORD0, out float4 fragment: SV_Target0)
{
	float4 color = tex2D(ReShade::BackBuffer, texcoord);
	float3 BlurColor2 = 0;
	float3 Blurtemp = 0;
	const float MaxDistance = 8*BloomWidth;
	float CurDistance = 0;
	const float Samplecount = 25.0;
	const float2 blurtempvalue = texcoord * ReShade::PixelSize * BloomWidth;
	float2 BloomSample = float2(2.5,-2.5);
	float2 BloomSampleValue;
	
	for(BloomSample.x = (2.5); BloomSample.x > -2.0; BloomSample.x = BloomSample.x - 1.0)
	{
		BloomSampleValue.x = BloomSample.x * blurtempvalue.x;
		float2 distancetemp = BloomSample.x * BloomSample.x * BloomWidth;
		
		for(BloomSample.y = (- 2.5); BloomSample.y < 2.0; BloomSample.y = BloomSample.y + 1.0)
		{
			distancetemp.y = BloomSample.y * BloomSample.y;
			CurDistance = (distancetemp.y * BloomWidth) + distancetemp.x;
			BloomSampleValue.y = BloomSample.y * blurtempvalue.y;
			Blurtemp.rgb = tex2D(ReShade::BackBuffer, float2(texcoord + BloomSampleValue)).rgb;
			BlurColor2.rgb += lerp(Blurtemp.rgb,color.rgb, sqrt(CurDistance / MaxDistance));
		}
	}
	BlurColor2.rgb = (BlurColor2.rgb / (Samplecount - (BloomPower - BloomThreshold*5)));
	const float Bloomamount = (dot(color.rgb,float3(0.299f, 0.587f, 0.114f)));
	const float3 BlurColor = BlurColor2.rgb * (BloomPower + 4.0);
	color.rgb = lerp(color.rgb,BlurColor.rgb, Bloomamount);	
	fragment = saturate(color);
}

void PS_Otis_AFG_BlendFogWithNormalBuffer(float4 vpos: SV_Position, float2 texcoord: TEXCOORD, out float4 fragment: SV_Target0)
{

    // Grab screen texture
	fragment.rgb = tex2D(ReShade::BackBuffer, texcoord).rgb;

	// Correct Aspect Ratio
	float2 UvCoordAspect = texcoord;
	UvCoordAspect.y += ReShade::AspectRatio * 0.5 - 0.5;
	UvCoordAspect.y /= ReShade::AspectRatio;
    // Center coordinates
	UvCoordAspect = UvCoordAspect * 2 - 1;
	UvCoordAspect *= Scale;

	// Tilt vector
	float Angle = radians(-Axis);
	float2 TiltVector = float2(sin(Angle), cos(Angle));
	// Blend Mask
	float BlendMask = dot(TiltVector, UvCoordAspect) + Offset;

	BlendMask = Overlay(BlendMask * 0.5 + 0.5); // Linear coordinates

	const float depth = ReShade::GetLinearizedDepth(texcoord).r;
	float fogFactor = clamp(saturate(depth - FogStart) * FogCurve, 0.0, MaxFogFactor);

	if (FlipFog) {fogFactor = 1-fogFactor;}
	
	float3 prefragment=lerp(tex2D(ReShade::BackBuffer, texcoord), lerp(tex2D(Otis_BloomSampler, texcoord), lerp(ColorA.rgb, ColorB.rgb, Flip ? 1 - BlendMask : BlendMask), fogFactor), fogFactor);

	switch (BlendM){
			case 0:{fragment=prefragment;break;}
			case 1:{fragment=lerp(fragment.rgb,Multiply(fragment.rgb,prefragment),fogFactor);break;}
			case 2:{fragment=lerp(fragment.rgb,Screen(fragment.rgb,prefragment),fogFactor);break;}
			case 3:{fragment=lerp(fragment.rgb,OverlayM(fragment.rgb,prefragment),fogFactor);break;}
			case 4:{fragment=lerp(fragment.rgb,Darken(fragment.rgb,prefragment),fogFactor);break;}
			case 5:{fragment=lerp(fragment.rgb,Lighten(fragment.rgb,prefragment),fogFactor);break;}
			case 6:{fragment=lerp(fragment.rgb,ColorDodge(fragment.rgb,prefragment),fogFactor);break;}
			case 7:{fragment=lerp(fragment.rgb,ColorBurn(fragment.rgb,prefragment),fogFactor);break;}
			case 8:{fragment=lerp(fragment.rgb,HardLight(fragment.rgb,prefragment),fogFactor);break;}
			case 9:{fragment=lerp(fragment.rgb,SoftLight(fragment.rgb,prefragment),fogFactor);break;}
			case 10:{fragment=lerp(fragment.rgb,Difference(fragment.rgb,prefragment),fogFactor);break;}
			case 11:{fragment=lerp(fragment.rgb,Exclusion(fragment.rgb,prefragment),fogFactor);break;}
			case 12:{fragment=lerp(fragment.rgb,Hue(fragment.rgb,prefragment),fogFactor);break;}
			case 13:{fragment=lerp(fragment.rgb,Saturation(fragment.rgb,prefragment),fogFactor);break;}
			case 14:{fragment=lerp(fragment.rgb,ColorM(fragment.rgb,prefragment),fogFactor);break;}
			case 15:{fragment=lerp(fragment.rgb,Luminosity(fragment.rgb,prefragment),fogFactor);break;}
	}
}
technique SunsetFog
{
	pass Otis_AFG_PassBloom0
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_AFG_PerformBloom;
		RenderTarget = Otis_BloomTarget;
	}
	
	pass Otis_AFG_PassBlend
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Otis_AFG_BlendFogWithNormalBuffer;
	}
}