#ifndef CUSTOM_SHADOWS_INCLUDED
#define CUSTOM_SHADOWS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl"
// PCF for directional shadows, default 2 x 2
#if defined(_DIRECTIONAL_PCF3)
	#define DIRECTIONAL_FILTER_SAMPLES 4
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_DIRECTIONAL_PCF5)
	#define DIRECTIONAL_FILTER_SAMPLES 9
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_DIRECTIONAL_PCF7)
	#define DIRECTIONAL_FILTER_SAMPLES 16
	#define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#if defined(_OTHER_PCF3)
	#define OTHER_FILTER_SAMPLES 4
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
#elif defined(_OTHER_PCF5)
	#define OTHER_FILTER_SAMPLES 9
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
#elif defined(_OTHER_PCF7)
	#define OTHER_FILTER_SAMPLES 16
	#define OTHER_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
#endif

#define MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT 4
#define MAX_CASCADE_COUNT 4

#define MAX_SHADOWED_OTHER_LIGHT_COUNT 16

TEXTURE2D_SHADOW(_DirectionalShadowAtlas);
TEXTURE2D_SHADOW(_OtherShadowAtlas);
#define SHADOW_SAMPLER sampler_linear_clamp_compare
SAMPLER_CMP(SHADOW_SAMPLER);

CBUFFER_START(_CustomShadows)
	int _CascadeCount;
	float4 _CascadeCullingSpheres[MAX_CASCADE_COUNT];
	float4x4 _DirectionalShadowMatrices[MAX_SHADOWED_DIRECTIONAL_LIGHT_COUNT * MAX_CASCADE_COUNT];
	float4x4 _OtherShadowMatrices[MAX_SHADOWED_OTHER_LIGHT_COUNT];
	float4 _OtherShadowTiles[MAX_SHADOWED_OTHER_LIGHT_COUNT];
	float4 _ShadowAtlasSize;
	float4 _ShadowDistanceFade;
	float4 _CascadeData[MAX_CASCADE_COUNT];
CBUFFER_END
// each light has its DirectionalShadowData
// get by GetDirectionalShadowData 
struct DirectionalShadowData {
	float strength;
	int tileIndex;
	float normalBias;
	int shadowMaskChannel;
};

struct OtherShadowData
{
	float strength;
	int tileIndex;
	bool isPoint;
	int shadowMaskChannel;
	float3 lightPositionWS;
	//  surface-to-light direction
	float3 lightDirectionWS;
	float3 spotDirectionWS;
};

struct ShadowMask {
	bool always;
	bool distance;
	float4 shadows;
};

struct ShadowData {
	int cascadeIndex;
	float cascadeBlend;
	float strength;
	ShadowMask shadowMask;
};

float SampleDirectionalShadowAtlas (float3 positionSTS) {
	return SAMPLE_TEXTURE2D_SHADOW(
		_DirectionalShadowAtlas, SHADOW_SAMPLER, positionSTS
	);
}

float FilterDirectionalShadow (float3 positionSTS) {
	// USING PCF to filte shadow
	#if defined(DIRECTIONAL_FILTER_SETUP)
		float weights[DIRECTIONAL_FILTER_SAMPLES];
		float2 positions[DIRECTIONAL_FILTER_SAMPLES];
		float4 size = _ShadowAtlasSize.yyxx;
		DIRECTIONAL_FILTER_SETUP(size, positionSTS.xy, weights, positions);
		float shadow = 0;
		for (int i = 0; i < DIRECTIONAL_FILTER_SAMPLES; i++) {
			shadow += weights[i] * SampleDirectionalShadowAtlas(
				float3(positions[i].xy, positionSTS.z)
			);
		}
		return shadow;
	#else
		return SampleDirectionalShadowAtlas(positionSTS);
	#endif
}

float SampleOtherShadowAtlas (float3 positionSTS, float3 bounds) {
	// bounds.xy is the min x, y of box. bounds.z is size. bound is a square.
	positionSTS.xy = clamp(positionSTS.xy, bounds.xy, bounds.xy + bounds.z);
	return SAMPLE_TEXTURE2D_SHADOW(
		_OtherShadowAtlas, SHADOW_SAMPLER, positionSTS
	);
}

