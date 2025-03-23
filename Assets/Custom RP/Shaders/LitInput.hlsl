#ifndef CUSTOM_LIT_INPUT_INCLUDED
#define CUSTOM_LIT_INPUT_INCLUDED
#include "../ShaderLibrary/Common.hlsl"
TEXTURE2D(_BaseMap);
TEXTURE2D(_EmissionMap);
SAMPLER(sampler_BaseMap);
TEXTURE2D(_MaskMap);
TEXTURE2D(_NormalMap);

TEXTURE2D(_DetailMap);
TEXTURE2D(_DetailNormalMap);
SAMPLER(sampler_DetailMap);

UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
	UNITY_DEFINE_INSTANCED_PROP(float4, _BaseMap_ST)
	UNITY_DEFINE_INSTANCED_PROP(float4, _DetailMap_ST)
	UNITY_DEFINE_INSTANCED_PROP(float4, _BaseColor)
	UNITY_DEFINE_INSTANCED_PROP(float4, _EmissionColor)
	UNITY_DEFINE_INSTANCED_PROP(float, _Cutoff)
	UNITY_DEFINE_INSTANCED_PROP(float, _Metallic)
	UNITY_DEFINE_INSTANCED_PROP(float, _Occlusion)
	UNITY_DEFINE_INSTANCED_PROP(float, _Smoothness)
	UNITY_DEFINE_INSTANCED_PROP(float, _Fresnel)
	//===== detail map control =====
	UNITY_DEFINE_INSTANCED_PROP(float, _DetailAlbedo)
	UNITY_DEFINE_INSTANCED_PROP(float, _DetailSmoothness)
	UNITY_DEFINE_INSTANCED_PROP(float, _DetailNormalScale)
	//==============================
	UNITY_DEFINE_INSTANCED_PROP(float, _NormalScale)
UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

#define INPUT_PROP(name) UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, name)

struct InputConfig {
	float2 baseUV;
	float2 detailUV;
	bool useMask;
	bool useDetail;
};


InputConfig GetInputConfig (float2 baseUV, float2 detailUV = 0.0) {
	InputConfig c;
	c.baseUV = baseUV;
	c.detailUV = detailUV;
	c.useMask = false;
	c.useDetail = false;
	return c;
}

// this UV is used in detail map.
float2 TransformDetailUV (float2 detailUV) {
	float4 detailST = INPUT_PROP(_DetailMap_ST);
	return detailUV * detailST.xy + detailST.zw;
}

float4 GetDetail (InputConfig c) {
	if (c.useDetail) {
		float4 map = SAMPLE_TEXTURE2D(_DetailMap, sampler_DetailMap, c.detailUV);
		return map * 2.0 - 1.0;
	}
	return 0.0;
}

float2 TransformBaseUV (float2 baseUV) {
	float4 baseST = INPUT_PROP(_BaseMap_ST);
	return baseUV * baseST.xy + baseST.zw;
}

// r is metallic mask
// g is occlusion mask
// b is detail mask
// a is smoothness mask
float4 GetMask (InputConfig c) {
	if (c.useMask) {
		return SAMPLE_TEXTURE2D(_MaskMap, sampler_BaseMap, c.baseUV);
	}
	return 1.0;
}

float4 GetBase (InputConfig c) {
	float4 map = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, c.baseUV);
	float4 color = INPUT_PROP(_BaseColor);
	if (c.useDetail)
	{
		// _DetailAlbedo is set by used to adjust the strength of detail albedo 
		float4 detail = GetDetail(c).r * INPUT_PROP(_DetailAlbedo);
		//When detail is less than 0, it will pull rgb towards 0.
		//The more negative the absolute value, the closer the map approaches 0.
		// When detail is greater than 0, it will pull rgb towards 1.
		// The more positive the absolute value, the closer the map approaches
		// map.rgb = lerp(map.rgb, detail < 0.0 ? 0.0 : 1.0, abs(detail));

		// interpolating in gamma space is better than in linear space
		// we use sqrt and square to approximate gamma space.
		// at the same time, we use mask map to avoid some position being detail modified.
		float mask = GetMask(c).b;
		map.rgb = lerp(sqrt(map.rgb), detail < 0.0 ? 0.0 : 1.0, abs(detail) * mask);
		map.rgb *= map.rgb;
	}
	return map * color;
}

float GetCutoff (InputConfig c) {
	return INPUT_PROP(_Cutoff);
}

float GetMetallic (InputConfig c) {
	// property set in Material inspector
	float metallic = INPUT_PROP(_Metallic);
	// mix with mask map
	metallic *= GetMask(c).r;
	return metallic;
}

float GetSmoothness (InputConfig c) {
	float smoothness = INPUT_PROP(_Smoothness);
	smoothness *= GetMask(c).a; // mask.a is used for normal smoothness
	if (c.useDetail)
	{
		// use detail map to modifiy base mask map and get more details
		float detail = GetDetail(c).b * INPUT_PROP(_DetailSmoothness);
		float mask = GetMask(c).b; // b is used for detail map
		smoothness = lerp(smoothness, detail < 0.0 ? 0.0 : 1.0, abs(detail) * mask);
	}
	return smoothness;
}

float3 GetEmission (InputConfig c) {
	float4 map = SAMPLE_TEXTURE2D(_EmissionMap, sampler_BaseMap, c.baseUV);
	float4 color = INPUT_PROP(_EmissionColor);
	return map.rgb * color.rgb;
}

float GetFresnel (InputConfig c) {
	return INPUT_PROP(_Fresnel);
}

// Occlusion only used in indrect brdf
float GetOcclusion (InputConfig c) {
	float strength = INPUT_PROP(_Occlusion);
	// occlusion from texture
	float occlusion = GetMask(c).g;
	// 1 means no occlusion, is it wrong in tutorial?
	occlusion = lerp(1.0, occlusion , strength);
	return occlusion;
}

float3 GetNormalTS (InputConfig c) {
	float4 map = SAMPLE_TEXTURE2D(_NormalMap, sampler_BaseMap, c.baseUV);
	float scale = INPUT_PROP(_NormalScale);
	// scale is used to control the strength of normal map
	float3 normal = DecodeNormal(map, scale);
	if (c.useDetail)
	{
		map = SAMPLE_TEXTURE2D(_DetailNormalMap, sampler_DetailMap, c.detailUV);
		scale = INPUT_PROP(_DetailNormalScale) * GetMask(c).b;
		float3 detail = DecodeNormal(map, scale);
		normal = BlendNormalRNM(normal, detail);
	}
	return normal;
}

#endif