#ifndef CUSTOM_LIT_PASS_INCLUDED
#define CUSTOM_LIT_PASS_INCLUDED


struct Attributes {
	float3 positionOS : POSITION;
	float2 baseUV : TEXCOORD0;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings {
	float4 positionCS : SV_POSITION;
	float2 baseUV : VAR_BASE_UV;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

bool _ShadowPancaking;

Varyings ShadowCasterPassVertex (Attributes input) {
	Varyings output;
	UNITY_SETUP_INSTANCE_ID(input);
	UNITY_TRANSFER_INSTANCE_ID(input, output);
	float3 positionWS = TransformObjectToWorld(input.positionOS);
	output.positionCS = TransformWorldToHClip(positionWS);
	
	output.baseUV = TransformBaseUV(input.baseUV);
	if (_ShadowPancaking)
	{
		#if UNITY_REVERSED_Z
		output.positionCS.z = min(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
		#else
		output.positionCS.z = max(output.positionCS.z, output.positionCS.w * UNITY_NEAR_CLIP_VALUE);
		#endif
	}
	return output;
}

float4 ShadowCasterPassFragment  (Varyings input) : SV_TARGET {
	InputConfig config = GetInputConfig(input.baseUV);
	UNITY_SETUP_INSTANCE_ID(input);
	ClipLOD(input.positionCS.xy, unity_LODFade.x);
	float4 base = GetBase(config);
	#if defined(_SHADOWS_CLIP)
		clip(base.a - GetCutoff(config));
	#elif defined(_SHADOWS_DITHER)
	float dither = InterleavedGradientNoise(input.positionCS.xy, 0);
	clip(base.a - dither);
	#endif
	return 0.0;
}


#endif