float FilterOtherShadow (float3 positionSTS, float3 bounds) {
	// USING PCF to filte shadow
	#if defined(OTHER_FILTER_SETUP)
		float weights[OTHER_FILTER_SAMPLES];
		float2 positions[OTHER_FILTER_SAMPLES];
		// directional used yyzz
		float4 size = _ShadowAtlasSize.wwzz;
		OTHER_FILTER_SETUP(size, positionSTS.xy, weights, positions);
		float shadow = 0;
		for (int i = 0; i < OTHER_FILTER_SAMPLES; i++) {
			shadow += weights[i] * SampleOtherShadowAtlas(
				float3(positions[i].xy, positionSTS.z), bounds
			);
		}
		return shadow;
	#else
		return SampleOtherShadowAtlas(positionSTS, bounds);
	#endif
}

float GetCascadedShadow (DirectionalShadowData directional, ShadowData global, Surface surfaceWS)
{
	float3 normalBias = surfaceWS.interpolatedNormal * (directional.normalBias * _CascadeData[global.cascadeIndex].y);
	float3 positionSTS = mul(_DirectionalShadowMatrices[directional.tileIndex],
		float4(surfaceWS.position + normalBias, 1.0)).xyz;
	float shadow = FilterDirectionalShadow(positionSTS);
	// blend between current cascade and next cascade
	// enable when "cascade blend" set to "soft"
	if (global.cascadeBlend < 1.0) {
		normalBias = surfaceWS.interpolatedNormal *
			(directional.normalBias * _CascadeData[global.cascadeIndex + 1].y);
		positionSTS = mul(
			_DirectionalShadowMatrices[directional.tileIndex + 1],
			float4(surfaceWS.position + normalBias, 1.0)
		).xyz;
		shadow = lerp(
			FilterDirectionalShadow(positionSTS), shadow, global.cascadeBlend
		);
	}
	return shadow;
}

static const float3 pointShadowPlanes[6] = {
	float3(-1.0, 0.0, 0.0),
	float3(1.0, 0.0, 0.0),
	float3(0.0, -1.0, 0.0),
	float3(0.0, 1.0, 0.0),
	float3(0.0, 0.0, -1.0),
	float3(0.0, 0.0, 1.0)
};

// equivalent GetCascadedShadow for point and spot 
float GetOtherShadow (OtherShadowData other, ShadowData global, Surface surfaceWS) {
	float tileIndex = other.tileIndex;
	float3 lightPlane = other.spotDirectionWS;

	if (other.isPoint) {
		// other.lightDirectionWS is surface-to-light, here needs negative
		float faceOffset = CubeMapFaceID(-other.lightDirectionWS);
		tileIndex += faceOffset;
		// The plane normals have to point in the opposite direction as the faces,
		// like the spot direction points toward the light.
		// for +X
		// ----------.--------.------>x
		//         light      +x face
		// normal vector of +x face and point to light is (-1, 0, 0)
		lightPlane = pointShadowPlanes[faceOffset];
	}
	
	float4 tileData = _OtherShadowTiles[tileIndex];
	// normal bias
	float3 surfaceToLight = other.lightPositionWS - surfaceWS.position;
	float distanceToPlane = dot(surfaceToLight, lightPlane);
	float3 normalBias = surfaceWS.interpolatedNormal * distanceToPlane * tileData.w;
	// here is perspective projection
	float4 positionSTS = mul(_OtherShadowMatrices[tileIndex],
		float4(surfaceWS.position + normalBias, 1.0));
	float shadow = FilterOtherShadow(positionSTS.xyz / positionSTS.w, tileData.xyz);
	return shadow;
}


float GetBakedShadow (ShadowMask mask, int channel) {
	float shadow = 1.0;
	if (mask.always || mask.distance) {
		if (channel >= 0) {
			shadow = mask.shadows[channel];
		}
	}
	return shadow;
}

float GetBakedShadow (ShadowMask mask, int channel,float strength) {
	if (mask.always ||mask.distance) {
		// only Baked Shadow, won't call MixBakedAndRealtimeShadows
		// lerp ourselves.
		return lerp(1.0, GetBakedShadow(mask, channel), strength);
	}
	return 1.0;
}

float MixBakedAndRealtimeShadows (
	ShadowData global, float shadow, int shadowMaskChannel, float strength
) {
	float baked = GetBakedShadow(global.shadowMask, shadowMaskChannel);
	if (global.shadowMask.always) {
		shadow = lerp(1.0, shadow, global.strength);
		shadow = min(baked, shadow);
		return lerp(1.0, shadow, strength);
	}
	if (global.shadowMask.distance) {
		// out of max shadow distance, global.strength = 0;
		shadow = lerp(baked, shadow, global.strength);
		// only light's strength used in lerp
		return lerp(1.0, shadow, strength);
	}
	// light's strength and globel.strength 
	return lerp(1.0, shadow, strength * global.strength);
}

// here global means one pixel has one shadow data at different stage of shading.
float GetDirectionalShadowAttenuation (DirectionalShadowData directional, ShadowData global, Surface surfaceWS) {
	#if !defined(_RECEIVE_SHADOWS)
		return 1.0;
	#endif
	float shadow;
	// directional.strength set by user
	// global.strength cal based on depth of object in scene, it depends on camera and fragment position.
	// independent of light 
	if (directional.strength * global.strength <= 0.0) {
		shadow = GetBakedShadow(global.shadowMask, directional.shadowMaskChannel,abs(directional.strength));
	}
	else {
		shadow = GetCascadedShadow(directional, global, surfaceWS);
		shadow = MixBakedAndRealtimeShadows(global, shadow, directional.shadowMaskChannel, directional.strength);
	}
	return shadow;
}

float GetOtherShadowAttenuation(OtherShadowData other, ShadowData global, Surface surfaceWS) {
	#if !defined(_RECEIVE_SHADOWS)
		return 1.0;
	#endif
	
	float shadow;
	// other.strength set by user
	// global.strength cal based on depth of object in scene
	if (other.strength * global.strength <= 0.0) {
		shadow = GetBakedShadow(global.shadowMask, other.shadowMaskChannel,abs(other.strength));
	}
	else {
		shadow = GetOtherShadow(other, global, surfaceWS);
		shadow = MixBakedAndRealtimeShadows(global, shadow, other.shadowMaskChannel, other.strength);
	}
	
	return shadow;
}

float FadedShadowStrength (float distance, float scale, float fade) {
	return saturate((1.0 - distance * scale) * fade);
}

ShadowData GetShadowData (Surface surfaceWS) {
	ShadowData data;
	// after GetShadowData, data.shadowMask will be set from gi.
	data.shadowMask.always = false;
	data.shadowMask.distance = false;
	data.shadowMask.shadows = 1.0;
	data.cascadeBlend = 1.0;

	// \frac{1-\frac{d}{m}}{f}
	// where d is the surface depth, m is the max shadow distance, and 
	// f is a fade range, expressed as a fraction of the max distance.
	data.strength = FadedShadowStrength(
		//_ShadowDistanceFade.x is 1f / settings.maxDistance
		//_ShadowDistanceFade.y is 1f / settings.distanceFade
		surfaceWS.depth, _ShadowDistanceFade.x, _ShadowDistanceFade.y
	);
	int i;
	for (i = 0; i < _CascadeCount; i++) {
		float4 sphere = _CascadeCullingSpheres[i];
		float distanceSqr = DistanceSquared(surfaceWS.position, sphere.xyz);
		if (distanceSqr < sphere.w) {
			// fade relates to cascade, so it used DistanceSquared(surfaceWS.position, sphere.xyz) instead of depth.
			float fade = FadedShadowStrength(
				distanceSqr, _CascadeData[i].x, _ShadowDistanceFade.z
			);
			if (i == _CascadeCount - 1) {
				// in the last cascade fade blends shadow and empty
				data.strength *= fade;
			}
			else {
				// not in last cascade, fade blends cascade i and i + 1
				data.cascadeBlend = fade;
			}
			break;
		}
	}
	// when no directional light, _CascadeCount is 0, so
	// i == _CascadeCount doesn't mean out of range.
	if (i == _CascadeCount && _CascadeCount > 0) {
		data.strength = 0.0;
	}
	#if defined(_CASCADE_BLEND_DITHER)
		else if (data.cascadeBlend < surfaceWS.dither) {
			i += 1;
		}
	#endif
	#if !defined(_CASCADE_BLEND_SOFT)
		data.cascadeBlend = 1.0;
	#endif
		data.cascadeIndex = i;
	return data;
}


#endif